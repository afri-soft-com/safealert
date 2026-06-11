import 'package:flutter/foundation.dart';
import '../utils/phone.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';

/// Routes nécessitant une authentification (US-14 mode invité).
const kAuthRequiredScreens = {
  'home', 'sos', 'contacts', 'dashboard', 'settings', 'leader', 'groups', 'history', 'privacy', 'admin', 'help',
};

class AuthProvider extends ChangeNotifier {
  final ApiService _api;

  AuthProvider({ApiService? apiService}) : _api = apiService ?? ApiService();
  bool _loading = false;
  bool _isAuthenticated = false;
  bool _isGuest = false;
  Map<String, dynamic>? _user;
  String? _error;
  String? _phone;
  String? _devCode;

  bool get loading => _loading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isGuest => _isGuest;
  Map<String, dynamic>? get user => _user;
  String? get error => _error;
  String? get phone => _phone;
  /// OTP de test renvoyé par l'API en dev quand SMS n'est pas configuré.
  String? get devCode => _devCode;

  Future<void> checkAuth() async {
    await _api.init();
    if (_api.hasToken) {
      try {
        final res = await _api.get('/auth/profile');
        _user = res;
        _isAuthenticated = true;
        _isGuest = false;
        _applyPrivacySettings();
        _startRealtimeServices();
      } catch (_) {
        await _api.clearToken();
      }
    }
    notifyListeners();
  }

  Future<bool> requestCode(String phone) async {
    _loading = true;
    _error = null;
    notifyListeners();
    final normalized = normalizePhone(phone);
    if (normalized == null) {
      _error = 'Numéro de téléphone invalide';
      _loading = false;
      notifyListeners();
      return false;
    }
    try {
      final res = await _api.post('/auth/request-code', {'phone': normalized});
      _phone = normalized;
      _devCode = res['devCode'] as String?;
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Erreur réseau';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyCode(String code, {String? pseudo}) async {
    if (_phone == null) return false;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.post('/auth/verify-code', {
        'phone': _phone!,
        'code': code,
        if (pseudo != null) 'pseudo': pseudo,
      });
      await _api.setToken(res['token'] as String);
      _user = res['user'] as Map<String, dynamic>;
      _isAuthenticated = true;
      _isGuest = false;
      _loading = false;
      notifyListeners();
      FCMService().uploadToken();
      _applyPrivacySettings();
      _startRealtimeServices();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Erreur réseau';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  void enterGuestMode() {
    _isGuest = true;
    _isAuthenticated = false;
    _user = null;
    notifyListeners();
  }

  void exitGuestMode() {
    _isGuest = false;
    notifyListeners();
  }

  bool requiresAuth(String screen) =>
      kAuthRequiredScreens.contains(screen) && !_isAuthenticated;

  Future<bool> updateProfile({bool? isDiscreetMode, bool? sharePresence}) async {
    if (!_isAuthenticated) return false;
    try {
      final body = <String, dynamic>{};
      if (isDiscreetMode != null) body['is_discreet_mode'] = isDiscreetMode;
      if (sharePresence != null) body['share_presence'] = sharePresence;
      final res = await _api.put('/auth/profile', body);
      _user = res;
      _applyPrivacySettings();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get isDiscreetMode => _user?['is_discreet_mode'] as bool? ?? false;
  bool get sharePresence => _user?['share_presence'] as bool? ?? true;

  void _applyPrivacySettings() {
    LocationService().sharePresence = sharePresence;
  }

  Future<void> logout() async {
    _stopRealtimeServices();
    await _api.clearToken();
    _user = null;
    _isAuthenticated = false;
    _isGuest = false;
    _phone = null;
    _devCode = null;
    LocationService().sharePresence = true;
    notifyListeners();
  }

  void _startRealtimeServices() {
    SocketService().connect();
    LocationService().startPeriodicUpdates();
  }

  void _stopRealtimeServices() {
    SocketService().disconnect();
    LocationService().stopPeriodicUpdates();
  }
}
