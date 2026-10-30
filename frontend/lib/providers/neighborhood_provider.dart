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

  static int clampHour(int hour) => hour.clamp(0, 23);

  static int clampMinute(int minute) {
    if (digestMinuteSlots.contains(minute)) return minute;
    // Snap to nearest lower slot
    if (minute < 0) return 0;
    if (minute >= 45) return 45;
    if (minute >= 30) return 30;
    if (minute >= 15) return 15;
    return 0;
  }

  /// Kinshasa = UTC+1 fixed (no DST). Convert local wall-clock → Kinshasa.
  static ({int hour, int minute}) localToKinshasa(int hour, int minute) {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day, hour, minute);
    final kinshasa = local.toUtc().add(const Duration(hours: 1));
    return (hour: kinshasa.hour, minute: kinshasa.minute);
  }

  /// Kinshasa wall-clock → device local wall-clock.
  static ({int hour, int minute}) kinshasaToLocal(int hour, int minute) {
    final now = DateTime.now();
    final asUtc = DateTime.utc(now.year, now.month, now.day, hour, minute)
        .subtract(const Duration(hours: 1));
    final local = asUtc.toLocal();
    return (hour: local.hour, minute: local.minute);
  }

  static String formatHm(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Next 15-min slot at least [minAhead] minutes from now (local).
  static ({int hour, int minute}) nextLocalSlot({int minAhead = 5}) {
    final target = DateTime.now().add(Duration(minutes: minAhead));
    var h = target.hour;
    var m = ((target.minute + 14) ~/ 15) * 15;
    if (m >= 60) {
      m = 0;
      h = (h + 1) % 24;
    }
    // If still in the past relative to now+minAhead within same hour snap
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

  Future<void> subscribe(String quartier, int digestHour, [int digestMinute = 0]) async {
    final k = localToKinshasa(clampHour(digestHour), clampMinute(digestMinute));
    await _api.post('/neighborhood/subscribe', {
      'quartier': quartier.trim(),
      'digest_hour': k.hour,
      'digest_minute': clampMinute(k.minute),
    });
    await load();
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
