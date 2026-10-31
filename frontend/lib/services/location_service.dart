import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'local_database.dart';

class LocationService {
  static final LocationService _instance = LocationService._();
  LocationService._();
  factory LocationService() => _instance;

  final ApiService _api = ApiService();
  final LocalDatabase _offline = LocalDatabase();
  Timer? _timer;
  StreamSubscription<Position>? _circleStream;
  bool sharePresence = true;
  bool _circleLiveForce = false;

  static const _cacheLatKey = 'last_good_lat';
  static const _cacheLngKey = 'last_good_lng';

  bool _isNullIsland(double lat, double lng) =>
      lat.abs() < 0.0001 && lng.abs() < 0.0001;

  Future<void> _cacheGoodPosition(double lat, double lng) async {
    if (_isNullIsland(lat, lng)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_cacheLatKey, lat);
    await prefs.setDouble(_cacheLngKey, lng);
  }

  Future<Position?> _cachedPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_cacheLatKey);
    final lng = prefs.getDouble(_cacheLngKey);
    if (lat == null || lng == null || _isNullIsland(lat, lng)) return null;
    return Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 999,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  /// Best-effort GPS for SOS: current → lastKnown → cached local → null.
  /// Never returns 0,0.
  Future<Position?> getPositionForSos() async {
    final resolved = await getPositionWithSource();
    return resolved.position;
  }

  /// Same cascade as [getPositionForSos], with a source label for UI messages.
  /// Sources: `gps` | `last_known` | `cache` | `none`.
  Future<({Position? position, String source})> getPositionWithSource() async {
    final current = await getCurrentPosition();
    if (current != null && !_isNullIsland(current.latitude, current.longitude)) {
      await _cacheGoodPosition(current.latitude, current.longitude);
      return (position: current, source: 'gps');
    }

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && !_isNullIsland(last.latitude, last.longitude)) {
        await _cacheGoodPosition(last.latitude, last.longitude);
        return (position: last, source: 'last_known');
      }
    } catch (_) {}

    final cached = await _cachedPosition();
    if (cached != null) return (position: cached, source: 'cache');
    return (position: null, source: 'none');
  }

  /// Why [getCurrentPosition] / cascade may fail (for UI copy).
  Future<String> diagnoseLocationBlocker() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'Le GPS / la localisation du téléphone est désactivé. Activez-le dans les réglages système.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return 'Permission de localisation refusée. Autorisez SafeAlert à accéder à la position.';
      }
      if (permission == LocationPermission.deniedForever) {
        return 'Permission de localisation bloquée. Ouvrez les réglages de l’app → Autorisations → Localisation.';
      }
      return 'Position introuvable pour le moment (signal GPS faible). Sortez à découvert ou réessayez dans quelques secondes.';
    } catch (_) {
      return 'Impossible d’accéder à la localisation. Vérifiez GPS et permissions SafeAlert.';
    }
  }

  Future<bool> openAppLocationSettings() => Geolocator.openAppSettings();

  Future<bool> openSystemLocationSettings() => Geolocator.openLocationSettings();

  Future<Position?> getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // Prefer a fresh fix; medium accuracy is more reliable indoors / under canopy.
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 15),
          ),
        );
        if (!_isNullIsland(pos.latitude, pos.longitude)) {
          await _cacheGoodPosition(pos.latitude, pos.longitude);
          return pos;
        }
      } catch (_) {
        // Fall through to high-accuracy short attempt.
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!_isNullIsland(pos.latitude, pos.longitude)) {
        await _cacheGoodPosition(pos.latitude, pos.longitude);
      }
      return pos;
    } catch (_) {
      return null;
    }
  }

  /// [force] bypasses the local `sharePresence` gate (caller must ensure the
  /// server allows the write — e.g. after enabling share_presence for a circle).
  Future<void> updatePosition(double lat, double lng, {bool force = false}) async {
    if (!_api.hasToken) return;
    if (!force && !_circleLiveForce && !sharePresence) return;
    if (_isNullIsland(lat, lng)) return;
    try {
      await _api.put('/auth/position', {'lat': lat, 'lng': lng});
      await _cacheGoodPosition(lat, lng);
    } catch (_) {
      // Circle / presence share: keep latest GPS for sync when back online.
      if (force || _circleLiveForce || sharePresence) {
        try {
          await _offline.enqueueCoalesced('position', {
            'lat': lat,
            'lng': lng,
            'at': DateTime.now().toUtc().toIso8601String(),
          });
          await _cacheGoodPosition(lat, lng);
        } catch (_) {}
      }
    }
  }

  Future<void> syncCurrentPosition({bool force = false}) async {
    final pos = await getCurrentPosition();
    if (pos != null) {
      await updatePosition(pos.latitude, pos.longitude, force: force || _circleLiveForce);
    }
  }

  void startPeriodicUpdates({Duration interval = const Duration(minutes: 2)}) {
    if (!sharePresence && !_circleLiveForce) return;
    _timer?.cancel();
    syncCurrentPosition(force: _circleLiveForce);
    _timer = Timer.periodic(interval, (_) => syncCurrentPosition(force: _circleLiveForce));
  }

  /// Live circle share: GPS stream + frequent push so family map moves with you.
  void startCircleLiveShare({
    Duration heartbeat = const Duration(seconds: 15),
    int distanceFilterMeters = 15,
  }) {
    _circleLiveForce = true;
    sharePresence = true;
    _timer?.cancel();
    _circleStream?.cancel();
    syncCurrentPosition(force: true);
    _timer = Timer.periodic(heartbeat, (_) => syncCurrentPosition(force: true));
    try {
      _circleStream = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
        ),
      ).listen(
        (pos) {
          if (_isNullIsland(pos.latitude, pos.longitude)) return;
          updatePosition(pos.latitude, pos.longitude, force: true);
        },
        onError: (_) {},
      );
    } catch (_) {
      // Stream unavailable — heartbeat timer still pushes.
    }
  }

  void stopCircleLiveShare() {
    _circleLiveForce = false;
    _circleStream?.cancel();
    _circleStream = null;
    // Keep a slower presence timer if global share is on.
    if (sharePresence) {
      startPeriodicUpdates();
    } else {
      stopPeriodicUpdates();
    }
  }

  void stopPeriodicUpdates() {
    _timer?.cancel();
    _timer = null;
    _circleStream?.cancel();
    _circleStream = null;
    _circleLiveForce = false;
  }
}
