import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/local_database.dart';
import '../services/location_service.dart';
import '../utils/network_error.dart' show ApiException, userFacingError;

class CheckInProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final LocalDatabase _cache = LocalDatabase();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _last;
  bool _queuedOffline = false;

  bool get loading => _loading;
  String? get error => _error;
  Map<String, dynamic>? get last => _last;
  bool get queuedOffline => _queuedOffline;

  Future<bool> imSafe({String? incidentId, String? tripId, String? message}) async {
    _loading = true;
    _error = null;
    _queuedOffline = false;
    notifyListeners();
    final pos = await LocationService().getCurrentPosition();
    final payload = {
      if (pos != null) 'lat': pos.latitude,
      if (pos != null) 'lng': pos.longitude,
      if (incidentId != null) 'incident_id': incidentId,
      if (tripId != null) 'trip_id': tripId,
      if (message != null) 'message': message,
    };
    try {
      final res = await _api.post('/checkin', payload);
      _last = res['check_in'] as Map<String, dynamic>?;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      final isNet = e is SocketException || e is http.ClientException;
      if (isNet || (e is ApiException && e.statusCode >= 500)) {
        try {
          await _cache.enqueue('checkin', payload);
          _queuedOffline = true;
          _error =
              'Hors ligne — « En sécurité » enregistré. Envoi auto dès reconnexion.';
          _loading = false;
          notifyListeners();
          return true;
        } catch (_) {}
      }
      _error = userFacingError(e, fallback: 'Impossible d\'envoyer le signal « en sécurité ».');
      _loading = false;
      notifyListeners();
      return false;
    }
  }
}
