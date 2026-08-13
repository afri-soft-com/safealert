import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../utils/network_error.dart';

class SafetyPingProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _active;
  List<Map<String, dynamic>> _history = [];
  bool _loading = false;
  String? _error;

  Map<String, dynamic>? get active => _active;
  List<Map<String, dynamic>> get history => _history;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> fetchActive() async {
    try {
      final res = await _api.get('/safety-pings/active');
      _active = res['id'] == null ? null : res;
      notifyListeners();
    } catch (_) {
      _active = null;
    }
  }

  Future<void> fetchHistory() async {
    try {
      final res = await _api.get('/safety-pings/mine');
      _history = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> schedule({
    int inMinutes = 60,
    int windowMinutes = 15,
    bool notifyGroups = false,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.post('/safety-pings', {
        'in_minutes': inMinutes,
        'window_minutes': windowMinutes,
        'notify_groups': notifyGroups,
      });
      _active = res['ping'] as Map<String, dynamic>?;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de planifier le contrôle.');
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> confirmOk() async {
    if (_active == null || _active!['id'] == null) return false;
    try {
      await _api.post('/safety-pings/${_active!['id']}/ok', {});
      _active = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = userFacingError(e, fallback: 'Confirmation impossible.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancel() async {
    if (_active == null || _active!['id'] == null) return false;
    try {
      await _api.post('/safety-pings/${_active!['id']}/cancel', {});
      _active = null;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
