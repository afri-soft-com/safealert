import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
import 'alert_sound_service.dart';
import 'api_service.dart';

class FCMService extends ChangeNotifier {
  static final FCMService _instance = FCMService._();
  FCMService._();
  factory FCMService() => _instance;

  final ApiService _api = ApiService();
  bool _initialized = false;
  bool _available = false;
  String? _token;
  StreamSubscription? _messageSub;

  bool get available => _available;
  String? get token => _token;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      final messaging = FirebaseMessaging.instance;

      // iOS + Android 13+ (POST_NOTIFICATIONS) — son demandé explicitement
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: false,
        announcement: false,
      );

      await AlertSoundService().initialize();

      _token = await messaging.getToken();
      if (_token == null) {
        debugPrint('FCM: no token — push disabled');
        return;
      }

      _available = true;
      debugPrint('FCM initialized');

      messaging.onTokenRefresh.listen((t) {
        _token = t;
        uploadToken();
      });

      _messageSub = FirebaseMessaging.onMessage.listen(_handleMessage);
      FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

      await _api.init();
      if (_api.hasToken) await uploadToken();

      notifyListeners();
    } catch (e) {
      debugPrint('FCM not configured — push notifications disabled ($e)');
    }
  }

  Future<void> uploadToken() async {
    if (!_available || _token == null) return;
    try {
      await _api.init();
      if (!_api.hasToken) return;
      final deviceId = await _api.ensureDeviceId();
      await _api.put('/auth/fcm-token', {
        'fcm_token': _token!,
        'device_id': deviceId,
        'device_label': defaultTargetPlatform.name,
      });
      debugPrint('FCM token registered with API');
    } catch (e) {
      debugPrint('FCM token upload failed: $e');
    }
  }

  Future<void> _handleMessage(RemoteMessage message) async {
    final type = message.data['type'] as String?;
    final title = message.notification?.title ?? 'SafeAlert';
    final body = message.notification?.body ?? '';
    debugPrint('FCM foreground: $title type=$type');

    if (AlertSoundService.isSosPayloadType(type)) {
      await AlertSoundService().playSosAlert();
      // En avant-plan FCM n'affiche pas la notif système : notif locale canal SOS.
      if (title.isNotEmpty || body.isNotEmpty) {
        await AlertSoundService().showSosLocalNotification(
          title: title.isNotEmpty ? title : '🚨 Alerte SafeAlert',
          body: body.isNotEmpty
              ? body
              : 'Une alerte SOS nécessite votre attention.',
          payload: type,
        );
      }
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }
}

/// Handler top-level (isolate). Canal Android `sos_alerts` + rejeu local.
@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  final type = message.data['type'] as String?;
  debugPrint('FCM background: ${message.notification?.title} type=$type');
  if (!AlertSoundService.isSosPayloadType(type)) return;

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final sounds = AlertSoundService();
    await sounds.initialize();
    await sounds.playSosAlert();
  } catch (e) {
    debugPrint('FCM background SOS sound failed: $e');
  }
}
