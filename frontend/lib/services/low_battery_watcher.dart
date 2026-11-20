import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'location_service.dart';

/// Warns trust contacts when the phone is almost empty during a trip or SOS.
///
/// Checks the battery every 2 minutes while logged in. At [threshold] % or
/// less (and not charging) it posts the last position to /battery/low; the
/// server only notifies if a trip or SOS is active, once every 6 h.
class LowBatteryWatcher {
  static final LowBatteryWatcher _instance = LowBatteryWatcher._();
  LowBatteryWatcher._();
  factory LowBatteryWatcher() => _instance;

  static const threshold = 5;
  static const _checkEvery = Duration(minutes: 2);
  /// After a server answer, wait before asking again (it has its own cooldown).
  static const _retryAfter = Duration(minutes: 30);

  final Battery _battery = Battery();
  Timer? _timer;
  DateTime? _lastSent;
  bool _checking = false;

  void start() {
    _timer ??= Timer.periodic(_checkEvery, (_) => check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastSent = null;
  }

  @visibleForTesting
  static bool shouldReport({
    required int level,
    required BatteryState state,
    DateTime? lastSent,
    DateTime? now,
  }) {
    if (level < 0 || level > threshold) return false;
    if (state == BatteryState.charging || state == BatteryState.full) return false;
    final t = now ?? DateTime.now();
    return lastSent == null || t.difference(lastSent) >= _retryAfter;
  }

  Future<void> check() async {
    if (_checking || !ApiService().hasToken) return;
    _checking = true;
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      if (!shouldReport(level: level, state: state, lastSent: _lastSent)) return;
      _lastSent = DateTime.now();
      final resolved = await LocationService().getPositionWithSource(urgent: true);
      final pos = resolved.position;
      await ApiService().post('/battery/low', {
        'battery_pct': level,
        if (pos != null) 'lat': pos.latitude,
        if (pos != null) 'lng': pos.longitude,
      });
    } catch (e) {
      debugPrint('LowBatteryWatcher: $e');
    } finally {
      _checking = false;
    }
  }
}
