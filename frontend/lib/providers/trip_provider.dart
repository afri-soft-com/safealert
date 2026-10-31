import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import '../services/local_database.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';
import '../services/trip_tracking_service.dart';
import '../utils/network_error.dart';

class TripProvider extends ChangeNotifier {
  static const _activeTripCacheKey = 'active_trip';
  static const _uuid = Uuid();

  final ApiService _api = ApiService();
  final LocalDatabase _cache = LocalDatabase();
  Map<String, dynamic>? _activeTrip;
  Map<String, dynamic>? _followedTrip;
  String? _followTripId;
  /// When set, refresh via `/public/trips/:token` (share-link followers).
  String? _publicFollowToken;
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  int _pendingOfflinePings = 0;
  int _pendingOfflineActions = 0;

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
  int get pendingOfflineActions => _pendingOfflineActions;
  bool get hasOfflinePings =>
      _pendingOfflinePings > 0 || _pendingOfflineActions > 0;
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

  /// Named places the traveler pinned along the trip.
  List<Map<String, dynamic>> placesFor(Map<String, dynamic>? trip) {
    if (trip == null) return const [];
    final raw = trip['places'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((p) =>
            p['lat'] != null &&
            p['lng'] != null &&
            (p['label']?.toString().trim().isNotEmpty ?? false))
        .toList();
  }

  TripProvider() {
    _bindSockets();
    _bindConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _offlineFlushTimer?.cancel();
    _fallbackPing?.cancel();
    super.dispose();
  }

  void _bindConnectivity() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        unawaited(flushPendingPings());
        unawaited(flushPendingTripActions());
        unawaited(fetchActive());
      }
    });
  }

  Future<void> _persistActiveTrip() async {
    final trip = _activeTrip;
    if (trip == null || trip['status']?.toString() != 'active') {
      await _cache.remove(_activeTripCacheKey);
      return;
    }
    await _cache.put(_activeTripCacheKey, trip);
  }

  Future<Map<String, dynamic>?> _loadCachedActiveTrip() async {
    final raw = await _cache.get(_activeTripCacheKey);
    if (raw is! Map) return null;
    final trip = Map<String, dynamic>.from(raw);
    if (trip['id'] == null || trip['status']?.toString() != 'active') {
      return null;
    }
    return trip;
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
      onTripPlace: (data) {
        final tripId = data['trip_id']?.toString();
        final placeRaw = data['place'];
        if (tripId == null || placeRaw is! Map) return;
        final place = Map<String, dynamic>.from(placeRaw);
        if (_activeTrip != null && _activeTrip!['id']?.toString() == tripId) {
          _activeTrip = _mergePlace(_activeTrip!, place);
          notifyListeners();
        }
        if (_followTripId == tripId) {
          _followedTrip = _mergePlace({...?_followedTrip, 'id': tripId}, place);
          notifyListeners();
        }
      },
    );
  }

  Map<String, dynamic> _mergePlace(
    Map<String, dynamic> trip,
    Map<String, dynamic> place,
  ) {
    final places = List<Map<String, dynamic>>.from(placesFor(trip));
    final id = place['id']?.toString();
    if (id != null && places.any((p) => p['id']?.toString() == id)) {
      return trip;
    }
    places.add(place);
    return {...trip, 'places': places};
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
      if (res.isEmpty || res['id'] == null) {
        _activeTrip = null;
        await _cache.remove(_activeTripCacheKey);
      } else {
        _activeTrip = res;
        await _persistActiveTrip();
      }
      notifyListeners();
    } catch (_) {
      // Offline / poor network: keep local snapshot so GPS tracking continues.
      final cached = await _loadCachedActiveTrip();
      if (cached != null) {
        _activeTrip = cached;
        notifyListeners();
      }
    }
    await _syncTracking();
    await refreshOfflinePingCount();
    unawaited(flushPendingPings());
    unawaited(flushPendingTripActions());
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
      if (_publicFollowToken != null &&
          _publicFollowToken!.isNotEmpty &&
          (_followTripId == null || _followTripId == id)) {
        final res = await _api.get(
          '/public/trips/${Uri.encodeComponent(_publicFollowToken!)}',
        );
        final trip = res['trip'];
        if (trip is Map && trip['id'] != null) {
          _followedTrip = Map<String, dynamic>.from(trip);
          _followTripId = _followedTrip!['id']?.toString();
          notifyListeners();
          return _followedTrip;
        }
      }
      final res = await _api.get('/trips/$id');
      if (res['id'] == null) return null;
      _followedTrip = res;
      _followTripId = id;
      _publicFollowToken = null;
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
    // Public share already populated `_followedTrip` — don't call /trips/:id
    // (403 for non-escorts).
    if (_followedTrip != null &&
        _followedTrip!['id']?.toString() == resolved) {
      _followTripId = resolved;
      notifyListeners();
      return _followedTrip;
    }
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
      final trip = res['trip'];
      if (trip is Map && trip['id'] != null) {
        final mapped = Map<String, dynamic>.from(trip);
        _followedTrip = mapped;
        _followTripId = mapped['id']?.toString();
        _publicFollowToken = token;
        notifyListeners();
        return _followTripId;
      }
    } catch (_) {}
    return token;
  }

  void clearFollowedTrip() {
    _followedTrip = null;
    _followTripId = null;
    _publicFollowToken = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> startTrip({
    double? destLat,
    double? destLng,
    double? originLat,
    double? originLng,
    String? destLabel,
    int? etaMinutes,
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
        if (etaMinutes != null) 'eta_minutes': etaMinutes,
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
      await _persistActiveTrip();
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

    final at = DateTime.now().toUtc().toIso8601String();
    final eventId = _uuid.v4();

    // Keep a local trail even offline so the traveler still sees progress.
    _activeTrip = _mergePing(_activeTrip!, {
      'lat': lat,
      'lng': lng,
      'status': _activeTrip!['status'],
    }, {
      'lat': lat,
      'lng': lng,
      'at': at,
    });
    unawaited(_persistActiveTrip());
    notifyListeners();

    try {
      final res = await _api.post('/trips/$tripId/ping', {
        'lat': lat,
        'lng': lng,
        'at': at,
        'client_event_id': eventId,
      });
      final trip = res['trip'] as Map<String, dynamic>?;
      if (trip != null) {
        final serverTrack = trackFor(trip);
        _activeTrip = serverTrack.isEmpty
            ? _mergePing(_activeTrip!, {
                'lat': lat,
                'lng': lng,
                'status': trip['status'],
              }, {'lat': lat, 'lng': lng, 'at': at})
            : trip;
        await _persistActiveTrip();
      } else {
        _activeTrip = null;
        await _cache.remove(_activeTripCacheKey);
      }
      notifyListeners();
      // After reconnect, drain any queued pings / actions.
      unawaited(flushPendingPings());
      unawaited(flushPendingTripActions());
      if (_activeTrip == null || _activeTrip!['status'] != 'active') {
        await _syncTracking();
        unawaited(fetchHistory());
      }
    } catch (e) {
      if (e is ApiException && (e.statusCode == 404 || e.statusCode == 401)) {
        _activeTrip = null;
        await _cache.remove(_activeTripCacheKey);
        notifyListeners();
        await _syncTracking();
        return;
      }
      // Network / 5xx → queue for later sync (idempotent via client_event_id).
      try {
        await _cache.enqueue('trip_ping', {
          'trip_id': tripId,
          'lat': lat,
          'lng': lng,
          'at': at,
          'client_event_id': eventId,
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
      unawaited(flushPendingTripActions());
    });
  }

  void _maybeStopOfflineFlushTimer() {
    if (_pendingOfflinePings == 0 && _pendingOfflineActions == 0) {
      _offlineFlushTimer?.cancel();
      _offlineFlushTimer = null;
    } else {
      _ensureOfflineFlushTimer();
    }
  }

  /// Sync queued GPS pings once back online (order preserved).
  Future<int> flushPendingPings() async {
    final pending = await _cache.listPending(kind: 'trip_ping', dueOnly: true);
    if (pending.isEmpty) {
      _pendingOfflinePings = 0;
      _maybeStopOfflineFlushTimer();
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
          if (payload['at'] != null) 'at': payload['at'],
          if (payload['client_event_id'] != null)
            'client_event_id': payload['client_event_id'],
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
    _maybeStopOfflineFlushTimer();
    if (sent > 0 && _followTripId != null) {
      unawaited(fetchTrip(_followTripId!));
    }
    if (sent > 0) {
      unawaited(fetchActive());
    }
    notifyListeners();
    return sent;
  }

  /// Sync queued arrive/cancel when back online.
  Future<int> flushPendingTripActions() async {
    final pending = await _cache.listPending(kind: 'trip_action', dueOnly: true);
    if (pending.isEmpty) {
      _pendingOfflineActions = 0;
      _maybeStopOfflineFlushTimer();
      notifyListeners();
      return 0;
    }
    var sent = 0;
    for (final item in pending) {
      final id = item['id'] as int;
      final payload = item['payload'] as Map<String, dynamic>;
      final tripId = payload['trip_id']?.toString();
      final action = payload['action']?.toString();
      if (tripId == null || (action != 'arrive' && action != 'cancel')) {
        await _cache.removePending(id);
        continue;
      }
      try {
        await _api.post('/trips/$tripId/$action', {});
        await _cache.removePending(id);
        sent++;
        if (action == 'cancel' || action == 'arrive') {
          if (_activeTrip?['id']?.toString() == tripId) {
            _activeTrip = action == 'cancel' ? null : {...?_activeTrip, 'status': 'arrived'};
            await _persistActiveTrip();
            await _syncTracking();
          }
        }
      } catch (e) {
        if (e is ApiException && (e.statusCode == 404 || e.statusCode == 401 || e.statusCode == 409)) {
          await _cache.removePending(id);
          continue;
        }
        await _cache.bumpPendingAttempt(id);
        break;
      }
    }
    final left = await _cache.listPending(kind: 'trip_action');
    _pendingOfflineActions = left.length;
    _maybeStopOfflineFlushTimer();
    if (sent > 0) unawaited(fetchHistory());
    notifyListeners();
    return sent;
  }

  Future<void> refreshOfflinePingCount() async {
    final pings = await _cache.listPending(kind: 'trip_ping');
    final actions = await _cache.listPending(kind: 'trip_action');
    _pendingOfflinePings = pings.length;
    _pendingOfflineActions = actions.length;
    if (_pendingOfflinePings > 0 || _pendingOfflineActions > 0) {
      _ensureOfflineFlushTimer();
    }
    notifyListeners();
  }

  /// Pin a named place at the current (or provided) GPS position.
  Future<Map<String, dynamic>?> addPlace(
    String label, {
    double? lat,
    double? lng,
  }) async {
    if (_activeTrip == null) return null;
    final name = label.trim();
    if (name.length < 2) {
      _error = 'Indiquez un nom de lieu (2 caractères min.).';
      notifyListeners();
      return null;
    }
    _error = null;
    try {
      var oLat = lat;
      var oLng = lng;
      if (oLat == null || oLng == null) {
        final pos = await LocationService().getCurrentPosition();
        oLat = pos?.latitude ??
            (_activeTrip!['last_lat'] as num?)?.toDouble() ??
            (_activeTrip!['origin_lat'] as num?)?.toDouble();
        oLng = pos?.longitude ??
            (_activeTrip!['last_lng'] as num?)?.toDouble() ??
            (_activeTrip!['origin_lng'] as num?)?.toDouble();
      }
      final res = await _api.post('/trips/${_activeTrip!['id']}/places', {
        'label': name,
        if (oLat != null) 'lat': oLat,
        if (oLng != null) 'lng': oLng,
      });
      final trip = res['trip'];
      if (trip is Map) {
        _activeTrip = Map<String, dynamic>.from(trip);
      } else {
        final place = res['place'];
        if (place is Map) {
          _activeTrip = _mergePlace(_activeTrip!, Map<String, dynamic>.from(place));
        }
      }
      notifyListeners();
      return res['place'] is Map
          ? Map<String, dynamic>.from(res['place'] as Map)
          : null;
    } catch (e) {
      _error = e is ApiException ? e.message : 'Impossible d\'enregistrer le lieu.';
      notifyListeners();
      return null;
    }
  }

  Future<void> arrive() async {
    if (_activeTrip == null) return;
    final tripId = _activeTrip!['id']?.toString();
    if (tripId == null) return;
    try {
      final res = await _api.post('/trips/$tripId/arrive', {});
      _activeTrip = res['trip'] as Map<String, dynamic>?;
      await _persistActiveTrip();
      notifyListeners();
    } catch (e) {
      if (e is! ApiException || (e.statusCode != 404 && e.statusCode != 401)) {
        try {
          await _cache.enqueue('trip_action', {
            'trip_id': tripId,
            'action': 'arrive',
          });
          _activeTrip = {..._activeTrip!, 'status': 'arrived'};
          await _persistActiveTrip();
          _pendingOfflineActions += 1;
          notifyListeners();
          _ensureOfflineFlushTimer();
        } catch (_) {}
      }
    }
    await _syncTracking();
    unawaited(fetchHistory());
  }

  Future<void> cancel() async {
    if (_activeTrip == null) return;
    final tripId = _activeTrip!['id']?.toString();
    if (tripId == null) return;
    try {
      await _api.post('/trips/$tripId/cancel', {});
      _activeTrip = null;
      await _cache.remove(_activeTripCacheKey);
      notifyListeners();
    } catch (e) {
      if (e is! ApiException || (e.statusCode != 404 && e.statusCode != 401)) {
        try {
          await _cache.enqueue('trip_action', {
            'trip_id': tripId,
            'action': 'cancel',
          });
          _activeTrip = null;
          await _cache.remove(_activeTripCacheKey);
          _pendingOfflineActions += 1;
          notifyListeners();
          _ensureOfflineFlushTimer();
        } catch (_) {}
      }
    }
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
