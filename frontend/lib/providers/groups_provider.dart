import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/local_database.dart';

class GroupsProvider extends ChangeNotifier {
  final ApiService _api;
  final LocalDatabase _cache;

  GroupsProvider({ApiService? apiService, LocalDatabase? localDatabase})
      : _api = apiService ?? ApiService(),
        _cache = localDatabase ?? LocalDatabase();
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> _discoverable = [];
  final Map<String, List<Map<String, dynamic>>> _joinRequestsByGroup = {};
  final Map<String, List<Map<String, dynamic>>> _membersByGroup = {};
  final Map<String, List<Map<String, dynamic>>> _messagesByGroup = {};
  final Map<String, List<Map<String, dynamic>>> _alertsByGroup = {};
  bool _loading = false;
  bool _isOffline = false;
  String? _lastJoinMessage;
  String? _lastError;

  List<Map<String, dynamic>> get myGroups => _myGroups;
  List<Map<String, dynamic>> get discoverable => _discoverable;
  bool get loading => _loading;
  bool get isOffline => _isOffline;
  String? get lastJoinMessage => _lastJoinMessage;
  String? get lastError => _lastError;

  /// Accepts raw code, safealert://group/CODE, or https://…/g/CODE.
  static String normalizeInviteCode(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final uriMatch = RegExp(
      r'(?:/(?:group|g)/|^group/)([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(s);
    if (uriMatch != null) return uriMatch.group(1)!.toUpperCase();
    return s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  int get totalPendingRequests => _myGroups.fold<int>(
        0,
        (sum, g) => sum + ((g['pending_requests'] as int?) ?? 0),
      );

  List<Map<String, dynamic>> joinRequestsFor(String groupId) =>
      _joinRequestsByGroup[groupId] ?? [];

  List<Map<String, dynamic>> membersFor(String groupId) =>
      _membersByGroup[groupId] ?? [];

  List<Map<String, dynamic>> messagesFor(String groupId) =>
      _messagesByGroup[groupId] ?? [];

  List<Map<String, dynamic>> alertsFor(String groupId) =>
      _alertsByGroup[groupId] ?? [];

  /// Robust JSON list → maps (avoids silent empty lists from `.cast` failures).
  static List<Map<String, dynamic>> mapList(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map && raw['data'] is List
            ? raw['data']
            : (raw is Map && raw['messages'] is List ? raw['messages'] : null));
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> fetchMyGroups() async {
    _loading = true;
    _isOffline = false;
    notifyListeners();
    try {
      final res = await _api.get('/groups');
      _myGroups = mapList(res['data'] ?? res);
      await _cache.put('my_groups', _myGroups);
    } catch (_) {
      final cached = await _cache.get('my_groups', maxAgeSeconds: 600);
      if (cached != null) {
        _myGroups = mapList(cached);
        _isOffline = true;
      } else {
        _myGroups = [];
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchDiscoverable() async {
    try {
      final res = await _api.get('/groups/discover');
      _discoverable = mapList(res['data'] ?? res);
      await _cache.put('discover_groups', _discoverable);
      notifyListeners();
    } catch (_) {
      final cached = await _cache.get('discover_groups', maxAgeSeconds: 600);
      if (cached != null) {
        _discoverable = mapList(cached);
        notifyListeners();
      }
    }
  }

  Future<void> fetchJoinRequests(String groupId) async {
    try {
      final res = await _api.get('/groups/$groupId/join-requests');
      _joinRequestsByGroup[groupId] = mapList(res['data'] ?? res);
      notifyListeners();
    } catch (_) {
      _joinRequestsByGroup[groupId] = [];
      notifyListeners();
    }
  }

  Future<void> fetchMembers(String groupId) async {
    try {
      final res = await _api.get('/groups/$groupId/members');
      _membersByGroup[groupId] = mapList(res['data'] ?? res);
      notifyListeners();
    } catch (_) {
      _membersByGroup[groupId] = [];
      notifyListeners();
    }
  }

  Future<void> fetchMessages(String groupId) async {
    try {
      final res = await _api.get('/groups/$groupId/messages');
      _messagesByGroup[groupId] = mapList(res['messages'] ?? res['data'] ?? res);
      notifyListeners();
    } catch (_) {
      _messagesByGroup[groupId] = [];
      notifyListeners();
    }
  }

  Future<bool> sendMessage(String groupId, String content) async {
    try {
      await _api.post('/groups/$groupId/messages', {'content': content});
      await fetchMessages(groupId);
      return true;
    } catch (_) {
      await _cache.enqueue('group_message', {
        'group_id': groupId,
        'content': content,
      });
      _isOffline = true;
      notifyListeners();
      return true; // queued locally
    }
  }

  Future<void> fetchAlerts(String groupId) async {
    try {
      final res = await _api.get('/groups/$groupId/alerts');
      _alertsByGroup[groupId] = mapList(res['data'] ?? res);
      notifyListeners();
    } catch (e) {
      debugPrint('fetchAlerts failed ($groupId): $e');
      // Keep previous alerts on transient errors instead of wiping the feed.
      if (!_alertsByGroup.containsKey(groupId)) {
        _alertsByGroup[groupId] = [];
      }
      notifyListeners();
    }
  }

  /// Refresh Alertes for every neighborhood group the user belongs to.
  Future<void> refreshAllAlerts() async {
    if (_myGroups.isEmpty) {
      await fetchMyGroups();
    }
    final ids = _myGroups
        .map((g) => g['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    await Future.wait(ids.map(fetchAlerts));
  }

  Future<bool> createAlert(
    String groupId, {
    required String type,
    required String title,
    String? body,
    double? lat,
    double? lng,
  }) async {
    try {
      await _api.post('/groups/$groupId/alerts', {
        'type': type,
        'title': title,
        if (body != null) 'body': body,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });
      await fetchAlerts(groupId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createGroup(String name, {String? description, String? zoneName}) async {
    try {
      await _api.post('/groups', {
        'name': name,
        if (description != null) 'description': description,
        if (zoneName != null) 'zone_name': zoneName,
      });
      await fetchMyGroups();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> joinGroup(String code) async {
    _lastJoinMessage = null;
    _lastError = null;
    final invite = normalizeInviteCode(code);
    if (invite.length < 6) {
      _lastError = 'Code d\'invitation invalide';
      notifyListeners();
      return false;
    }
    try {
      final res = await _api.post('/groups/join', {'invite_code': invite});
      _lastJoinMessage = res['message'] as String? ?? 'Groupe rejoint';
      await Future.wait([fetchMyGroups(), fetchDiscoverable()]);
      return true;
    } catch (e) {
      _lastError = e is ApiException
          ? e.message
          : 'Code invalide ou impossible de rejoindre';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setMemberRole(String groupId, String userId, String role) async {
    _lastError = null;
    try {
      await _api.patch('/groups/$groupId/members/$userId', {'role': role});
      await fetchMembers(groupId);
      await fetchMyGroups();
      return true;
    } catch (e) {
      _lastError = e is ApiException ? e.message : 'Impossible de modifier le rôle';
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestJoinGroup(String groupId) async {
    _lastJoinMessage = null;
    try {
      final res = await _api.post('/groups/$groupId/join', {});
      _lastJoinMessage = res['message'] as String? ?? 'Demande envoyée';
      await fetchDiscoverable();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> approveJoinRequest(String requestId, String groupId) async {
    try {
      await _api.put('/groups/join-requests/$requestId/approve', {});
      await fetchJoinRequests(groupId);
      await fetchMyGroups();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rejectJoinRequest(String requestId, String groupId) async {
    try {
      await _api.put('/groups/join-requests/$requestId/reject', {});
      await fetchJoinRequests(groupId);
      await fetchMyGroups();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> leaveGroup(String id) async {
    try {
      await _api.delete('/groups/$id/leave');
      await fetchMyGroups();
      return true;
    } catch (_) {
      return false;
    }
  }
}
