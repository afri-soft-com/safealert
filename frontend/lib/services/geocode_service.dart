import 'dart:convert';
import 'package:http/http.dart' as http;

/// Nominatim (OpenStreetMap) geocoding for trip address UX.
/// Respects usage policy: User-Agent + light client-side throttle.
class GeocodeService {
  static final GeocodeService _instance = GeocodeService._();
  GeocodeService._();
  factory GeocodeService() => _instance;

  static const _userAgent =
      'SafeAlert/1.0 (citizen-safety-app; https://safealert-api.onrender.com)';
  static const _reverseUrl = 'https://nominatim.openstreetmap.org/reverse';
  static const _searchUrl = 'https://nominatim.openstreetmap.org/search';
  static const _minInterval = Duration(milliseconds: 1100);

  /// Bias search toward Kinshasa / RDC (viewbox: west,north,east,south).
  static const _viewboxCd = '12.0,5.5,31.5,-13.5';

  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, String> _reverseCache = {};
  final Map<String, ({double lat, double lng, String label})> _forwardCache = {};
  final Map<String, List<({double lat, double lng, String label})>> _suggestCache = {};

  Future<void> _throttle() async {
    final elapsed = DateTime.now().difference(_lastRequestAt);
    if (elapsed < _minInterval) {
      await Future<void>.delayed(_minInterval - elapsed);
    }
    _lastRequestAt = DateTime.now();
  }

  String _cacheKey(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  /// Reverse geocode → display label (or coords fallback string).
  Future<String?> reverse(double lat, double lng) async {
    final key = _cacheKey(lat, lng);
    if (_reverseCache.containsKey(key)) return _reverseCache[key];

    try {
      await _throttle();
      final uri = Uri.parse(_reverseUrl).replace(queryParameters: {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
        'addressdetails': '1',
        'zoom': '16',
      });
      final res = await http.get(uri, headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
        'Accept-Language': 'fr',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final label = _pickLabel(data);
      if (label != null && label.isNotEmpty) {
        _reverseCache[key] = label;
      }
      return label;
    } catch (_) {
      return null;
    }
  }

  /// Forward geocode free-text address → first match.
  Future<({double lat, double lng, String label})?> forward(String query) async {
    final list = await suggest(query, limit: 1);
    return list.isEmpty ? null : list.first;
  }

  /// Autocomplete suggestions (multiple places).
  Future<List<({double lat, double lng, String label})>> suggest(
    String query, {
    int limit = 6,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    final coordMatch = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*[,;\s]\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(q);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lng = double.tryParse(coordMatch.group(2)!);
      if (lat != null && lng != null) {
        return [(lat: lat, lng: lng, label: q)];
      }
    }

    final cacheKey = '${q.toLowerCase()}|$limit';
    if (_suggestCache.containsKey(cacheKey)) return _suggestCache[cacheKey]!;
    if (limit == 1 && _forwardCache.containsKey(q.toLowerCase())) {
      return [_forwardCache[q.toLowerCase()]!];
    }

    try {
      await _throttle();
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {
        'q': q,
        'format': 'json',
        'addressdetails': '1',
        'limit': '$limit',
        'countrycodes': 'cd,cg,rw,bi,ug,ao,zm',
        'viewbox': _viewboxCd,
        'bounded': '0',
        'accept-language': 'fr',
      });
      final res = await http.get(uri, headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
        'Accept-Language': 'fr',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) {
        // Retry without country filter for rare place names
        return _suggestUnscoped(q, limit: limit);
      }
      final out = <({double lat, double lng, String label})>[];
      for (final item in data) {
        if (item is! Map) continue;
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lng = double.tryParse(item['lon']?.toString() ?? '');
        if (lat == null || lng == null) continue;
        final label = _pickLabel(item) ?? item['display_name']?.toString() ?? q;
        out.add((lat: lat, lng: lng, label: label));
      }
      if (out.isEmpty) return _suggestUnscoped(q, limit: limit);
      _suggestCache[cacheKey] = out;
      if (out.isNotEmpty) {
        _forwardCache[q.toLowerCase()] = out.first;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<({double lat, double lng, String label})>> _suggestUnscoped(
    String q, {
    required int limit,
  }) async {
    try {
      await _throttle();
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {
        'q': q,
        'format': 'json',
        'addressdetails': '1',
        'limit': '$limit',
        'accept-language': 'fr',
      });
      final res = await http.get(uri, headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
        'Accept-Language': 'fr',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body);
      if (data is! List) return const [];
      final out = <({double lat, double lng, String label})>[];
      for (final item in data) {
        if (item is! Map) continue;
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lng = double.tryParse(item['lon']?.toString() ?? '');
        if (lat == null || lng == null) continue;
        final label = _pickLabel(item) ?? item['display_name']?.toString() ?? q;
        out.add((lat: lat, lng: lng, label: label));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  String? _pickLabel(Map data) {
    final display = data['display_name']?.toString().trim();
    if (display != null && display.isNotEmpty) {
      final parts = display.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (parts.length <= 3) return display;
      return parts.take(4).join(', ');
    }
    final address = data['address'];
    if (address is Map) {
      final suburb = address['suburb'] ??
          address['neighbourhood'] ??
          address['city_district'] ??
          address['quarter'] ??
          address['city'] ??
          address['town'] ??
          address['village'] ??
          address['municipality'];
      final road = address['road'] ?? address['pedestrian'];
      if (road != null && suburb != null) return '$road, $suburb';
      if (suburb != null) return suburb.toString();
      if (road != null) return road.toString();
    }
    return null;
  }
}
