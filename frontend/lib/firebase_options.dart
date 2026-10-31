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

  // iOS aligné sur safealert-be940 (même projet que le backend FCM / Android).
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDA1LkClrZfgFaWN3hOcexFF0oR6QAJo4M',
    appId: '1:552870535150:ios:38fd4c3f1836a2305938ff',
    messagingSenderId: '552870535150',
    projectId: 'safealert-be940',
    storageBucket: 'safealert-be940.firebasestorage.app',
    iosBundleId: 'com.kakiranya.safealert',
  );
}
