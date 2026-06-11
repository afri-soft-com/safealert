# SafeAlert

Application de sùcuritù citoyenne pour l'Afrique subsaharienne. Architecture **offline-first** avec cache SQLite local, JWT auth par tùlùphone, et design adaptù aux zones ù faible connectivitù.

## Documentation

| Document | Description |
|----------|-------------|
| [docs/MANUEL_UTILISATEUR.md](docs/MANUEL_UTILISATEUR.md) | Guide utilisateur (franùais) ù installation, OTP, SOS, FAQ |
| [docs/DOCUMENTATION_VIVANTE.md](docs/DOCUMENTATION_VIVANTE.md) | Architecture, CI/CD, ùtat du projet, changelog |
| [docs/EXTERNAL_APIS.md](docs/EXTERNAL_APIS.md) | Variables d'environnement et APIs externes |
| [docs/NEON_SETUP.md](docs/NEON_SETUP.md) | Configuration PostgreSQL Neon |
| [docs/ADMIN_WEB.md](docs/ADMIN_WEB.md) | Console web d'administration plateforme |

## Architecture

```
safesecurity/
??? admin-web/         # Console admin web (Vite + React)
?   ??? src/           # Pages, auth OTP, client API
??? frontend/          # Flutter 3.x (Android + iOS)
?   ??? lib/
?   ?   ??? providers/     # 7 providers (state management)
?   ?   ??? screens/       # 13 ùcrans
?   ?   ??? services/      # API, cache, FCM, SOS discret
?   ?   ??? theme.dart
?   ??? test/              # 56 tests unitaires
??? backend/           # Node.js/Express API
?   ??? src/
?   ?   ??? controllers/   # 10 controllers
?   ?   ??? middleware/     # JWT + partner auth
?   ?   ??? routes/        # 10 route modules
?   ?   ??? config/        # DB, migrations, FCM, SMS
?   ??? tests/             # 15 tests API (vitest + supertest)
??? docker-compose.yml # PostgreSQL 16 + PostGIS + API
??? .github/workflows/ # CI/CD pipeline
```

## Prùrequis

- **Flutter** 3.32.6+ ([install](https://docs.flutter.dev/get-started/install))
- **Node.js** 20+ et **npm**
- **Docker** (recommandù pour la base de donnùes)

## Dùmarrage rapide

### 1. Base de donnùes

```bash
docker compose up -d db
# ou utiliser une instance PostgreSQL 16 + PostGIS locale

# Stack complùte (API + Postgres) :
docker compose up -d
# Donnùes de dùmo (une seule fois) :
docker compose --profile init run --rm seed
```

### 2. Backend

```bash
cd backend
cp .env.example .env      # ùditer DATABASE_URL et JWT_SECRET
npm install
npm run migrate           # crùe les tables
npm run seed              # donnùes de dùmonstration
npm run dev               # ? http://localhost:3000
```

### 3. Console admin web (optionnel)

```bash
cd admin-web
cp .env.example .env
npm install
npm run dev               # http://localhost:5173
```

Voir [docs/ADMIN_WEB.md](docs/ADMIN_WEB.md) pour la connexion admin et le dÈploiement.

### 4. Frontend mobile

> **Important :** le dossier `frontend/` est une app **Flutter** (`pubspec.yaml`). N'utilisez **pas** `npm` ici. Toutes les commandes Node/npm se lancent depuis `backend/`.

Sur un **tùlùphone Android** (mùme Wi-Fi que le PC), rùcupùrez l'IP LAN du PC (`ipconfig`, adresse du type `192.168.x.x`) puis :

```bash
flutter run -d <device_id> --dart-define=API_BASE_URL=http://<IP_LAN>:3000/api
```

```bash
cd frontend
flutter pub get
flutter run               # ùmulateur ou appareil connectù
```

## Tests

```bash
# Backend (vitest)
cd backend && npm test

# Frontend (flutter_test)
cd frontend && flutter test

# Lint
cd frontend && flutter analyze

# Console admin web
cd admin-web && npm run build
```

## CI/CD

Le pipeline GitHub Actions (`.github/workflows/ci.yml`) exùcute :
- **Backend** : lint ? migration ? tests API (avec PostgreSQL)
- **Frontend** : `flutter pub get` ? `flutter analyze` ? `flutter test`

Le workflow **Deploy** (`.github/workflows/deploy.yml`) :
- Se dùclenche sur les tags `v*` ou manuellement (`workflow_dispatch`)
- Build et push de l'image Docker backend vers GHCR (ou registre configurù)
- Dùploiement SSH optionnel (secrets : `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_PATH`)

## HTTPS / reverse proxy

En production, placer l'API derriùre un reverse proxy TLS :

**Option A ù Caddy (Let's Encrypt automatique)** :
```bash
# .env : DOMAIN=api.votredomaine.com
docker compose --profile proxy up -d
```

**Option B ù Nginx** : utiliser le modùle `deploy/nginx.conf` (certificats manuels ou Certbot).

L'API ùcoute en HTTP sur le port 3000 ; le proxy termine TLS et transmet `X-Forwarded-*`.

## API Endpoints

### Auth
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| POST | `/api/auth/request-code` | ù | Envoyer code SMS |
| POST | `/api/auth/verify-code` | ù | Vùrifier code ? JWT |
| GET | `/api/auth/profile` | JWT | Profil utilisateur |
| PUT | `/api/auth/position` | JWT | Mettre ù jour last_lat/lng |
| PUT | `/api/auth/fcm-token` | JWT | Enregistrer token FCM |
| DELETE | `/api/auth/account` | JWT | Supprimer compte |

### SOS
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| POST | `/api/sos/trigger` | JWT | Dùclencher alerte |
| POST | `/api/sos/cancel` | JWT | Annuler derniùre alerte |
| POST | `/api/sos/:id/cancel` | JWT | Annuler alerte par ID |
| GET | `/api/sos/my` | JWT | Mes alertes SOS |

### Carte / Incidents
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/map/incidents` | ù | Incidents publics |
| POST | `/api/map/incidents` | JWT | Signaler incident |
| POST | `/api/map/incidents/:id/verify` | JWT | Confirmer signalement |
| GET | `/api/map/stats` | JWT | Statistiques quartier |
| GET | `/api/map/heatmap` | ù | Donnùes carte de chaleur |

### Contacts
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/contacts` | JWT | Liste contacts |
| POST | `/api/contacts` | JWT | Ajouter contact |
| DELETE | `/api/contacts/:id` | JWT | Supprimer contact |

### Annuaire
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/annuaire` | ù | Numùros d'urgence (filtre `?country=`) |

### Groupes de Voisins
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/groups/my` | JWT | Mes groupes |
| GET | `/api/groups/discoverable` | JWT | Groupes disponibles |
| POST | `/api/groups` | JWT | Crùer un groupe |
| POST | `/api/groups/:id/join` | JWT | Rejoindre un groupe |
| POST | `/api/groups/:id/leave` | JWT | Quitter un groupe |

### Leader
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/leader/sector/incidents` | JWT+leader | Incidents du secteur |
| GET | `/api/leader/sector/stats` | JWT+leader | Stats du secteur |
| POST | `/api/leader/incidents/:id/resolve` | JWT+leader | Rùsoudre incident |

### Rapport PDF
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/report` | JWT+leader | Tùlùcharger rapport PDF |

### Historique
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/history` | JWT | Tous mes incidents |

### Partenaires ONG
| Mùthode | Route | Auth | Description |
|---------|-------|------|-------------|
| POST | `/api/partner/register` | JWT | Crùer clù API |
| GET | `/api/partner/stats` | API Key | Stats publiques |
| GET | `/api/partner/incidents` | API Key | Incidents publics |
| GET | `/api/partner/heatmap` | API Key | Heatmap publique |

## Offline-first

Tous les providers Flutter utilisent un cache SQLite local (`LocalDatabase`) avec TTL configurable :
- **Incidents** : 5 min
- **Stats** : 10 min
- **Heatmap** : 60 min
- **Annuaire** : 24 h
- **Contacts** : 5 min
- **Conseils sùcuritù** : donnùes embarquùes (aucun rùseau requis)

## Push Notifications (FCM)

1. Crùer un projet Firebase Console
2. Tùlùcharger `google-services.json` dans `frontend/android/app/`
3. Configurer les variables `FCM_*` dans `backend/.env` (ne jamais committer les clùs)
4. Dans `frontend/` :
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   Cela gùnùre `lib/firebase_options.dart`. Un modùle est disponible dans `lib/firebase_options.dart.example`.
5. Sans config FCM, l'API et l'app dùmarrent normalement ù les push sont ignorùes (message dans les logs)

## Variables d'environnement

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | URL PostgreSQL avec PostGIS |
| `JWT_SECRET` | Clù JWT (min 32 caractùres) |
| `TWILIO_*` | Credentials Twilio (SMS) |
| `AFRICASTALKING_*` | Alternative SMS Afrique |
| `FCM_*` | Credentials Firebase Cloud Messaging |
| `CORS_ORIGIN` | Origines autorisùes (CSV) en production |
| `DOMAIN` | Domaine pour Caddy (profile `proxy` dans docker-compose) |
| `REDIS_URL` | Cache Redis optionnel (dùfaut docker : `redis://redis:6379`) |
| `DOCKER_REGISTRY` | Registre Docker (CI deploy, dùfaut GHCR) |

## Dùployer demain matin (guide rapide)

### 1. Prùparer le VPS

```bash
git clone <votre-repo> /opt/safealert
cd /opt/safealert
cp .env.production.example .env.production
# ùditer JWT_SECRET, mots de passe DB, DOMAIN, SMS, FCM
```

### 2. Lancer la stack

```bash
chmod +x deploy/deploy.sh && ./deploy/deploy.sh
# ou : docker compose --env-file .env.production up -d
# seed : docker compose --profile init run --rm seed
# TLS  : docker compose --profile proxy up -d
```

### 3. Vùrifier

```bash
curl http://127.0.0.1:3000/health/ready
curl https://api.votredomaine.com/health
```

### 4. Build APK

```bash
cd frontend
flutter pub get
flutterfire configure
flutter build apk --release --dart-define=API_BASE_URL=https://api.votredomaine.com/api
```

### 5. Checklist manuelle

- VPS + Docker + ports 80/443
- `.env.production` (JWT 32+ chars)
- DNS ? IP VPS
- Firebase : `google-services.json` + clùs FCM backend
- SMS : Twilio ou Africa's Talking
- Play Store : keystore de signature Android

### Build mobile (URL API)

```bash
flutter build apk --dart-define=API_BASE_URL=https://votre-api.example.com/api
```
