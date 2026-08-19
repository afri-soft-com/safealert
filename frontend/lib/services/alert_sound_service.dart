import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sons et canaux de notification pour les alertes critiques.
///
/// **Politique mode discret / camouflage** :
/// - Camouflage calculatrice = ne pas attirer l'attention sur l'appareil.
/// - Les sons **forts** d'alerte entrante (sirène in-app + notif locale sonore)
///   sont **désactivés** tant que le mode discret local est actif.
/// - Le déclenchement **SOS discret** (volume / secousse / code contrainte) reste
///   silencieux sur l'émetteur (vibration courte uniquement).
/// - Les push système en arrière-plan peuvent encore utiliser le canal Android
///   `sos_alerts` (son OS) ; le muting discret s'applique surtout au premier plan
///   et au player in-app.
class AlertSoundService {
  static final AlertSoundService _instance = AlertSoundService._();
  AlertSoundService._();
  factory AlertSoundService() => _instance;

  static const sosChannelId = 'sos_alerts';
  static const defaultChannelId = 'safealert_default';

  static const _criticalTypes = {
    'sos_alert',
    'nearby_alert',
    'group_sos',
    'sector_sos',
    'trust_zone_alert',
    'safety_ping_ask',
    'safety_ping_missed',
  };

  final AudioPlayer _player = AudioPlayer();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  DateTime? _lastPlayAt;

  bool get ready => _ready;

  static bool isCriticalPayloadType(String? type) =>
      type != null && _criticalTypes.contains(type);

  static bool isSosPayloadType(String? type) => isCriticalPayloadType(type);

  Future<bool> isDiscreetModeActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('discreet_mode_local') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize() async {
    if (_ready) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _notifications.initialize(
        settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            sosChannelId,
            'Alertes SOS SafeAlert',
            description:
                'Alertes d\'urgence sonores (désactivées en mode discret in-app)',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('sos_alert'),
            enableVibration: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        );
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            defaultChannelId,
            'Notifications SafeAlert',
            description: 'Notifications générales (check-in, groupes, etc.)',
            importance: Importance.defaultImportance,
            playSound: true,
          ),
        );
        await android.requestNotificationsPermission();
      }

      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      _ready = true;
      debugPrint('AlertSoundService ready');
    } catch (e) {
      debugPrint('AlertSoundService init failed: $e');
    }
  }

  /// Son fort d'alerte. Aucun son en mode discret.
  Future<void> playSosAlert() async {
    if (await isDiscreetModeActive()) {
      debugPrint('playSosAlert skipped — mode discret');
      return;
    }
    final now = DateTime.now();
    if (_lastPlayAt != null &&
        now.difference(_lastPlayAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastPlayAt = now;
    try {
      if (!_ready) await initialize();
      await HapticFeedback.heavyImpact();
      await _player.stop();
      await _player.play(AssetSource('sounds/sos_alert.wav'), volume: 1.0);
    } catch (e) {
      debugPrint('playSosAlert failed: $e');
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }

  /// SOS discret local : pas de sirène, vibration seule.
  Future<void> feedbackDiscreteSosTrigger() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  Future<void> showSosLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      if (!_ready) await initialize();
      final discreet = await isDiscreetModeActive();
      await _notifications.show(
        id: title.hashCode ^ body.hashCode,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            sosChannelId,
            'Alertes SOS SafeAlert',
            channelDescription:
                'Alertes d\'urgence sonores (désactivées en mode discret in-app)',
            importance: Importance.max,
            priority: Priority.max,
            playSound: !discreet,
            sound: discreet
                ? null
                : const RawResourceAndroidNotificationSound('sos_alert'),
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: false,
            enableVibration: !discreet,
            silent: discreet,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: !discreet,
            interruptionLevel: discreet
                ? InterruptionLevel.passive
                : InterruptionLevel.timeSensitive,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('showSosLocalNotification failed: $e');
    }
  }

  Future<void> disposePlayer() async {
    await _player.dispose();
  }
}
