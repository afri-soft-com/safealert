# Configuration Firebase — SafeAlert

Guide pas à pas pour activer les notifications push (FCM) sur Android et le backend SafeAlert.

---

## État actuel (août 2026)

| Élément | Statut |
|---------|--------|
| Projet Firebase | `safealert-prod` (déjà créé) |
| Package Android | `com.safealert.safealert` |
| `google-services.json` | Présent dans le dépôt : `frontend/android/app/google-services.json` |
| `firebase_options.dart` | Présent (`frontend/lib/firebase_options.dart`) |
| Plugin Gradle `google-services` | Configuré (`settings.gradle.kts` + `app/build.gradle.kts`) |
| Backend Admin SDK | `backend/src/config/firebase.js` — **HTTP v1 via compte de service** |
| Vars Render `FCM_*` | À renseigner manuellement (sync: false dans `render.yaml`) |

Sans `FCM_*` sur Render, l’API démarre mais les push sont ignorées (`FCM not configured`).

---

## Prérequis

- Compte [Firebase Console](https://console.firebase.google.com/)
- Flutter SDK installé
- Package Android : `com.safealert.safealert` (voir `frontend/android/app/build.gradle.kts`)

---

## 1. Créer un projet Firebase (si besoin)

> Si le projet `safealert-prod` existe déjà avec l’app Android `com.safealert.safealert`, passez à la section **5** (compte de service / Render).

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

> Ce fichier contient des identifiants **client** (API key liée au package) — ce n’est **pas** le secret serveur.  
> Ne le confondez jamais avec le JSON du **compte de service** (`*firebase-adminsdk*.json`).

Le plugin Gradle `com.google.gms.google-services` est déjà configuré dans `frontend/android/app/build.gradle.kts`.

---

## 3. Configurer Flutter (`firebase_options.dart`)

### Option A — FlutterFire CLI (recommandé)

```bash
dart pub global activate flutterfire_cli
cd frontend
flutterfire configure --project=safealert-prod --platforms=android,ios --android-package-name=com.safealert.safealert --ios-bundle-id=com.safealert.safealert --yes
```

Cela régénère `frontend/lib/firebase_options.dart`. L’init dans `fcm_service.dart` utilise déjà `DefaultFirebaseOptions.currentPlatform`.

### Option B — Manuel

1. Copiez `frontend/lib/firebase_options.dart.example` vers `frontend/lib/firebase_options.dart`
2. Remplissez les valeurs depuis la console Firebase → Paramètres du projet → Vos applications

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

### Étapes manuelles restantes (Apple + push prod)

1. **Compte Apple Developer** — certificat / provisioning pour `com.safealert.safealert`
2. **Clé APNs** (.p8) — [Apple Developer → Keys](https://developer.apple.com/account/resources/authkeys/list)
3. **Firebase Console** → Paramètres → **Cloud Messaging** → **Configuration Apple** → téléverser la clé APNs (Key ID, Team ID, .p8)
4. **Xcode** (Mac) → target Runner → **Signing & Capabilities** → Push Notifications + Background Modes (*Remote notifications*)
5. **Release / TestFlight** : passer `aps-environment` à `production` dans `Runner.entitlements`

---

## 5. Compte de service pour le backend (HTTP v1 — requis)

Le backend utilise **firebase-admin** avec un **compte de service** (FCM HTTP v1).  
**Ne pas** utiliser la « Server key » legacy Cloud Messaging (obsolète / refusée).

1. Firebase Console → ⚙ **Paramètres du projet** → onglet **Comptes de service**
2. **Générer une nouvelle clé privée** → téléchargez le JSON (ex. `safealert-prod-firebase-adminsdk-xxxxx.json`)
3. **Ne commitez jamais ce fichier** — déjà ignoré par Git (`*firebase-adminsdk*.json`, `**/serviceAccount*.json`)

Extrayez ces champs du JSON :

| Champ JSON | Variable d’environnement |
|------------|--------------------------|
| `project_id` | `FCM_PROJECT_ID` |
| `client_email` | `FCM_CLIENT_EMAIL` |
| `private_key` | `FCM_PRIVATE_KEY` |

Alias acceptés : `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`.

```env
FCM_PROJECT_ID=safealert-prod
FCM_CLIENT_EMAIL=firebase-adminsdk-xxxxx@safealert-prod.iam.gserviceaccount.com
FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n"
```

**Important :** la clé privée doit conserver les `\n` littéraux — le backend les convertit (`privateKey.replace(/\\n/g, "\n")`).

Sur Google Cloud (lié au projet Firebase), activez **Firebase Cloud Messaging API** si une erreur d’API désactivée apparaît.

---

## 6. Variables exactes sur Render (`safealert-api`)

Dashboard Render → service **safealert-api** → **Environment** → ajoutez / mettez à jour :

| Variable | Valeur |
|----------|--------|
| `FCM_PROJECT_ID` | `project_id` du JSON compte de service (ex. `safealert-prod`) |
| `FCM_CLIENT_EMAIL` | `client_email` du JSON |
| `FCM_PRIVATE_KEY` | `private_key` du JSON — **une ligne** avec `\n` échappés, entre guillemets |

Puis **Manual Deploy** / redémarrage. Logs attendus : `Firebase FCM initialized`.

Sans ces trois variables : `FCM not configured — push notifications disabled`.

Référence Blueprint : `render.yaml` (clés présentes, `sync: false` → valeurs uniquement dans le dashboard).

---

## 7. Git, secrets et CI

| Fichier | Dans Git ? | Secret GitHub ? |
|---------|------------|-----------------|
| `frontend/android/app/google-services.json` | Oui (config client, déjà dans le dépôt) | **Non** — le job AAB CI le lit depuis le repo |
| `frontend/lib/firebase_options.dart` | Oui (mêmes IDs client) | Non |
| JSON compte de service (`*firebase-adminsdk*.json`) | **Non** (gitignore) | **Non** — uniquement variables `FCM_*` sur Render |
| `FCM_PRIVATE_KEY` etc. | **Non** | Non côté GitHub ; secrets **Render** uniquement |

- **Ne jamais committer** de clé privée / JSON Admin SDK.
- Si un jour vous retirez `google-services.json` du dépôt, il faudrait alors un secret CI (ex. `GOOGLE_SERVICES_JSON`) + une étape qui écrit le fichier avant `flutter build appbundle`. **Ce n’est pas le cas aujourd’hui.**

---

## 8. Vérification / test push

| Étape | Vérification |
|-------|----------------|
| Android | `flutter run` sur appareil physique — accepter la permission notifications |
| Token FCM | Logs app : `FCM initialized` puis après login `FCM token registered with API` |
| Backend | Logs Render : `Firebase FCM initialized` |
| Upload token | `PUT /api/auth/fcm-token` (authentifié) enregistre `users.fcm_token` |
| DB | `SELECT id, phone, left(fcm_token, 20) FROM users WHERE fcm_token IS NOT NULL;` |
| Push console | Firebase Console → **Messaging** → campagne test / « Send test message » avec le token appareil |
| Push métier | Déclencher un SOS avec un contact de confiance qui a un compte + `fcm_token` |

Il n’y a **pas** d’endpoint HTTP dédié « test push » : l’envoi passe par `sendPush` (SOS, proximité, groupes, etc.).

### Flux minimal de test

1. Deux comptes (A = SOS, B = contact de confiance de A), tous deux connectés sur appareils physiques.
2. B doit avoir un `fcm_token` en base après login.
3. A déclenche un SOS → B reçoit la notification FCM.

---

## 9. Dépannage

| Problème | Solution |
|----------|----------|
| `google-services.json` manquant | Télécharger depuis Firebase → `frontend/android/app/` |
| Push Android 13+ refusées | Accepter la permission ; `POST_NOTIFICATIONS` + `requestPermission` dans l’app |
| `Firebase FCM initialized` absent | Vérifier les 3 `FCM_*` sur Render (surtout `\n` dans `FCM_PRIVATE_KEY`) |
| Erreur « legacy server key » | Ne pas utiliser la Server key ; utiliser le compte de service Admin |
| Token null (émulateur) | Utiliser un appareil physique avec Play Services |
| Push iOS non reçues | Clé APNs (.p8) téléversée dans Firebase → Cloud Messaging |

---

## Fichiers concernés

| Fichier | Rôle |
|---------|------|
| `frontend/android/app/google-services.json` | Config Android Firebase |
| `frontend/ios/Runner/GoogleService-Info.plist` | Config iOS Firebase |
| `frontend/lib/firebase_options.dart` | Options Flutter |
| `frontend/lib/services/fcm_service.dart` | Init FCM + upload token |
| `backend/src/config/firebase.js` | Admin SDK + `sendPush` |
| `backend/.env.example` / `.env.production.example` | Variables |
| `render.yaml` | Déclare `FCM_*` (valeurs dans le dashboard) |

Voir aussi [EXTERNAL_APIS.md](EXTERNAL_APIS.md) section Firebase Cloud Messaging.

---

*Dernière mise à jour : août 2026*
