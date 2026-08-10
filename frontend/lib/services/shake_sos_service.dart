import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// SOS discret par secousse (3 secousses fortes en ~2 s).
class ShakeSOSService {
  static StreamSubscription? _sub;
  static VoidCallback? _onTrigger;
  static final List<DateTime> _shakes = [];
  static bool _armed = true;

  static void init(VoidCallback onTrigger) {
    if (kIsWeb) return;
    _onTrigger = onTrigger;
    _sub?.cancel();
    _sub = accelerometerEventStream().listen((event) {
      final g = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      // ~2.7g spike
      if (g > 27) {
        final now = DateTime.now();
        _shakes.removeWhere((t) => now.difference(t).inMilliseconds > 2000);
        _shakes.add(now);
        if (_shakes.length >= 3 && _armed) {
          _armed = false;
          _shakes.clear();
          _onTrigger?.call();
          Future.delayed(const Duration(seconds: 8), () => _armed = true);
        }
      }
    }, onError: (_) {});
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
