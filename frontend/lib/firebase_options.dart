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

  // iOS : valeurs provisoires — compléter après téléchargement de
  // GoogleService-Info.plist (Firebase Console → app iOS → safealert-prod).
  // Voir docs/FIREBASE_SETUP.md §4. Ne pas inventer de plist localement.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: '844603867770',
    projectId: 'safealert-prod',
    storageBucket: 'safealert-prod.firebasestorage.app',
    iosBundleId: 'com.safealert.safealert',
  );
}
