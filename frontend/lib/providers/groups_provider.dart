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

  List<Map<String, dynamic>> get myGroups => _myGroups;
  List<Map<String, dynamic>> get discoverable => _discoverable;
  bool get loading => _loading;
  bool get isOffline => _isOffline;
  String? get lastJoinMessage => _lastJoinMessage;

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

  Future<void> fetchMyGroups() async {
    _loading = true;
    _isOffline = false;
    notifyListeners();
    try {
      final res = await _api.get('/groups');
      _myGroups = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      await _cache.put('my_groups', _myGroups);
    } catch (_) {
      final cached = await _cache.get('my_groups', maxAgeSeconds: 600);
      if (cached != null) {
        _myGroups = (cached as List).cast<Map<String, dynamic>>();
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
      _discoverable = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      await _cache.put('discover_groups', _discoverable);
      notifyListeners();
    } catch (_) {
      final cached = await _cache.get('discover_groups', maxAgeSeconds: 600);
      if (cached != null) {
        _discoverable = (cached as List).cast<Map<String, dynamic>>();
        notifyListeners();
      }
    }
  }

  Future<void> fetchJoinRequests(String groupId) async {
    try {
      final res = await _api.get('/groups/$groupId/join-requests');
      _joinRequestsByGroup[groupId] =
          (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      notifyListeners();
    } catch (_) {
      _joinRequestsByGroup[groupId] = [];
      notifyListeners();
    }
  }

  Future<void> fetchMembers(String groupId) async {
    try {
      final res = await _api.get('/groups/$groupId/members');
      _membersByGroup[groupId] =
          (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      notifyListeners();
    } catch (_) {
      _membersByGroup[groupId] = [];
      notifyListeners();
    }
  }

  Future<void> fetchMessages(String groupId) async {
    try {
      final res = await _api.get('/groups/$groupId/messages');
      _messagesByGroup[groupId] =
          (res['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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
      return false;
    }
  }

  Future<void> fetchAlerts(String groupId) async {
    try {
      final res = await _api.get('/groups/$groupId/alerts');
      _alertsByGroup[groupId] =
          (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      notifyListeners();
    } catch (_) {
      _alertsByGroup[groupId] = [];
      notifyListeners();
    }
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
    try {
      final res = await _api.post('/groups/join', {'invite_code': code});
      _lastJoinMessage = res['message'] as String? ?? 'Demande envoyée';
      await fetchDiscoverable();
      return true;
    } catch (_) {
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
