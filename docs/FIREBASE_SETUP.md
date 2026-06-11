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

## 4. iOS — configuration depuis zéro (optionnel)

> **Important — Windows :** vous pouvez préparer les fichiers et la doc Firebase ici, mais **compiler et tester sur iPhone nécessite un Mac avec Xcode**. Sur Windows, concentrez-vous sur Android ; configurez iOS dans Firebase maintenant pour être prêt quand un Mac sera disponible.

### Identifiant exact à utiliser

Copiez-collez **exactement** ce bundle ID dans la console Firebase :

```
com.safealert.safealert
```

(Valeur `PRODUCT_BUNDLE_IDENTIFIER` dans `frontend/ios/Runner.xcodeproj/project.pbxproj`.)

### Étape par étape — Console Firebase

1. Ouvrez [console.firebase.google.com](https://console.firebase.google.com/) et sélectionnez le projet **`safealert-prod`** (ou créez-le à la section 1 si ce n'est pas déjà fait).
2. Sur la page d'accueil du projet, cliquez sur l'icône **iOS** (ou **Ajouter une application** → **iOS**).
3. **ID du bundle iOS** : saisissez `com.safealert.safealert` (sans espace, sensible à la casse).
4. **Surnom de l'app** (optionnel) : `SafeAlert iOS`.
5. **ID App Store** (optionnel) : laissez vide pour l'instant.
6. Cliquez sur **Enregistrer l'application**.
7. **Téléchargez `GoogleService-Info.plist`** — bouton de téléchargement sur l'écran de configuration. **Ne commitez pas ce fichier** tant qu'il n'est pas placé localement ; ne créez pas de fichier factice.
8. **Où placer le fichier** (sur Mac ou après transfert depuis Windows) :

```
frontend/ios/Runner/GoogleService-Info.plist
```

9. Dans Xcode (Mac uniquement) : ouvrez `frontend/ios/Runner.xcworkspace`, vérifiez que `GoogleService-Info.plist` apparaît dans le groupe **Runner** (glisser-déposer si besoin, cochez **Copy items if needed**).
10. **Notifications push (APNs)** — requis pour recevoir des alertes sur un **vrai iPhone** :
    - [Apple Developer](https://developer.apple.com/account/) → **Certificates, Identifiers & Profiles** → **Keys** → **+** → cochez **Apple Push Notifications service (APNs)** → créez la clé → téléchargez le fichier `.p8` (une seule fois).
    - Firebase Console → **Paramètres du projet** (engrenage) → onglet **Cloud Messaging** → section **Configuration de l'application Apple** → **Téléverser** la clé APNs (.p8), renseignez **Key ID** et **Team ID** Apple.
11. Mettez à jour Flutter :
    - **Recommandé** : sur Mac, `cd frontend && flutterfire configure` (sélectionner iOS + projet `safealert-prod`).
    - **Manuel** : copiez les valeurs `API_KEY`, `GOOGLE_APP_ID`, `GCM_SENDER_ID`, `PROJECT_ID` depuis `GoogleService-Info.plist` vers `frontend/lib/firebase_options.dart` (section `ios`).

### Après le téléchargement du plist

1. Placez `GoogleService-Info.plist` au chemin indiqué ci-dessus.
2. Régénérez ou complétez `firebase_options.dart` (CLI ou manuel).
3. Sur Mac : `cd frontend && flutter run` sur un simulateur ou un iPhone branché.
4. Si vous travaillez depuis Windows : dites **« ajoute iOS »** à l'équipe / à l'assistant — le plist pourra être installé et `firebase_options.dart` complété pour vous.

### Limites iOS sous Windows

| Action | Windows | Mac + Xcode |
|--------|---------|-------------|
| Créer l'app iOS dans Firebase | Oui | Oui |
| Télécharger `GoogleService-Info.plist` | Oui | Oui |
| Placer le plist dans le repo | Oui (fichiers) | Oui |
| Téléverser la clé APNs dans Firebase | Oui (navigateur) | Oui |
| `flutter run` sur simulateur / iPhone | Non | Oui |
| Test push sur appareil réel | Non | Oui |

Sans `GoogleService-Info.plist` et sans valeurs iOS valides dans `firebase_options.dart`, l'app **Android** continue de fonctionner ; le build iOS échouera ou Firebase ne s'initialisera pas correctement sur iOS.

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

## 6. Vérification

| Étape | Vérification |
|-------|----------------|
| Android | `flutter run` — pas d'erreur Firebase au démarrage |
| Token FCM | Logs : `FCM initialized` dans la console Flutter |
| Backend | Log serveur : `Firebase FCM initialized` |
| Upload token | Après connexion, `PUT /api/auth/fcm-token` enregistre le token |

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
| `frontend/ios/Runner/GoogleService-Info.plist` | Config iOS Firebase (à télécharger) |
| `frontend/lib/firebase_options.dart` | Options Flutter (généré) |
| `frontend/lib/services/fcm_service.dart` | Init FCM côté app |
| `backend/src/config/firebase.js` | Admin SDK + envoi push |
| `backend/.env.example` | Variables d'environnement |

Voir aussi [EXTERNAL_APIS.md](EXTERNAL_APIS.md) section Firebase Cloud Messaging.

---

*Dernière mise à jour : juin 2026*
