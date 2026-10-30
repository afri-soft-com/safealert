import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class NeighborhoodProvider extends ChangeNotifier {
  NeighborhoodProvider({ApiService? apiService}) : _api = apiService ?? ApiService();

  final ApiService _api;
  List<Map<String, dynamic>> _subscriptions = [];
  bool _loading = false;

  List<Map<String, dynamic>> get subscriptions => _subscriptions;
  bool get loading => _loading;

  static const digestMinuteSlots = [0, 15, 30, 45];
  static const radiusPresetsM = [2000, 5000, 10000];

  static int clampHour(int hour) => hour.clamp(0, 23);

  static int clampMinute(int minute) {
    if (digestMinuteSlots.contains(minute)) return minute;
    if (minute < 0) return 0;
    if (minute >= 45) return 45;
    if (minute >= 30) return 30;
    if (minute >= 15) return 15;
    return 0;
  }

  static int clampRadiusM(int m) {
    if (m < 500) return 500;
    if (m > 30000) return 30000;
    return m;
  }

  /// Kinshasa = UTC+1 fixed (no DST). Convert local wall-clock → Kinshasa.
  static ({int hour, int minute}) localToKinshasa(int hour, int minute) {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day, hour, minute);
    final kinshasa = local.toUtc().add(const Duration(hours: 1));
    return (hour: kinshasa.hour, minute: kinshasa.minute);
  }

  static ({int hour, int minute}) kinshasaToLocal(int hour, int minute) {
    final now = DateTime.now();
    final asUtc = DateTime.utc(now.year, now.month, now.day, hour, minute)
        .subtract(const Duration(hours: 1));
    final local = asUtc.toLocal();
    return (hour: local.hour, minute: local.minute);
  }

  static String formatHm(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static String formatRadius(int meters) {
    if (meters >= 1000 && meters % 1000 == 0) return '${meters ~/ 1000} km';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '$meters m';
  }

  static ({int hour, int minute}) nextLocalSlot({int minAhead = 5}) {
    final target = DateTime.now().add(Duration(minutes: minAhead));
    var h = target.hour;
    var m = ((target.minute + 14) ~/ 15) * 15;
    if (m >= 60) {
      m = 0;
      h = (h + 1) % 24;
    }
    final candidate = DateTime(target.year, target.month, target.day, h, m);
    if (candidate.isBefore(target)) {
      m += 15;
      if (m >= 60) {
        m = 0;
        h = (h + 1) % 24;
      }
    }
    return (hour: h, minute: clampMinute(m));
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/neighborhood');
      _subscriptions = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      _subscriptions = [];
    }
    _loading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>> subscribe({
    required String quartier,
    required int digestHour,
    int digestMinute = 0,
    String? city,
    required double lat,
    required double lng,
    int radiusM = 5000,
  }) async {
    final k = localToKinshasa(clampHour(digestHour), clampMinute(digestMinute));
    final body = <String, dynamic>{
      'quartier': quartier.trim(),
      'digest_hour': k.hour,
      'digest_minute': clampMinute(k.minute),
      'lat': lat,
      'lng': lng,
      'radius_m': clampRadiusM(radiusM),
    };
    final c = city?.trim();
    if (c != null && c.length >= 2) body['city'] = c;

    final created = await _api.post('/neighborhood/subscribe', body);
    await load();
    return created;
  }

  Future<void> updateTime(String id, int digestHour, [int digestMinute = 0]) async {
    final k = localToKinshasa(clampHour(digestHour), clampMinute(digestMinute));
    await _api.patch('/neighborhood/$id', {
      'digest_hour': k.hour,
      'digest_minute': clampMinute(k.minute),
    });
    await load();
  }

  @Deprecated('Use updateTime')
  Future<void> updateHour(String id, int digestHour) => updateTime(id, digestHour, 0);

  Future<void> sendNow(String id) async {
    await _api.post('/neighborhood/$id/send-now', {});
  }

  Future<void> unsubscribe(String id) async {
    await _api.delete('/neighborhood/$id');
    await load();
  }
}
