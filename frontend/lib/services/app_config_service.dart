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
      if (f is Map) features = Map<String, dynamic>.from(f);
      _lastFetch = DateTime.now();
    } catch (e) {
      debugPrint('AppConfigService: $e');
    }
  }

  bool get canSendSos => sosEnabled && !maintenance;
}
