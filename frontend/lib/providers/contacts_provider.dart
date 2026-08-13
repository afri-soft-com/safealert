import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/local_database.dart';

class ContactsProvider extends ChangeNotifier {
  final ApiService _api;
  final LocalDatabase _cache;

  ContactsProvider({ApiService? apiService, LocalDatabase? localDatabase})
      : _api = apiService ?? ApiService(),
        _cache = localDatabase ?? LocalDatabase();
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = false;
  bool _isOffline = false;

  List<Map<String, dynamic>> get contacts => _contacts;
  bool get loading => _loading;
  bool get isOffline => _isOffline;

  Future<void> fetchContacts() async {
    _loading = true;
    _isOffline = false;
    notifyListeners();
    try {
      final res = await _api.get('/contacts');
      final raw = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _contacts = raw.map((c) {
        final m = Map<String, dynamic>.from(c);
        m['is_online'] = m['is_online'] == true || m['status'] == 'online';
        return m;
      }).toList();
      await _cache.put('contacts', _contacts);
    } catch (_) {
      final cached = await _cache.get('contacts', maxAgeSeconds: 3600);
      if (cached != null) {
        _contacts = (cached as List).cast<Map<String, dynamic>>();
        _isOffline = true;
      } else {
        _contacts = [];
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> addContact(String name, String phone) async {
    try {
      await _api.post('/contacts', {'contact_name': name, 'contact_phone': phone});
      await fetchContacts();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteContact(String id) async {
    try {
      await _api.delete('/contacts/$id');
      await fetchContacts();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> createInvite({int ttlHours = 48}) async {
    try {
      return await _api.post('/invites/circle', {'ttl_hours': ttlHours, 'max_uses': 5});
    } catch (_) {
      return null;
    }
  }

  Future<bool> acceptInvite(String code) async {
    try {
      await _api.post('/invites/circle/accept', {'code': code.trim().toUpperCase()});
      await fetchContacts();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCache() async {
    await _cache.remove('contacts');
    _contacts = [];
    notifyListeners();
  }
}