# SafeAlert

Application de sécurité citoyenne pour l'Afrique subsaharienne. Architecture **offline-first** avec cache SQLite local, JWT auth par téléphone, et design adapté aux zones à faible connectivité.

## Documentation

| Document | Description |
|----------|-------------|
| [docs/MANUEL_UTILISATEUR.md](docs/MANUEL_UTILISATEUR.md) | Guide utilisateur (français) — installation, OTP, SOS, FAQ |
| [docs/DOCUMENTATION_VIVANTE.md](docs/DOCUMENTATION_VIVANTE.md) | Architecture, CI/CD, état du projet, changelog |
| [docs/EXTERNAL_APIS.md](docs/EXTERNAL_APIS.md) | Variables d'environnement et APIs externes |
| [docs/NEON_SETUP.md](docs/NEON_SETUP.md) | Configuration PostgreSQL Neon |

## Architecture

```
safesecurity/
├── frontend/          # Flutter 3.x (Android + iOS)
│   ├── lib/
│   │   ├── providers/     # 7 providers (state management)
│   │   ├── screens/       # 13 écrans
│   │   ├── services/      # API, cache, FCM, SOS discret
│   │   └── theme.dart
│   └── test/              # 56 tests unitaires
├── backend/           # Node.js/Express API
│   ├── src/
│   │   ├── controllers/   # 10 controllers
│   │   ├── middleware/     # JWT + partner auth
│   │   ├── routes/        # 10 route modules
│   │   └── config/        # DB, migrations, FCM, SMS
│   └── tests/             # 15 tests API (vitest + supertest)
├── docker-compose.yml # PostgreSQL 16 + PostGIS + API
└── .github/workflows/ # CI/CD pipeline
```

## Prérequis

- **Flutter** 3.32.6+ ([install](https://docs.flutter.dev/get-started/install))
- **Node.js** 20+ et **npm**
- **Docker** (recommandé pour la base de données)

## Démarrage rapide

### 1. Base de données

```bash
docker compose up -d db
# ou utiliser une instance PostgreSQL 16 + PostGIS locale

# Stack complète (API + Postgres) :
docker compose up -d
# Données de démo (une seule fois) :
docker compose --profile init run --rm seed
```

### 2. Backend

```bash
cd backend
cp .env.example .env      # éditer DATABASE_URL et JWT_SECRET
npm install
npm run migrate           # crée les tables
npm run seed              # données de démonstration
npm run dev               # → http://localhost:3000
```

### 3. Frontend

> **Important :** le dossier `frontend/` est une app **Flutter** (`pubspec.yaml`). N'utilisez **pas** `npm` ici. Toutes les commandes Node/npm se lancent depuis `backend/`.

Sur un **t�l�phone Android** (m�me Wi-Fi que le PC), r�cup�rez l'IP LAN du PC (`ipconfig`, adresse du type `192.168.x.x`) puis :

```bash
flutter run -d <device_id> --dart-define=API_BASE_URL=http://<IP_LAN>:3000/api
```

```bash
cd frontend
flutter pub get
flutter run               # émulateur ou appareil connecté
```

## Tests

```bash
# Backend (vitest)
cd backend && npm test

# Frontend (flutter_test)
cd frontend && flutter test

# Lint
cd frontend && flutter analyze
```

## CI/CD

Le pipeline GitHub Actions (`.github/workflows/ci.yml`) exécute :
- **Backend** : lint → migration → tests API (avec PostgreSQL)
- **Frontend** : `flutter pub get` → `flutter analyze` → `flutter test`

Le workflow **Deploy** (`.github/workflows/deploy.yml`) :
- Se déclenche sur les tags `v*` ou manuellement (`workflow_dispatch`)
- Build et push de l'image Docker backend vers GHCR (ou registre configuré)
- Déploiement SSH optionnel (secrets : `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_PATH`)

## HTTPS / reverse proxy

En production, placer l'API derrière un reverse proxy TLS :

**Option A — Caddy (Let's Encrypt automatique)** :
```bash
# .env : DOMAIN=api.votredomaine.com
docker compose --profile proxy up -d
```

**Option B — Nginx** : utiliser le modèle `deploy/nginx.conf` (certificats manuels ou Certbot).

L'API écoute en HTTP sur le port 3000 ; le proxy termine TLS et transmet `X-Forwarded-*`.

## API Endpoints

### Auth
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| POST | `/api/auth/request-code` | — | Envoyer code SMS |
| POST | `/api/auth/verify-code` | — | Vérifier code → JWT |
| GET | `/api/auth/profile` | JWT | Profil utilisateur |
| PUT | `/api/auth/position` | JWT | Mettre à jour last_lat/lng |
| PUT | `/api/auth/fcm-token` | JWT | Enregistrer token FCM |
| DELETE | `/api/auth/account` | JWT | Supprimer compte |

### SOS
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| POST | `/api/sos/trigger` | JWT | Déclencher alerte |
| POST | `/api/sos/cancel` | JWT | Annuler dernière alerte |
| POST | `/api/sos/:id/cancel` | JWT | Annuler alerte par ID |
| GET | `/api/sos/my` | JWT | Mes alertes SOS |

### Carte / Incidents
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/map/incidents` | — | Incidents publics |
| POST | `/api/map/incidents` | JWT | Signaler incident |
| POST | `/api/map/incidents/:id/verify` | JWT | Confirmer signalement |
| GET | `/api/map/stats` | JWT | Statistiques quartier |
| GET | `/api/map/heatmap` | — | Données carte de chaleur |

### Contacts
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/contacts` | JWT | Liste contacts |
| POST | `/api/contacts` | JWT | Ajouter contact |
| DELETE | `/api/contacts/:id` | JWT | Supprimer contact |

### Annuaire
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/annuaire` | — | Numéros d'urgence (filtre `?country=`) |

### Groupes de Voisins
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/groups/my` | JWT | Mes groupes |
| GET | `/api/groups/discoverable` | JWT | Groupes disponibles |
| POST | `/api/groups` | JWT | Créer un groupe |
| POST | `/api/groups/:id/join` | JWT | Rejoindre un groupe |
| POST | `/api/groups/:id/leave` | JWT | Quitter un groupe |

### Leader
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/leader/sector/incidents` | JWT+leader | Incidents du secteur |
| GET | `/api/leader/sector/stats` | JWT+leader | Stats du secteur |
| POST | `/api/leader/incidents/:id/resolve` | JWT+leader | Résoudre incident |

### Rapport PDF
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/report` | JWT+leader | Télécharger rapport PDF |

### Historique
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| GET | `/api/history` | JWT | Tous mes incidents |

### Partenaires ONG
| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| POST | `/api/partner/register` | JWT | Créer clé API |
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
- **Conseils sécurité** : données embarquées (aucun réseau requis)

## Push Notifications (FCM)

1. Créer un projet Firebase Console
2. Télécharger `google-services.json` dans `frontend/android/app/`
3. Configurer les variables `FCM_*` dans `backend/.env` (ne jamais committer les clés)
4. Dans `frontend/` :
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   Cela génère `lib/firebase_options.dart`. Un modèle est disponible dans `lib/firebase_options.dart.example`.
5. Sans config FCM, l'API et l'app démarrent normalement — les push sont ignorées (message dans les logs)

## Variables d'environnement

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | URL PostgreSQL avec PostGIS |
| `JWT_SECRET` | Clé JWT (min 32 caractères) |
| `TWILIO_*` | Credentials Twilio (SMS) |
| `AFRICASTALKING_*` | Alternative SMS Afrique |
| `FCM_*` | Credentials Firebase Cloud Messaging |
| `CORS_ORIGIN` | Origines autorisées (CSV) en production |
| `DOMAIN` | Domaine pour Caddy (profile `proxy` dans docker-compose) |
| `REDIS_URL` | Cache Redis optionnel (défaut docker : `redis://redis:6379`) |
| `DOCKER_REGISTRY` | Registre Docker (CI deploy, défaut GHCR) |

## Déployer demain matin (guide rapide)

### 1. Préparer le VPS

```bash
git clone <votre-repo> /opt/safealert
cd /opt/safealert
cp .env.production.example .env.production
# Éditer JWT_SECRET, mots de passe DB, DOMAIN, SMS, FCM
```

### 2. Lancer la stack

```bash
chmod +x deploy/deploy.sh && ./deploy/deploy.sh
# ou : docker compose --env-file .env.production up -d
# seed : docker compose --profile init run --rm seed
# TLS  : docker compose --profile proxy up -d
```

### 3. Vérifier

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
- DNS → IP VPS
- Firebase : `google-services.json` + clés FCM backend
- SMS : Twilio ou Africa's Talking
- Play Store : keystore de signature Android

### Build mobile (URL API)

```bash
flutter build apk --dart-define=API_BASE_URL=https://votre-api.example.com/api
```
