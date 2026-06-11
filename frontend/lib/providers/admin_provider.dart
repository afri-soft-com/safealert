import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class AdminProvider extends ChangeNotifier {
  final ApiService _api;

  AdminProvider({ApiService? apiService}) : _api = apiService ?? ApiService();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _partners = [];
  bool _loadingUsers = false;
  bool _loadingPartners = false;
  String? _error;
  int _usersTotal = 0;
  int _usersPage = 1;

  List<Map<String, dynamic>> get users => _users;
  List<Map<String, dynamic>> get partners => _partners;
  bool get loadingUsers => _loadingUsers;
  bool get loadingPartners => _loadingPartners;
  String? get error => _error;
  int get usersTotal => _usersTotal;
  int get usersPage => _usersPage;

  static const roleLabels = {
    'citizen': 'Citoyen',
    'leader': 'Responsable',
    'agent': 'Agent',
    'platform_admin': 'Administrateur',
  };

  Future<void> fetchUsers({int page = 1}) async {
    _loadingUsers = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.get('/admin/users?page=$page&limit=20');
      _users = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _usersTotal = res['total'] as int? ?? _users.length;
      _usersPage = res['page'] as int? ?? page;
    } on ApiException catch (e) {
      _error = e.message;
      _users = [];
    } catch (_) {
      _error = 'Erreur réseau';
    }
    _loadingUsers = false;
    notifyListeners();
  }

  Future<void> fetchPartners() async {
    _loadingPartners = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.get('/admin/partners');
      _partners = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } on ApiException catch (e) {
      _error = e.message;
      _partners = [];
    } catch (_) {
      _error = 'Erreur réseau';
    }
    _loadingPartners = false;
    notifyListeners();
  }

  Future<bool> updateUserRole(String userId, String role) async {
    try {
      await _api.patch('/admin/users/$userId/role', {'role': role});
      await fetchUsers(page: _usersPage);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateUserSector(String userId, String? sector) async {
    try {
      await _api.patch('/admin/users/$userId/sector', {'sector_name': sector ?? ''});
      await fetchUsers(page: _usersPage);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> createPartner(String name) async {
    try {
      final res = await _api.post('/admin/partners', {'partner_name': name});
      await fetchPartners();
      return res['api_key'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<bool> revokePartner(String id) async {
    try {
      await _api.delete('/admin/partners/$id');
      await fetchPartners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
