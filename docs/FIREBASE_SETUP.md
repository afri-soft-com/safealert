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

## 4. iOS (optionnel)

1. Ajoutez une app iOS dans Firebase (bundle ID : voir `ios/Runner.xcodeproj`)
2. Téléchargez `GoogleService-Info.plist` → `frontend/ios/Runner/`
3. Incluez iOS dans `flutterfire configure`

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
| `firebase_options.dart` absent | `flutterfire configure` ou copier l'exemple |
| Push non reçues | Vérifier FCM_* dans `.env`, token enregistré en base (`users.fcm_token`) |
| Erreur clé privée | Entourer `FCM_PRIVATE_KEY` de guillemets, `\n` entre les lignes |

---

## Fichiers concernés

| Fichier | Rôle |
|---------|------|
| `frontend/android/app/google-services.json` | Config Android Firebase |
| `frontend/lib/firebase_options.dart` | Options Flutter (généré) |
| `frontend/lib/services/fcm_service.dart` | Init FCM côté app |
| `backend/src/config/firebase.js` | Admin SDK + envoi push |
| `backend/.env.example` | Variables d'environnement |

Voir aussi [EXTERNAL_APIS.md](EXTERNAL_APIS.md) section Firebase Cloud Messaging.

---

*Dernière mise à jour : juin 2026*
