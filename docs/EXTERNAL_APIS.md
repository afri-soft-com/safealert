# Inventaire des APIs externes — SafeAlert

Ce document recense toutes les intégrations externes à configurer avant un déploiement en production.

**Légende statut :** `À configurer` = requis ou recommandé en prod · `Optionnel` = l'app fonctionne sans · `Intégré` = aucune clé requise

---

## 1. PostgreSQL + PostGIS (base de données)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Stockage utilisateurs, incidents, contacts, groupes, clés partenaires |
| **Variables** | `DATABASE_URL`, `DATABASE_URL_DIRECT` (Neon), `POSTGRES_*` (Docker local) |
| **Fichiers** | `backend/src/config/database.js`, `docker-compose.yml`, `docker-compose.neon.yml` |
| **Statut** | À configurer |
| **Valeur (placeholder)** | Voir ci-dessous |

### Stratégie de déploiement

| Environnement | Fichier Compose | Base de données |
|---------------|-----------------|-----------------|
| Développement local | `docker-compose.yml` | PostGIS dans Docker (`db:5432`) |
| Production tout-en-un VPS | `docker-compose.yml` | PostGIS sur le même VPS |
| **Production recommandée** | `docker-compose.neon.yml` | **Neon** (PostGIS) + API/Redis sur VPS |

**Neon** : PostgreSQL managé compatible PostGIS. Deux URLs :

- `DATABASE_URL` — endpoint **poolé** (`-pooler` dans l'hôte) pour l'API en runtime
- `DATABASE_URL_DIRECT` — endpoint **direct** (sans pooler) pour `npm run migrate` et DDL

Après création du projet Neon : `CREATE EXTENSION IF NOT EXISTS postgis;` puis lancer les migrations SafeAlert.

**Placeholder Neon :**

```
DATABASE_URL=postgresql://USER:PASS@ep-xxx-pooler.region.aws.neon.tech/safealert?sslmode=require
DATABASE_URL_DIRECT=postgresql://USER:PASS@ep-xxx.region.aws.neon.tech/safealert?sslmode=require
```

**Placeholder Docker local :** `postgresql://user:MOT_DE_PASSE@db:5432/safealert`

---

## 2. Twilio (SMS — OTP et alertes)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Envoi des codes OTP à l'inscription et SMS d'alerte SOS aux contacts |
| **Variables** | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER` |
| **URL API** | `https://api.twilio.com` (SDK officiel) |
| **Fichiers** | `backend/src/services/sms.js`, `backend/src/controllers/authController.js` |
| **Statut** | À configurer (sinon simulation console en dev) |
| **Valeur (placeholder)** | SID / Token depuis [console.twilio.com](https://console.twilio.com) |

**Dev sans Twilio :** avec `NODE_ENV=development` et variables Twilio/Africa's Talking vides, le code OTP s'affiche dans le terminal backend (`[DEV OTP]`) et est renvoyé dans la réponse `POST /api/auth/request-code` via le champ `devCode` (jamais en production).

---

## 3. Africa's Talking (SMS — alternative Afrique)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Fallback SMS si Twilio non configuré (marchés africains) |
| **Variables** | `AFRICASTALKING_API_KEY`, `AFRICASTALKING_USERNAME` |
| **URL API** | `https://api.africastalking.com/version1/messaging` |
| **Fichiers** | `backend/src/services/sms.js` |
| **Statut** | Optionnel (utilisé si Twilio absent) |
| **Valeur (placeholder)** | Clé API depuis [africastalking.com](https://africastalking.com) |

---

## 4. Firebase Cloud Messaging (push notifications)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Notifications push SOS, alertes de proximité (500 m), annulations |
| **Variables backend** | `FCM_PROJECT_ID`, `FCM_PRIVATE_KEY`, `FCM_CLIENT_EMAIL` |
| **Variables frontend** | `google-services.json` (Android), `GoogleService-Info.plist` (iOS), `lib/firebase_options.dart` |
| **URL** | Firebase Admin SDK (pas d'URL fixe) |
| **Fichiers** | `backend/src/config/firebase.js`, `frontend/lib/services/fcm_service.dart` |
| **Statut** | À configurer pour les push en production |
| **Valeur (placeholder)** | Compte de service Firebase (JSON) — voir README section FCM |

---

## 5. Redis (cache optionnel — recommandé en production)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Cache des alertes actives et utilisateurs à proximité |
| **Variables** | `REDIS_URL` |
| **Fichiers** | `backend/src/config/redis.js`, `backend/src/services/alert.js`, `docker-compose.yml`, `docker-compose.neon.yml` |
| **Statut** | Optionnel (dégradation gracieuse sans Redis) |
| **Valeur (placeholder)** | `redis://redis:6379` |

### Décision d'infrastructure — où déployer Redis ?

| Option | Quand l'utiliser | `REDIS_URL` |
|--------|------------------|-------------|
| **Conteneur Docker sur le VPS** (recommandé) | API hébergée sur VPS via `docker-compose` / `docker-compose.neon.yml` | `redis://redis:6379` |
| Upstash / Redis managé | Pas de Redis sur le VPS, ou scaling multi-région | `rediss://default:TOKEN@xxx.upstash.io:6379` |
| Absent | Dev minimal, tests CI | laisser vide |

**Choix retenu pour SafeAlert :** Redis en **conteneur Docker sur le même VPS que l'API** (`redis:7-alpine`). Latence minimale, aucun coût tiers, aligné avec le déploiement SSH actuel. L'API continue de fonctionner sans Redis (cache désactivé).

---

## 6. OpenStreetMap (tuiles cartographiques)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Affichage de la carte des incidents (tuiles raster) |
| **Variables** | Aucune (URL publique) |
| **URL** | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` |
| **Fichiers** | `frontend/lib/screens/map_screen.dart`, `frontend/lib/screens/heatmap_screen.dart` |
| **Statut** | Intégré — respecter la [politique d'utilisation OSM](https://operations.osmfoundation.org/policies/tiles/) en production (User-Agent, cache) |
| **Valeur** | — |

---

## 7. Google Maps (liens SMS uniquement)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Lien de position GPS dans les SMS d'alerte |
| **Variables** | Aucune |
| **URL** | `https://maps.google.com/?q={lat},{lng}` |
| **Fichiers** | `backend/src/services/alert.js` |
| **Statut** | Intégré |
| **Valeur** | — |

---

## 8. Socket.io (temps réel)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Diffusion temps réel des alertes SOS et changements d'incidents |
| **Variables** | Dérivé de `API_BASE_URL` (frontend) — même origine que l'API |
| **Fichiers** | `backend/src/server.js`, `frontend/lib/services/socket_service.dart` |
| **Statut** | Intégré (hébergé avec l'API backend) |
| **Valeur (placeholder)** | `https://api.votredomaine.com` |

---

## 9. API SafeAlert (backend interne)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Toutes les routes REST (`/api/*`) |
| **Variables frontend** | `API_BASE_URL` (build Flutter : `--dart-define=API_BASE_URL=...`) |
| **Variables backend** | `PORT`, `NODE_ENV`, `JWT_SECRET`, `JWT_EXPIRES_IN`, `CORS_ORIGIN` |
| **Fichiers** | `frontend/lib/services/api_service.dart`, `backend/src/server.js` |
| **Statut** | À configurer |
| **Valeur (placeholder)** | `https://api.votredomaine.com/api` |

---

## 10. GitHub Container Registry (CI/CD)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Stockage et distribution de l'image Docker backend |
| **Image** | `ghcr.io/afri-soft-com/safealert-api` (tags : `latest`, `sha`, `v*`) |
| **Auth CI** | `GITHUB_TOKEN` (permissions `packages: write` dans le workflow) |
| **Variables VPS** | `API_IMAGE` dans `.env.production` |
| **Fichiers** | `.github/workflows/deploy.yml`, `.github/workflows/ci.yml`, `docker-compose.neon.yml` |
| **Statut** | Configuré dans les workflows — rendre le package GHCR public ou authentifier le VPS |

Le VPS tire l'image via `docker compose pull` (`API_IMAGE=ghcr.io/afri-soft-com/safealert-api:latest`).

---

## 11. Déploiement SSH (VPS)

| Champ | Valeur |
|-------|--------|
| **Objectif** | Déploiement automatique sur le serveur de production |
| **Variables (secrets GitHub)** | `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_PATH`, `PRODUCTION_URL`, `COMPOSE_FILE` |
| **Fichiers** | `.github/workflows/deploy.yml`, `deploy/deploy.sh`, `docker-compose.neon.yml` |
| **Statut** | À configurer pour déploiement auto |
| **Valeur (placeholder)** | `DEPLOY_PATH=/opt/safealert`, `COMPOSE_FILE=docker-compose.neon.yml`, `PRODUCTION_URL=https://api.votredomaine.com` |

### Smoke tests post-déploiement (GitHub Actions)

Le job `smoke-production` dans `deploy.yml` vérifie après build/déploiement :

- `GET /health` → 200
- `GET /health/ready` → 200
- `GET /api/map/incidents` → 200 ou 401 (API joignable)

Retries : 12 tentatives, intervalle 10 s. Secret requis : `PRODUCTION_URL`.

---

## 12. Caddy / reverse proxy TLS

| Champ | Valeur |
|-------|--------|
| **Objectif** | Terminaison HTTPS (Let's Encrypt) devant l'API |
| **Variables** | `DOMAIN` |
| **Fichiers** | `deploy/Caddyfile`, `docker-compose.yml` (profile `proxy`) |
| **Statut** | À configurer en production |
| **Valeur (placeholder)** | `api.votredomaine.com` |

---

## Checklist rapide avant déploiement

- [ ] `JWT_SECRET` ≥ 32 caractères aléatoires
- [ ] Neon : projet dédié SafeAlert, `CREATE EXTENSION postgis`, URLs poolée + directe
- [ ] `DATABASE_URL` / `DATABASE_URL_DIRECT` (Neon) ou Postgres Docker local
- [ ] `REDIS_URL=redis://redis:6379` (Redis sur VPS) ou Upstash si managé
- [ ] `API_IMAGE=ghcr.io/afri-soft-com/safealert-api:latest` sur le VPS
- [ ] SMS : Twilio **ou** Africa's Talking
- [ ] Firebase : `google-services.json` + clés FCM backend
- [ ] DNS `DOMAIN` → IP du VPS
- [ ] `API_BASE_URL` dans le build APK/IPA
- [ ] Secrets GitHub : `DEPLOY_*`, `PRODUCTION_URL`
- [ ] Package GHCR public ou `docker login ghcr.io` sur le VPS
- [ ] Keystore Android pour signature Play Store
