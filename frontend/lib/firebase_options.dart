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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAUGfLqvMoiA7D5nxYLjmqAwLU_Kzhsu0g',
    appId: '1:844603867770:android:5ce7ecb4ccb0b2414ff1c3',
    messagingSenderId: '844603867770',
    projectId: 'safealert-prod',
    authDomain: 'safealert-prod.firebaseapp.com',
    storageBucket: 'safealert-prod.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAUGfLqvMoiA7D5nxYLjmqAwLU_Kzhsu0g',
    appId: '1:844603867770:android:5ce7ecb4ccb0b2414ff1c3',
    messagingSenderId: '844603867770',
    projectId: 'safealert-prod',
    storageBucket: 'safealert-prod.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC8eWVdUmyxjdfwcLt5G-fxG4u8wcPWaMQ',
    appId: '1:844603867770:ios:d22d977de1ee3f604ff1c3',
    messagingSenderId: '844603867770',
    projectId: 'safealert-prod',
    storageBucket: 'safealert-prod.firebasestorage.app',
    iosBundleId: 'com.safealert.safealert',
  );
}
