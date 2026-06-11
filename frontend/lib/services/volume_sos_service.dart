import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Détection SOS via boutons volume.
///
/// **Android** : 3 appuis rapides sur Volume ↓ (app au premier plan).
/// **iOS** : non supporté — Apple ne permet pas d'intercepter les touches
/// volume en arrière-plan sans API privées ; utiliser le bouton SOS in-app.
class VolumeSOSService {
  static const _channel = MethodChannel('com.safealert.safealert/volume_sos');
  static bool _initialized = false;
  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void init(VoidCallback onTrigger) {
    if (_initialized || !isSupported) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'triggerSOS') {
        onTrigger();
      }
    });
  }
}
