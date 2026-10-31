import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nearby_connections_plus/flutter_nearby_connections_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Real-time family-circle positions **without Internet**:
/// 1. UDP multicast on the local Wi‑Fi / hotspot (Android ↔ iOS)
/// 2. Nearby Connections / Multipeer when peers are the same OS & nearby
///
/// Range is local only (same network or ~Bluetooth distance). Distant
/// relatives still need cellular/Internet via the normal API path.
class CircleMeshService extends ChangeNotifier {
  static final CircleMeshService _instance = CircleMeshService._();
  CircleMeshService._();
  factory CircleMeshService() => _instance;

  static const _udpPort = 41789;
  static final _multicast = InternetAddress('239.255.67.89');
  static const _serviceType = 'sa-circle'; // ≤15 chars (Bonjour)

  RawDatagramSocket? _udp;
  NearbyService? _nearby;
  StreamSubscription? _nearbyStateSub;
  StreamSubscription? _nearbyDataSub;
  Timer? _heartbeat;
  Timer? _prune;
  final Set<String> _connectedPeerIds = {};
  String? _lastPacket;

  String? _circleId;
  String? _inviteCode;
  String? _userId;
  String? _pseudo;
  bool _running = false;
  bool _sharing = false;
  String? _lastError;

  /// userId → last mesh sighting
  final Map<String, Map<String, dynamic>> peers = {};

  bool get running => _running;
  bool get sharing => _sharing;
  String? get circleId => _circleId;
  String? get lastError => _lastError;
  int get peerCount => peers.length;

  String _circleToken(String inviteCode) {
    final digest = sha256.convert(utf8.encode('safealert-circle:${inviteCode.trim().toUpperCase()}'));
    return digest.toString().substring(0, 8);
  }

  String _sign(Map<String, dynamic> body, String inviteCode) {
    final canonical = jsonEncode(body);
    final digest = sha256.convert(utf8.encode('$inviteCode|$canonical'));
    return digest.toString().substring(0, 10);
  }

  Future<void> start({
    required String circleId,
    required String inviteCode,
    required String userId,
    required String pseudo,
    bool shareOwnPosition = false,
  }) async {
    if (_running &&
        _circleId == circleId &&
        _inviteCode == inviteCode &&
        _userId == userId) {
      _sharing = shareOwnPosition || _sharing;
      _pseudo = pseudo;
      if (_sharing) _kickHeartbeat();
      notifyListeners();
      return;
    }

    await stop();
    _circleId = circleId;
    _inviteCode = inviteCode.trim().toUpperCase();
    _userId = userId;
    _pseudo = pseudo;
    _sharing = shareOwnPosition;
    _lastError = null;
    _running = true;

    await _startUdp();
    unawaited(_startNearby());
    _prune = Timer.periodic(const Duration(seconds: 8), (_) => _pruneStale());
    if (_sharing) _kickHeartbeat();
    notifyListeners();
  }

  Future<void> setSharing(bool value) async {
    _sharing = value;
    if (_sharing) {
      _kickHeartbeat();
    } else {
      _heartbeat?.cancel();
      _heartbeat = null;
    }
    notifyListeners();
  }

  void publishPosition(double lat, double lng) {
    if (!_running || !_sharing) return;
    if (!_isSane(lat, lng)) return;
    final packet = _buildPacket(lat, lng);
    _lastPacket = packet;
    _sendUdp(packet);
    _sendNearby(packet);
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _prune?.cancel();
    _prune = null;
    try {
      _udp?.close();
    } catch (_) {}
    _udp = null;
    await _stopNearby();
    peers.clear();
    _running = false;
    _sharing = false;
    _circleId = null;
    _inviteCode = null;
    notifyListeners();
  }

  Future<void> _startUdp() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _udpPort,
        reuseAddress: true,
        reusePort: !Platform.isIOS,
      );
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;
      try {
        socket.joinMulticast(_multicast);
      } catch (e) {
        debugPrint('CircleMesh UDP joinMulticast: $e');
      }
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        _onRawMessage(utf8.decode(dg.data, allowMalformed: true));
      });
      _udp = socket;
      debugPrint('CircleMesh UDP listening on $_udpPort');
    } catch (e) {
      _lastError = 'Wi‑Fi local indisponible ($e)';
      debugPrint('CircleMesh UDP bind failed: $e');
    }
  }

  void _sendUdp(String packet) {
    final sock = _udp;
    if (sock == null) return;
    final bytes = utf8.encode(packet);
    try {
      sock.send(bytes, _multicast, _udpPort);
    } catch (_) {}
    try {
      sock.send(bytes, InternetAddress('255.255.255.255'), _udpPort);
    } catch (_) {}
  }

  Future<void> _startNearby() async {
    if (kIsWeb) return;
    try {
      await _ensureNearbyPermissions();
      final nearby = NearbyService();
      final name = 'SA|${_circleToken(_inviteCode!)}|${_pseudo ?? 'Membre'}';
      await nearby.init(
        serviceType: _serviceType,
        strategy: Strategy.P2P_CLUSTER,
        deviceName: name,
        callback: (running) {
          debugPrint('CircleMesh Nearby running=$running');
        },
      );
      _nearbyStateSub = nearby.stateChangedSubscription(
        callback: (devices) {
          final token = 'SA|${_circleToken(_inviteCode!)}|';
          for (final d in devices) {
            final ours = d.deviceName.startsWith(token);
            if (!ours) continue;
            if (d.state == SessionState.notConnected) {
              nearby.invitePeer(deviceID: d.deviceId, deviceName: d.deviceName);
            } else if (d.state == SessionState.connected) {
              _connectedPeerIds.add(d.deviceId);
              final pkt = _lastPacket;
              if (pkt != null) {
                nearby.sendMessage(d.deviceId, pkt);
              }
            } else if (d.state == SessionState.connecting) {
              /* wait */
            }
          }
          _connectedPeerIds.removeWhere(
            (id) => !devices.any(
              (d) => d.deviceId == id && d.state == SessionState.connected,
            ),
          );
        },
      );
      _nearbyDataSub = nearby.dataReceivedSubscription(
        callback: (data) {
          try {
            final msg = data is Map
                ? (data['message']?.toString() ?? '')
                : data.toString();
            _onRawMessage(msg);
          } catch (_) {}
        },
      );
      await nearby.startAdvertisingPeer(deviceName: name);
      await nearby.startBrowsingForPeers();
      _nearby = nearby;
    } catch (e) {
      debugPrint('CircleMesh Nearby start failed: $e');
      // UDP path may still work — don't fail hard.
      _lastError ??= 'Bluetooth proximité limité ($e)';
    }
  }

  void _sendNearby(String packet) {
    final nearby = _nearby;
    if (nearby == null) return;
    for (final id in _connectedPeerIds.toList()) {
      try {
        nearby.sendMessage(id, packet);
      } catch (_) {}
    }
  }

  Future<void> _stopNearby() async {
    try {
      await _nearbyStateSub?.cancel();
      await _nearbyDataSub?.cancel();
      await _nearby?.stopAdvertisingPeer();
      await _nearby?.stopBrowsingForPeers();
    } catch (_) {}
    _nearbyStateSub = null;
    _nearbyDataSub = null;
    _nearby = null;
    _connectedPeerIds.clear();
    _lastPacket = null;
  }

  Future<void> _ensureNearbyPermissions() async {
    if (kIsWeb) return;
    final need = <Permission>[
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ];
    try {
      await need.request();
    } catch (_) {}
  }

  void _kickHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      // Caller (LocationService / screen) should feed GPS; this keeps mesh alive
      // with last known if needed — no-op without publishPosition.
    });
  }

  String _buildPacket(double lat, double lng) {
    final body = <String, dynamic>{
      'v': 1,
      'c': _circleToken(_inviteCode!),
      'u': _userId,
      'n': (_pseudo ?? 'Membre').substring(0, (_pseudo ?? 'Membre').length.clamp(0, 24)),
      'la': double.parse(lat.toStringAsFixed(5)),
      'ln': double.parse(lng.toStringAsFixed(5)),
      't': DateTime.now().millisecondsSinceEpoch,
    };
    body['s'] = _sign(body, _inviteCode!);
    return jsonEncode(body);
  }

  void _onRawMessage(String raw) {
    if (!_running || _inviteCode == null) return;
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final token = map['c']?.toString();
    if (token != _circleToken(_inviteCode!)) return;
    final uid = map['u']?.toString();
    if (uid == null || uid.isEmpty || uid == _userId) return;
    final sig = map.remove('s')?.toString();
    if (sig == null || sig != _sign(map, _inviteCode!)) return;

    final lat = (map['la'] as num?)?.toDouble();
    final lng = (map['ln'] as num?)?.toDouble();
    if (lat == null || lng == null || !_isSane(lat, lng)) return;
    final at = (map['t'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

    peers[uid] = {
      'user_id': uid,
      'pseudo': map['n']?.toString() ?? 'Proche',
      'last_lat': lat,
      'last_lng': lng,
      'visible_on_map': true,
      'share_until': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      'mesh': true,
      'mesh_at': at,
      'source': 'mesh',
    };
    notifyListeners();
  }

  void _pruneStale() {
    final cutoff = DateTime.now().millisecondsSinceEpoch - 45000;
    final before = peers.length;
    peers.removeWhere((_, v) => ((v['mesh_at'] as int?) ?? 0) < cutoff);
    if (peers.length != before) notifyListeners();
  }

  bool _isSane(double lat, double lng) =>
      lat.abs() > 0.0001 &&
      lng.abs() > 0.0001 &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;
}
