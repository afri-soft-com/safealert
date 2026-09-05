import 'package:flutter/foundation.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  final ApiService _api = ApiService();
  bool _isAuthenticated = false;
  Map<String, dynamic>? _user;

  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get user => _user;

  Future<void> checkAuth() async {
    await _api.init();
    if (_api.hasToken) {
      try {
        final res = await _api.get('/auth/profile');
        _user = res;
        _isAuthenticated = true;
      } catch (_) {
        await _api.clearToken();
      }
    }
    notifyListeners();
  }

  Future<void> requestCode(String phone) async {
    await _api.post('/auth/request-code', {'phone': phone});
  }

  Future<void> verifyCode(String phone, String code, {String? pseudo, bool isNewAccount = false}) async {
    final res = await _api.post('/auth/verify-code', {
      'phone': phone,
      'code': code,
      'isNewAccount': isNewAccount,
      if (isNewAccount && pseudo != null && pseudo.trim().isNotEmpty) 'pseudo': pseudo.trim(),
    });
    await _api.setToken(res['token'] as String);
    _user = res['user'] as Map<String, dynamic>;
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> logout() async {
    await _api.clearToken();
    _user = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}
