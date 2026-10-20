# Guide App Store iOS — SafeAlert

Bundle ID : **`com.safealert.safealert`** (aligné Android / Firebase).  
Projet Firebase : `safealert-prod` (voir `docs/FIREBASE_SETUP.md` § iOS).

## Prérequis (une fois)

1. **Apple Developer Program** (compte payant) — Team ID noté
2. Mac avec **Xcode** récent + CocoaPods
3. App créée dans [App Store Connect](https://appstoreconnect.apple.com) : SafeAlert, bundle `com.safealert.safealert`
4. **Clé APNs** (.p8) → Firebase → Cloud Messaging → Apple
5. OAuth Google : client iOS dans Cloud Console (`GOOGLE_IOS_CLIENT_ID` côté Render si utilisé)

## Build local (IPA / Archive)

```bash
cd frontend
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://safealert-api.onrender.com/api \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<WEB_CLIENT_ID>.apps.googleusercontent.com
```

Ou ouvrir `frontend/ios/Runner.xcworkspace` → **Product → Archive** → Distribute App → App Store Connect.

## Signing

- Xcode → Runner → **Signing & Capabilities**
  - Team Apple
  - Push Notifications
  - Background Modes : Location + Remote notifications
- Pour TestFlight / prod : `Runner.entitlements` → `aps-environment` = **`production`**

## Checklist fiche App Store

- [ ] Icône 1024×1024 (sans alpha)
- [ ] Captures iPhone 6.7" / 6.1" (FR)
- [ ] Politique confidentialité HTTPS (`https://safealert-admin.onrender.com/privacy.html`)
- [ ] CGU (`…/cgu.html`)
- [ ] Catégorie : Utilitaires / Style de vie
- [ ] Âge 17+ si SOS / contenu sensible
- [ ] Privacy Nutrition Labels : localisation, contacts, identifiants, données d’usage
- [ ] Compte démo testeur si login requis (OTP / Google)

## Versions

Aligner `frontend/pubspec.yaml` (`version: x.y.z+build`) avec Android à chaque soumission.  
CFBundleShortVersionString / CFBundleVersion suivent Flutter (`FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER`).

## CI (à venir)

Pas encore de job `mobile-ipa` dans `.github/workflows/ci.yml`. Prochaine étape possible :

- Secrets : `APP_STORE_CONNECT_KEY_*`, certs distribution
- Job `flutter build ipa` + upload TestFlight (`xcrun altool` / `fastlane deliver`)

En attendant : archive manuelle depuis un Mac.

## Après première soumission

1. TestFlight interne → testeurs
2. Soumission Review App Store
3. Mettre `APP_LATEST_VERSION` Render à la version iOS/Android publiée
4. Lien App Store dans `APP_STORE_URL` (ou URL séparée iOS côté app si besoin)
