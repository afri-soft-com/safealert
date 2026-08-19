import 'dart:async';

import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';
import '../services/trip_tracking_service.dart';
import '../utils/network_error.dart';

class TripProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _activeTrip;
  Map<String, dynamic>? _followedTrip;
  String? _followTripId;
  String? _shareUrl;
  String? _shareText;
  Map<String, dynamic>? _routeSuggestion;
  bool _loading = false;
  String? _error;
  bool _socketBound = false;
  String? _trackingTripId;
  Timer? _fallbackPing;

  Map<String, dynamic>? get activeTrip => _activeTrip;
  Map<String, dynamic>? get followedTrip => _followedTrip;
  String? get followTripId => _followTripId;
  String? get shareUrl => _shareUrl;
  String? get shareText => _shareText;
  Map<String, dynamic>? get routeSuggestion => _routeSuggestion;
  bool get loading => _loading;
  String? get error => _error;
  bool get isTracking =>
      TripTrackingService().isRunning || _fallbackPing != null;

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
        if (_activeTrip != null && _activeTrip!['id']?.toString() == tripId) {
          _activeTrip = {
            ..._activeTrip!,
            'last_lat': data['lat'],
            'last_lng': data['lng'],
            'status': data['status'] ?? _activeTrip!['status'],
          };
          notifyListeners();
        }
        if (_followTripId == tripId) {
          _followedTrip = {
            ...?_followedTrip,
            'id': tripId,
            'last_lat': data['lat'],
            'last_lng': data['lng'],
            'status': data['status'] ?? _followedTrip?['status'],
          };
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
    return fetchTrip(id);
  }

  void clearFollowedTrip() {
    _followedTrip = null;
    _followTripId = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> startTrip({
    required double destLat,
    required double destLng,
    double? originLat,
    double? originLng,
    String? destLabel,
    int etaMinutes = 30,
    List<String>? escortContactIds,
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
      final res = await _api.post('/trips', {
        'origin_lat': oLat,
        'origin_lng': oLng,
        'dest_lat': destLat,
        'dest_lng': destLng,
        if (destLabel != null) 'dest_label': destLabel,
        'eta_minutes': etaMinutes,
        if (escortContactIds != null && escortContactIds.isNotEmpty)
          'escort_contact_ids': escortContactIds,
      });
      _activeTrip = res['trip'] as Map<String, dynamic>?;
      _shareUrl = res['share_url'] as String?;
      _shareText = res['share_text'] as String?;
      _loading = false;
      notifyListeners();
      await _syncTracking();
      return _activeTrip;
    } catch (e) {
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
    try {
      final res = await _api.post('/trips/${_activeTrip!['id']}/ping', {
        'lat': lat,
        'lng': lng,
      });
      _activeTrip = res['trip'] as Map<String, dynamic>?;
      notifyListeners();
      if (_activeTrip == null || _activeTrip!['status'] != 'active') {
        await _syncTracking();
      }
    } catch (e) {
      if (e is ApiException && (e.statusCode == 404 || e.statusCode == 401)) {
        _activeTrip = null;
        notifyListeners();
        await _syncTracking();
      }
    }
  }

  Future<void> arrive() async {
    if (_activeTrip == null) return;
    try {
      final res = await _api.post('/trips/${_activeTrip!['id']}/arrive', {});
      _activeTrip = res['trip'] as Map<String, dynamic>?;
      notifyListeners();
    } catch (_) {}
    await _syncTracking();
  }

  Future<void> cancel() async {
    if (_activeTrip == null) return;
    try {
      await _api.post('/trips/${_activeTrip!['id']}/cancel', {});
      _activeTrip = null;
      notifyListeners();
    } catch (_) {}
    await _syncTracking();
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
      _fallbackPing = Timer.periodic(const Duration(seconds: 20), (_) => ping());
      debugPrint('TripTracking: GPS stream unavailable, using periodic pings');
    } else {
      _fallbackPing?.cancel();
      _fallbackPing = null;
    }
    notifyListeners();
  }
}
