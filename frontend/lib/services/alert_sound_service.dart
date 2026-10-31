import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_sound_prefs.dart';

/// Sons et canaux de notification pour les alertes SafeAlert.
///
/// **Politique son** :
/// - Les alertes SOS / signalements **reçus** sont toujours sonores
///   (priorité max) — le camouflage calculatrice ne mute pas une urgence.
/// - L'émetteur ne joue jamais la sirène.
/// - Le son est **propre à SafeAlert** (pas le bip système générique).
/// - L'utilisateur choisit parmi 3 sons SafeAlert dans Paramètres.
class AlertSoundService {
  static final AlertSoundService _instance = AlertSoundService._();
  AlertSoundService._();
  factory AlertSoundService() => _instance;

  /// Legacy channel — kept for older installs; FCM SOS uses *_v2 now.
  static const legacySosChannelId = 'sos_alerts';
  static const fcmSosChannelId = 'safealert_sos_siren_v2';
  static const generalChannelId = 'safealert_general_v2';
  static const legacyGeneralChannelId = 'safealert_general_v1';

  static const _sosTypes = {
    'sos_alert',
    'nearby_alert',
    'group_sos',
    'group_report',
    'sector_sos',
    'trust_zone_alert',
    'safety_ping_ask',
    'safety_ping_missed',
  };

  final AudioPlayer _player = AudioPlayer();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final NotificationSoundPrefs _prefs = NotificationSoundPrefs();
  bool _ready = false;
  DateTime? _lastPlayAt;
  void Function(String? payload)? _onNotificationTap;

  bool get ready => _ready;

  SafeAlertSoundId get preferredSound => _prefs.current;

  String get activeSosChannelId => _prefs.current.androidSosChannelId;

  static bool isSosPayloadType(String? type) =>
      type != null && _sosTypes.contains(type);

  static bool isCriticalPayloadType(String? type) => isSosPayloadType(type);

  Future<void> initialize({
    void Function(String? payload)? onNotificationTap,
  }) async {
    if (onNotificationTap != null) {
      _onNotificationTap = onNotificationTap;
    }
    if (_ready) return;
    try {
      await _prefs.load();

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentSound: true,
      );
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        ),
        onDidReceiveNotificationResponse: (response) {
          _onNotificationTap?.call(response.payload);
        },
      );

      // Explicit iOS permission + foreground presentation (Firebase may own
      // UNUserNotificationCenter; still request so local alerts can sound).
      try {
        await _notifications
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } catch (_) {}

      await _ensureAndroidChannels();
      await _configureAudioSession();

      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      _ready = true;
      debugPrint(
        'AlertSoundService ready sound=${_prefs.current.storageKey} '
        'channel=$activeSosChannelId',
      );
    } catch (e) {
      debugPrint('AlertSoundService init failed: $e');
    }
  }

  /// Play SOS even if the hardware mute switch is on (iOS) / DND light.
  Future<void> _configureAudioSession() async {
    try {
      final ctx = AudioContextConfig(
        respectSilence: false,
        stayAwake: true,
        focus: AudioContextConfigFocus.duckOthers,
        route: AudioContextConfigRoute.system,
      ).build();
      await AudioPlayer.global.setAudioContext(ctx);
      await _player.setAudioContext(ctx);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
    } catch (e) {
      debugPrint('AlertSoundService audio session: $e');
    }
  }

  Future<void> _ensureAndroidChannels() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    for (final sound in SafeAlertSoundId.values) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          sound.androidSosChannelId,
          'Alertes SafeAlert — ${sound.labelFr}',
          description:
              'Son SafeAlert distinct (${sound.labelFr}). Toujours audible pour les urgences.',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(sound.androidRawName),
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
    }

    // Channel id used by FCM sendPush (must match backend SOS_CHANNEL_ID).
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        fcmSosChannelId,
        'Alertes SOS SafeAlert (sirène)',
        description: 'Canal FCM SOS — son sirène SafeAlert',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('safealert_siren'),
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    // Soft general channel still uses SafeAlert beacon (not system default).
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        generalChannelId,
        'Notifications SafeAlert',
        description: 'Notifications générales avec son SafeAlert',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('safealert_beacon'),
        enableVibration: true,
      ),
    );

    // Keep legacy channel pointed at siren so old FCM payloads still sound.
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        legacySosChannelId,
        'Alertes SOS SafeAlert',
        description: 'Canal historique — son sirène SafeAlert',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('safealert_siren'),
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    await android.requestNotificationsPermission();
  }

  /// Persist preference and recreate channel usage for local notifications.
  Future<void> setPreferredSound(SafeAlertSoundId id) async {
    await _prefs.setSound(id);
    if (!_ready) {
      await initialize();
    } else {
      await _ensureAndroidChannels();
    }
  }

  /// Preview the chosen SafeAlert sound (Settings).
  Future<void> previewSound([SafeAlertSoundId? id]) async {
    final sound = id ?? _prefs.current;
    try {
      if (!_ready) await initialize();
      await _player.stop();
      await _player.play(AssetSource(sound.assetPath), volume: 1.0);
    } catch (e) {
      debugPrint('previewSound failed: $e');
    }
  }

  bool _launchPayloadConsumed = false;

  /// If the app was launched by tapping a local notification, deliver payload once.
  Future<void> consumeLaunchPayload(void Function(String? payload)? onTap) async {
    if (_launchPayloadConsumed) return;
    final cb = onTap ?? _onNotificationTap;
    if (cb == null) return;
    try {
      // initialize() must already have run (avoid recurse).
      if (!_ready) return;
      final details = await _notifications.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        _launchPayloadConsumed = true;
        final payload = details!.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          debugPrint('AlertSoundService launch payload present');
          cb(payload);
        }
      }
    } catch (e) {
      debugPrint('consumeLaunchPayload failed: $e');
    }
  }

  /// Soft SafeAlert beacon for non-SOS notifications (still branded).
  Future<void> playGeneralAlert() async {
    try {
      if (!_ready) await initialize();
      await _configureAudioSession();
      await _player.stop();
      await _player.play(
        AssetSource(SafeAlertSoundId.beacon.assetPath),
        volume: 0.85,
        mode: PlayerMode.mediaPlayer,
      );
    } catch (e) {
      debugPrint('playGeneralAlert failed: $e');
    }
  }

  /// Son fort d'alerte — toujours (ignore le mode camouflage).
  Future<void> playSosAlert() async {
    final now = DateTime.now();
    if (_lastPlayAt != null &&
        now.difference(_lastPlayAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastPlayAt = now;
    try {
      if (!_ready) await initialize();
      if (!_prefs.loaded) await _prefs.load();
      await _configureAudioSession();
      await HapticFeedback.heavyImpact();
      await _player.stop();
      await _player.play(
        AssetSource(_prefs.current.assetPath),
        volume: 1.0,
        mode: PlayerMode.mediaPlayer,
      );
    } catch (e) {
      debugPrint('playSosAlert failed: $e');
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
      // Last resort: system tray local notif (plays channel / .caf sound).
      try {
        await showSosLocalNotification(
          title: 'SafeAlert',
          body: 'Alerte reçue',
        );
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
      if (!_prefs.loaded) await _prefs.load();
      final sound = _prefs.current;
      await _notifications.show(
        id: title.hashCode ^ body.hashCode ^ DateTime.now().millisecond,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            sound.androidSosChannelId,
            'Alertes SafeAlert — ${sound.labelFr}',
            channelDescription:
                'Alertes d\'urgence sonores SafeAlert (toujours audibles)',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(sound.androidRawName),
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: false,
            enableVibration: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
            sound: sound.iosSoundFile,
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
