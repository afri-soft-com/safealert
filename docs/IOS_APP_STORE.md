# Guide App Store iOS — SafeAlert (via GitHub Actions)

Bundle ID iOS : **`com.kakiranya.safealert`** (Android Play reste `com.safealert.safealert`)  
Team ID : **`SW53MG3W9P`**  
Workflow : [`.github/workflows/mobile-ios.yml`](../.github/workflows/mobile-ios.yml)  
Release rolling : tag GitHub **`ipa-main`**

## Flux CI

```
Actions → Mobile iOS → Run workflow
  → macOS runner
  → flutter build ipa (signé)
  → artifact + release ipa-main
  → xcrun altool → TestFlight (si clés ASC présentes)
```

Déclencheurs :

| Événement | Comportement |
|-----------|----------------|
| **Run workflow** (manuel) | Build + TestFlight si `upload_testflight=true` |
| Push `main` sur `frontend/**` | Build + TestFlight (échoue clairement si secrets absents) |

## Secrets GitHub à créer

Repo → **Settings → Secrets and variables → Actions** :

### Signature (obligatoire pour le build)

| Secret | Contenu |
|--------|---------|
| `IOS_TEAM_ID` | Team ID Apple (10 caractères) |
| `IOS_BUILD_CERTIFICATE_BASE64` | Certificat **Apple Distribution** exporté `.p12` → base64 |
| `IOS_P12_PASSWORD` | Mot de passe du `.p12` |
| `IOS_PROVISION_PROFILE_BASE64` | Profil **App Store** `.mobileprovision` → base64 |
| `IOS_KEYCHAIN_PASSWORD` | (optionnel) mot de passe keychain CI |

Encoder (Mac / Linux) :

```bash
base64 -i distribution.p12 | pbcopy          # → IOS_BUILD_CERTIFICATE_BASE64
base64 -i SafeAlert_AppStore.mobileprovision | pbcopy  # → IOS_PROVISION_PROFILE_BASE64
```

Windows (PowerShell) :

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("distribution.p12")) | Set-Clipboard
```

### TestFlight / App Store Connect (upload)

Créer une clé API : [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)

| Secret | Contenu |
|--------|---------|
| `APP_STORE_CONNECT_KEY_ID` | Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Fichier `.p8` en base64 |

Rôle clé : **Developer** ou **App Manager** (upload builds).

### Variable déjà utilisée (Android)

| Variable | Rôle |
|----------|------|
| `GOOGLE_SERVER_CLIENT_ID` | Web client OAuth (`--dart-define`) |
| `API_BASE_URL` | `https://safealert-api.onrender.com/api` |

## Une fois côté Apple (hors CI)

1. **Apple Developer** — app ID `com.kakiranya.safealert` + Push Notifications (déjà enregistré)
2. **Certificat Distribution** + **Provisioning Profile App Store** pour `com.kakiranya.safealert`
3. **App Store Connect** — créer l’app SafeAlert (bundle `com.kakiranya.safealert`)
4. **APNs .p8** → Firebase Cloud Messaging (push)
5. Remplir les secrets GitHub ci-dessus
6. **Actions → Mobile iOS → Run workflow**

## Build local (optionnel, Mac)

```bash
cd frontend
flutter pub get && cd ios && pod install && cd ..
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist \
  --dart-define=API_BASE_URL=https://safealert-api.onrender.com/api \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<WEB_CLIENT_ID>.apps.googleusercontent.com
```

## Checklist fiche App Store

- [ ] Icône 1024×1024 (sans alpha)
- [ ] Captures iPhone 6.7" / 6.1" (FR)
- [ ] Privacy : `https://safealert-admin.onrender.com/privacy.html`
- [ ] CGU : `https://safealert-admin.onrender.com/cgu.html`
- [ ] Privacy Nutrition Labels (localisation, etc.)
- [ ] Compte démo testeur si besoin

## Versions

Aligner `frontend/pubspec.yaml` avec Android à chaque soumission.  
Le job CI met `aps-environment` à **production** pour le build release (le fichier repo reste `development` pour le debug local).
