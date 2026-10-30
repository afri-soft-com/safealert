import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Remote kill switch / feature flags from GET /api/app/config.
class AppConfigService {
  AppConfigService._();
  static final AppConfigService instance = AppConfigService._();
  factory AppConfigService() => instance;

  final ApiService _api = ApiService();

  bool maintenance = false;
  bool sosEnabled = true;
  String maintenanceBanner = '';
  Map<String, dynamic> features = {};
  Map<String, bool> homeTiles = {};
  DateTime? _lastFetch;

  Future<void> refresh({bool force = false}) async {
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 2)) {
      return;
    }
    try {
      final data = await _api.get('/app/config');
      maintenance = data['maintenance'] == true;
      sosEnabled = data['sosEnabled'] != false;
      maintenanceBanner = (data['maintenanceBanner'] as String?)?.trim() ?? '';
      final f = data['features'];
      if (f is Map) {
        features = Map<String, dynamic>.from(f);
        final tiles = f['homeTiles'];
        if (tiles is Map) {
          homeTiles = tiles.map(
            (k, v) => MapEntry(k.toString(), v != false),
          );
        }
      }
      _lastFetch = DateTime.now();
    } catch (e) {
      debugPrint('AppConfigService: $e');
    }
  }

  bool get canSendSos => sosEnabled && !maintenance;

  /// Carte de chaleur (`FEATURE_HEATMAP`, défaut on).
  bool get heatmapEnabled => features['heatmap'] != false;
  bool get fakeCallEnabled => features['fakeCall'] != false;
  bool get arrivalTimerEnabled => features['arrivalTimer'] != false;
  bool get sosAudioEnabled => features['sosAudio'] != false;
  bool get sosPublicShareEnabled => features['sosPublicShare'] != false;
  bool get liveCirclesEnabled => features['liveCircles'] != false;
  bool get neighborhoodWatchEnabled => features['neighborhoodWatch'] != false;
  bool get trustZonesEnabled => features['trustZones'] != false;
  bool get safeTripEnabled => features['safeTrip'] != false;

  /// Home tile visibility (admin Services SafeAlert). Defaults to visible.
  bool tileVisible(String key) {
    if (homeTiles.containsKey(key)) return homeTiles[key] == true;
    switch (key) {
      case 'heatmap':
        return heatmapEnabled;
      case 'fake_call':
        return fakeCallEnabled;
      case 'safety_ping':
        return arrivalTimerEnabled;
      case 'live_circles':
        return liveCirclesEnabled;
      case 'neighborhood':
        return neighborhoodWatchEnabled;
      case 'trust_zones':
        return trustZonesEnabled;
      case 'trip':
        return safeTripEnabled;
      default:
        return true;
    }
  }
}
