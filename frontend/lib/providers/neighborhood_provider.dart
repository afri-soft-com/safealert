import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class NeighborhoodProvider extends ChangeNotifier {
  NeighborhoodProvider({ApiService? apiService}) : _api = apiService ?? ApiService();

  final ApiService _api;
  List<Map<String, dynamic>> _subscriptions = [];
  bool _loading = false;

  List<Map<String, dynamic>> get subscriptions => _subscriptions;
  bool get loading => _loading;

  static int clampHour(int hour) => hour.clamp(0, 23);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get('/neighborhood');
      _subscriptions = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      _subscriptions = [];
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> subscribe(String quartier, int digestHour) async {
    await _api.post('/neighborhood/subscribe', {
      'quartier': quartier.trim(),
      'digest_hour': clampHour(digestHour),
    });
    await load();
  }

  Future<void> updateHour(String id, int digestHour) async {
    await _api.patch('/neighborhood/$id', {
      'digest_hour': clampHour(digestHour),
    });
    await load();
  }

  Future<void> unsubscribe(String id) async {
    await _api.delete('/neighborhood/$id');
    await load();
  }
}
