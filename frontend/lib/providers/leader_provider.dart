import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/local_database.dart';

class LeaderProvider extends ChangeNotifier {
  final ApiService _api;
  final LocalDatabase _cache;

  LeaderProvider({ApiService? apiService, LocalDatabase? localDatabase})
      : _api = apiService ?? ApiService(),
        _cache = localDatabase ?? LocalDatabase();
  List<Map<String, dynamic>> _incidents = [];
  Map<String, dynamic>? _stats;
  bool _loading = false;
  bool _isOffline = false;

  List<Map<String, dynamic>> get incidents => _incidents;
  Map<String, dynamic>? get stats => _stats;
  bool get loading => _loading;
  bool get isOffline => _isOffline;

  Future<void> fetchSectorIncidents() async {
    _loading = true;
    _isOffline = false;
    notifyListeners();
    try {
      final res = await _api.get('/leader/sector/incidents');
      _incidents = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      await _cache.put('sector_incidents', _incidents);
    } catch (_) {
      final cached = await _cache.get('sector_incidents', maxAgeSeconds: 300);
      if (cached != null) {
        _incidents = (cached as List).cast<Map<String, dynamic>>();
        _isOffline = true;
      } else {
        _incidents = [];
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchSectorStats() async {
    try {
      final res = await _api.get('/leader/sector/stats');
      _stats = res;
      await _cache.put('sector_stats', _stats);
      notifyListeners();
    } catch (_) {
      final cached = await _cache.get('sector_stats', maxAgeSeconds: 600);
      if (cached != null) {
        _stats = cached as Map<String, dynamic>;
        _isOffline = true;
        notifyListeners();
      }
    }
  }

  Future<bool> acknowledgeIncident(String id) async {
    try {
      await _api.put('/leader/sector/incidents/$id/acknowledge', {});
      await fetchSectorIncidents();
      await fetchSectorStats();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resolveIncident(String id) async {
    try {
      await _api.put('/leader/sector/incidents/$id/resolve', {});
      await fetchSectorIncidents();
      await fetchSectorStats();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> assignAgent(String incidentId, String agentId, {int? etaMinutes}) async {
    try {
      await _api.post('/leader/incidents/$incidentId/assign', {
        'agent_id': agentId,
        if (etaMinutes != null) 'eta_minutes': etaMinutes,
      });
      await fetchSectorIncidents();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> markEnRoute(String incidentId, {int? etaMinutes}) async {
    try {
      await _api.post('/leader/incidents/$incidentId/en-route', {
        if (etaMinutes != null) 'eta_minutes': etaMinutes,
      });
      await fetchSectorIncidents();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> closeWithReason(String incidentId, String reason, {bool falseAlarm = false}) async {
    try {
      await _api.post('/leader/incidents/$incidentId/close', {
        'reason': reason,
        if (falseAlarm) 'status': 'false_alarm',
      });
      await fetchSectorIncidents();
      await fetchSectorStats();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchChat(String incidentId) async {
    try {
      final res = await _api.get('/leader/incidents/$incidentId/chat');
      return (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> postChat(String incidentId, String body) async {
    try {
      await _api.post('/leader/incidents/$incidentId/chat', {'body': body});
      return true;
    } catch (_) {
      return false;
    }
  }
}