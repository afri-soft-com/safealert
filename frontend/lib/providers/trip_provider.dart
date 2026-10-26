import 'dart:async';

import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/local_database.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';
import '../services/trip_tracking_service.dart';
import '../utils/network_error.dart';

class TripProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final LocalDatabase _cache = LocalDatabase();
  Map<String, dynamic>? _activeTrip;
  Map<String, dynamic>? _followedTrip;
  String? _followTripId;
  String? _shareUrl;
  String? _shareText;
  Map<String, dynamic>? _routeSuggestion;
  List<Map<String, dynamic>> _history = [];
  bool _loading = false;
  bool _historyLoading = false;
  String? _error;
  bool _socketBound = false;
  String? _trackingTripId;
  Timer? _fallbackPing;
  Timer? _offlineFlushTimer;
  int _pendingOfflinePings = 0;

  Map<String, dynamic>? get activeTrip => _activeTrip;
  Map<String, dynamic>? get followedTrip => _followedTrip;
  String? get followTripId => _followTripId;
  String? get shareUrl => _shareUrl;
  String? get shareText => _shareText;
  Map<String, dynamic>? get routeSuggestion => _routeSuggestion;
  List<Map<String, dynamic>> get history => _history;
  bool get loading => _loading;
  bool get historyLoading => _historyLoading;
  String? get error => _error;
  int get pendingOfflinePings => _pendingOfflinePings;
  bool get hasOfflinePings => _pendingOfflinePings > 0;
  bool get isTracking =>
      TripTrackingService().isRunning || _fallbackPing != null;
  bool get isPatrol =>
      _activeTrip?['trip_mode']?.toString() == 'patrol';

  /// Continuous trail for the followed (or active) trip.
  List<Map<String, dynamic>> trackFor(Map<String, dynamic>? trip) {
    if (trip == null) return const [];
    final raw = trip['track'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((p) => p['lat'] != null && p['lng'] != null)
        .toList();
  }

  TripProvider() {
    _bindSockets();
  }

  void _bindSockets() {
    if (_socketBound) return;
    _socketBound = true;
    SocketService().setTripHandlers(
      onTripPing: (data) {
        final tripId = data['trip_id']?.toString();
        if (tripId == null) return;
        final point = <String, dynamic>{
          'lat': data['lat'],
          'lng': data['lng'],
          if (data['at'] != null) 'at': data['at'],
        };
        if (_activeTrip != null && _activeTrip!['id']?.toString() == tripId) {
          _activeTrip = _mergePing(_activeTrip!, data, point);
          notifyListeners();
        }
        if (_followTripId == tripId) {
          _followedTrip = _mergePing(
            {...?_followedTrip, 'id': tripId},
            data,
            point,
          );
          notifyListeners();
        }
      },
      onEscortTrip: (trip) {
        _followedTrip = trip;
        _followTripId = trip['id']?.toString();
        notifyListeners();
      },
    );
  }

  Map<String, dynamic> _mergePing(
    Map<String, dynamic> trip,
    Map<String, dynamic> data,
    Map<String, dynamic> point,
  ) {
    final track = List<Map<String, dynamic>>.from(trackFor(trip));
    final lat = (point['lat'] as num?)?.toDouble();
    final lng = (point['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      final last = track.isEmpty ? null : track.last;
      final lastLat = (last?['lat'] as num?)?.toDouble();
      final lastLng = (last?['lng'] as num?)?.toDouble();
      final same = lastLat != null &&
          lastLng != null &&
          (lastLat - lat).abs() < 0.00001 &&
          (lastLng - lng).abs() < 0.00001;
      if (!same) track.add(point);
    }
    return {
      ...trip,
      'last_lat': data['lat'] ?? trip['last_lat'],
      'last_lng': data['lng'] ?? trip['last_lng'],
      'status': data['status'] ?? trip['status'],
      'track': track,
    };
  }

  Future<void> fetchActive() async {
    try {
      final res = await _api.get('/trips/active');
      _activeTrip = res.isEmpty || res['id'] == null ? null : res;
      notifyListeners();
    } catch (_) {
      _activeTrip = null;
    }
    await _syncTracking();
  }

  Future<void> fetchHistory() async {
    _historyLoading = true;
    notifyListeners();
    try {
      final res = await _api.get('/trips/history');
      final list = res['trips'];
      _history = list is List
          ? list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de charger l\'historique.');
    }
    _historyLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> fetchTrip(String id) async {
    try {
      final res = await _api.get('/trips/$id');
      if (res['id'] == null) return null;
      _followedTrip = res;
      _followTripId = id;
      notifyListeners();
      return res;
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de charger le trajet.');
      notifyListeners();
      return null;
    }
  }

  void openEscortForTrip(String id) {
    _followTripId = id;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> openEscortMap(String id) async {
    openEscortForTrip(id);
    final resolved = await resolveFollowInput(id);
    if (resolved == null) return null;
    _followTripId = resolved;
    return fetchTrip(resolved);
  }

  /// Accepte un UUID, un lien `/t/token`, ou le token de partage.
  Future<String?> resolveFollowInput(String raw) async {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final uuid = RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    ).firstMatch(t);
    if (uuid != null) return uuid.group(0);

    var token = t;
    final urlMatch = RegExp(r'/t/([A-Za-z0-9]+)').firstMatch(t);
    if (urlMatch != null) token = urlMatch.group(1)!;
    if (token.contains('-')) return token;
    try {
      final res = await _api.get('/public/trips/${Uri.encodeComponent(token)}');
      final id = (res['trip'] as Map?)?['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return token;
  }

  void clearFollowedTrip() {
    _followedTrip = null;
    _followTripId = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> startTrip({
    double? destLat,
    double? destLng,
    double? originLat,
    double? originLng,
    String? destLabel,
    int etaMinutes = 30,
    String transportMode = 'moto',
    String tripMode = 'destination',
    List<String>? escortContactIds,
    String? vehiclePlate,
    String? vehicleNote,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      var oLat = originLat;
      var oLng = originLng;
      if (oLat == null || oLng == null) {
        final pos = await LocationService().getCurrentPosition();
        if (pos == null) {
          _error = 'Position GPS indisponible — définissez le départ sur la carte';
          _loading = false;
          notifyListeners();
          return null;
        }
        oLat = pos.latitude;
        oLng = pos.longitude;
      }
      final isPatrol = tripMode == 'patrol';
      if (!isPatrol && (destLat == null || destLng == null)) {
        _error = 'Destination requise pour un trajet classique.';
        _loading = false;
        notifyListeners();
        return null;
      }
      final res = await _api.post('/trips', {
        'origin_lat': oLat,
        'origin_lng': oLng,
        if (destLat != null) 'dest_lat': destLat,
        if (destLng != null) 'dest_lng': destLng,
        if (destLabel != null) 'dest_label': destLabel,
        'eta_minutes': etaMinutes,
        'transport_mode': transportMode,
        'trip_mode': isPatrol ? 'patrol' : 'destination',
        if (isPatrol) 'notify_on_delay': false,
        if (escortContactIds != null && escortContactIds.isNotEmpty)
          'escort_contact_ids': escortContactIds,
        if (vehiclePlate != null && vehiclePlate.trim().isNotEmpty)
          'vehicle_plate': vehiclePlate.trim(),
        if (vehicleNote != null && vehicleNote.trim().isNotEmpty)
          'vehicle_note': vehicleNote.trim(),
      });
      _activeTrip = res['trip'] as Map<String, dynamic>?;
      _shareUrl = res['share_url'] as String?;
      _shareText = res['share_text'] as String?;
      _loading = false;
      notifyListeners();
      await _syncTracking();
      unawaited(fetchHistory());
      return _activeTrip;
    } catch (e) {
      if (e is ApiException && e.statusCode == 409) {
        await fetchActive();
        _loading = false;
        if (_activeTrip != null) {
          _error = null;
          notifyListeners();
          return _activeTrip;
        }
      }
      _error = userFacingError(e, fallback: 'Impossible de démarrer le trajet.');
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> createShareLink() async {
    if (_activeTrip == null) return null;
    try {
      final res = await _api.post('/trips/${_activeTrip!['id']}/share', {});
      _shareUrl = res['share_url'] as String?;
      _shareText = res['share_text'] as String?;
      notifyListeners();
      return res;
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible de créer le lien.');
      notifyListeners();
      return null;
    }
  }

  Future<void> fetchRouteSuggestion({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final res = await _api.get(
        '/corridors/suggest?origin_lat=$originLat&origin_lng=$originLng'
        '&dest_lat=$destLat&dest_lng=$destLng',
      );
      _routeSuggestion = res;
      notifyListeners();
    } catch (_) {
      _routeSuggestion = null;
    }
  }

  Future<void> ping() async {
    if (_activeTrip == null) return;
    final pos = await LocationService().getCurrentPosition();
    if (pos == null) return;
    await pingAt(pos.latitude, pos.longitude);
  }

  Future<void> pingAt(double lat, double lng) async {
    if (_activeTrip == null) return;
    final tripId = _activeTrip!['id']?.toString();
    if (tripId == null) return;

    // Keep a local trail even offline so the traveler still sees progress.
    _activeTrip = _mergePing(_activeTrip!, {
      'lat': lat,
      'lng': lng,
      'status': _activeTrip!['status'],
    }, {
      'lat': lat,
      'lng': lng,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    notifyListeners();

    try {
      final res = await _api.post('/trips/$tripId/ping', {
        'lat': lat,
        'lng': lng,
      });
      final trip = res['trip'] as Map<String, dynamic>?;
      if (trip != null) {
        final serverTrack = trackFor(trip);
        _activeTrip = serverTrack.isEmpty
            ? _mergePing(_activeTrip!, {
                'lat': lat,
                'lng': lng,
                'status': trip['status'],
              }, {'lat': lat, 'lng': lng})
            : trip;
      } else {
        _activeTrip = null;
      }
      notifyListeners();
      // After reconnect, drain any queued pings.
      unawaited(flushPendingPings());
      if (_activeTrip == null || _activeTrip!['status'] != 'active') {
        await _syncTracking();
        unawaited(fetchHistory());
      }
    } catch (e) {
      if (e is ApiException && (e.statusCode == 404 || e.statusCode == 401)) {
        _activeTrip = null;
        notifyListeners();
        await _syncTracking();
        return;
      }
      // Network / 5xx → queue for later sync
      try {
        await _cache.enqueue('trip_ping', {
          'trip_id': tripId,
          'lat': lat,
          'lng': lng,
          'at': DateTime.now().toUtc().toIso8601String(),
        });
        _pendingOfflinePings += 1;
        notifyListeners();
        _ensureOfflineFlushTimer();
      } catch (_) {}
    }
  }

  void _ensureOfflineFlushTimer() {
    _offlineFlushTimer ??= Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(flushPendingPings());
    });
  }

  /// Sync queued GPS pings once back online (order preserved).
  Future<int> flushPendingPings() async {
    final pending = await _cache.listPending(kind: 'trip_ping', dueOnly: true);
    if (pending.isEmpty) {
      _pendingOfflinePings = 0;
      _offlineFlushTimer?.cancel();
      _offlineFlushTimer = null;
      notifyListeners();
      return 0;
    }
    var sent = 0;
    for (final item in pending) {
      final id = item['id'] as int;
      final payload = item['payload'] as Map<String, dynamic>;
      final tripId = payload['trip_id']?.toString();
      final lat = payload['lat'];
      final lng = payload['lng'];
      if (tripId == null || lat == null || lng == null) {
        await _cache.removePending(id);
        continue;
      }
      try {
        await _api.post('/trips/$tripId/ping', {
          'lat': lat,
          'lng': lng,
        });
        await _cache.removePending(id);
        sent++;
      } catch (e) {
        if (e is ApiException && (e.statusCode == 404 || e.statusCode == 401)) {
          await _cache.removePending(id);
          continue;
        }
        await _cache.bumpPendingAttempt(id);
        break; // keep order — stop until network recovers
      }
    }
    final left = await _cache.listPending(kind: 'trip_ping');
    _pendingOfflinePings = left.length;
    if (_pendingOfflinePings == 0) {
      _offlineFlushTimer?.cancel();
      _offlineFlushTimer = null;
    } else {
      _ensureOfflineFlushTimer();
    }
    if (sent > 0 && _followTripId != null) {
      unawaited(fetchTrip(_followTripId!));
    }
    if (sent > 0 && _activeTrip != null) {
      unawaited(fetchActive());
    }
    notifyListeners();
    return sent;
  }

  Future<void> refreshOfflinePingCount() async {
    final left = await _cache.listPending(kind: 'trip_ping');
    _pendingOfflinePings = left.length;
    notifyListeners();
  }

  Future<void> arrive() async {
    if (_activeTrip == null) return;
    try {
      final res = await _api.post('/trips/${_activeTrip!['id']}/arrive', {});
      _activeTrip = res['trip'] as Map<String, dynamic>?;
      notifyListeners();
    } catch (_) {}
    await _syncTracking();
    unawaited(fetchHistory());
  }

  Future<void> cancel() async {
    if (_activeTrip == null) return;
    try {
      await _api.post('/trips/${_activeTrip!['id']}/cancel', {});
      _activeTrip = null;
      notifyListeners();
    } catch (_) {}
    await _syncTracking();
    unawaited(fetchHistory());
  }

  Future<void> stopTracking() async {
    _trackingTripId = null;
    _fallbackPing?.cancel();
    _fallbackPing = null;
    await TripTrackingService().stop();
    notifyListeners();
  }

  Future<void> _syncTracking() async {
    final id = _activeTrip?['id']?.toString();
    final active = id != null && _activeTrip?['status'] == 'active';
    if (!active) {
      if (_trackingTripId != null || TripTrackingService().isRunning || _fallbackPing != null) {
        _trackingTripId = null;
        _fallbackPing?.cancel();
        _fallbackPing = null;
        await TripTrackingService().stop();
        notifyListeners();
      }
      return;
    }
    if (_trackingTripId == id && (TripTrackingService().isRunning || _fallbackPing != null)) {
      return;
    }
    _trackingTripId = id;
    final started = await TripTrackingService().start(onPosition: pingAt);
    if (!started) {
      _fallbackPing?.cancel();
      _fallbackPing = Timer.periodic(const Duration(seconds: 12), (_) => ping());
      debugPrint('TripTracking: GPS stream unavailable, using periodic pings');
    } else {
      _fallbackPing?.cancel();
      _fallbackPing = null;
    }
    notifyListeners();
  }
}
