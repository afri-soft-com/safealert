# Configuration Firebase — SafeAlert

Guide pas à pas pour activer les notifications push (FCM) sur Android et le backend SafeAlert.

---

## Prérequis

- Compte [Firebase Console](https://console.firebase.google.com/)
- Flutter SDK installé
- Package Android : `com.safealert.safealert` (voir `frontend/android/app/build.gradle.kts`)

---

## 1. Créer un projet Firebase

1. Ouvrez [console.firebase.google.com](https://console.firebase.google.com/)
2. **Ajouter un projet** → nommez-le (ex. `safealert-prod`)
3. Désactivez Google Analytics si non nécessaire
4. Créez le projet

---

## 2. Ajouter l'application Android

1. Dans le projet Firebase → **Ajouter une application** → **Android**
2. **Nom du package Android** : `com.safealert.safealert`
3. (Optionnel) Surnom et certificat SHA-1 pour Auth — non requis pour FCM seul
4. Téléchargez **`google-services.json`**
5. Placez-le dans :

```
frontend/android/app/google-services.json
```

> Ce fichier contient des identifiants publics — ne pas le confondre avec la clé de compte de service backend.

Le plugin Gradle `com.google.gms.google-services` est déjà configuré dans `frontend/android/app/build.gradle.kts`.

---

## 3. Configurer Flutter (`firebase_options.dart`)

### Option A — FlutterFire CLI (recommandé)

```bash
dart pub global activate flutterfire_cli
cd frontend
flutterfire configure
```

Sélectionnez votre projet Firebase et les plateformes (Android, iOS).

Cela génère `frontend/lib/firebase_options.dart`. Mettez à jour `fcm_service.dart` :

```dart
import '../firebase_options.dart';
// ...
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

### Option B — Manuel

1. Copiez `frontend/lib/firebase_options.dart.example` vers `frontend/lib/firebase_options.dart`
2. Remplissez les valeurs depuis la console Firebase → Paramètres du projet → Vos applications
3. Appliquez la même modification dans `fcm_service.dart` que ci-dessus

---

## 4. iOS

L'app iOS est enregistrée dans Firebase (`safealert-prod`, app **SafeAlert iOS**) avec le bundle ID **`com.safealert.safealert`**.

### Fichiers configurés dans le dépôt

| Fichier | Rôle |
|---------|------|
| `frontend/ios/Runner/GoogleService-Info.plist` | Config Firebase iOS (`safealert-prod`) |
| `frontend/lib/firebase_options.dart` | Section `ios` complétée |
| `frontend/ios/Podfile` | CocoaPods (Firebase via plugins Flutter) |
| `frontend/ios/Runner/Runner.entitlements` | Push Notifications (`aps-environment: development`) |
| `frontend/ios/Runner/Info.plist` | `UIBackgroundModes` : `remote-notification` |

> **Attention :** un `GoogleService-Info.plist` trouvé dans `Downloads` peut appartenir à un **autre projet** (ex. AutoDiag). Vérifiez `PROJECT_ID` = `safealert-prod` et `BUNDLE_ID` = `com.safealert.safealert`.

### Régénérer la config iOS

```bash
cd frontend
dart pub global activate flutterfire_cli
flutterfire configure --project=safealert-prod --platforms=ios,android --ios-bundle-id=com.safealert.safealert --yes
```

Sur Mac : `cd ios && pod install`

### Étapes manuelles restantes (Apple + push prod)

1. **Compte Apple Developer** — certificat / provisioning pour `com.safealert.safealert`
2. **Clé APNs** (.p8) — [Apple Developer → Keys](https://developer.apple.com/account/resources/authkeys/list)
3. **Firebase Console** → Paramètres → **Cloud Messaging** → **Configuration Apple** → téléverser la clé APNs (Key ID, Team ID, .p8)
4. **Xcode** (Mac) → target Runner → **Signing & Capabilities** → Push Notifications + Background Modes (*Remote notifications*)
5. **Release / TestFlight** : passer `aps-environment` à `production` dans `Runner.entitlements`

### Tester iOS

| Environnement | Firebase | Token FCM | Push |
|---------------|----------|-----------|------|
| **Simulateur** (Mac) | Oui | Souvent non | Non |
| **iPhone physique** | Oui | Oui (APNs requis) | Oui |

```bash
cd frontend && flutter pub get
cd ios && pod install && cd ..
flutter run -d "iPhone 16"          # simulateur
flutter run -d <device-id>          # iPhone branché
```

Logs attendus : `FCM initialized` (iPhone) ou `FCM: no token` (simulateur, normal).

> **Windows :** préparation des fichiers possible ici ; `flutter run` / `flutter build ios` nécessitent un Mac avec Xcode.

---

## 5. Compte de service pour le backend

Les push serveur → app utilisent l'**Admin SDK** avec un compte de service :

1. Firebase Console → **Paramètres du projet** → **Comptes de service**
2. **Générer une nouvelle clé privée** → téléchargez le JSON
3. **Ne commitez jamais ce fichier** dans Git

Extrayez ces champs du JSON et ajoutez-les au `.env` backend :

```env
# Alias acceptés : FCM_* ou FIREBASE_*
FCM_PROJECT_ID=votre-project-id
FCM_CLIENT_EMAIL=firebase-adminsdk-xxxxx@votre-project-id.iam.gserviceaccount.com
FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n"
```

**Important :** la clé privée doit conserver les `\n` littéraux (ou retours à la ligne échappés) — le backend les convertit automatiquement.

Redémarrez l'API. Au démarrage vous devez voir : `Firebase FCM initialized`.

Sans ces variables, l'API fonctionne mais les push sont désactivés.

---

## 6. Vérification / readiness production

| Étape | Vérification |
|-------|----------------|
| Android | `flutter run` — pas d'erreur Firebase au démarrage |
| iOS | `flutter run` sur Mac — pas d'erreur Firebase ; plist présent dans `ios/Runner/` |
| Token FCM | Logs : `FCM initialized` puis `FCM token registered with API` après login |
| Refresh | Rotation token → `onTokenRefresh` re-uploade automatiquement |
| Backend | Log serveur : `Firebase FCM initialized` |
| Upload token | Après connexion, `PUT /api/auth/fcm-token` enregistre le token |
| DB | `SELECT fcm_token FROM users WHERE phone = '…'` non null après login |
| Push test | Déclencher SOS → contact avec FCM reçoit la notif |

---

## 7. Dépannage

| Problème | Solution |
|----------|----------|
| `google-services.json` manquant | Télécharger depuis Firebase, placer dans `android/app/` |
| `GoogleService-Info.plist` manquant (iOS) | Console Firebase → app iOS → télécharger, placer dans `ios/Runner/` |
| Build iOS sous Windows | Impossible sans Mac ; préparer Firebase + plist, tester plus tard |
| Push iOS non reçues | Clé APNs (.p8) téléversée dans Firebase → Cloud Messaging |
| `firebase_options.dart` absent | `flutterfire configure` ou copier l'exemple |
| Push non reçues (Android) | Vérifier FCM_* dans `.env`, token enregistré en base (`users.fcm_token`) |
| Erreur clé privée | Entourer `FCM_PRIVATE_KEY` de guillemets, `\n` entre les lignes |

---

## Fichiers concernés

| Fichier | Rôle |
|---------|------|
| `frontend/android/app/google-services.json` | Config Android Firebase |
| `frontend/ios/Runner/GoogleService-Info.plist` | Config iOS Firebase |
| `frontend/ios/Podfile` | Dépendances CocoaPods iOS |
| `frontend/ios/Runner/Runner.entitlements` | Capability push APNs |
| `frontend/lib/firebase_options.dart` | Options Flutter (généré) |
| `frontend/lib/services/fcm_service.dart` | Init FCM côté app |
| `backend/src/config/firebase.js` | Admin SDK + envoi push |
| `backend/.env.example` | Variables d'environnement |

Voir aussi [EXTERNAL_APIS.md](EXTERNAL_APIS.md) section Firebase Cloud Messaging.

---

*Dernière mise à jour : juin 2026*
