import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Plateforme non supportée pour Firebase.');
    }
  }

  // Aligné sur google-services.json (projet safealert-be940).
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAcyB7nckbY2w-4zS97cd5xEYF8D2-NxSc',
    appId: '1:552870535150:android:887347eb7ddad7a05938ff',
    messagingSenderId: '552870535150',
    projectId: 'safealert-be940',
    authDomain: 'safealert-be940.firebaseapp.com',
    storageBucket: 'safealert-be940.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAcyB7nckbY2w-4zS97cd5xEYF8D2-NxSc',
    appId: '1:552870535150:android:887347eb7ddad7a05938ff',
    messagingSenderId: '552870535150',
    projectId: 'safealert-be940',
    storageBucket: 'safealert-be940.firebasestorage.app',
  );

  // iOS : encore l’ancien projet jusqu’à dépôt d’un GoogleService-Info.plist safealert-be940.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC8eWVdUmyxjdfwcLt5G-fxG4u8wcPWaMQ',
    appId: '1:844603867770:ios:d22d977de1ee3f604ff1c3',
    messagingSenderId: '844603867770',
    projectId: 'safealert-prod',
    storageBucket: 'safealert-prod.firebasestorage.app',
    iosBundleId: 'com.safealert.safealert',
  );
}
