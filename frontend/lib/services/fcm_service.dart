import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
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
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final messaging = FirebaseMessaging.instance;

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await messaging.requestPermission(
          alert: true, badge: true, sound: true,
        );
      }

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

      // Upload if already authenticated (token may already be in ApiService)
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
      await _api.put('/auth/fcm-token', {'fcm_token': _token!});
      debugPrint('FCM token registered with API');
    } catch (e) {
      debugPrint('FCM token upload failed: $e');
    }
  }

  void _handleMessage(RemoteMessage message) {
    debugPrint('FCM foreground: ${message.notification?.title}');
  }

  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    debugPrint('FCM background: ${message.notification?.title}');
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }
}
