# Guide publication Google Play — SafeAlert

Compte Play Console disponible. App Store iOS : plus tard.

## Checklist rapide (dans l’ordre)

### A. Assets (déjà générés dans le repo)

| Fichier | Usage |
|---------|--------|
| `frontend/assets/images/logo.png` | Icône launcher Android/iOS |
| `frontend/assets/branding/splash.png` | Écran d’accueil Flutter |
| Splash natif | `flutter_native_splash` (fond `#0B6E6E` + logo) |

Régénérer icônes / splash natif après changement de logo :

```bash
cd frontend
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

### B. Signature (une seule fois — obligatoire Play Store)

```bash
cd frontend/android
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp key.properties.example key.properties
# Éditer storePassword, keyPassword, keyAlias=upload, storeFile=../upload-keystore.jks
```

Sauvegarder le `.jks` hors Git (coffre-fort). Ne jamais committer `key.properties`.

Secrets CI optionnels :

| Secret | Contenu |
|--------|---------|
| `ANDROID_KEYSTORE_BASE64` | `certutil -encode upload-keystore.jks stdout` (ou `base64 -w0`) |
| `ANDROID_KEY_PROPERTIES` | contenu de `key.properties` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | JSON compte de service Play (upload internal auto) |

### C. Build AAB pointant vers Render

```bash
cd frontend
flutter build appbundle --release --dart-define=API_BASE_URL=https://safealert-api.onrender.com/api
```

Fichier : `build/app/outputs/bundle/release/app-release.aab`  
Ou télécharger la release GitHub **`aab-main`** (CI, si `frontend/**` a changé).

### D. Play Console — étapes

1. **Créer l’app** → Application → Gratuit → déclarations.
2. **Fiche Play** : titre SafeAlert, descriptions, icône 512×512 (exporterer le logo), feature graphic 1024×500, 2–8 captures téléphone.
3. **Politique de confidentialité** : URL HTTPS publique obligatoire.
4. **Data safety** : localisation, téléphone, notifications (usage SOS).
5. **Classement du contenu** + public cible (pas enfants si SOS adulte).
6. **Internal testing** : uploader l’AAB → ajouter testeurs e-mail → lien de test.
7. **Play App Signing** : accepter (Google gère la clé app ; vous gardez la clé d’upload).
8. Après tests : **Closed / Open testing** puis **Production** (pays : RDC + autres).

### E. Avant soumission

- [ ] API Render live : `curl https://safealert-api.onrender.com/health/ready`
- [ ] OTP SMS réel (SerdiPay / Twilio) configuré — voir `docs/EXTERNAL_APIS.md`
- [ ] FCM prod : `google-services.json` + vars `FCM_*` backend — voir `docs/FIREBASE_SETUP.md`
- [ ] Migrations DB à jour (`npm run migrate`) pour les nouvelles tables (trajets, check-in, etc.)
- [ ] Feature flags revue (`docs/FEATURES.md`) — `FEATURE_PREMIUM` off par défaut
- [ ] Compte `platform_admin` pour admin-web
- [ ] Incrémenter `version` dans `pubspec.yaml` (`1.0.0+1` → `1.0.1+2`) à chaque upload

### F. CI automatique

Sur push `main` si `frontend/**` change :

1. Build AAB
2. Artifact Actions
3. Release prerelease `aab-main`
4. Upload Play **internal** si `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` est défini
