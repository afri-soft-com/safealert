import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';

class TripProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _activeTrip;
  Map<String, dynamic>? _followedTrip;
  String? _followTripId;
  bool _loading = false;
  String? _error;
  bool _socketBound = false;

  Map<String, dynamic>? get activeTrip => _activeTrip;
  Map<String, dynamic>? get followedTrip => _followedTrip;
  String? get followTripId => _followTripId;
  bool get loading => _loading;
  String? get error => _error;

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
  }

  Future<Map<String, dynamic>?> fetchTrip(String id) async {
    try {
      final res = await _api.get('/trips/$id');
      if (res['id'] == null) return null;
      _followedTrip = res;
      _followTripId = id;
      notifyListeners();
      return res;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    } catch (_) {
      _error = 'Impossible de charger le trajet';
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
    String? destLabel,
    int etaMinutes = 30,
    List<String>? escortContactIds,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final pos = await LocationService().getCurrentPosition();
      if (pos == null) {
        _error = 'Position GPS indisponible';
        _loading = false;
        notifyListeners();
        return null;
      }
      final res = await _api.post('/trips', {
        'origin_lat': pos.latitude,
        'origin_lng': pos.longitude,
        'dest_lat': destLat,
        'dest_lng': destLng,
        if (destLabel != null) 'dest_label': destLabel,
        'eta_minutes': etaMinutes,
        if (escortContactIds != null && escortContactIds.isNotEmpty)
          'escort_contact_ids': escortContactIds,
      });
      _activeTrip = res['trip'] as Map<String, dynamic>?;
      _loading = false;
      notifyListeners();
      return _activeTrip;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Erreur trajet';
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> ping() async {
    if (_activeTrip == null) return;
    final pos = await LocationService().getCurrentPosition();
    if (pos == null) return;
    try {
      final res = await _api.post('/trips/${_activeTrip!['id']}/ping', {
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
      _activeTrip = res['trip'] as Map<String, dynamic>?;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> arrive() async {
    if (_activeTrip == null) return;
    try {
      final res = await _api.post('/trips/${_activeTrip!['id']}/arrive', {});
      _activeTrip = res['trip'] as Map<String, dynamic>?;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> cancel() async {
    if (_activeTrip == null) return;
    try {
      await _api.post('/trips/${_activeTrip!['id']}/cancel', {});
      _activeTrip = null;
      notifyListeners();
    } catch (_) {}
  }
}
