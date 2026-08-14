import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._();
  LocationService._();
  factory LocationService() => _instance;

  final ApiService _api = ApiService();
  Timer? _timer;
  bool sharePresence = true;

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
    final current = await getCurrentPosition();
    if (current != null && !_isNullIsland(current.latitude, current.longitude)) {
      await _cacheGoodPosition(current.latitude, current.longitude);
      return current;
    }

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && !_isNullIsland(last.latitude, last.longitude)) {
        await _cacheGoodPosition(last.latitude, last.longitude);
        return last;
      }
    } catch (_) {}

    return _cachedPosition();
  }

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

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
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

  Future<void> updatePosition(double lat, double lng) async {
    if (!_api.hasToken || !sharePresence) return;
    if (_isNullIsland(lat, lng)) return;
    try {
      await _api.put('/auth/position', {'lat': lat, 'lng': lng});
      await _cacheGoodPosition(lat, lng);
    } catch (_) {}
  }

  Future<void> syncCurrentPosition() async {
    final pos = await getCurrentPosition();
    if (pos != null) {
      await updatePosition(pos.latitude, pos.longitude);
    }
  }

  void startPeriodicUpdates({Duration interval = const Duration(minutes: 2)}) {
    if (!sharePresence) return;
    _timer?.cancel();
    syncCurrentPosition();
    _timer = Timer.periodic(interval, (_) => syncCurrentPosition());
  }

  void stopPeriodicUpdates() {
    _timer?.cancel();
    _timer = null;
  }
}
