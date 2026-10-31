import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Real-time family-circle positions **without Internet** via UDP multicast
/// on the local Wi‑Fi / hotspot (works Android ↔ iOS).
///
/// Range is local only (same network). Distant relatives still need Internet
/// via the normal API path.
class CircleMeshService extends ChangeNotifier {
  static final CircleMeshService _instance = CircleMeshService._();
  CircleMeshService._();
  factory CircleMeshService() => _instance;

  static const _udpPort = 41789;
  static final _multicast = InternetAddress('239.255.67.89');

  RawDatagramSocket? _udp;
  Timer? _prune;

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
    final digest = sha256.convert(
      utf8.encode('safealert-circle:${inviteCode.trim().toUpperCase()}'),
    );
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
    _prune = Timer.periodic(const Duration(seconds: 8), (_) => _pruneStale());
    notifyListeners();
  }

  Future<void> setSharing(bool value) async {
    _sharing = value;
    notifyListeners();
  }

  void publishPosition(double lat, double lng) {
    if (!_running || !_sharing) return;
    if (!_isSane(lat, lng)) return;
    _sendUdp(_buildPacket(lat, lng));
  }

  Future<void> stop() async {
    _prune?.cancel();
    _prune = null;
    try {
      _udp?.close();
    } catch (_) {}
    _udp = null;
    peers.clear();
    _running = false;
    _sharing = false;
    _circleId = null;
    _inviteCode = null;
    notifyListeners();
  }

  Future<void> _startUdp() async {
    if (kIsWeb) {
      _lastError = 'Mesh local indisponible sur le web';
      return;
    }
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

  String _buildPacket(double lat, double lng) {
    final body = <String, dynamic>{
      'v': 1,
      'c': _circleToken(_inviteCode!),
      'u': _userId,
      'n': (_pseudo ?? 'Membre')
          .substring(0, (_pseudo ?? 'Membre').length.clamp(0, 24)),
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
    final at =
        (map['t'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

    peers[uid] = {
      'user_id': uid,
      'pseudo': map['n']?.toString() ?? 'Proche',
      'last_lat': lat,
      'last_lng': lng,
      'visible_on_map': true,
      'share_until':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
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
