import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Notifications reçues (push), y compris celles manquées hors de l'app.
class InboxService extends ChangeNotifier {
  InboxService._();
  static final InboxService instance = InboxService._();
  factory InboxService() => instance;

  final ApiService _api = ApiService();
  List<Map<String, dynamic>> items = [];
  int unread = 0;
  bool loading = false;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      await _api.init();
      if (!_api.hasToken) {
        items = [];
        unread = 0;
        return;
      }
      final res = await _api.get('/inbox');
      final list = res['data'];
      items = list is List
          ? list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];
      final rawUnread = res['unread'];
      unread = rawUnread is int
          ? rawUnread
          : items.where((e) => e['read_at'] == null).length;
    } catch (e) {
      debugPrint('InboxService refresh: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _api.post('/inbox/$id/read', {});
    } catch (_) {}
    await refresh();
  }

  Future<void> markAllRead() async {
    try {
      await _api.post('/inbox/read-all', {});
    } catch (_) {}
    await refresh();
  }
}
