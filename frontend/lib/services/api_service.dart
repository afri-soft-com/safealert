import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/network_error.dart';
import 'session_file.dart';

export '../utils/network_error.dart' show ApiException;

class ApiService {
  /// Production Render. Override at build time for local dev:
  /// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://safealert-api.onrender.com/api',
  );

  /// Délai réseau (cold start Render peut dépasser 60 s).
  static const Duration requestTimeout = Duration(seconds: 90);

  static const _tokenKey = 'auth_token';
  static const _deviceIdKey = 'device_id';
  static const _migratedKey = 'secure_token_migrated_v1';

  /// Socket.io server origin (API base URL without `/api` suffix).
  static String get socketOrigin {
    if (baseUrl.endsWith('/api')) {
      return baseUrl.substring(0, baseUrl.length - 4);
    }
    final uri = Uri.parse(baseUrl);
    if (uri.hasPort) return '${uri.scheme}://${uri.host}:${uri.port}';
    return '${uri.scheme}://${uri.host}';
  }

  String? _token;
  String? _deviceId;
  /// iOS: after-first-unlock, this device only, not iCloud.
  /// iCloud Keychain and WhenUnlocked both drop the JWT when iOS kills the app.
  /// Android: encrypted shared prefs. Always mirror token in SharedPreferences.
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  static final ApiService _instance = ApiService._();
  ApiService._();
  factory ApiService() => _instance;

  bool get _isWidgetTest {
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      return false;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isWidgetTest) {
      _token = prefs.getString(_tokenKey);
      _deviceId = prefs.getString(_deviceIdKey);
      return;
    }
    final stored = await SessionFile.read();
    final fileToken = stored['token']?.toString();
    final fileDevice = stored['deviceId']?.toString();
    if (fileToken != null && fileToken.isNotEmpty) {
      _token = fileToken;
    }
    if (fileDevice != null && fileDevice.isNotEmpty) {
      _deviceId = fileDevice;
    }

    String? secureToken;
    try {
      await _migrateTokenIfNeeded(prefs);
      secureToken = await _secure.read(key: _tokenKey);
      _deviceId ??= await _secure.read(key: _deviceIdKey);
    } catch (_) {
      /* Keychain can throw before first unlock — fall through to prefs. */
    }
    var prefsToken = prefs.getString(_tokenKey);
    if (prefsToken == null || prefsToken.isEmpty) {
      try {
        await prefs.reload();
        prefsToken = prefs.getString(_tokenKey);
      } catch (_) {}
    }
    _token ??= (prefsToken != null && prefsToken.isNotEmpty)
        ? prefsToken
        : (secureToken != null && secureToken.isNotEmpty ? secureToken : null);
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = prefs.getString(_deviceIdKey);
    }
    if (_token != null && _token != fileToken) {
      await SessionFile.merge({'token': _token, 'deviceId': _deviceId});
    }
  }

  /// Copy legacy prefs → Keychain once, but KEEP the prefs mirror for resilience.
  Future<void> _migrateTokenIfNeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_migratedKey) == true) return;

    try {
      final legacyToken = prefs.getString(_tokenKey);
      final existingSecure = await _secure.read(key: _tokenKey);
      if ((existingSecure == null || existingSecure.isEmpty) &&
          legacyToken != null &&
          legacyToken.isNotEmpty) {
        await _secure.write(key: _tokenKey, value: legacyToken);
      }
      // Do NOT remove prefs token — dual storage avoids silent iOS logouts.
      await prefs.setBool(_migratedKey, true);
    } catch (_) {
      prefs.setBool(_migratedKey, false);
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  bool get hasToken => _token != null;
  String? get token => _token;
  String? get deviceId => _deviceId;

  Future<String> ensureDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = await _secure.read(key: _deviceIdKey) ?? prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = 'dev-${DateTime.now().millisecondsSinceEpoch}-${prefs.hashCode.abs()}';
    }
    _deviceId = id;
    await SessionFile.merge({'deviceId': id, if (_token != null) 'token': _token});
    try {
      await _secure.write(key: _deviceIdKey, value: id);
    } catch (_) {}
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  Future<void> setToken(String token) async {
    _token = token;
    // Flush to disk first. iOS can kill the app before Keychain/UserDefaults
    // finish writing, which dropped the session on the next launch.
    await SessionFile.merge({'token': token, 'deviceId': _deviceId});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    try {
      await _secure.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  Future<void> clearToken() async {
    _token = null;
    await SessionFile.remove(const ['token']);
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<Map<String, dynamic>> get(String path) async {
    final res = await http
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(requestTimeout);
    return _handle(res);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final res = await http
        .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
        .timeout(timeout ?? requestTimeout);
    return _handle(res);
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final res = await http
        .put(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
        .timeout(requestTimeout);
    return _handle(res);
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final res = await http
        .patch(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
        .timeout(requestTimeout);
    return _handle(res);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final res = await http
        .delete(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(requestTimeout);
    return _handle(res);
  }

  Map<String, dynamic> _handle(http.Response res) {
    dynamic body;
    try {
      body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    } catch (_) {
      throw ApiException('Réponse serveur invalide', res.statusCode);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (body is List) return {'data': body, 'message': 'ok'};
      if (body is Map) return body as Map<String, dynamic>;
    }
    if (body is Map && body.containsKey('error')) {
      final raw = body['error'] as String? ?? '';
      final mapped = mapKnownApiMessage(raw);
      final message = mapped ??
          (!looksTechnical(raw) && raw.isNotEmpty
              ? raw
              : messageForStatusCode(res.statusCode));
      throw ApiException(message, res.statusCode);
    }
    throw ApiException(messageForStatusCode(res.statusCode), res.statusCode);
  }
}
