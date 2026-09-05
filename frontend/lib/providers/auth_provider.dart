import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../utils/phone.dart';
import '../utils/network_error.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../services/local_pin_service.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';
import '../services/trip_tracking_service.dart';

/// Routes nécessitant une authentification (US-14 mode invité).
const kAuthRequiredScreens = {
  'home', 'sos', 'contacts', 'dashboard', 'settings', 'leader', 'groups',
  'history', 'admin', 'trip', 'escort_map', 'trust_zones', 'neighborhood',
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
  final LocalPinService _pin;

  AuthProvider({ApiService? apiService, LocalPinService? pinService})
      : _api = apiService ?? ApiService(),
        _pin = pinService ?? LocalPinService();
  bool _loading = false;
  bool _isAuthenticated = false;
  bool _isGuest = false;
  Map<String, dynamic>? _user;
  String? _error;
  String? _phone;
  String? _devCode;
  bool _hasLocalPin = false;
  bool _pinUnlocked = false;
  bool _needsPinSetup = false;
  String? _pinPhone;

  bool get loading => _loading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isGuest => _isGuest;
  Map<String, dynamic>? get user => _user;
  String? get error => _error;
  String? get phone => _phone;
  /// OTP de test renvoyé par l'API en dev quand SMS n'est pas configuré.
  String? get devCode => _devCode;
  bool get hasLocalPin => _hasLocalPin;
  bool get pinUnlocked => _pinUnlocked;
  bool get needsPinSetup => _needsPinSetup;
  bool get needsPinUnlock => _hasLocalPin && !_pinUnlocked;
  String? get pinPhone => _pinPhone;
  /// Session serveur valide et barrière PIN locale franchie.
  bool get canEnterApp =>
      _isAuthenticated && !_needsPinSetup && (!_hasLocalPin || _pinUnlocked);

  String get role => _user?['role'] as String? ?? UserRoles.citizen;
  String get roleLabel => UserRoles.labels[role] ?? 'Citoyen';
  bool get isCitizen => role == UserRoles.citizen;
  bool get isLeader => role == UserRoles.leader;
  bool get isAgent => role == UserRoles.agent;
  bool get isPlatformAdmin => role == UserRoles.platformAdmin;
  bool get isAdmin => role == UserRoles.admin;
  bool get canAccessOps => isLeader || isAgent || isAdmin || isPlatformAdmin;
  bool get canAccessAdmin => isAdmin || isPlatformAdmin;

  Future<void> _refreshPinState() async {
    try {
      _hasLocalPin = await _pin.hasPin();
      _pinPhone = await _pin.storedPhone();
    } catch (_) {
      _hasLocalPin = false;
      _pinPhone = null;
    }
  }

  Future<void> loadPinState() async {
    await _refreshPinState();
    notifyListeners();
  }

  Future<void> checkAuth() async {
    await _api.init();
    await _refreshPinState();
    if (_api.hasToken) {
      try {
        final res = await _api.get('/auth/profile');
        _user = res;
        _isAuthenticated = true;
        _isGuest = false;
        final profilePhone = res['phone'] as String?;
        if (_hasLocalPin) {
          _pinUnlocked = false;
          if (profilePhone != null && _pinPhone != null && profilePhone != _pinPhone) {
            await _pin.clear();
            await _refreshPinState();
            _needsPinSetup = true;
          }
        } else {
          _needsPinSetup = true;
        }
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
      await _refreshPinState();
      final storedPhone = _pinPhone;
      if (storedPhone != null && storedPhone != _phone) {
        await _pin.clear();
        await _refreshPinState();
      }
      // Après tout OTP réussi : créer ou renouveler le PIN local (pas de SMS ensuite).
      _needsPinSetup = true;
      _pinUnlocked = false;
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
      kAuthRequiredScreens.contains(screen) && !canEnterApp;

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

  Future<bool> setLocalPin(String pin, {required String confirm}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    if (pin != confirm) {
      _error = 'Les codes PIN ne correspondent pas';
      _loading = false;
      notifyListeners();
      return false;
    }
    final phone = _phone ?? _user?['phone'] as String? ?? _pinPhone;
    if (phone == null || phone.isEmpty) {
      _error = 'Numéro introuvable. Recommencez la connexion.';
      _loading = false;
      notifyListeners();
      return false;
    }
    try {
      await _pin.setPin(pin, phone: phone);
      await _refreshPinState();
      _needsPinSetup = false;
      _pinUnlocked = true;
      _loading = false;
      notifyListeners();
      return true;
    } on ArgumentError catch (e) {
      _error = e.message?.toString() ?? 'Le code PIN doit contenir 4 à 6 chiffres';
      _loading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Impossible d\'enregistrer le code PIN';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _pin.verify(pin);
      if (!ok) {
        _error = 'Code PIN incorrect';
        _loading = false;
        notifyListeners();
        return false;
      }
      _pinUnlocked = true;
      _needsPinSetup = false;
      _loading = false;
      if (!_isAuthenticated) {
        _error =
            'Session expirée. Utilisez « Code PIN oublié » pour recevoir un code par SMS.';
        notifyListeners();
        return false;
      }
      notifyListeners();
      return true;
    } catch (_) {
      _error = 'Impossible de vérifier le code PIN';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Demande un OTP SMS uniquement pour réinitialiser le PIN (même numéro).
  Future<bool> requestForgotPinCode() async {
    final phone = _pinPhone ?? _phone ?? _user?['phone'] as String?;
    if (phone == null || phone.isEmpty) {
      _error = 'Aucun numéro enregistré. Saisissez votre numéro.';
      notifyListeners();
      return false;
    }
    return requestCode(phone);
  }

  Future<void> clearLocalPin() async {
    await _pin.clear();
    await _refreshPinState();
    _needsPinSetup = _isAuthenticated;
    _pinUnlocked = false;
    notifyListeners();
  }

  Future<void> logout() async {
    _stopRealtimeServices();
    await _api.clearToken();
    _user = null;
    _isAuthenticated = false;
    _isGuest = false;
    _phone = null;
    _devCode = null;
    _pinUnlocked = false;
    _needsPinSetup = false;
    await _refreshPinState();
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

  bool get _skipRealtimeSideEffects {
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      return false;
    }
  }

  void _startRealtimeServices() {
    if (_skipRealtimeSideEffects) return;
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
