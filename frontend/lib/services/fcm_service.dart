import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import 'alert_sound_service.dart';
import 'api_service.dart';
import 'in_app_alert_service.dart';

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
  static const _pendingOpenPrefsKey = 'safealert_pending_notif_open';

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
    _clearPersistedPending();
    return p;
  }

  void queueOpenFromData(Map<String, dynamic> raw) {
    final data = _stringifyData(raw);
    final type = data['type'];
    if (type == null || type.isEmpty) {
      debugPrint('FCM queueOpen skipped: missing type keys=${data.keys}');
      return;
    }
    if (isOwnPushData(data, currentUserId: _currentUserId)) return;
    _pendingOpen = data;
    _persistPending(data);
    notifyListeners();
  }

  Future<void> _persistPending(Map<String, String> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingOpenPrefsKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _clearPersistedPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingOpenPrefsKey);
    } catch (_) {}
  }

  /// Restore a cold-start / pre-auth pending open (PIN, splash race).
  Future<void> restorePersistedPending() async {
    if (_pendingOpen != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingOpenPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final data = _stringifyData(Map<String, dynamic>.from(decoded));
        if (data['type'] != null && data['type']!.isNotEmpty) {
          _pendingOpen = data;
          notifyListeners();
        }
      }
    } catch (_) {}
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

  /// Merge notification title/body into data map for handlers that only see data.
  static Map<String, dynamic> messageToOpenData(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    final n = message.notification;
    if (n?.title != null && n!.title!.isNotEmpty) {
      data.putIfAbsent('title', () => n.title);
    }
    if (n?.body != null && n!.body!.isNotEmpty) {
      data.putIfAbsent('body', () => n.body);
    }
    return data;
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

      // Local notification cold-start (iOS often opens via this path).
      await AlertSoundService().consumeLaunchPayload((payload) {
        final parsed = parseNotificationPayload(payload);
        if (parsed != null) queueOpenFromData(parsed);
      });

      await restorePersistedPending();

      // iOS: FCM token is useless until APNs registration completes. Without
      // this wait, getToken() often returns null or a token that never receives
      // pushes when the app is killed.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await _waitForApnsToken(messaging);
        debugPrint(
          apns == null
              ? 'FCM: APNs token still null after wait — push may fail when killed'
              : 'FCM: APNs token ready (${apns.length} chars)',
        );
      }

      // Always wire listeners first — iOS can briefly return a null FCM token
      // while APNs is still registering; exiting early used to kill foreground
      // banners/sounds entirely even with the app open.
      _messageSub = FirebaseMessaging.onMessage.listen(_handleMessage);
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        queueOpenFromData(messageToOpenData(message));
      });
      FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

      // Cold start from system (APNs) notification.
      await _captureInitialMessage(messaging);

      // iOS race: getInitialMessage can be null if called too early — retry once.
      if (_pendingOpen == null &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 800), () async {
          await _captureInitialMessage(messaging);
          await AlertSoundService().consumeLaunchPayload((payload) {
            final parsed = parseNotificationPayload(payload);
            if (parsed != null) queueOpenFromData(parsed);
          });
        }));
      }

      _token = await messaging.getToken();
      if (_token == null) {
        debugPrint('FCM: no token yet — listeners active, will retry on refresh');
        messaging.onTokenRefresh.listen((t) {
          _token = t;
          _available = true;
          uploadToken();
          notifyListeners();
        });
        await _api.init();
        notifyListeners();
        return;
      }

      _available = true;
      debugPrint('FCM initialized tokenPrefix=${_token!.substring(0, 12)}…');

      messaging.onTokenRefresh.listen((t) {
        _token = t;
        uploadToken();
      });

      await _api.init();
      if (_api.hasToken) await uploadToken();

      notifyListeners();
    } catch (e) {
      debugPrint('FCM not configured — push notifications disabled ($e)');
    }
  }

  Future<String?> _waitForApnsToken(FirebaseMessaging messaging) async {
    for (var i = 0; i < 15; i++) {
      try {
        final t = await messaging.getAPNSToken();
        if (t != null && t.isNotEmpty) return t;
      } catch (e) {
        debugPrint('FCM getAPNSToken attempt $i failed: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return null;
  }

  Future<void> _captureInitialMessage(FirebaseMessaging messaging) async {
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        debugPrint(
          'FCM getInitialMessage type=${initial.data['type']} '
          'keys=${initial.data.keys.toList()}',
        );
        queueOpenFromData(messageToOpenData(initial));
      }
    } catch (e) {
      debugPrint('FCM getInitialMessage failed: $e');
    }
  }

  /// Re-check launch/pending opens after the UI is ready (PIN / splash).
  Future<void> refreshPendingOpens() async {
    await restorePersistedPending();
    if (_pendingOpen != null) {
      notifyListeners();
      return;
    }
    try {
      await _captureInitialMessage(FirebaseMessaging.instance);
      await AlertSoundService().consumeLaunchPayload((payload) {
        final parsed = parseNotificationPayload(payload);
        if (parsed != null) queueOpenFromData(parsed);
      });
    } catch (_) {}
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
      String? apnsToken;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        } catch (e) {
          debugPrint('FCM upload: getAPNSToken failed: $e');
        }
      }
      await _api.put('/auth/fcm-token', {
        'fcm_token': _token!,
        'device_id': deviceId,
        'device_label': defaultTargetPlatform.name,
        if (apnsToken != null && apnsToken.isNotEmpty) 'apns_token': apnsToken,
      });
      debugPrint(
        apnsToken == null || apnsToken.isEmpty
            ? 'FCM token registered with API'
            : 'FCM+APNs tokens registered with API',
      );
    } catch (e) {
      debugPrint('FCM token upload failed: $e');
    }
  }

  Future<void> _handleMessage(RemoteMessage message) async {
    final data = messageToOpenData(message);
    final type = data['type']?.toString();
    final title = message.notification?.title ??
        data['title']?.toString() ??
        'SafeAlert';
    final body = message.notification?.body ??
        data['body']?.toString() ??
        '';
    debugPrint('FCM foreground: $title type=$type');

    if (_isOwnPush(message)) return;

    // Banner first so the user always sees something even if audio/local
    // notifications fail (common on iOS when UNUserNotificationCenter is
    // owned by Firebase swizzling).
    final presentData = <String, dynamic>{
      ...data,
      if (title.isNotEmpty) 'title': title,
      if (body.isNotEmpty) 'body': body,
      if (type != null && type.isNotEmpty) 'type': type,
    };

    if (AlertSoundService.isSosPayloadType(type)) {
      InAppAlertService().present(presentData);
      queueOpenFromData(data);
      try {
        await AlertSoundService().playSosAlert();
      } catch (e) {
        debugPrint('FCM foreground SOS sound: $e');
      }
      try {
        await AlertSoundService().showSosLocalNotification(
          title: title.isNotEmpty ? title : '🚨 Alerte SafeAlert',
          body: body.isNotEmpty
              ? body
              : 'Une alerte SOS nécessite votre attention.',
          payload: encodeNotificationPayload(data),
        );
      } catch (e) {
        debugPrint('FCM foreground SOS local notif: $e');
      }
      return;
    }

    if (title.isNotEmpty || body.isNotEmpty) {
      InAppAlertService().present(presentData);
      try {
        await AlertSoundService().playGeneralAlert();
      } catch (_) {}
      try {
        await AlertSoundService().showSosLocalNotification(
          title: title.isNotEmpty ? title : 'SafeAlert',
          body: body,
          payload: encodeNotificationPayload(data),
        );
      } catch (_) {}
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
    // On iOS, the system already plays aps.sound when a notification payload
    // is present and the app is killed/backgrounded. Still show a local
    // notification with payload so tap → action screen works if the OS
    // delivers a data-only wake, and reinforce sound on Android.
    final sounds = AlertSoundService();
    await sounds.initialize();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await sounds.playSosAlert();
    }
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        '🚨 Alerte SafeAlert';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        'Une alerte SOS nécessite votre attention.';
    // Avoid duplicate banners on iOS when APNs already showed the remote notif.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      if (message.notification != null) {
        debugPrint('FCM iOS background: system notification present — skip local duplicate');
        return;
      }
    }
    await sounds.showSosLocalNotification(
      title: title,
      body: body,
      payload: FCMService.encodeNotificationPayload(message.data),
    );
  } catch (e) {
    debugPrint('FCM background SOS sound failed: $e');
  }
}
