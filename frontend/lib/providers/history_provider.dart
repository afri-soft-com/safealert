import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/local_database.dart';

class HistoryProvider extends ChangeNotifier {
  final ApiService _api;
  final LocalDatabase _cache;

  HistoryProvider({ApiService? apiService, LocalDatabase? localDatabase})
      : _api = apiService ?? ApiService(),
        _cache = localDatabase ?? LocalDatabase();
  List<Map<String, dynamic>> _history = [];
  bool _loading = false;
  bool _isOffline = false;

  List<Map<String, dynamic>> get history => _history;
  bool get loading => _loading;
  bool get isOffline => _isOffline;

  Future<void> fetchHistory() async {
    _loading = true;
    _isOffline = false;
    notifyListeners();
    try {
      final res = await _api.get('/history');
      _history = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      await _cache.put('history', _history);
    } catch (_) {
      final cached = await _cache.get('history', maxAgeSeconds: 300);
      if (cached != null) {
        _history = (cached as List).cast<Map<String, dynamic>>();
        _isOffline = true;
      } else {
        _history = [];
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> cancelSOS(int id) async {
    try {
      await _api.post('/sos/$id/cancel', {});
      await fetchHistory();
      return true;
    } catch (_) {
      return false;
    }
  }

  String statusLabel(String? status) {
    switch (status) {
      case 'active': return 'Actif';
      case 'resolved': return 'Résolu';
      case 'false_alarm': return 'Fausse alerte';
      default: return status ?? 'Inconnu';
    }
  }

  String typeIcon(String? type) {
    switch (type) {
      case 'sos': return '🚨';
      case 'sos_discret': return '🤫';
      case 'vol': return '💰';
      case 'agression': return '👊';
      case 'accident': return '🚗';
      case 'incendie': return '🔥';
      case 'autre': return '📌';
      default: return '📍';
    }
  }
}
