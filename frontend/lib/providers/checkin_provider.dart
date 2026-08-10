import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../utils/network_error.dart';

class CheckInProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _last;

  bool get loading => _loading;
  String? get error => _error;
  Map<String, dynamic>? get last => _last;

  Future<bool> imSafe({String? incidentId, String? tripId, String? message}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final pos = await LocationService().getCurrentPosition();
      final res = await _api.post('/checkin', {
        if (pos != null) 'lat': pos.latitude,
        if (pos != null) 'lng': pos.longitude,
        if (incidentId != null) 'incident_id': incidentId,
        if (tripId != null) 'trip_id': tripId,
        if (message != null) 'message': message,
      });
      _last = res['check_in'] as Map<String, dynamic>?;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = userFacingError(e, fallback: 'Impossible d\'envoyer le signal « en sécurité ».');
      _loading = false;
      notifyListeners();
      return false;
    }
  }
}
