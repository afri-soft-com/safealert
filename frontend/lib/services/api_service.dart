import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/network_error.dart';

class ApiService {
  /// Production Render. Override at build time for local dev:
  /// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://safealert-api.onrender.com/api',
  );

  /// Délai réseau (cold start Render peut dépasser 60 s).
  static const Duration requestTimeout = Duration(seconds: 90);

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

  static final ApiService _instance = ApiService._();
  ApiService._();
  factory ApiService() => _instance;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  bool get hasToken => _token != null;
  String? get token => _token;

  Future<void> setToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  Future<Map<String, dynamic>> get(String path) async {
    final res = await http
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(requestTimeout);
    return _handle(res);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
        .timeout(requestTimeout);
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

export '../utils/network_error.dart' show ApiException;
