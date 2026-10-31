import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/phone.dart';
import '../utils/network_error.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../services/local_pin_service.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';
import '../services/trip_tracking_service.dart';
import '../services/google_sign_in_service.dart';
import '../services/apple_auth_service.dart';

const _kCachedUserKey = 'safealert_cached_user_v1';
/// Persists across app kills: false only after explicit « Verrouiller ».
const _kSessionUnlockedKey = 'safealert_session_unlocked_v1';

/// Routes nécessitant une authentification (US-14 mode invité).
const kAuthRequiredScreens = {
  'home', 'sos', 'contacts', 'dashboard', 'settings', 'leader', 'groups',
  'history', 'admin', 'trip', 'escort_map', 'trust_zones', 'live_circles',
  'neighborhood', 'neighborhood_digest', 'incoming_sos',
  'offline_queue', 'safety_ping', 'safety_ping_missed', 'premium',
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
  final GoogleSignInService _google;

  AuthProvider({
    ApiService? apiService,
    LocalPinService? pinService,
    GoogleSignInService? googleSignIn,
  })  : _api = apiService ?? ApiService(),
        _pin = pinService ?? LocalPinService(),
        _google = googleSignIn ?? GoogleSignInService();
  bool _loading = false;
  bool _isAuthenticated = false;
  bool _isGuest = false;
  Map<String, dynamic>? _user;
  String? _error;
  String? _phone;
  String? _devCode;
  String? _otpHint;
  bool? _lastSmsSent;
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
  /// Hint after OTP request (SMS sent / code shown when SMS failed).
  String? get otpHint => _otpHint;
  bool? get lastSmsSent => _lastSmsSent;

  /// Surface a gate message (e.g. CGU not accepted) without starting a network call.
  void setLoginGateError(String message) {
    _error = message;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
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

  Future<void> _cacheUser(Map<String, dynamic>? user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user == null) {
        await prefs.remove(_kCachedUserKey);
      } else {
        await prefs.setString(_kCachedUserKey, jsonEncode(user));
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCachedUserKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<bool> _readSessionUnlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Default true: closing the app must not force the PIN screen.
      return prefs.getBool(_kSessionUnlockedKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _writeSessionUnlocked(bool unlocked) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSessionUnlockedKey, unlocked);
    } catch (_) {}
  }

  Future<void> _applyPinGateAfterAuth() async {
    if (_hasLocalPin) {
      _needsPinSetup = false;
      _pinUnlocked = await _readSessionUnlocked();
    } else {
      _needsPinSetup = true;
      _pinUnlocked = false;
    }
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
        await _cacheUser(res);
        final profilePhone = res['phone'] as String?;
        final identity = (profilePhone != null && profilePhone.isNotEmpty)
            ? profilePhone
            : res['id']?.toString();
        if (_hasLocalPin) {
          _needsPinSetup = false;
          if (identity != null && _pinPhone != null && identity != _pinPhone) {
            await _pin.clear();
            await _refreshPinState();
            _needsPinSetup = true;
            _pinUnlocked = false;
            await _writeSessionUnlocked(false);
          } else {
            _pinUnlocked = await _readSessionUnlocked();
          }
        } else {
          _needsPinSetup = true;
          _pinUnlocked = false;
        }
        _applyPrivacySettings();
        if (!_hasLocalPin || _pinUnlocked) {
          _startRealtimeServices();
        }
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          // Session revoked / expired — full sign-out.
          await _api.clearToken();
          await _cacheUser(null);
          await _writeSessionUnlocked(false);
          _user = null;
          _isAuthenticated = false;
        } else {
          // Keep token on API errors (5xx, 429…) — restore from cache if possible.
          await _restoreCachedSessionKeepingToken();
        }
      } catch (_) {
        // Network / timeout: never wipe the token on app open.
        await _restoreCachedSessionKeepingToken();
      }
    }
    notifyListeners();
  }

  Future<void> _restoreCachedSessionKeepingToken() async {
    final cached = await _loadCachedUser();
    if (cached == null) {
      _isAuthenticated = _api.hasToken;
      await _applyPinGateAfterAuth();
      return;
    }
    _user = cached;
    _isAuthenticated = true;
    _isGuest = false;
    await _applyPinGateAfterAuth();
    _applyPrivacySettings();
  }

  /// Lock behind PIN without clearing the server session (explicit « Verrouiller »).
  Future<void> lockSession() async {
    if (!_hasLocalPin) return;
    _pinUnlocked = false;
    await _writeSessionUnlocked(false);
    _stopRealtimeServices();
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
      final exposed = res['devCode'] ?? res['codeOtp'];
      _devCode = exposed?.toString();
      final smsOk = res['smsEnvoye'] == true;
      _lastSmsSent = smsOk;
      if (smsOk) {
        _otpHint = 'Code envoyé par SMS. Vérifiez vos messages (et le spam).';
        _error = null;
      } else if (_devCode != null && _devCode!.isNotEmpty) {
        _otpHint = 'SMS non délivré — saisissez ce code : $_devCode';
        _error = _otpHint;
      } else {
        _otpHint =
            'SMS non reçu. Réessayez dans une minute ou vérifiez le numéro +243.';
        _error = _otpHint;
      }
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = userFacingError(e);
      _otpHint = null;
      _lastSmsSent = null;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyCode(String code, {String? pseudo, bool isNewAccount = false}) async {
    if (_phone == null) return false;
    if (isNewAccount && (pseudo == null || pseudo.trim().isEmpty)) {
      _error = 'Pseudo requis pour créer un compte';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final deviceId = await _api.ensureDeviceId();
      final res = await _api.post('/auth/verify-code', {
        'phone': _phone!,
        'code': code,
        'isNewAccount': isNewAccount,
        if (isNewAccount && pseudo != null && pseudo.trim().isNotEmpty) 'pseudo': pseudo.trim(),
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
      await _cacheUser(_user);
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
      return true;
    } catch (e) {
      _error = userFacingError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  String? get _pinIdentity {
    final phone = _phone ?? _user?['phone'] as String?;
    if (phone != null && phone.isNotEmpty) return phone;
    final id = _user?['id'] as String?;
    if (id != null && id.isNotEmpty) return id;
    return _pinPhone;
  }

  Future<bool> loginWithGoogle({Future<String?> Function()? obtainIdToken}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final token = obtainIdToken != null
          ? await obtainIdToken()
          : await _google.signInIdToken();
      if (token == null) {
        // Should be rare with google_sign_in 7 authenticate(); never leave UI blank.
        _error =
            'Connexion Google fermée sans compte. Si vous n’avez pas annulé, '
            'vérifiez OAuth/SHA (Web client be940).';
        _loading = false;
        notifyListeners();
        return false;
      }
      if (token.isEmpty) {
        _error =
            'Connexion Google mal configurée (jeton manquant). Vérifiez l’identifiant client Web.';
        _loading = false;
        notifyListeners();
        return false;
      }
      final deviceId = await _api.ensureDeviceId();
      final res = await _api.post('/auth/google', {
        'idToken': token,
        'device_id': deviceId,
        'device_label': defaultTargetPlatform.name,
      });
      await _api.setToken(res['token'] as String);
      _user = res['user'] as Map<String, dynamic>;
      _phone = _user?['phone'] as String?;
      _isAuthenticated = true;
      _isGuest = false;
      await _cacheUser(_user);
      await _refreshPinState();
      final identity = _pinIdentity;
      final stored = _pinPhone;
      if (stored != null && identity != null && stored != identity) {
        await _pin.clear();
        await _refreshPinState();
      }
      _needsPinSetup = true;
      _pinUnlocked = false;
      _loading = false;
      notifyListeners();
      FCMService().uploadToken();
      _applyPrivacySettings();
      return true;
    } catch (e) {
      final mapped = mapGoogleSignInError(e);
      _error = mapped ?? userFacingError(e);
      if (mapped == null &&
          (e.toString().toLowerCase().contains('cancel') ||
              e.toString().toLowerCase().contains('12501'))) {
        _error = null;
      }
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sign in with Apple (iOS — App Store guideline 4.8 when Google is offered).
  Future<bool> loginWithApple() async {
    if (!AppleAuthService.isAvailable) {
      _error = 'Connexion Apple disponible uniquement sur iOS';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final cred = await AppleAuthService.obtainCredentials();
      if (cred == null) {
        _error = 'Connexion Apple annulée ou indisponible';
        _loading = false;
        notifyListeners();
        return false;
      }
      final deviceId = await _api.ensureDeviceId();
      final res = await _api.post('/auth/apple', {
        'identityToken': cred.identityToken,
        if (cred.fullName != null && cred.fullName!.isNotEmpty) 'fullName': cred.fullName,
        'device_id': deviceId,
        'device_label': defaultTargetPlatform.name,
      });
      await _api.setToken(res['token'] as String);
      _user = res['user'] as Map<String, dynamic>;
      _phone = _user?['phone'] as String?;
      _isAuthenticated = true;
      _isGuest = false;
      await _cacheUser(_user);
      await _refreshPinState();
      final identity = _pinIdentity;
      final stored = _pinPhone;
      if (stored != null && identity != null && stored != identity) {
        await _pin.clear();
        await _refreshPinState();
      }
      _needsPinSetup = true;
      _pinUnlocked = false;
      _loading = false;
      notifyListeners();
      FCMService().uploadToken();
      _applyPrivacySettings();
      return true;
    } catch (e) {
      _error = AppleAuthService.errorMessage(e);
      if (_error!.toLowerCase().contains('annul')) {
        _error = null;
      }
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> linkPhone(String phone, String code) async {
    final normalized = normalizePhone(phone);
    if (normalized == null) {
      _error = 'Numéro de téléphone invalide';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.post('/auth/link-phone', {
        'phone': normalized,
        'code': code,
      });
      final user = res['user'];
      if (user is Map<String, dynamic>) {
        _user = user;
        _phone = user['phone'] as String?;
      }
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
    final phone = _pinIdentity;
    if (phone == null || phone.isEmpty) {
      _error = 'Compte introuvable. Recommencez la connexion.';
      _loading = false;
      notifyListeners();
      return false;
    }
    try {
      await _pin.setPin(pin, phone: phone);
      await _refreshPinState();
      _needsPinSetup = false;
      _pinUnlocked = true;
      await _writeSessionUnlocked(true);
      _startRealtimeServices();
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
      if (!_isAuthenticated) {
        final restored = await _restoreSessionFromStoredToken();
        if (!restored) {
          _pinUnlocked = false;
          await _writeSessionUnlocked(false);
          _error =
              'Session expirée. Un code SMS est nécessaire. Utilisez « Code PIN oublié ».';
          _loading = false;
          notifyListeners();
          return false;
        }
      }
      await _writeSessionUnlocked(true);
      _startRealtimeServices();
      _loading = false;
      notifyListeners();
      return true;
    } catch (_) {
      _error = 'Impossible de vérifier le code PIN';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _restoreSessionFromStoredToken() async {
    await _api.init();
    if (!_api.hasToken) return false;
    try {
      final res = await _api.get('/auth/profile');
      _user = res;
      _isAuthenticated = true;
      _isGuest = false;
      await _cacheUser(res);
      _applyPrivacySettings();
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _api.clearToken();
        await _cacheUser(null);
        return false;
      }
      // Soft failure: use cache if present.
      final cached = await _loadCachedUser();
      if (cached != null) {
        _user = cached;
        _isAuthenticated = true;
        _isGuest = false;
        _applyPrivacySettings();
        return true;
      }
      return false;
    } catch (_) {
      final cached = await _loadCachedUser();
      if (cached != null) {
        _user = cached;
        _isAuthenticated = true;
        _isGuest = false;
        _applyPrivacySettings();
        return true;
      }
      return false;
    }
  }

  /// Demande un OTP SMS uniquement pour réinitialiser le PIN (même numéro).
  Future<bool> requestForgotPinCode() async {
    final phone = _pinPhone ?? _phone ?? _user?['phone'] as String?;
    if (phone == null || phone.isEmpty) {
      _error =
          'Aucun numéro associé. Reconnectez-vous avec Google, ou associez un +243 dans Paramètres.';
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

  /// Verrouille l'app derrière le PIN. Garde le jeton et le PIN (pas de SMS).
  Future<void> logout() async {
    await _refreshPinState();
    await lockSession();
    _isGuest = false;
    _devCode = null;
    _otpHint = null;
    _lastSmsSent = null;
    if (_hasLocalPin) {
      _needsPinSetup = false;
    } else if (_isAuthenticated) {
      _needsPinSetup = true;
    }
    LocationService().sharePresence = true;
    notifyListeners();
  }

  /// Déconnexion complète : efface jeton + PIN. Prochaine fois = SMS / OAuth.
  Future<void> switchPhone() async {
    _stopRealtimeServices();
    await _api.clearToken();
    await _cacheUser(null);
    await _writeSessionUnlocked(false);
    await _pin.clear();
    _user = null;
    _isAuthenticated = false;
    _isGuest = false;
    _phone = null;
    _devCode = null;
    _otpHint = null;
    _lastSmsSent = null;
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
