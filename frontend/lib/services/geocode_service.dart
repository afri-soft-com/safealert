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
  final Map<String, PlaceDetails> _placeCache = {};
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
    final details = await reverseDetails(lat, lng);
    return details?.label;
  }

  /// Reverse geocode with commune (city) + quartier breakdown.
  Future<PlaceDetails?> reverseDetails(double lat, double lng) async {
    final key = _cacheKey(lat, lng);
    if (_placeCache.containsKey(key)) return _placeCache[key];
    if (_reverseCache.containsKey(key) && !_placeCache.containsKey(key)) {
      // Label-only cache from older calls — still try full fetch below.
    }

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
      final details = PlaceDetails.fromNominatim(data);
      if (details.label.isNotEmpty) {
        _reverseCache[key] = details.label;
        _placeCache[key] = details;
      }
      return details;
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

  String? _pickLabel(Map data) => PlaceDetails.fromNominatim(data).label;
}

/// Structured place from Nominatim (commune + quartier for circle member cards).
class PlaceDetails {
  final String label;
  final String? commune;
  final String? quartier;
  final String? road;
  final String? country;

  const PlaceDetails({
    required this.label,
    this.commune,
    this.quartier,
    this.road,
    this.country,
  });

  factory PlaceDetails.fromNominatim(Map data) {
    final address = data['address'];
    String? quartier;
    String? commune;
    String? road;
    String? country;
    if (address is Map) {
      quartier = _str(
        address['suburb'] ??
            address['neighbourhood'] ??
            address['quarter'] ??
            address['city_district'] ??
            address['residential'],
      );
      commune = _str(
        address['city'] ??
            address['town'] ??
            address['municipality'] ??
            address['village'] ??
            address['county'],
      );
      road = _str(address['road'] ?? address['pedestrian']);
      country = _str(address['country']);
    }

    final display = data['display_name']?.toString().trim();
    String label;
    if (quartier != null && commune != null && quartier != commune) {
      label = road != null ? '$road, $quartier, $commune' : '$quartier, $commune';
    } else if (display != null && display.isNotEmpty) {
      final parts =
          display.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      label = parts.length <= 3 ? display : parts.take(4).join(', ');
    } else if (road != null && (quartier ?? commune) != null) {
      label = '$road, ${quartier ?? commune}';
    } else {
      label = quartier ?? commune ?? road ?? '';
    }

    return PlaceDetails(
      label: label,
      commune: commune,
      quartier: quartier,
      road: road,
      country: country,
    );
  }

  static String? _str(Object? v) {
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }
}
