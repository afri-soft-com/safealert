import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// GPS continu d'un trajet actif, y compris hors de l'écran Trajet
/// (notification Android de type foreground service).
class TripTrackingService {
  static final TripTrackingService _instance = TripTrackingService._();
  TripTrackingService._();
  factory TripTrackingService() => _instance;

  StreamSubscription<Position>? _sub;
  Future<void> Function(double lat, double lng)? _onPosition;
  DateTime? _lastEmitAt;

  static const _minInterval = Duration(seconds: 15);

  bool get isRunning => _sub != null;

  Future<bool> start({
    required Future<void> Function(double lat, double lng) onPosition,
  }) async {
    _onPosition = onPosition;
    if (_sub != null) return true;

    final permission = await _ensurePermission();
    if (!permission) return false;

    try {
      _sub = Geolocator.getPositionStream(
        locationSettings: _settings(),
      ).listen(
        _handlePosition,
        onError: (e) => debugPrint('TripTracking GPS error: $e'),
        cancelOnError: false,
      );
      return true;
    } catch (e) {
      debugPrint('TripTracking start failed: $e');
      _sub = null;
      return false;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _onPosition = null;
    _lastEmitAt = null;
  }

  void _handlePosition(Position pos) {
    if (pos.latitude.abs() < 0.0001 && pos.longitude.abs() < 0.0001) return;
    final now = DateTime.now();
    if (_lastEmitAt != null && now.difference(_lastEmitAt!) < _minInterval) {
      return;
    }
    _lastEmitAt = now;
    final cb = _onPosition;
    if (cb == null) return;
    unawaited(cb(pos.latitude, pos.longitude));
  }

  LocationSettings _settings() {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Trajet sécurisé SafeAlert',
          notificationText:
              'Suivi GPS en cours — vos contacts voient votre position',
          notificationChannelName: 'Trajet sécurisé',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
  }

  Future<bool> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }
}
