import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/local_database.dart';

class AnnuaireProvider extends ChangeNotifier {
  final ApiService _api;
  final LocalDatabase _cache;

  AnnuaireProvider({ApiService? apiService, LocalDatabase? localDatabase})
      : _api = apiService ?? ApiService(),
        _cache = localDatabase ?? LocalDatabase();
  List<Map<String, dynamic>> _numbers = [];
  bool _loading = false;
  bool _isOffline = false;

  List<Map<String, dynamic>> get numbers => _numbers;
  bool get loading => _loading;
  bool get isOffline => _isOffline;

  Future<void> fetchNumbers({String? country}) async {
    _loading = true;
    _isOffline = false;
    notifyListeners();
    try {
      String path = '/annuaire';
      if (country != null) path += '?country=$country';
      final res = await _api.get(path);
      _numbers = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      await _cache.put('annuaire', _numbers);
    } catch (_) {
      final cached = await _cache.get('annuaire', maxAgeSeconds: 86400);
      if (cached != null) {
        _numbers = (cached as List).cast<Map<String, dynamic>>();
        _isOffline = true;
      } else {
        _numbers = [];
      }
    }
    _loading = false;
    notifyListeners();
  }
}