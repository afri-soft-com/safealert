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

  static const int _cacheTtlSeconds = 86400; // 24 h (US-12)

  Future<void> fetchNumbers({String? country}) async {
    final cacheKey = country != null ? 'annuaire_$country' : 'annuaire';

    final cached = await _cache.get(cacheKey, maxAgeSeconds: _cacheTtlSeconds);
    if (cached != null) {
      _numbers = (cached as List).cast<Map<String, dynamic>>();
      notifyListeners();
    }

    _loading = _numbers.isEmpty;
    _isOffline = false;
    notifyListeners();
    try {
      String path = '/annuaire';
      if (country != null) path += '?country=$country';
      final res = await _api.get(path);
      _numbers = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      await _cache.put(cacheKey, _numbers);
    } catch (_) {
      if (_numbers.isEmpty) {
        final fallback = await _cache.get(cacheKey, maxAgeSeconds: _cacheTtlSeconds);
        if (fallback != null) {
          _numbers = (fallback as List).cast<Map<String, dynamic>>();
        }
      }
      _isOffline = _numbers.isNotEmpty;
    }
    _loading = false;
    notifyListeners();
  }
}