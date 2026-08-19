# Guide publication Google Play — SafeAlert

Compte Play Console disponible. App Store iOS : plus tard.

## Checklist rapide (dans l’ordre)

### A. Assets (déjà générés dans le repo)

| Fichier | Usage |
|---------|--------|
| `frontend/assets/branding/app-icon.png` | Source launcher (`flutter_launcher_icons`) |
| `frontend/assets/branding/playstore/icon-512.png` | Icône fiche Play (512×512, fond plein) |
| `frontend/assets/branding/splash.png` | Écran d’accueil Flutter |
| Splash natif | `flutter_native_splash` (fond `#0B6E6E` + logo) |

Après chaque rebuild AAB : uploader aussi `icon-512.png` dans Play Console → Présence sur le Play Store → Icône de l’application (la fiche peut rester « non examinée » ; l’icône installée suit le nouveau AAB).

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
5. **Permissions photos/vidéos** : l’AAB ne doit **pas** déclarer `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` (preuves témoin via photo picker + CAMERA seulement). Si Play Console affiche encore « Photo and video permissions », choisir que l’accès large n’est **pas** requis / migrer vers le sélecteur, puis uploader un AAB sans ces permissions. Ne pas tenter une déclaration « core gallery » — SafeAlert n’est pas une app galerie.
6. **Classement du contenu** + public cible (pas enfants si SOS adulte).
7. **Internal testing** : uploader l’AAB → ajouter testeurs e-mail → lien de test.
8. **Play App Signing** : accepter (Google gère la clé app ; vous gardez la clé d’upload).
9. Après tests : **Closed / Open testing** puis **Production** (pays : RDC + autres).

### E. Avant soumission

- [ ] API Render live : `curl https://safealert-api.onrender.com/health/ready`
- [ ] OTP SMS réel (SerdiPay / Twilio) configuré — voir `docs/EXTERNAL_APIS.md`
- [ ] FCM prod : `google-services.json` + vars `FCM_*` backend — voir `docs/FIREBASE_SETUP.md`
- [ ] Migrations DB à jour (`npm run migrate`) pour les nouvelles tables (trajets, check-in, etc.)
- [ ] Feature flags revue (`docs/FEATURES.md`) — `FEATURE_PREMIUM` off par défaut
- [ ] Compte `platform_admin` pour admin-web
- [ ] Incrémenter `version` dans `pubspec.yaml` (`1.0.0+1` → `1.0.1+2`) à chaque upload
- [ ] (Optionnel) Vars Render pour le fallback version : `APP_LATEST_VERSION`, `APP_MIN_VERSION`, `APP_FORCE_UPDATE`, `APP_STORE_URL` — voir ci-dessous

### Mises à jour in-app (Android)

Deux mécanismes complémentaires :

1. **Google Play In-App Updates** (`in_app_update`) — sur les builds installés via Play (piste Internal incluse). Au démarrage / reprise / toutes les ~45 min, l’app vérifie une mise à jour et privilégie le mode **flexible** (téléchargement en arrière-plan, puis redémarrage).
2. **API `GET /api/app/version`** — fallback soft / force avant propagation Play. Réponse : `{ minVersion, latestVersion, forceUpdate, storeUrl }`.

Configurer sur Render (ou `.env`) :

| Variable | Rôle |
|----------|------|
| `APP_LATEST_VERSION` | Dernière version recommandée (ex. `1.0.1`) — bannière soft si l’app est plus ancienne |
| `APP_MIN_VERSION` | Version minimale — dialogue bloquant si l’app est en dessous |
| `APP_FORCE_UPDATE` | `true` pour forcer la mise à jour même sans `APP_MIN_VERSION` |
| `APP_STORE_URL` | Lien Play (défaut : fiche `com.safealert.safealert`) |

Après chaque upload Play Internal réussi, mettez à jour `APP_LATEST_VERSION` sur l’API pour les utilisateurs qui n’ont pas encore reçu la propagation Play.

### F. CI automatique

Sur push `main` si `frontend/**` change :

1. Build AAB
2. Artifact Actions
3. Release prerelease `aab-main`
4. Upload Play **internal** (`status: completed`) si `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` est défini — la version est immédiatement disponible pour les testeurs internes (pas de draft)

L’AAB est aussi toujours sur la release GitHub **`aab-main`**, même si Play refuse le commit.

### Foreground Service (obligatoire après suivi GPS trajet)

Le trajet sécurisé utilise un service Android `location` au premier plan (`FOREGROUND_SERVICE_LOCATION`). Play bloque l’API tant que la déclaration n’est pas faite **une fois** :

1. Play Console → SafeAlert → **Surveillance et amélioration** → **Contenu de l’application** (Policy → App content)
2. Si le formulaire n’apparaît pas : **Tester → Tests internes → Créer une version**, uploader manuellement l’AAB `aab-main`, enregistrer — le formulaire se débloque
3. Déclarer : **oui**, type **Location**
4. Justification (exemple) : *« Suivi GPS d’un trajet sécurisé pour que les contacts d’escorte voient la position en direct. Notification persistante tant que le trajet est actif. »*
5. Vidéo démo (souvent exigée) : démarrer un trajet, quitter l’écran, montrer la notification « Trajet sécurisé SafeAlert »

Ensuite les uploads CI Play Internal redeviennent automatiques.
