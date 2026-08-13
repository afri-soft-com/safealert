# SafeAlert — Fiche de commercialisation (API & secrets)

> **Objectif** : recenser **toutes** les clés, variables d'environnement, comptes tiers et fichiers à compléter pour mettre SafeAlert en production **demain matin**.  
> **Usage** : remplissez les champs `VOTRE_VALEUR_ICI` ou les lignes vides, puis suivez la checklist finale.  
> **Sécurité** : ne commitez **jamais** ce fichier une fois rempli. Ajoutez-le à `.gitignore` si nécessaire.

---

## Ordre de complétion recommandé

1. **Infrastructure** — VPS, DNS, domaine API (`DOMAIN`), certificats TLS (Caddy ou Nginx)
2. **Base de données** — mots de passe PostgreSQL + `DATABASE_URL` cohérents
3. **Sécurité API** — `JWT_SECRET` (32+ caractères aléatoires)
4. **SMS OTP** — Twilio **ou** Africa's Talking (obligatoire en production pour l'authentification par téléphone)
5. **Firebase** — projet Console, FCM backend + fichiers mobile
6. **Build mobile** — `API_BASE_URL`, keystore Android, soumission stores
7. **CI/CD** — secrets GitHub Actions (Docker + déploiement SSH)
8. **Partenaires ONG** — création des clés API via l'endpoint (pas de variable d'env)
9. **Optionnel** — Redis, webhooks de monitoring

---

## Tableau récapitulatif

| Service | Variable(s) | Obligatoire ? | Où l'obtenir | Fichier à modifier |
|---------|-------------|---------------|--------------|-------------------|
| Serveur Node.js | `PORT`, `NODE_ENV` | Oui (prod) | — | `.env.production` |
| JWT | `JWT_SECRET`, `JWT_EXPIRES_IN` | **Oui** | Générer localement (openssl) | `.env.production`, conteneur `api` |
| PostgreSQL | `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `DATABASE_URL` | **Oui** | VPS / Docker | `.env.production`, `docker-compose.yml` |
| CORS | `CORS_ORIGIN` | **Oui** (prod) | Votre domaine app/web | `.env.production` |
| Domaine / TLS | `DOMAIN` | **Oui** (HTTPS public) | Registrar DNS | `.env.production`, `deploy/Caddyfile` |
| Twilio SMS | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER` | **Oui** (OTP prod) | [Twilio Console](https://console.twilio.com/) | `.env.production` → conteneur `api` |
| Africa's Talking SMS | `AFRICASTALKING_API_KEY`, `AFRICASTALKING_USERNAME` | Alternative SMS | [Africa's Talking](https://account.africastalking.com/) | `.env.production` → conteneur `api` |
| Firebase FCM (backend) | `FCM_PROJECT_ID`, `FCM_PRIVATE_KEY`, `FCM_CLIENT_EMAIL` | Recommandé | [Firebase Console](https://console.firebase.google.com/) | `.env.production` → conteneur `api` |
| Firebase (Android) | `google-services.json` | Recommandé | Firebase Console → App Android | `frontend/android/app/google-services.json` |
| Firebase (iOS) | `GoogleService-Info.plist` | Si iOS | Firebase Console → App iOS | `frontend/ios/Runner/GoogleService-Info.plist` |
| Firebase (Flutter) | `firebase_options.dart` | Recommandé | `flutterfire configure` | `frontend/lib/firebase_options.dart` |
| Redis (cache) | `REDIS_URL` | Non | Docker interne | `.env.production` |
| API mobile Flutter | `API_BASE_URL` (dart-define) | **Oui** | Votre URL HTTPS API | Commande `flutter build` |
| GitHub Actions Docker | `DOCKER_REGISTRY`, `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `DOCKER_IMAGE` | Si CI/CD | GHCR / Docker Hub | GitHub → Settings → Secrets |
| GitHub Actions Deploy | `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_PATH` | Si deploy auto | VPS SSH | GitHub → Settings → Secrets |
| Keystore Android | `storeFile`, `storePassword`, `keyAlias`, `keyPassword` | **Oui** (Play Store) | Généré par vous (ne pas perdre) | `frontend/android/key.properties` + `build.gradle.kts` |
| Play Console | App ID, listing, politique | **Oui** (Android) | [Google Play Console](https://play.google.com/console/) | Console web |
| App Store Connect | Bundle ID, listing | Si iOS | [App Store Connect](https://appstoreconnect.apple.com/) | Console web |
| API Partenaires ONG | Clé générée à l'exécution | Par partenaire | `POST /api/partner/register` (JWT) | Base de données (table `partner_api_keys`) |
| DNS | Enregistrements A/AAAA | **Oui** | Registrar (OVH, Cloudflare, etc.) | Panneau DNS |
| Monitoring (optionnel) | Webhook URL | Non | Slack, Discord, PagerDuty… | À brancher manuellement |

> **⚠️ Important Docker** : le fichier `docker-compose.yml` ne transmet pas encore `FCM_*`, `TWILIO_*` ni `AFRICASTALKING_*` au service `api`. Après avoir rempli `.env.production`, ajoutez `env_file: .env.production` au service `api` **ou** listez ces variables dans la section `environment`. Vérifiez aussi que `POSTGRES_PASSWORD` dans `docker-compose.yml` correspond à celui de `DATABASE_URL`.

---

## Sections détaillées par service

---

### 1. Serveur & environnement Node.js

**Variables exactes :**

```env
PORT=3000
NODE_ENV=production
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| `PORT` | |
| `NODE_ENV` | `production` |

**Documentation** : [Node.js — Production best practices](https://nodejs.org/en/docs/guides/nodejs-docker-webapp)

**Étapes :**

1. Copier `.env.production.example` → `.env.production` à la racine du dépôt.
2. Laisser `PORT=3000` sauf conflit sur le VPS.
3. Mettre `NODE_ENV=production` (active la validation JWT stricte et masque les codes OTP dans les logs).

**Notes prod :** en production, l'API refuse de démarrer si `JWT_SECRET` est faible ou absent.

---

### 2. JWT (authentification API)

**Variables exactes :**

```env
JWT_SECRET=
JWT_EXPIRES_IN=30d
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| `JWT_SECRET` | `VOTRE_VALEUR_ICI` |
| `JWT_EXPIRES_IN` | `30d` |

**Documentation** : [jsonwebtoken — expiresIn](https://github.com/auth0/node-jsonwebtoken#usage)

**Étapes pour obtenir la clé :**

1. Générer une chaîne aléatoire d'au moins 32 caractères :
   ```bash
   openssl rand -base64 48
   ```
2. Coller le résultat dans `JWT_SECRET=` (sans guillemets).
3. Conserver une copie sécurisée (coffre-fort, gestionnaire de mots de passe).

**Notes prod :** minimum **32 caractères**. Ne jamais réutiliser `change-me-in-production`. Rotation = déconnexion de tous les utilisateurs.

---

### 3. PostgreSQL / PostGIS

**Variables exactes :**

```env
POSTGRES_DB=safealert
POSTGRES_USER=
POSTGRES_PASSWORD=
DATABASE_URL=postgresql://USER:MOT_DE_PASSE@db:5432/safealert
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| `POSTGRES_DB` | `safealert` |
| `POSTGRES_USER` | `VOTRE_VALEUR_ICI` |
| `POSTGRES_PASSWORD` | `VOTRE_VALEUR_ICI` |
| `DATABASE_URL` | `VOTRE_VALEUR_ICI` |

**Console / doc :**

- Image Docker : [postgis/postgis](https://hub.docker.com/r/postgis/postgis)
- Format URL : [PostgreSQL connection URIs](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING-URIS)

**Étapes :**

1. Choisir un utilisateur et un mot de passe forts (20+ caractères).
2. Aligner `DATABASE_URL` avec `POSTGRES_USER` / `POSTGRES_PASSWORD` et l'hôte `db` (réseau Docker Compose).
3. Mettre à jour `docker-compose.yml` → service `db` → `POSTGRES_PASSWORD` (actuellement `changeme` par défaut).
4. Au premier déploiement : `docker compose --profile init run --rm seed` pour les données initiales.

**Notes prod :** sauvegardes quotidiennes du volume `pgdata`. Région VPS proche de vos utilisateurs (Afrique centrale / de l'Ouest recommandé).

---

### 4. CORS & domaine public

**Variables exactes :**

```env
CORS_ORIGIN=
DOMAIN=
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| `CORS_ORIGIN` | `VOTRE_VALEUR_ICI` |
| `DOMAIN` | `VOTRE_VALEUR_ICI` |

**Exemples :**

```env
CORS_ORIGIN=https://votredomaine.com,https://app.votredomaine.com
DOMAIN=api.votredomaine.com
```

**Documentation :**

- CORS Express : [cors package](https://github.com/expressjs/cors)
- Caddy (TLS auto) : [Caddy — Automatic HTTPS](https://caddyserver.com/docs/automatic-https)

**Étapes :**

1. Réserver un sous-domaine API (ex. `api.votredomaine.com`).
2. Créer un enregistrement DNS **A** (ou **AAAA**) pointant vers l'IP du VPS.
3. Renseigner `DOMAIN` = nom d'hôte complet de l'API (sans `https://`).
4. Renseigner `CORS_ORIGIN` avec l'origine de votre app (scheme + host). Plusieurs origines : séparées par des virgules.
5. Lancer le proxy TLS : `docker compose --profile proxy up -d` (utilise `deploy/Caddyfile`).

**Notes prod :** ne pas laisser `CORS_ORIGIN=*` en production. Let's Encrypt exige que les ports 80 et 443 soient ouverts.

**Alternative Nginx :** modèle `deploy/nginx.conf` — remplacer `YOUR_DOMAIN` et chemins certificats.

---

### 5. Twilio (SMS — prioritaire)

**Variables exactes :**

```env
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_PHONE_NUMBER=
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| `TWILIO_ACCOUNT_SID` | `VOTRE_VALEUR_ICI` |
| `TWILIO_AUTH_TOKEN` | `VOTRE_VALEUR_ICI` |
| `TWILIO_PHONE_NUMBER` | `VOTRE_VALEUR_ICI` |

**Console :** [https://console.twilio.com/](https://console.twilio.com/)  
**Documentation :** [Twilio SMS — Node.js](https://www.twilio.com/docs/sms/quickstart/node)

**Étapes :**

1. Créer un compte Twilio et vérifier votre identité.
2. Console → **Account Info** → copier **Account SID** et **Auth Token**.
3. Acheter un numéro SMS capable d'envoyer vers vos pays cibles (+243 RDC, etc.).
4. Format du numéro expéditeur : E.164 (ex. `+14155552671`).
5. Coller les trois variables dans `.env.production`.

**Notes prod :**

- Twilio est essayé **en premier** ; si échec, le backend tente Africa's Talking.
- Sans SMS configuré en production, les OTP ne partent pas par SMS (simulation console uniquement en dev).
- Budget : ~0,05–0,10 USD/SMS selon destination ; prévoir un plafond de dépenses dans la console.
- Pour l'Afrique : vérifier la couverture SMS par pays dans la console Twilio.

---

### 6. Africa's Talking (SMS — alternative Afrique)

**Variables exactes :**

```env
AFRICASTALKING_API_KEY=
AFRICASTALKING_USERNAME=
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| `AFRICASTALKING_API_KEY` | `VOTRE_VALEUR_ICI` |
| `AFRICASTALKING_USERNAME` | `VOTRE_VALEUR_ICI` |

**Console :** [https://account.africastalking.com/](https://account.africastalking.com/)  
**Documentation :** [Africa's Talking — SMS API](https://developers.africastalking.com/docs/sms/overview)

**Étapes :**

1. Créer un compte sur Africa's Talking.
2. Sandbox : username `sandbox` + clé API sandbox (tests).
3. Production : demander l'activation du compte live et un **Sender ID** approuvé par pays.
4. Settings → **API Key** → générer / copier la clé.
5. Username = identifiant de l'app (ex. `sandbox` ou votre username live).

**Notes prod :**

- Recommandé si vos utilisateurs sont principalement en Afrique subsaharienne (meilleurs tarifs locaux).
- Endpoint utilisé par le backend : `https://api.africastalking.com/version1/messaging`
- Compléter Twilio **ou** Africa's Talking au minimum.

---

### 7. Firebase Cloud Messaging — backend (push notifications)

**Variables exactes :**

```env
FCM_PROJECT_ID=
FCM_PRIVATE_KEY=
FCM_CLIENT_EMAIL=
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| `FCM_PROJECT_ID` | `VOTRE_VALEUR_ICI` |
| `FCM_PRIVATE_KEY` | `VOTRE_VALEUR_ICI` |
| `FCM_CLIENT_EMAIL` | `VOTRE_VALEUR_ICI` |

**Console :** [https://console.firebase.google.com/](https://console.firebase.google.com/)  
**Documentation :** [Firebase Admin SDK — Service account](https://firebase.google.com/docs/admin/setup)

**Étapes :**

1. Créer un projet Firebase (ex. `safealert-prod`).
2. Paramètres projet → **Comptes de service** → **Générer une nouvelle clé privée** (JSON).
3. Depuis le JSON téléchargé :
   - `project_id` → `FCM_PROJECT_ID`
   - `private_key` → `FCM_PRIVATE_KEY` (garder les `\n` ou mettre la clé sur une ligne avec `\n` échappés)
   - `client_email` → `FCM_CLIENT_EMAIL`
4. Activer **Cloud Messaging API** dans Google Cloud Console si demandé.

**Exemple format `FCM_PRIVATE_KEY` dans `.env` :**

```env
FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n"
```

**Notes prod :** sans FCM, l'API et l'app démarrent ; les push sont ignorées (log d'avertissement). Gratuit pour volumes modérés.

---

### 8. Firebase — application mobile (Flutter)

**Fichiers & commandes (pas de variables `.env` backend) :**

| Élément | Emplacement | Statut actuel |
|---------|-------------|---------------|
| `google-services.json` | `frontend/android/app/google-services.json` | Présent (`safealert-prod`) |
| `GoogleService-Info.plist` | `frontend/ios/Runner/GoogleService-Info.plist` | Présent (`safealert-prod`) |
| `firebase_options.dart` | `frontend/lib/firebase_options.dart` | Présent — régénérer via FlutterFire si besoin |
| Package Android | `com.safealert.safealert` | Déjà configuré |

**Console :** [Firebase Console](https://console.firebase.google.com/)  
**Documentation :** [FlutterFire — Configure](https://firebase.flutter.dev/docs/overview)

**Étapes :**

1. Firebase Console → Ajouter une app **Android** (package `com.safealert.safealert`).
2. Télécharger `google-services.json` → remplacer le fichier dans `frontend/android/app/`.
3. (iOS) Ajouter une app **iOS** (bundle `com.safealert.app` selon l'exemple) → télécharger `GoogleService-Info.plist` → `frontend/ios/Runner/`.
4. Dans `frontend/` :
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
5. Vérifier que `lib/firebase_options.dart` est généré (modèle : `lib/firebase_options.dart.example`).

**Champs Firebase Options (référence — remplis par FlutterFire) :**

| Champ | Android | iOS |
|-------|---------|-----|
| `apiKey` | | |
| `appId` | | |
| `messagingSenderId` | | |
| `projectId` | | |
| `storageBucket` | | |
| `iosBundleId` | — | `com.safealert.app` |

**Notes prod :** activer les notifications push dans Firebase → Cloud Messaging. Tester sur appareil physique (émulateur limité pour FCM).

---

### 9. Redis (cache alertes actives — optionnel)

**Variable exacte :**

```env
REDIS_URL=
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| `REDIS_URL` | `VOTRE_VALEUR_ICI` |

**Valeur par défaut Docker Compose :**

```env
REDIS_URL=redis://redis:6379
```

**Documentation :** [Redis — Connection strings](https://redis.io/docs/latest/develop/clients/nodejs/connect/)

**Étapes :**

1. Avec Docker Compose : le service `redis` est déjà défini ; utiliser `redis://redis:6379`.
2. Sans Redis : laisser vide ou omettre — l'API fonctionne sans cache.

**Notes prod :** améliore les performances des alertes actives ; non bloquant pour le lancement.

---

### 10. API mobile Flutter (`API_BASE_URL`)

**Variable de build (dart-define, pas dans `.env`) :**

```bash
--dart-define=API_BASE_URL=https://api.votredomaine.com/api
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| URL API HTTPS | `VOTRE_VALEUR_ICI` |

**Fichier source :** `frontend/lib/services/api_service.dart` (valeur par défaut dev : `http://10.0.2.2:3000/api`)

**Étapes :**

1. Déterminer l'URL publique HTTPS de l'API (ex. `https://api.votredomaine.com/api`).
2. **Toujours** inclure le suffixe `/api`.
3. Utiliser cette URL dans **chaque** build release (APK, AAB, iOS).

**Notes prod :** l'app utilise aussi cette URL pour Socket.io (origine sans `/api`). Certificat TLS valide obligatoire.

---

### 11. GitHub Actions — secrets CI/CD

**Secrets à créer :** GitHub → dépôt → **Settings** → **Secrets and variables** → **Actions**

| Secret | Obligatoire ? | Description | Votre valeur |
|--------|---------------|-------------|--------------|
| `DOCKER_REGISTRY` | Non (défaut `ghcr.io`) | Registre conteneur | |
| `DOCKER_USERNAME` | Non (défaut = actor GitHub) | Utilisateur registre | |
| `DOCKER_PASSWORD` | Non (défaut = `GITHUB_TOKEN`) | Token / PAT registre | |
| `DOCKER_IMAGE` | Non | Chemin image complet (override) | |
| `DEPLOY_HOST` | Si deploy SSH | IP ou hostname VPS | |
| `DEPLOY_USER` | Si deploy SSH | Utilisateur SSH (ex. `root`, `deploy`) | |
| `DEPLOY_SSH_KEY` | Si deploy SSH | Clé privée SSH (PEM) | |
| `DEPLOY_PATH` | Non (défaut `/opt/safealert`) | Répertoire sur le VPS | |

**Workflow :** `.github/workflows/deploy.yml`  
**Documentation :**

- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [appleboy/ssh-action](https://github.com/appleboy/ssh-action)

**Étapes :**

1. Activer **Packages** sur le dépôt pour GHCR.
2. Créer une paire SSH dédiée au déploiement (`ssh-keygen -t ed25519`).
3. Ajouter la clé **publique** dans `~/.ssh/authorized_keys` sur le VPS.
4. Coller la clé **privée** dans le secret `DEPLOY_SSH_KEY`.
5. Renseigner `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH`.
6. Déclencher : tag `v*` (ex. `v1.0.0`) ou **workflow_dispatch** avec `deploy=true`.

**Notes prod :** le job deploy exécute `docker compose pull api && up -d api` sur le VPS — le VPS doit avoir Docker et `.env.production` déjà configuré.

---

### 12. Keystore Android (signature Play Store)

> **Ne pas générer ici** — remplir les champs une fois votre keystore créé et stocké en lieu sûr.

**Fichier `frontend/android/key.properties` (à créer) :**

```properties
storePassword=
keyPassword=
keyAlias=
storeFile=
```

| Champ à compléter | Votre valeur |
|-------------------|--------------|
| `storePassword` | |
| `keyAlias` | |
| `keyPassword` | |
| `storeFile` | chemin relatif ex. `../upload-keystore.jks` |

**Documentation :**

- [Flutter — Android deployment](https://docs.flutter.dev/deployment/android)
- [Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756)

**Étapes :**

1. Générer le keystore (une seule fois, **sauvegarder offline**) :
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Placer `upload-keystore.jks` hors du dépôt (ou dans `frontend/android/` — **gitignored**).
3. Créer `key.properties` avec les mots de passe et l'alias.
4. Configurer `frontend/android/app/build.gradle.kts` pour utiliser `signingConfigs.release` (actuellement : signature **debug** en release — à corriger avant Play Store).
5. **Ne jamais** commiter le keystore ni `key.properties`.

**Notes prod :** perte du keystore = impossibilité de mettre à jour l'app sur le Play Store.

---

### 13. Google Play Console & App Store Connect (checklist IDs)

**Pas de secrets dans le code — checklist à cocher demain :**

#### Google Play Console

| Élément | Votre valeur / statut |
|---------|----------------------|
| Compte développeur Google Play (frais unique) | ☐ Créé |
| Nom de l'application | SafeAlert |
| Package name | `com.safealert.safealert` |
| Version (`versionCode` / `versionName`) | `1.0.0+1` (cf. `frontend/pubspec.yaml`) |
| Catégorie | Sécurité / Social |
| Icône 512×512 | ☐ |
| Captures d'écran (téléphone) | ☐ |
| Politique de confidentialité (URL) | |
| Déclaration contenu / cible d'âge | ☐ |
| Fiche Data safety (localisation, contacts, etc.) | ☐ |
| AAB signé uploadé | ☐ |
| Test interne / production | ☐ |

**Console :** [https://play.google.com/console/](https://play.google.com/console/)

#### App Store Connect (si iOS)

| Élément | Votre valeur / statut |
|---------|----------------------|
| Apple Developer Program | ☐ |
| Bundle ID | `com.safealert.app` |
| App ID / SKU | |
| Certificats & profils de provisioning | ☐ |
| `GoogleService-Info.plist` installé | ☐ |
| Captures + metadata App Store | ☐ |
| Soumission review | ☐ |

**Console :** [https://appstoreconnect.apple.com/](https://appstoreconnect.apple.com/)

---

### 14. API Partenaires ONG (pas de variable d'environnement)

Les clés partenaires sont **générées dynamiquement** et stockées en base (`partner_api_keys`).

**Endpoints :**

| Méthode | Route | Auth |
|---------|-------|------|
| POST | `/api/partner/register` | JWT utilisateur |
| GET | `/api/partner/stats` | Header `X-API-Key` |
| GET | `/api/partner/incidents` | Header `X-API-Key` |
| GET | `/api/partner/heatmap` | Header `X-API-Key` |

**Création d'une clé (demain, après déploiement) :**

```bash
curl -X POST https://api.votredomaine.com/api/partner/register \
  -H "Authorization: Bearer VOTRE_JWT_UTILISATEUR" \
  -H "Content-Type: application/json" \
  -d '{"partner_name": "Nom ONG Partenaire"}'
```

| Partenaire | `partner_name` | `api_key` reçue | Date | Notes |
|------------|----------------|-----------------|------|-------|
| | | | | |
| | | | | |

**Notes prod :** transmettre la clé aux partenaires par canal sécurisé. Révoquer via base de données (`is_active = false`) si compromis.

---

### 15. DNS & certificats SSL

| Élément | Votre valeur |
|---------|--------------|
| Registrar / DNS | |
| Enregistrement A `@` ou `api` → IP VPS | |
| TTL | |
| Email admin domaine (Let's Encrypt) | |
| Option proxy | Caddy (auto) **ou** Nginx + Certbot |

**Étapes :**

1. Pointer `DOMAIN` (ex. `api.votredomaine.com`) vers l'IP du VPS.
2. Ouvrir ports **80** et **443** (pare-feu).
3. Lancer Caddy : `docker compose --profile proxy up -d`.
4. Vérifier : `curl https://api.votredomaine.com/health`

---

### 16. Monitoring & webhooks (optionnel — non intégré au code)

Le dépôt n'inclut pas encore de webhook de monitoring. Options à brancher manuellement :

| Service | Usage | URL webhook |
|---------|-------|-------------|
| UptimeRobot / Better Stack | Ping `/health` | |
| Slack / Discord | Alertes downtime | |
| Sentry | Erreurs Node.js / Flutter | |
| Datadog | Métriques VPS | |

**Healthchecks existants :**

- `GET /health` — liveness
- `GET /health/ready` — readiness (DB)

---

## Section `.env.production` complet (copier-coller)

Créer le fichier `.env.production` à la **racine** du dépôt (ne pas commiter) :

```env
# ============================================================
# SafeAlert — PRODUCTION (remplir toutes les valeurs demain)
# cp .env.production.example .env.production
# ============================================================

# --- Serveur ---
PORT=3000
NODE_ENV=production
DOMAIN=
CORS_ORIGIN=

# --- Docker Compose (PostgreSQL) ---
POSTGRES_DB=safealert
POSTGRES_USER=
POSTGRES_PASSWORD=

# --- Backend API ---
DATABASE_URL=postgresql://USER:MOT_DE_PASSE@db:5432/safealert
JWT_SECRET=
JWT_EXPIRES_IN=30d

# --- SMS (Twilio prioritaire, puis Africa's Talking) ---
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_PHONE_NUMBER=
AFRICASTALKING_API_KEY=
AFRICASTALKING_USERNAME=

# --- Firebase Cloud Messaging (backend) ---
FCM_PROJECT_ID=
FCM_PRIVATE_KEY=
FCM_CLIENT_EMAIL=

# --- Redis (optionnel) ---
REDIS_URL=redis://redis:6379

# --- Build mobile (commande flutter, pas lu par Docker) ---
# API_BASE_URL=https://api.votredomaine.com/api

# --- CI/CD GitHub (secrets Actions, pas dans ce fichier) ---
# DOCKER_REGISTRY=ghcr.io
# DOCKER_USERNAME=
# DOCKER_PASSWORD=
# DOCKER_IMAGE=
# DEPLOY_HOST=
# DEPLOY_USER=
# DEPLOY_SSH_KEY=
# DEPLOY_PATH=/opt/safealert
```

**Backend local / développement** — fichier séparé `backend/.env` (même variables sauf `DOMAIN`) :

```env
PORT=3000
NODE_ENV=development
CORS_ORIGIN=
DATABASE_URL=postgresql://user:password@localhost:5432/safealert
JWT_SECRET=
JWT_EXPIRES_IN=30d
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_PHONE_NUMBER=
AFRICASTALKING_API_KEY=
AFRICASTALKING_USERNAME=
FCM_PROJECT_ID=
FCM_PRIVATE_KEY=
FCM_CLIENT_EMAIL=
REDIS_URL=
```

---

## Checklist finale commercialisation (demain matin)

Cochez dans l'ordre :

### Phase A — Infrastructure (≈ 30 min)

- [ ] VPS provisionné (Ubuntu/Debian, 2 Go+ RAM recommandé)
- [ ] Docker + Docker Compose installés
- [ ] Dépôt cloné dans `/opt/safealert` (ou chemin choisi)
- [ ] `.env.production` créé et **toutes** les sections remplies
- [ ] `docker-compose.yml` : mot de passe Postgres aligné + `env_file` ou vars FCM/SMS pour le service `api`
- [ ] DNS `DOMAIN` → IP VPS propagé
- [ ] `./deploy/deploy.sh` exécuté **ou** `docker compose --env-file .env.production up -d`
- [ ] Seed : `docker compose --profile init run --rm seed`
- [ ] Proxy TLS : `docker compose --profile proxy up -d`
- [ ] `curl https://VOTRE_DOMAIN/health` → OK
- [ ] `curl https://VOTRE_DOMAIN/health/ready` → `"db":"ok"`

### Phase B — SMS & auth (≈ 20 min)

- [ ] Twilio **ou** Africa's Talking configuré et testé
- [ ] Envoi OTP test : `POST /api/auth/request-code` avec un vrai numéro
- [ ] Vérification : code reçu par SMS (pas seulement dans les logs)
- [ ] `JWT_SECRET` ≥ 32 caractères

### Phase C — Firebase & push (≈ 30 min)

- [ ] Projet Firebase créé
- [ ] `google-services.json` réel dans `frontend/android/app/`
- [ ] `flutterfire configure` → `firebase_options.dart` généré
- [ ] `FCM_*` backend renseignés
- [ ] Test push depuis Firebase Console vers un token FCM

### Phase D — Application mobile (≈ 45 min)

- [ ] Keystore Android créé + `key.properties` + signature release configurée
- [ ] Build : `flutter build appbundle --release --dart-define=API_BASE_URL=https://VOTRE_DOMAIN/api`
- [ ] Test APK/AAB sur appareil réel (login OTP, SOS, carte offline)
- [ ] (iOS) `GoogleService-Info.plist` + build Xcode si applicable

### Phase E — Stores & CI/CD (≈ 1 h)

- [ ] Play Console : fiche, AAB, politique de confidentialité
- [ ] (iOS) App Store Connect si applicable
- [ ] Secrets GitHub Actions configurés
- [ ] Tag `v1.0.0` → image Docker poussée sur GHCR
- [ ] (Optionnel) Deploy SSH automatique testé

### Phase F — Partenaires & go-live

- [ ] Clés API partenaires créées via `/api/partner/register`
- [ ] Monitoring uptime configuré sur `/health`
- [ ] Sauvegarde Postgres planifiée
- [ ] Équipe support / numéros d'urgence vérifiés dans l'app

---

## Commandes build & deploy (après remplissage des APIs)

### Déploiement VPS (Linux)

```bash
cd /opt/safealert
cp .env.production.example .env.production
# Éditer .env.production avec vos valeurs

chmod +x deploy/deploy.sh
./deploy/deploy.sh

# Vérifications
curl http://127.0.0.1:3000/health/ready
curl https://api.votredomaine.com/health
docker compose --env-file .env.production logs -f api
```

### Déploiement VPS (Windows — PowerShell)

```powershell
cd C:\chemin\vers\safesecurity
Copy-Item .env.production.example .env.production
# Éditer .env.production

.\deploy\deploy.ps1
```

### Docker manuel

```bash
docker compose --env-file .env.production up -d db redis api
docker compose --env-file .env.production --profile init run --rm seed
docker compose --env-file .env.production --profile proxy up -d
```

### Build Android (production)

```bash
cd frontend
flutter pub get
dart pub global activate flutterfire_cli
flutterfire configure

flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.votredomaine.com/api

# APK pour tests internes
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.votredomaine.com/api
```

**Sortie AAB :** `frontend/build/app/outputs/bundle/release/app-release.aab`  
**Sortie APK :** `frontend/build/app/outputs/flutter-apk/app-release.apk`

### Build iOS (si applicable)

```bash
cd frontend
flutterfire configure
flutter build ios --release \
  --dart-define=API_BASE_URL=https://api.votredomaine.com/api
# Puis archive via Xcode → App Store Connect
```

### CI/CD — déclencher un déploiement

```bash
git tag v1.0.0
git push origin v1.0.0
# Ou : GitHub → Actions → Deploy → Run workflow → deploy=true
```

### Test SMS / auth rapide

```bash
curl -X POST https://api.votredomaine.com/api/auth/request-code \
  -H "Content-Type: application/json" \
  -d '{"phone": "+243XXXXXXXXX"}'
```

### Test partenaire API

```bash
curl https://api.votredomaine.com/api/partner/stats \
  -H "X-API-Key: CLE_PARTENAIRE_GENEREE"
```

---

## Références rapides du dépôt

| Fichier | Rôle |
|---------|------|
| `.env.production.example` | Modèle variables production |
| `backend/.env.example` | Modèle backend développement |
| `docker-compose.yml` | Stack Postgres + Redis + API + Caddy |
| `deploy/deploy.sh` / `deploy.ps1` | Script premier déploiement |
| `deploy/Caddyfile` | Reverse proxy TLS |
| `deploy/nginx.conf` | Alternative Nginx |
| `.github/workflows/deploy.yml` | Build Docker + deploy SSH |
| `.github/workflows/ci.yml` | Tests + build APK CI |
| `frontend/lib/services/api_service.dart` | `API_BASE_URL` |
| `backend/src/config/firebase.js` | Init FCM backend |
| `backend/src/services/sms.js` | Twilio + Africa's Talking |
| `README.md` | Guide déploiement rapide |

---

*Document généré pour SafeAlert v1.0.0 — compléter demain matin, puis archiver une copie chiffrée des secrets.*
