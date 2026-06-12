# SafeAlert — déploiement sur Render.com

## Déploiement via MCP Render (Cursor)

Le serveur MCP `user-render` permet de créer et configurer les services depuis Cursor.

### Prérequis MCP

1. Clé API Render : [Account Settings → API Keys](https://dashboard.render.com/u/settings#api-keys)
2. Dans Cursor : **Settings → MCP → user-render** → variable `RENDER_API_KEY`
3. **GitHub connecté à Render** avec accès au dépôt `afri-soft-com/safealert` (obligatoire pour un dépôt privé)

### État du workspace (dernière session MCP)

| Élément | Statut |
|---------|--------|
| Connexion MCP | ✅ OK |
| Workspace | **My Workspace** (`celestinkas@gmail.com`) |
| Key Value `safealert-redis` | ✅ Créé (Frankfurt, free, `allkeys-lru`) |
| Web Service `safealert-api` | ⚠️ Bloqué — dépôt GitHub privé non accessible à Render |
| Static Site `safealert-admin` | ⏸ Non créé (attendre l’API) |

### Créer l’API après connexion GitHub

Une fois le dépôt connecté dans [Render Dashboard → Account → GitHub](https://dashboard.render.com/) :

**Option A — Blueprint (recommandé)** : New → Blueprint → repo `afri-soft-com/safealert` → Apply `render.yaml`.

**Option B — MCP `create_web_service`** :

| Paramètre | Valeur |
|-----------|--------|
| `name` | `safealert-api` |
| `runtime` | `node` |
| `repo` | `https://github.com/afri-soft-com/safealert` |
| `branch` | `main` |
| `region` | `frankfurt` |
| `plan` | `starter` (évite le sleep du free tier) |
| `buildCommand` | `cd backend && npm install && npm run migrate` |
| `startCommand` | `cd backend && npm start` |

Variables d’environnement à définir via MCP `update_environment_variables` ou le dashboard (ne jamais committer) :

- `NODE_ENV=production`, `HOST=0.0.0.0`, `JWT_EXPIRES_IN=30d`
- `DATABASE_URL` (Neon poolée), `DATABASE_URL_DIRECT` (Neon direct pour migrations)
- `JWT_SECRET`, `TWILIO_*`, `FCM_*`
- `REDIS_URL` (copier depuis le dashboard Key Value `safealert-redis`)
- `NOMINATIM_USER_AGENT` (ex. `SafeAlert/1.0 (safealert-api.onrender.com)`)
- `CORS_ORIGIN` (URL admin-web une fois déployée)

**Limitations MCP** : pas de `rootDir`, pas de `healthCheckPath`, pas de runtime Docker. Configurer **Health Check Path** `/health/ready` manuellement dans le dashboard après création.

### Static Site admin-web (optionnel, MCP)

```
create_static_site:
  name: safealert-admin
  repo: https://github.com/afri-soft-com/safealert
  branch: main
  buildCommand: cd admin-web && npm install && npm run build
  publishPath: admin-web/dist
  envVars:
    - VITE_API_BASE_URL=https://safealert-api.onrender.com/api
```

---

## Verdict de compatibilité

**Oui, partiellement compatible.**

SafeAlert peut tourner sur Render en remplacement (ou en complément) du déploiement VPS actuel (`docker-compose.neon.yml` + SSH dans `.github/workflows/deploy.yml`). L’architecture cible reste la même : **PostgreSQL sur Neon**, **Redis managé**, **API Node.js** en Web Service Render.

| Composant | Render | Notes |
|-----------|--------|-------|
| API Node (`backend/`) | ✅ | Dockerfile existant, `npm start` → `node src/server.js` |
| PostgreSQL | ✅ (Neon) | Pas de Postgres local sur Render — `DATABASE_URL` Neon |
| Redis | ✅ (optionnel) | Render Key Value, Upstash, ou sans Redis (cache désactivé) |
| Health checks | ✅ | `/health` et `/health/ready` déjà implémentés |
| Socket.io (SOS temps réel) | ⚠️ | OK sur **une seule instance** ; pas de scaling horizontal sans adaptateur Redis |
| admin-web | ✅ (optionnel) | Static Site Render ou servi via `ADMIN_WEB_DIST` sur l’API |
| CI/CD actuel (GHCR + SSH) | — | Alternative indépendante ; Render peut builder depuis Git |

### Limitations importantes

1. **Plan gratuit Render** : le Web Service s’endort après ~15 min d’inactivité. Au réveil, cold start de 30–60 s — **déconseillé pour une app SOS en production**.
2. **Socket.io** : fonctionne sur une instance unique. Ne pas activer l’autoscaling Render sans ajouter `@socket.io/redis-adapter` au backend.
3. **Latence Afrique (RDC)** : Render propose surtout **Frankfurt**, **Oregon**, **Singapore**. Neon est en `aws-us-east-1`. Les utilisateurs à Kinshasa subiront une latence plus élevée qu’avec un VPS régional (ex. Afrique du Sud).
4. **Redis** : recommandé pour le cache des alertes actives (`/api/map/incidents`). Sans `REDIS_URL`, l’API fonctionne mais interroge Postgres à chaque requête.
5. **Migrations Neon** : utiliser `DATABASE_URL_DIRECT` (endpoint sans `-pooler`) pour le `preDeployCommand`.

---

## Architecture cible

```
[App Flutter / admin-web]
         │
         ▼
[Render Web Service — safealert-api]
         │
    ┌────┴────┐
    ▼         ▼
 [Neon]   [Redis Render Key Value ou Upstash]
PostgreSQL
```

---

## Déploiement rapide (Blueprint)

Le fichier `render.yaml` à la racine du dépôt décrit l’infrastructure.

### 1. Prérequis

- Compte [render.com](https://render.com)
- Projet Neon configuré ([docs/NEON_SETUP.md](./NEON_SETUP.md))
- Secrets : `JWT_SECRET` (32+ caractères), Twilio, FCM (voir [docs/FIREBASE_SETUP.md](./FIREBASE_SETUP.md))

### 2. Créer le Blueprint

1. Render Dashboard → **New** → **Blueprint**
2. Connecter le dépôt GitHub `safesecurity`
3. Render détecte `render.yaml`
4. Renseigner les variables marquées `sync: false` (voir liste ci-dessous)
5. **Apply**

Render crée :

- **Key Value** `safealert-redis` (Redis compatible, plan free)
- **Web Service** `safealert-api` (Docker, région Frankfurt par défaut)

### 3. Déploiement manuel (sans Blueprint)

Si vous préférez créer les services à la main :

#### Web Service — API

| Paramètre | Valeur |
|-----------|--------|
| Type | Web Service |
| Runtime | Docker |
| Root Directory | `backend` |
| Dockerfile | `./Dockerfile` |
| Health Check Path | `/health/ready` |
| Pre-Deploy Command | `sh -c 'DATABASE_URL="${DATABASE_URL_DIRECT:-$DATABASE_URL}" npm run migrate'` |
| Start Command | *(défaut Dockerfile)* `node src/server.js` |
| Region | Frankfurt (meilleur compromis pour l’Afrique) |
| Plan | Starter minimum pour prod (pas de sleep) |

#### Redis (au choix)

**Option A — Render Key Value** (intégré au Blueprint)

- Dashboard → **New** → **Key Value**
- Copier l’URL de connexion → `REDIS_URL`

**Option B — Upstash** (free tier, `rediss://...`)

- [console.upstash.com](https://console.upstash.com) → créer une base Redis
- Coller `REDIS_URL` dans les env vars Render

**Option C — Sans Redis**

- Laisser `REDIS_URL` vide — l’API logue `Redis not configured — alert cache disabled`

#### Static Site — admin-web (optionnel)

| Paramètre | Valeur |
|-----------|--------|
| Type | Static Site |
| Root Directory | `admin-web` |
| Build Command | `npm install && npm run build` |
| Publish Directory | `dist` |
| Env (build) | `VITE_API_BASE_URL=https://safealert-api.onrender.com/api` |

Mettre à jour `CORS_ORIGIN` sur l’API avec l’URL du site admin.

### CI/CD GitHub Actions

Le workflow `.github/workflows/ci.yml` :

- **Vérifie** le build `admin-web` à chaque push / PR.
- **Déclenche** le déploiement Render sur `main` si `admin-web/**` ou `render.yaml` a changé.

Configurer le secret GitHub **`RENDER_DEPLOY_HOOK_ADMIN`** (optionnel) :

1. Render Dashboard → **safealert-admin** → **Settings** → **Deploy Hook** → copier l’URL.
2. GitHub → repo → **Settings** → **Secrets and variables** → **Actions** → New secret.

Sans ce secret, le déploiement repose sur l’auto-deploy Render branché au dépôt GitHub.

---

## Variables d’environnement

### Obligatoires

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | URL **poolée** Neon (`-pooler`, `?sslmode=require`) |
| `DATABASE_URL_DIRECT` | URL **directe** Neon (migrations / DDL) |
| `JWT_SECRET` | Secret fort, 32+ caractères |
| `NODE_ENV` | `production` |
| `PORT` | `3000` (Render injecte aussi `PORT` automatiquement) |

### Recommandées

| Variable | Description |
|----------|-------------|
| `REDIS_URL` | Render Key Value ou Upstash |
| `CORS_ORIGIN` | Origines autorisées, ex. `https://admin.votredomaine.com` |
| `JWT_EXPIRES_IN` | `30d` (défaut) |

### SMS (OTP login)

| Variable | Description |
|----------|-------------|
| `TWILIO_ACCOUNT_SID` | Console Twilio |
| `TWILIO_AUTH_TOKEN` | Console Twilio |
| `TWILIO_PHONE_NUMBER` | Numéro émetteur E.164 |
| `AFRICASTALKING_API_KEY` | Alternative SMS |
| `AFRICASTALKING_USERNAME` | Alternative SMS |

### Notifications push

| Variable | Description |
|----------|-------------|
| `FCM_PROJECT_ID` | Firebase |
| `FCM_PRIVATE_KEY` | Clé privée (échapper les `\n` ou coller multiligne) |
| `FCM_CLIENT_EMAIL` | Compte de service Firebase |

### Optionnelles

| Variable | Description |
|----------|-------------|
| `PLATFORM_ADMIN_PHONE` | Promotion admin lors d’une migration |
| `ADMIN_WEB_DIST` | Chemin vers `admin-web/dist` si servi par l’API |
| `HOST` | `0.0.0.0` (défaut dans le code) |

Référence complète : `.env.production.example` et `backend/.env.example`.

---

## Vérification post-déploiement

```bash
curl https://safealert-api.onrender.com/health
curl https://safealert-api.onrender.com/health/ready
curl https://safealert-api.onrender.com/api/map/incidents
```

Attendu :

- `/health` → `200`, `"status":"ok"`
- `/health/ready` → `200`, `"db":"ok"`
- `/api/map/incidents` → `200` ou `401`

Configurer `PRODUCTION_URL` dans les secrets GitHub si vous réutilisez le job `smoke-production` du workflow CI.

---

## Comparaison Render vs VPS (déploiement actuel)

| | Render | VPS + docker-compose.neon.yml |
|---|--------|-------------------------------|
| Postgres | Neon (externe) | Neon (externe) |
| Redis | Key Value / Upstash | Conteneur local |
| Déploiement | Git push / Blueprint | GHCR + SSH |
| HTTPS | Automatique (`*.onrender.com`) | Caddy (profil `proxy`) |
| Coût entrée | Free (avec sleep) / ~7 $/mo Starter | Coût VPS |
| Latence RDC | Élevée (EU/US) | Configurable (région VPS) |
| Socket.io | 1 instance | 1 instance |

Les deux approches sont valides. Pour la **production SOS en RDC**, un **VPS régional** ou un plan Render **Starter sans sleep** + région **Frankfurt** reste préférable au plan gratuit.

---

## Seed initial (numéros d’urgence)

Une fois l’API déployée, depuis votre machine locale :

```bash
cd backend
DATABASE_URL="postgresql://...direct..." npm run seed
```

Ou via un one-off Render Shell avec `DATABASE_URL_DIRECT`.

---

## Promouvoir un administrateur plateforme

Voir [ADMIN_WEB.md](./ADMIN_WEB.md) :

```sql
UPDATE users SET role = 'platform_admin' WHERE phone = '+243XXXXXXXXX';
```

---

## Dépannage

| Symptôme | Cause probable | Action |
|----------|----------------|--------|
| 503 sur `/health/ready` | Neon inaccessible ou mauvaise URL | Vérifier `DATABASE_URL`, IP allowlist Neon |
| Migration échoue | URL poolée pour DDL | Utiliser `DATABASE_URL_DIRECT` en pre-deploy |
| Cold start long | Plan free | Passer au plan Starter |
| WebSocket SOS instable | Scaling > 1 instance | Désactiver autoscaling ou ajouter Redis adapter Socket.io |
| OTP SMS échoue | Twilio trial / geo | Voir [EXTERNAL_APIS.md](./EXTERNAL_APIS.md) |
| CORS admin-web | Origine non listée | Ajouter l’URL dans `CORS_ORIGIN` |
