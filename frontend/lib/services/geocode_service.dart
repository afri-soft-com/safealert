import 'dart:convert';
import 'package:http/http.dart' as http;

/// Nominatim (OpenStreetMap) geocoding for trip address UX.
/// Respects usage policy: User-Agent + light client-side throttle.
class GeocodeService {
  static final GeocodeService _instance = GeocodeService._();
  GeocodeService._();
  factory GeocodeService() => _instance;

  static const _userAgent =
      'SafeAlert/1.0 (citizen-safety-app; contact@safealert.local)';
  static const _reverseUrl = 'https://nominatim.openstreetmap.org/reverse';
  static const _searchUrl = 'https://nominatim.openstreetmap.org/search';
  static const _minInterval = Duration(milliseconds: 1100);

  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, String> _reverseCache = {};
  final Map<String, ({double lat, double lng, String label})> _forwardCache = {};

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
    final q = query.trim();
    if (q.isEmpty) return null;
    final cacheKey = q.toLowerCase();
    if (_forwardCache.containsKey(cacheKey)) return _forwardCache[cacheKey];

    // Already looks like "lat, lng"
    final coordMatch = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*[,;\s]\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(q);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lng = double.tryParse(coordMatch.group(2)!);
      if (lat != null && lng != null) {
        return (lat: lat, lng: lng, label: q);
      }
    }

    try {
      await _throttle();
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {
        'q': q,
        'format': 'json',
        'addressdetails': '1',
        'limit': '1',
      });
      final res = await http.get(uri, headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return null;
      final first = data.first;
      if (first is! Map) return null;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lng == null) return null;
      final label = _pickLabel(first) ?? q;
      final result = (lat: lat, lng: lng, label: label);
      _forwardCache[cacheKey] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  String? _pickLabel(Map data) {
    final display = data['display_name']?.toString().trim();
    if (display != null && display.isNotEmpty) {
      // Keep first 2–3 comma segments for a shorter UI label
      final parts = display.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (parts.length <= 2) return display;
      return parts.take(3).join(', ');
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
