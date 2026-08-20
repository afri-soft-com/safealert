import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../utils/network_error.dart';
import 'auth_provider.dart';

class AdminProvider extends ChangeNotifier {
  final ApiService _api;

  AdminProvider({ApiService? apiService}) : _api = apiService ?? ApiService();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _partners = [];
  List<Map<String, dynamic>> _subscriptions = [];
  bool _loadingUsers = false;
  bool _loadingPartners = false;
  bool _loadingSubs = false;
  String? _error;
  int _usersTotal = 0;
  int _usersPage = 1;
  int _subsTotal = 0;
  int _subsPage = 1;

  List<Map<String, dynamic>> get users => _users;
  List<Map<String, dynamic>> get partners => _partners;
  List<Map<String, dynamic>> get subscriptions => _subscriptions;
  bool get loadingUsers => _loadingUsers;
  bool get loadingPartners => _loadingPartners;
  bool get loadingSubs => _loadingSubs;
  String? get error => _error;
  int get usersTotal => _usersTotal;
  int get usersPage => _usersPage;
  int get subsTotal => _subsTotal;
  int get subsPage => _subsPage;

  static const roleLabels = UserRoles.labels;

  Future<void> fetchUsers({int page = 1}) async {
    _loadingUsers = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.get('/admin/users?page=$page&limit=20');
      _users = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _usersTotal = res['total'] as int? ?? _users.length;
      _usersPage = res['page'] as int? ?? page;
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de charger les utilisateurs.');
      _users = [];
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
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de charger les partenaires.');
      _partners = [];
    }
    _loadingPartners = false;
    notifyListeners();
  }

  Future<bool> updateUserRole(String userId, String role) async {
    try {
      await _api.patch('/admin/users/$userId/role', {'role': role});
      await fetchUsers(page: _usersPage);
      return true;
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de modifier le rôle.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> setUserActive(String userId, bool active) async {
    try {
      await _api.patch('/admin/users/$userId/active', {'is_active': active});
      await fetchUsers(page: _usersPage);
      return true;
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de mettre à jour le compte.');
      notifyListeners();
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
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de révoquer le partenaire.');
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchSubscriptions({int page = 1}) async {
    _loadingSubs = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.get('/admin/premium?page=$page&limit=20&status=all');
      _subscriptions = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _subsTotal = res['total'] as int? ?? _subscriptions.length;
      _subsPage = res['page'] as int? ?? page;
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de charger les abonnements.');
      _subscriptions = [];
    }
    _loadingSubs = false;
    notifyListeners();
  }

  Future<bool> grantPremium(String userId, {int days = 30}) async {
    try {
      await _api.post('/premium/grant', {'user_id': userId, 'days': days});
      await fetchSubscriptions(page: _subsPage);
      await fetchUsers(page: _usersPage);
      return true;
    } catch (e) {
      _error = userFacingError(e, fallback: "Impossible d'accorder l'abonnement.");
      notifyListeners();
      return false;
    }
  }

  Future<bool> grantPremiumByQuery(String query, {int days = 30}) async {
    try {
      final found = await _api.get('/admin/users?page=1&limit=5&q=${Uri.encodeComponent(query)}');
      final data = (found['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (data.isEmpty) {
        _error = 'Aucun utilisateur trouvé.';
        notifyListeners();
        return false;
      }
      return grantPremium(data.first['id'] as String, days: days);
    } catch (e) {
      _error = userFacingError(e, fallback: "Impossible d'accorder l'abonnement.");
      notifyListeners();
      return false;
    }
  }

  Future<bool> revokePremium(String userId) async {
    try {
      await _api.post('/premium/revoke', {'user_id': userId});
      await fetchSubscriptions(page: _subsPage);
      await fetchUsers(page: _usersPage);
      return true;
    } catch (e) {
      _error = userFacingError(e, fallback: "Impossible de révoquer l'abonnement.");
      notifyListeners();
      return false;
    }
  }
}
