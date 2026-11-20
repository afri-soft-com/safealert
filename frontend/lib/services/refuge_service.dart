import 'api_service.dart';

class Refuge {
  final String id;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final String? address;
  final String? phone;
  final bool open24h;
  final double? distanceKm;

  const Refuge({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.address,
    this.phone,
    this.open24h = false,
    this.distanceKm,
  });

  static String? _text(dynamic v) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  factory Refuge.fromJson(Map<String, dynamic> j) => Refuge(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        category: (j['category'] ?? 'other').toString(),
        lat: double.tryParse(j['lat'].toString()) ?? 0,
        lng: double.tryParse(j['lng'].toString()) ?? 0,
        address: _text(j['address']),
        phone: _text(j['phone']),
        open24h: j['open_24h'] == true,
        distanceKm: j['distance_km'] == null ? null : double.tryParse(j['distance_km'].toString()),
      );
}

/// Safe places (hospital, pharmacy, fuel station…) from /api/refuges.
class RefugeService {
  final ApiService _api = ApiService();

  /// slug → (emoji, label)
  static const categories = <String, (String, String)>{
    'hospital': ('🏥', 'Hôpital'),
    'pharmacy': ('💊', 'Pharmacie'),
    'fuel': ('⛽', 'Station-service'),
    'church': ('⛪', 'Église'),
    'shop': ('🏪', 'Commerce ouvert'),
    'other': ('📍', 'Autre'),
  };

  static bool canEdit(String role) =>
      const {'leader', 'agent', 'admin', 'platform_admin'}.contains(role);

  static String formatDistance(double km) =>
      km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

  Future<List<Refuge>> fetch({double? lat, double? lng, String? category, double radiusKm = 15}) async {
    final q = <String>[
      if (lat != null && lng != null) ...['lat=$lat', 'lng=$lng', 'radius_km=$radiusKm'],
      if (category != null) 'category=$category',
    ];
    final res = await _api.get('/refuges${q.isEmpty ? '' : '?${q.join('&')}'}');
    final list = (res['refuges'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => Refuge.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> create({
    required String name,
    required String category,
    required double lat,
    required double lng,
    String? phone,
    String? address,
    bool open24h = false,
  }) async {
    await _api.post('/refuges', {
      'name': name.trim(),
      'category': category,
      'lat': lat,
      'lng': lng,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
      'open_24h': open24h,
    });
  }
}
