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

1. **Google Play In-App Updates** (`in_app_update`) — sur les builds installés via Play (piste Internal incluse). Au démarrage, à la reprise, et toutes les **~5 min** pendant l’usage, l’app vérifie une mise à jour et privilégie le mode **flexible** (téléchargement en arrière-plan, puis redémarrage).
2. **API `GET /api/app/version`** — fallback soft / force avant propagation Play. Réponse : `{ minVersion, latestVersion, forceUpdate, storeUrl }`. La bannière **disparaît dès que la version installée ≥ `latestVersion`** (pas de cache, `forceUpdate` ignoré si déjà à jour).

Configurer sur Render (ou `.env`) :

| Variable | Rôle |
|----------|------|
| `APP_LATEST_VERSION` | Dernière version recommandée (ex. `1.0.1`) — bannière soft si l’app est plus ancienne |
| `APP_MIN_VERSION` | Version minimale — dialogue bloquant si l’app est en dessous |
| `APP_FORCE_UPDATE` | `true` pour forcer la mise à jour même sans `APP_MIN_VERSION` |
| `APP_STORE_URL` | Lien Play (défaut : fiche `com.safealert.safealert`) |

Après chaque upload Play, mettez `APP_LATEST_VERSION` **exactement** à la version livrée (`pubspec` avant `+build`, ex. `1.0.9`). Si elle reste plus haute que l’app installée, la bannière ne disparaît pas.

### Quitter le canal Internal Beta

Le message Play « Vous êtes un testeur interne… SafeAlert (Internal Beta) » vient du canal **Tests internes**, pas de la fiche Production.

1. **Publier en Production** (la CI uploade `internal` puis tente `production` ; si Play refuse l’accès Production, l’erreur API est dans les logs du job) :
   - Play Console → l’application SafeAlert → **Tester** → **Tests internes** → la version concernée
   - **Promouvoir la version** → **Production**
   - **Examiner** → **Lancer le déploiement en production**
   - Alternative : **Production** → **Créer une version** → importer le même AAB → Examiner → Lancer
2. **Côté testeur** (pour voir uniquement la fiche publique) :
   - Play Console → **Tester** → **Tests internes** → **Testeurs** → retirer leur Gmail de la liste
   - Puis installer depuis la fiche Production **une fois la version Production publiée** (pas seulement « en attente d’examen »)
3. Sur le téléphone : Play Store → SafeAlert → si le bandeau Internal Beta reste, quitter le programme de test (lien « Quitter » sur la fiche de test) puis réinstaller depuis la fiche Production.

Sans version Production **publiée**, Play continuera d’afficher Internal Beta même après retrait de la liste.

### F. CI automatique

Sur push `main` si `frontend/**` change :

1. Build AAB
2. Artifact Actions
3. Release prerelease `aab-main`
4. Upload Play **internal** puis **production** (`status: completed`) si `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` est défini. Internal reste disponible pour les testeurs même si Production est refusée par Play. Ne pas passer `changesNotSentForReview` : Play le refuse si les changements partent automatiquement en revue.

L’AAB est aussi toujours sur la release GitHub **`aab-main`**, même si Play refuse le commit.

### Foreground Service (obligatoire après suivi GPS trajet)

Le trajet sécurisé utilise un service Android `location` au premier plan (`FOREGROUND_SERVICE_LOCATION`). Play bloque l’API tant que la déclaration n’est pas faite **une fois** :

1. Play Console → SafeAlert → **Surveillance et amélioration** → **Contenu de l’application** (Policy → App content)
2. Si le formulaire n’apparaît pas : **Tester → Tests internes → Créer une version**, uploader manuellement l’AAB `aab-main`, enregistrer — le formulaire se débloque
3. Déclarer : **oui**, type **Location**
4. Justification (exemple) : *« Suivi GPS d’un trajet sécurisé pour que les contacts d’escorte voient la position en direct. Notification persistante tant que le trajet est actif. »*
5. Vidéo démo (souvent exigée) : démarrer un trajet, quitter l’écran, montrer la notification « Trajet sécurisé SafeAlert »

Ensuite les uploads CI Play Internal redeviennent automatiques.
