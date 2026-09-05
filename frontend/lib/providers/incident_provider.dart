import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/alert_sound_service.dart';
import '../services/api_service.dart';
import '../services/app_config_service.dart';
import '../services/local_database.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';
import '../data/incident_types.dart';
import '../utils/location_format.dart';
import '../utils/network_error.dart';

class IncidentProvider extends ChangeNotifier {
  final ApiService _api;
  final LocalDatabase _cache;
  final AlertSoundService? _injectedSounds;
  final String? Function()? _resolveUserId;

  AlertSoundService get _sounds => _injectedSounds ?? AlertSoundService();
  String? get _myUserId => _resolveUserId?.call() ?? SocketService().currentUserId;

  /// Last SOS we sent — used to ignore our own socket/FCM echo.
  DateTime? _ownOutgoingAlertAt;
  String? _ownOutgoingIncidentId;

  IncidentProvider({
    ApiService? apiService,
    LocalDatabase? localDatabase,
    AlertSoundService? alertSoundService,
    String? Function()? currentUserId,
  })  : _api = apiService ?? ApiService(),
        _cache = localDatabase ?? LocalDatabase(),
        _injectedSounds = alertSoundService,
        _resolveUserId = currentUserId {
    SocketService().setSosAlertHandler(handleSosAlert);
    SocketService().setSosLiveHandler(handleSosLive);
  }
  List<Map<String, dynamic>> _incidents = [];
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _heatmap = [];
  Map<String, dynamic>? _lastSosAlert;
  bool _loading = false;
  bool _isOffline = false;
  List<IncidentTypeDef> _incidentTypes = List<IncidentTypeDef>.from(kFallbackIncidentTypes);

  List<Map<String, dynamic>> get incidents => _incidents;
  Map<String, dynamic>? get stats => _stats;
  List<Map<String, dynamic>> get heatmap => _heatmap;
  Map<String, dynamic>? get lastSosAlert => _lastSosAlert;
  bool get loading => _loading;
  bool get isOffline => _isOffline;
  List<IncidentTypeDef> get incidentTypes => _incidentTypes;

  String labelForType(String? slug) =>
      incidentTypeLabel(slug, catalog: _incidentTypes);

  Future<void> fetchIncidentTypes() async {
    try {
      final res = await _api.get('/incident-types');
      final raw = (res['data'] as List?) ?? const [];
      final parsed = raw
          .whereType<Map>()
          .map((e) => IncidentTypeDef.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.slug.isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) {
        _incidentTypes = parsed;
        await _cache.put(
          'incident_types',
          parsed.map((t) => t.toJson()).toList(),
        );
        notifyListeners();
        return;
      }
    } catch (_) {
      final cached = await _cache.get('incident_types');
      if (cached is List && cached.isNotEmpty) {
        _incidentTypes = cached
            .whereType<Map>()
            .map((e) => IncidentTypeDef.fromJson(Map<String, dynamic>.from(e)))
            .where((t) => t.slug.isNotEmpty)
            .toList();
        if (_incidentTypes.isNotEmpty) {
          notifyListeners();
          return;
        }
      }
    }
    _incidentTypes = List<IncidentTypeDef>.from(kFallbackIncidentTypes);
    notifyListeners();
  }

  void handleSosAlert(Map<String, dynamic> alert) {
    _lastSosAlert = alert;
    // Destinataires seulement — pas de sirène sur l'appareil émetteur.
    if (!_isOwnIncomingAlert(alert)) {
      _sounds.playSosAlert();
    }
    fetchIncidents();
  }

  bool _isOwnIncomingAlert(Map<String, dynamic> alert) {
    final myId = _myUserId;
    final sender = alert['user_id']?.toString() ?? alert['userId']?.toString();
    if (myId != null && sender != null && sender.isNotEmpty) {
      return sender == myId;
    }
    final alertId = alert['id']?.toString();
    if (_ownOutgoingIncidentId != null &&
        alertId != null &&
        alertId == _ownOutgoingIncidentId) {
      return true;
    }
    // Écho socket sans user_id (API plus ancienne) juste après notre envoi.
    if (sender == null &&
        _ownOutgoingAlertAt != null &&
        DateTime.now().difference(_ownOutgoingAlertAt!) <
            const Duration(seconds: 5)) {
      return true;
    }
    return false;
  }

  void _markOwnOutgoing({String? incidentId}) {
    _ownOutgoingAlertAt = DateTime.now();
    _ownOutgoingIncidentId = incidentId;
  }

  /// Mises à jour live (batterie / position) — pas de sirène.
  void handleSosLive(Map<String, dynamic> alert) {
    _lastSosAlert = alert;
    notifyListeners();
  }

  Future<void> fetchIncidents({
    double? lat,
    double? lng,
    double? radiusKm,
    int hours = 24,
    String? incidentType,
    List<String>? severities,
  }) async {
    _loading = true;
    _isOffline = false;
    notifyListeners();

    // Empty multi-select → no markers (no API call).
    if (severities != null && severities.isEmpty) {
      _incidents = [];
      _loading = false;
      notifyListeners();
      return;
    }

    try {
      String path = '/map/incidents?limit=100&hours=$hours';
      if (lat != null && lng != null && radiusKm != null) {
        path += '&lat=$lat&lng=$lng&radius_km=$radiusKm';
      }
      if (incidentType != null && incidentType.isNotEmpty && incidentType != 'all') {
        path += '&incident_type=$incidentType';
      }
      if (severities != null && severities.isNotEmpty) {
        final sorted = [...severities]..sort();
        path += '&severity=${Uri.encodeQueryComponent(sorted.join(','))}';
      }
      final res = await _api.get(path);
      _incidents = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      await _cache.put('incidents', _incidents);
    } catch (_) {
      final cached = await _cache.get('incidents', maxAgeSeconds: 300);
      if (cached != null) {
        _incidents = (cached as List).cast<Map<String, dynamic>>();
        _isOffline = true;
      } else {
        _incidents = [];
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> reportIncident(
    double lat,
    double lng,
    String type, {
    String? description,
    bool anonymous = false,
    dynamic evidence,
    bool consentEvidence = false,
  }) async {
    final payload = {
      'lat': lat,
      'lng': lng,
      'incident_type': type,
      if (description != null) 'description': description,
      'is_anonymous': anonymous,
      if (evidence != null && consentEvidence) ...{
        'evidence': evidence is List ? evidence : [evidence],
        'consent_evidence': true,
      },
    };
    try {
      await _api.post('/map/incidents', payload);
      await fetchIncidents();
    } catch (_) {
      await _cache.enqueue('report', payload);
      _isOffline = true;
      notifyListeners();
    }
  }

  Future<void> publishLiveStatus(String incidentId) async {
    try {
      final pos = await LocationService().getCurrentPosition();
      if (pos == null) return;
      int? battery;
      try {
        battery = await Battery().batteryLevel;
      } catch (_) {}
      await _api.post('/sos/live', {
        'incident_id': incidentId,
        'lat': pos.latitude,
        'lng': pos.longitude,
        if (battery != null) 'battery_pct': battery,
      });
    } catch (_) {}
  }

  Future<void> fetchStats() async {
    try {
      final res = await _api.get('/map/stats');
      _stats = res;
      await _cache.put('stats', _stats);
      notifyListeners();
    } catch (_) {
      final cached = await _cache.get('stats', maxAgeSeconds: 600);
      if (cached != null) {
        _stats = cached as Map<String, dynamic>;
        _isOffline = true;
        notifyListeners();
      }
    }
  }

  Future<void> fetchHeatmap({int days = 30, String? slot}) async {
    try {
      var path = '/map/heatmap?days=$days';
      if (slot != null && slot.isNotEmpty) path += '&slot=$slot';
      final res = await _api.get(path);
      _heatmap = (res['zones'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      await _cache.put('heatmap', _heatmap);
      notifyListeners();
    } catch (_) {
      final cached = await _cache.get('heatmap', maxAgeSeconds: 3600);
      if (cached != null) {
        _heatmap = (cached as List).cast<Map<String, dynamic>>();
        _isOffline = true;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>?> fetchCitizenDispatch(String incidentId) async {
    try {
      return await _api.get('/leader/incidents/$incidentId/citizen-status');
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> triggerSOS(double lat, double lng, {String? type, String? description}) async {
    await AppConfigService().refresh();
    if (!AppConfigService().canSendSos) {
      return {
        'blocked': true,
        'message': AppConfigService().maintenanceBanner.isNotEmpty
            ? AppConfigService().maintenanceBanner
            : 'Les alertes sont temporairement indisponibles. Utilisez l\'annuaire d\'urgence si besoin.',
      };
    }

    final resolved = await LocationService().getPositionWithSource();
    final pos = resolved.position;
    var useLat = pos?.latitude ?? lat;
    var useLng = pos?.longitude ?? lng;
    if ((useLat.abs() < 0.0001 && useLng.abs() < 0.0001)) {
      // Still null-island — server may substitute users.last_lat/last_lng
      useLat = lat;
      useLng = lng;
    }

    int? battery;
    try {
      battery = await Battery().batteryLevel;
    } catch (_) {}

    final payload = {
      'lat': useLat,
      'lng': useLng,
      'incident_type': type ?? 'sos',
      if (description != null) 'description': description,
      if (battery != null) 'battery': battery,
    };
    final isDiscrete = (type ?? 'sos') == 'sos_discret';
    try {
      if (pos != null) {
        await LocationService().updatePosition(useLat, useLng);
      }
      final res = await _api.post('/sos/trigger', payload);
      if (resolved.source == 'last_known' || resolved.source == 'cache') {
        res['positionNote'] =
            'Position approximative (dernière connue). Activez le GPS pour une localisation plus précise.';
      } else if (resolved.source == 'none') {
        res['positionNote'] =
            'GPS indisponible — le serveur a utilisé votre dernière position enregistrée si elle existe.';
      }
      _markOwnOutgoing(incidentId: res['incident']?['id']?.toString());
      // Émetteur : jamais de sirène. SOS discret = vibration courte seulement.
      if (isDiscrete) {
        await _sounds.feedbackDiscreteSosTrigger();
      }
      return res;
    } catch (e) {
      if (e is ApiException && (e.statusCode == 400 || e.statusCode == 422)) {
        return {
          'blocked': true,
          'message': userFacingError(
            e,
            fallback:
                'Position GPS indisponible. Activez la localisation et réessayez, ou utilisez l\'annuaire d\'urgence.',
          ),
        };
      }
      await _cache.enqueuePendingSos(payload);
      _isOffline = true;
      notifyListeners();
      // Optional SMS fallback if we have trust contacts cached
      await _trySmsFallback(payload);
      _markOwnOutgoing();
      if (isDiscrete) {
        await _sounds.feedbackDiscreteSosTrigger();
      }
      return {
        'queued': true,
        'message': 'Alerte enregistrée hors ligne — envoi automatique dès que le réseau revient',
        ...payload,
      };
    }
  }

  Future<void> _trySmsFallback(Map<String, dynamic> payload) async {
    try {
      final contacts = await _cache.get('trust_contacts', maxAgeSeconds: 86400 * 7)
          ?? await _cache.get('contacts', maxAgeSeconds: 86400 * 7);
      if (contacts is! List || contacts.isEmpty) return;
      final first = contacts.first;
      String? phone;
      if (first is Map) {
        phone = first['contact_phone']?.toString() ?? first['phone']?.toString();
      }
      if (phone == null || phone.isEmpty) return;
      final lat = payload['lat'];
      final lng = payload['lng'];
      final where = LocationFormat.displayLine(
        zoneName: payload['zone_name']?.toString(),
        lat: lat as num?,
        lng: lng as num?,
        approximate: true,
      );
      final body = Uri.encodeComponent(
        'SafeAlert SOS — j\'ai besoin d\'aide. Lieu : $where. Carte : https://maps.google.com/?q=$lat,$lng',
      );
      final uri = Uri.parse('sms:$phone?body=$body');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  /// Renvoie les SOS en file locale (après perte réseau).
  Future<int> flushPendingSos() async => flushOfflineQueue(kinds: const ['sos']);

  /// Flush SOS + signalements + messages groupe hors-ligne (avec backoff).
  Future<int> flushOfflineQueue({List<String>? kinds}) async {
    final pending = await _cache.listPending(dueOnly: true);
    var sent = 0;
    for (final item in pending) {
      final kind = item['kind'] as String;
      if (kinds != null && !kinds.contains(kind)) continue;
      final id = item['id'] as int;
      final payload = item['payload'] as Map<String, dynamic>;
      try {
        if (kind == 'sos') {
          await _api.post('/sos/trigger', payload);
        } else if (kind == 'report') {
          await _api.post('/map/incidents', payload);
        } else if (kind == 'group_message') {
          final groupId = payload['group_id'];
          await _api.post('/groups/$groupId/messages', {
            'content': payload['content'],
          });
        } else {
          continue;
        }
        await _cache.removePending(id);
        sent++;
      } catch (_) {
        await _cache.bumpPendingAttempt(id);
        // Continue other kinds; stop only for same kind chain via backoff
        continue;
      }
    }
    if (sent > 0) {
      _isOffline = false;
      await fetchIncidents();
      notifyListeners();
    }
    return sent;
  }

  Future<bool> cancelSOS() async {
    try {
      await _api.post('/sos/cancel', {});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyIncident(dynamic id) async {
    try {
      await _api.post('/map/incidents/$id/verify', {});
      await fetchIncidents();
      return true;
    } catch (e) {
      _lastVerifyError = userFacingError(e, fallback: 'Impossible de confirmer le signalement.');
      return false;
    }
  }

  String? _lastVerifyError;
  String? get lastVerifyError => _lastVerifyError;
}