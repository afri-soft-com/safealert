import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._();
  LocationService._();
  factory LocationService() => _instance;

  final ApiService _api = ApiService();
  Timer? _timer;
  bool sharePresence = true;

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

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> updatePosition(double lat, double lng) async {
    if (!_api.hasToken || !sharePresence) return;
    try {
      await _api.put('/auth/position', {'lat': lat, 'lng': lng});
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
