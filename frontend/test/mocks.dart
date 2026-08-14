import 'package:sqflite/sqflite.dart';
import 'package:safealert/services/api_service.dart';
import 'package:safealert/services/local_database.dart';

class _CacheEntry {
  final dynamic data;
  final int cachedAt;
  _CacheEntry(this.data, this.cachedAt);
}

class FakeLocalDatabase implements LocalDatabase {
  final Map<String, _CacheEntry> _store = {};
  final List<Map<String, dynamic>> _pending = [];
  int _pendingSeq = 0;

  @override
  Future<Database> get database async => throw UnimplementedError('use in-memory fake');

  @override
  Future<void> put(String key, dynamic data, {int? ttlSeconds}) async {
    _store[key] = _CacheEntry(data, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Future<dynamic> get(String key, {int? maxAgeSeconds}) async {
    final entry = _store[key];
    if (entry == null) return null;
    if (maxAgeSeconds != null) {
      final age = DateTime.now().millisecondsSinceEpoch - entry.cachedAt;
      if (age > maxAgeSeconds * 1000) {
        _store.remove(key);
        return null;
      }
    }
    return entry.data;
  }

  @override
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }

  @override
  Future<int> enqueuePendingSos(Map<String, dynamic> payload) async {
    return enqueue('sos', payload);
  }

  @override
  Future<int> enqueue(String kind, Map<String, dynamic> payload) async {
    final id = ++_pendingSeq;
    _pending.add({
      'id': id,
      'kind': kind,
      'payload': Map<String, dynamic>.from(payload),
      'attempts': 0,
    });
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> listPendingSos() async {
    return listPending(kind: 'sos');
  }

  @override
  Future<List<Map<String, dynamic>>> listPending({String? kind, bool dueOnly = false}) async {
    final rows = kind == null
        ? _pending
        : _pending.where((r) => r['kind'] == kind);
    final now = DateTime.now().millisecondsSinceEpoch;
    return rows
        .where((r) {
          if (!dueOnly) return true;
          final next = (r['next_attempt_at'] as int?) ?? 0;
          return next <= now;
        })
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  @override
  Future<void> removePendingSos(int id) async {
    await removePending(id);
  }

  @override
  Future<void> removePending(int id) async {
    _pending.removeWhere((r) => r['id'] == id);
  }

  @override
  Future<void> bumpPendingSosAttempt(int id) async {
    await bumpPendingAttempt(id);
  }

  @override
  Future<void> bumpPendingAttempt(int id) async {
    for (final row in _pending) {
      if (row['id'] == id) {
        final attempts = ((row['attempts'] as int?) ?? 0) + 1;
        row['attempts'] = attempts;
        final delaySec = (30 * (1 << (attempts - 1).clamp(0, 6))).clamp(30, 1800);
        row['next_attempt_at'] = DateTime.now().millisecondsSinceEpoch + delaySec * 1000;
        return;
      }
    }
  }
}

class FakeApiService implements ApiService {
  bool _hasToken = false;
  String? _token;
  String? lastPath;
  Map<String, dynamic>? lastBody;

  final Map<String, Map<String, dynamic> Function()> _getResponses = {};
  final Map<String, Map<String, dynamic> Function()> _postResponses = {};
  final Map<String, Map<String, dynamic> Function()> _putResponses = {};
  final Map<String, Map<String, dynamic> Function()> _patchResponses = {};
  final Map<String, Map<String, dynamic> Function()> _deleteResponses = {};

  @override
  bool get hasToken => _hasToken;

  @override
  String? get token => _token;

  @override
  String? get deviceId => 'test-device';

  @override
  Future<String> ensureDeviceId() async => 'test-device';

  void onGet(String path, Map<String, dynamic> Function() response) {
    _getResponses[path] = response;
  }

  void onPost(String path, Map<String, dynamic> Function() response) {
    _postResponses[path] = response;
  }

  void onPut(String path, Map<String, dynamic> Function() response) {
    _putResponses[path] = response;
  }

  void onPatch(String path, Map<String, dynamic> Function() response) {
    _patchResponses[path] = response;
  }

  void onDelete(String path, Map<String, dynamic> Function() response) {
    _deleteResponses[path] = response;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> setToken(String token) async {
    _token = token;
    _hasToken = true;
  }

  @override
  Future<void> clearToken() async {
    _token = null;
    _hasToken = false;
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    lastPath = path;
    final factory = _getResponses[path];
    if (factory != null) return factory();
    throw Exception('Not stubbed: GET $path');
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    lastPath = path;
    lastBody = body;
    final factory = _postResponses[path];
    if (factory != null) return factory();
    throw Exception('Not stubbed: POST $path');
  }

  @override
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    lastPath = path;
    lastBody = body;
    final factory = _putResponses[path];
    if (factory != null) return factory();
    throw Exception('Not stubbed: PUT $path');
  }

  @override
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    lastPath = path;
    lastBody = body;
    final factory = _patchResponses[path];
    if (factory != null) return factory();
    throw Exception('Not stubbed: PATCH $path');
  }

  @override
  Future<Map<String, dynamic>> delete(String path) async {
    lastPath = path;
    final factory = _deleteResponses[path];
    if (factory != null) return factory();
    throw Exception('Not stubbed: DELETE $path');
  }
}
