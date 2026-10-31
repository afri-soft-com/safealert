import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String? _currentUserId;
  StreamSubscription? _messageSub;
  StreamSubscription? _openedSub;

  /// Pending navigation from notification tap (consumed by root navigator).
  Map<String, String>? _pendingOpen;

  bool get available => _available;
  String? get token => _token;
  Map<String, String>? get pendingOpen => _pendingOpen;

  static const _userIdPrefsKey = 'safealert_current_user_id';

  void setCurrentUserId(String? id) {
    _currentUserId = id;
    SharedPreferences.getInstance().then((prefs) {
      if (id == null || id.isEmpty) {
        prefs.remove(_userIdPrefsKey);
      } else {
        prefs.setString(_userIdPrefsKey, id);
      }
    });
  }

  Map<String, String>? takePendingOpen() {
    final p = _pendingOpen;
    _pendingOpen = null;
    return p;
  }

  void queueOpenFromData(Map<String, dynamic> raw) {
    final data = _stringifyData(raw);
    final type = data['type'];
    if (type == null || type.isEmpty) return;
    if (isOwnPushData(data, currentUserId: _currentUserId)) return;
    _pendingOpen = data;
    notifyListeners();
  }

  static Map<String, String> _stringifyData(Map<String, dynamic> raw) {
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (v == null) return;
      final s = v.toString();
      if (s.isEmpty) return;
      out[k] = s;
    });
    return out;
  }

  bool _isOwnPush(RemoteMessage message) {
    return isOwnPushData(message.data, currentUserId: _currentUserId);
  }

  static bool isOwnPushData(
    Map<String, dynamic> data, {
    String? currentUserId,
  }) {
    final sender = data['userId'] ?? data['user_id'];
    if (currentUserId == null ||
        currentUserId.isEmpty ||
        sender == null ||
        sender.toString().isEmpty) {
      return false;
    }
    return sender.toString() == currentUserId;
  }

  static Future<bool> isOwnPushFromPrefs(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return isOwnPushData(
        data,
        currentUserId: prefs.getString(_userIdPrefsKey),
      );
    } catch (_) {
      return false;
    }
  }

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

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: false,
        announcement: false,
        provisional: false,
      );

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      await AlertSoundService().initialize(
        onNotificationTap: (payload) {
          final parsed = parseNotificationPayload(payload);
          if (parsed != null) queueOpenFromData(parsed);
        },
      );

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
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        queueOpenFromData(message.data);
      });

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        queueOpenFromData(initial.data);
      }

      FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

      await _api.init();
      if (_api.hasToken) await uploadToken();

      notifyListeners();
    } catch (e) {
      debugPrint('FCM not configured — push notifications disabled ($e)');
    }
  }

  /// Local notification payload: JSON map, or legacy bare type string.
  static Map<String, dynamic>? parseNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      /* legacy */
    }
    return {'type': payload};
  }

  static String encodeNotificationPayload(Map<String, dynamic> data) {
    try {
      return jsonEncode(_stringifyData(data));
    } catch (_) {
      return data['type']?.toString() ?? 'alert';
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
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'SafeAlert';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        '';
    debugPrint('FCM foreground: $title type=$type');

    if (_isOwnPush(message)) return;

    if (AlertSoundService.isSosPayloadType(type)) {
      await AlertSoundService().playSosAlert();
      await AlertSoundService().showSosLocalNotification(
        title: title.isNotEmpty ? title : '🚨 Alerte SafeAlert',
        body: body.isNotEmpty
            ? body
            : 'Une alerte SOS nécessite votre attention.',
        payload: encodeNotificationPayload(message.data),
      );
      // Critical alerts: open the action screen as soon as the user taps the
      // local notification (queued via AlertSoundService). Also auto-open for
      // safety-ping miss in foreground so the recipient sees next steps.
      if (type == 'safety_ping_missed') {
        queueOpenFromData(message.data);
      }
      return;
    }

    if (title.isNotEmpty || body.isNotEmpty) {
      await AlertSoundService().playGeneralAlert();
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _openedSub?.cancel();
    super.dispose();
  }
}

@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  final type = message.data['type'] as String?;
  debugPrint('FCM background: ${message.notification?.title} type=$type');
  if (!AlertSoundService.isSosPayloadType(type)) return;
  if (await FCMService.isOwnPushFromPrefs(message.data)) return;

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final sounds = AlertSoundService();
    await sounds.initialize();
    await sounds.playSosAlert();
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        '🚨 Alerte SafeAlert';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        'Une alerte SOS nécessite votre attention.';
    await sounds.showSosLocalNotification(
      title: title,
      body: body,
      payload: FCMService.encodeNotificationPayload(message.data),
    );
  } catch (e) {
    debugPrint('FCM background SOS sound failed: $e');
  }
}
