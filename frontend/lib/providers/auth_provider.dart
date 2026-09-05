import 'package:flutter/foundation.dart';
import '../utils/phone.dart';
import '../utils/network_error.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';
import '../services/trip_tracking_service.dart';

/// Routes nécessitant une authentification (US-14 mode invité).
const kAuthRequiredScreens = {
  'home', 'sos', 'contacts', 'dashboard', 'settings', 'leader', 'groups',
  'history', 'privacy', 'admin', 'help', 'trip', 'escort_map', 'trust_zones', 'neighborhood',
  'offline_queue', 'safety_ping', 'premium',
};

/// Écrans réservés aux responsables / agents (secteur).
const kLeaderScreens = {'leader'};

/// Écrans réservés à l'administrateur plateforme.
const kAdminScreens = {'admin'};

/// Rôles plateforme SafeAlert (chaînes API).
abstract final class UserRoles {
  static const citizen = 'citizen';
  static const leader = 'leader';
  static const agent = 'agent';
  static const admin = 'admin';
  static const platformAdmin = 'platform_admin';

  static const labels = {
    citizen: 'Citoyen',
    leader: 'Responsable',
    agent: 'Agent',
    admin: 'Administrateur',
    platformAdmin: 'Super administrateur',
  };
}

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

  String get role => _user?['role'] as String? ?? UserRoles.citizen;
  String get roleLabel => UserRoles.labels[role] ?? 'Citoyen';
  bool get isCitizen => role == UserRoles.citizen;
  bool get isLeader => role == UserRoles.leader;
  bool get isAgent => role == UserRoles.agent;
  bool get isPlatformAdmin => role == UserRoles.platformAdmin;
  bool get isAdmin => role == UserRoles.admin;
  bool get canAccessOps => isLeader || isAgent || isAdmin || isPlatformAdmin;
  bool get canAccessAdmin => isAdmin || isPlatformAdmin;

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
    } catch (e) {
      _error = userFacingError(e);
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
      final deviceId = await _api.ensureDeviceId();
      final res = await _api.post('/auth/verify-code', {
        'phone': _phone!,
        'code': code,
        if (pseudo != null) 'pseudo': pseudo,
        'device_id': deviceId,
        'device_label': defaultTargetPlatform.name,
      });
      await _api.setToken(res['token'] as String);
      if (res['deviceId'] != null) {
        // server may echo device id
      }
      _user = res['user'] as Map<String, dynamic>;
      _isAuthenticated = true;
      _isGuest = false;
      _loading = false;
      notifyListeners();
      FCMService().uploadToken();
      _applyPrivacySettings();
      _startRealtimeServices();
      return true;
    } catch (e) {
      _error = userFacingError(e);
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

  /// Garde d'accès par rôle (complément de [requiresAuth]).
  bool canAccessScreen(String screen) {
    if (requiresAuth(screen)) return false;
    if (kAdminScreens.contains(screen) && !canAccessAdmin) return false;
    if (kLeaderScreens.contains(screen) && !canAccessOps) return false;
    return true;
  }

  Future<bool> updateProfile({bool? isDiscreetMode, bool? sharePresence, bool? sosNotifyGroups}) async {
    if (!_isAuthenticated) return false;
    try {
      final body = <String, dynamic>{};
      if (isDiscreetMode != null) body['is_discreet_mode'] = isDiscreetMode;
      if (sharePresence != null) body['share_presence'] = sharePresence;
      if (sosNotifyGroups != null) body['sos_notify_groups'] = sosNotifyGroups;
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
  bool get sosNotifyGroups => _user?['sos_notify_groups'] as bool? ?? true;

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

  /// Déconnecter tous les autres appareils (garde la session actuelle).
  Future<bool> revokeAllOtherSessions() async {
    try {
      await _api.post('/auth/sessions/revoke-all', {'keep_current': true});
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startRealtimeServices() {
    final id = _user?['id']?.toString();
    SocketService().connect(userId: id);
    FCMService().setCurrentUserId(id);
    LocationService().startPeriodicUpdates();
  }

  void _stopRealtimeServices() {
    FCMService().setCurrentUserId(null);
    SocketService().disconnect();
    LocationService().stopPeriodicUpdates();
    TripTrackingService().stop();
  }

  /// Test helper: authenticated session without socket/location side effects.
  @visibleForTesting
  void setSessionForTest(Map<String, dynamic> user) {
    _user = Map<String, dynamic>.from(user);
    _isAuthenticated = true;
    _isGuest = false;
    _error = null;
    notifyListeners();
  }
}
