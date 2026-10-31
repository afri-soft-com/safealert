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
      'v2:${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  /// Reverse geocode → display label (or coords fallback string).
  Future<String?> reverse(double lat, double lng) async {
    final details = await reverseDetails(lat, lng);
    return details?.label;
  }

  /// Reverse geocode with commune (city) + quartier breakdown.
  Future<PlaceDetails?> reverseDetails(double lat, double lng) async {
    final key = _cacheKey(lat, lng);
    if (_placeCache.containsKey(key)) return _placeCache[key];

    try {
      await _throttle();
      // zoom=18 → building/street level; coarser zoom often returns the
      // province ("Kinshasa") as city and a wrong suburb as quartier.
      final uri = Uri.parse(_reverseUrl).replace(queryParameters: {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
        'addressdetails': '1',
        'zoom': '18',
      });
      final res = await http.get(uri, headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
        'Accept-Language': 'fr',
      }).timeout(const Duration(seconds: 10));
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
    String? road;
    String? country;
    String? state;
    final parts = <String>[];
    if (data['display_name'] is String) {
      parts.addAll(
        data['display_name']
            .toString()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      );
    }

    String? suburb;
    String? neighbourhood;
    String? quarter;
    String? cityDistrict;
    String? residential;
    String? city;
    String? town;
    String? municipality;
    String? village;
    String? county;
    String? borough;

    if (address is Map) {
      suburb = _str(address['suburb']);
      neighbourhood = _str(address['neighbourhood']);
      quarter = _str(address['quarter']);
      cityDistrict = _cleanDistrict(_str(address['city_district']));
      residential = _str(address['residential']);
      city = _str(address['city']);
      town = _str(address['town']);
      municipality = _str(address['municipality']);
      village = _str(address['village']);
      county = _str(address['county']);
      borough = _str(address['borough']);
      road = _str(address['road'] ?? address['pedestrian'] ?? address['path']);
      country = _str(address['country']);
      state = _str(address['state'] ?? address['province']);
    }

    // Kinshasa / grandes villes RDC : « city » = province, la commune est
    // souvent suburb / city_district / borough. Le quartier est plus petit.
    final megaCity = _isMegaCity(city) || _isMegaCity(state);
    String? commune;
    String? quartier;

    if (megaCity) {
      commune = cityDistrict ??
          borough ??
          municipality ??
          suburb ??
          _communeFromDisplay(parts, city ?? state);
      quartier = neighbourhood ??
          quarter ??
          residential ??
          (suburb != null && suburb != commune ? suburb : null) ??
          _quartierFromDisplay(parts, commune, city ?? state);
      // Keep province as context only when commune missing.
      commune ??= city ?? town ?? municipality;
    } else {
      commune = municipality ??
          cityDistrict ??
          borough ??
          city ??
          town ??
          village ??
          county;
      quartier = neighbourhood ??
          quarter ??
          suburb ??
          residential ??
          cityDistrict;
      if (quartier != null &&
          commune != null &&
          _norm(quartier) == _norm(commune)) {
        quartier = neighbourhood ?? quarter ?? residential;
        if (quartier != null && _norm(quartier) == _norm(commune)) {
          quartier = null;
        }
      }
    }

    // Drop junk / duplicated labels.
    if (quartier != null && commune != null && _norm(quartier) == _norm(commune)) {
      quartier = null;
    }
    if (commune != null && state != null && _norm(commune) == _norm(state) && !megaCity) {
      // Prefer a finer display part when commune collapsed to province.
      commune = _communeFromDisplay(parts, state) ?? commune;
    }

    final labelParts = <String>[
      if (road != null) road,
      if (quartier != null) quartier,
      if (commune != null) commune,
    ];
    final label = labelParts.isNotEmpty
        ? labelParts.join(', ')
        : (parts.isNotEmpty ? parts.take(3).join(', ') : '');

    return PlaceDetails(
      label: label,
      commune: commune,
      quartier: quartier,
      road: road,
      country: country,
    );
  }

  static bool _isMegaCity(String? name) {
    if (name == null) return false;
    final n = _norm(name);
    return n == 'kinshasa' ||
        n == 'kinshasa city' ||
        n.contains('ville de kinshasa') ||
        n == 'lubumbashi' ||
        n == 'mbuji-mayi' ||
        n == 'mbujimayi' ||
        n == 'goma' ||
        n == 'bukavu' ||
        n == 'brazzaville' ||
        n == 'pointe-noire';
  }

  static String? _cleanDistrict(String? raw) {
    if (raw == null) return null;
    return raw
        .replaceFirst(RegExp(r'^commune\s+(de\s+)?', caseSensitive: false), '')
        .trim();
  }

  /// Heuristic: in "street, quartier, Commune, Kinshasa, …" commune is often index 2.
  static String? _communeFromDisplay(List<String> parts, String? mega) {
    if (parts.length < 3) return null;
    final megaN = mega != null ? _norm(mega) : null;
    for (var i = 1; i < parts.length && i < 5; i++) {
      final p = parts[i];
      final n = _norm(p);
      if (megaN != null && n == megaN) continue;
      if (n.contains('république') || n.contains('congo') || n == 'cd') continue;
      if (RegExp(r'^\d').hasMatch(p)) continue;
      // Prefer capitalized commune-looking tokens over micro-POI.
      if (p.length >= 3) return _cleanDistrict(p) ?? p;
    }
    return null;
  }

  static String? _quartierFromDisplay(
    List<String> parts,
    String? commune,
    String? mega,
  ) {
    if (parts.isEmpty) return null;
    final skip = {_norm(commune ?? ''), _norm(mega ?? ''), 'cd', 'rdc'};
    for (final p in parts.take(4)) {
      final n = _norm(p);
      if (n.isEmpty || skip.contains(n)) continue;
      if (n.contains('république') || n.contains('congo')) continue;
      if (RegExp(r'^\d').hasMatch(p)) continue;
      if (commune != null && _norm(p) == _norm(commune)) continue;
      return p;
    }
    return null;
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _str(Object? v) {
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }
}
