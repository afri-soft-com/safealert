import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Sons et canaux de notification pour les alertes SOS.
///
/// **Politique son (choix produit)** :
/// - Les alertes SOS / signalements **reçus** (cercle, proximité, groupe,
///   secteur, zone) sont **toujours** sonores à priorité max — le camouflage
///   calculatrice ne mute pas une urgence entrante.
/// - L'appareil **émetteur** ne joue jamais la sirène (ni SOS standard, ni
///   signalement). Le SOS discret local garde une vibration courte uniquement.
/// - Les autres notifications utilisent le canal `safealert_default`.
class AlertSoundService {
  static final AlertSoundService _instance = AlertSoundService._();
  AlertSoundService._();
  factory AlertSoundService() => _instance;

  static const sosChannelId = 'sos_alerts';
  static const defaultChannelId = 'safealert_default';

  static const _sosTypes = {
    'sos_alert',
    'nearby_alert',
    'group_sos',
    'sector_sos',
    'trust_zone_alert',
  };

  final AudioPlayer _player = AudioPlayer();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  DateTime? _lastPlayAt;

  bool get ready => _ready;

  static bool isSosPayloadType(String? type) =>
      type != null && _sosTypes.contains(type);

  /// Alias pour appels existants / FCM.
  static bool isCriticalPayloadType(String? type) => isSosPayloadType(type);

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
        settings: const InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        ),
      );

      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            sosChannelId,
            'Alertes SOS SafeAlert',
            description:
                'Alertes d\'urgence sonores prioritaires (toujours audibles)',
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

  /// Son fort d'alerte SOS — toujours (ignore le mode camouflage).
  Future<void> playSosAlert() async {
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

  /// Déclenchement SOS discret local : pas de sirène (émetteur), vibration seule.
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
      await _notifications.show(
        id: title.hashCode ^ body.hashCode,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            sosChannelId,
            'Alertes SOS SafeAlert',
            channelDescription:
                'Alertes d\'urgence sonores prioritaires (toujours audibles)',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('sos_alert'),
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: false,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
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
