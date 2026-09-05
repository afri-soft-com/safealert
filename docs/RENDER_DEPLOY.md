# SafeAlert — déploiement sur Render.com

## Déploiement via MCP Render (Cursor)

Le serveur MCP `user-render` permet de créer et configurer les services depuis Cursor.

### Prérequis MCP

1. Clé API Render : [Account Settings → API Keys](https://dashboard.render.com/u/settings#api-keys)
2. Dans Cursor : **Settings → MCP → user-render** → variable `RENDER_API_KEY`
3. **GitHub connecté à Render** avec accès au dépôt `afri-soft-com/safealert` (obligatoire pour un dépôt privé)

### État du workspace (août 2026)

| Élément | Statut |
|---------|--------|
| Workspace | **My Workspace** (`celestinkas@gmail.com`) |
| PostgreSQL `safealert-db` | ✅ Frankfurt (Blueprint `render.yaml`) |
| Key Value `safealert-redis` | Créé (Frankfurt, free) — peut être **suspended** après inactivité |
| Web Service `safealert-api` | ✅ Live — `https://safealert-api.onrender.com` (`srv-d8le8e8js32c7397i4tg`) |
| Static Site `safealert-admin` | ✅ Live — `https://safealert-admin.onrender.com` (`srv-d8ltt3nlk1mc73bl4c9g`) |
| CI auto-deploy | ✅ Push `main` → API Render + smoke `/health/ready` (secret `RENDER_API_KEY`) |
| Health check | `/health/ready` |
| Build / start | `cd backend && npm ci` / `cd backend && npm run migrate && npm start` |

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
- `DATABASE_URL` / `DATABASE_URL_DIRECT` — injectés depuis Postgres **`safealert-db`** (Blueprint) ; sinon coller l’URL Internal depuis Connect
- `JWT_SECRET`, `AFRISOFT_HUB_API_KEY`, `TWILIO_*`, `FCM_*`
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

**Oui — stack prod cible sur Render.**

SafeAlert tourne sur Render : **PostgreSQL `safealert-db`**, **Redis Key Value**, **API Node.js** (`safealert-api`), **admin-web** static. Un déploiement VPS alternatif (`docker-compose.neon.yml` + SSH) existe encore dans `.github/workflows/deploy.yml` mais n’est plus le chemin principal.

| Composant | Render | Notes |
|-----------|--------|-------|
| API Node (`backend/`) | ✅ | `npm run migrate && npm start` (`render.yaml`) |
| PostgreSQL | ✅ `safealert-db` | Frankfurt, Postgres 16 — `DATABASE_URL` depuis Blueprint |
| Redis | ✅ | Key Value `safealert-redis` (ou Upstash) |
| Health checks | ✅ | `/health` et `/health/ready` |
| Socket.io (SOS temps réel) | ⚠️ | OK sur **une seule instance** ; adaptateur Redis si scaling |
| admin-web | ✅ | Static Site `safealert-admin` |
| CI/CD | ✅ | Push `main` → backup + deploy Render ([CI.md](./CI.md)) |

### Limitations importantes

1. **Plan gratuit Render** : le Web Service s’endort après ~15 min d’inactivité. Au réveil, cold start de 30–60 s — **déconseillé pour une app SOS en production**.
2. **Socket.io** : fonctionne sur une instance unique. Ne pas activer l’autoscaling Render sans adaptateur Redis.
3. **Latence Afrique (RDC)** : Render propose surtout **Frankfurt**, **Oregon**, **Singapore**. Frankfurt est le meilleur compromis documenté ; un VPS régional (ex. Afrique du Sud) peut rester plus proche.
4. **Redis** : recommandé pour le cache des alertes actives (`/api/map/incidents`). Sans `REDIS_URL`, l’API fonctionne mais interroge Postgres à chaque requête.
5. **Backup CI** : depuis GitHub Actions, utiliser l’**External Database URL** de `safealert-db` (l’Internal n’est pas joignable hors Render). Voir [CI.md](./CI.md).

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
 [safealert-db]   [Redis safealert-redis]
 PostgreSQL
```

---

## Déploiement rapide (Blueprint)

Le fichier `render.yaml` à la racine du dépôt décrit l’infrastructure.

### 1. Prérequis

- Compte [render.com](https://render.com)
- Secrets : `JWT_SECRET` (32+ caractères), Twilio, FCM (voir [docs/FIREBASE_SETUP.md](./FIREBASE_SETUP.md))

### 2. Créer le Blueprint

1. Render Dashboard → **New** → **Blueprint**
2. Connecter le dépôt GitHub `safesecurity`
3. Render détecte `render.yaml`
4. Renseigner les variables marquées `sync: false` (voir liste ci-dessous)
5. **Apply**

Render crée :

- **PostgreSQL** `safealert-db` (Frankfurt, Postgres 16)
- **Key Value** `safealert-redis` (Redis compatible, plan free)
- **Web Service** `safealert-api` (région Frankfurt)
- **Static Site** `safealert-admin`

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
| Pre-Deploy Command | *(optionnel)* `npm run migrate` — sinon migrate au start (`render.yaml`) |
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

Voir le guide détaillé : **[CI.md](./CI.md)** (ordre des jobs, backup, secrets, Run workflow).

Le workflow `.github/workflows/ci.yml` :

- **Vérifie** backend / frontend / `admin-web` selon les chemins (PR + push).
- **`db-backup`** — `pg_dump` prod **avant** le deploy Render si `backend/**` change. Secret recommandé : `PROD_DATABASE_URL` = **External Database URL** de `safealert-db` (pas Internal). Fallbacks : `DATABASE_URL_DIRECT` / `DATABASE_URL`. Skip + warning si secret absent.
- **Déclenche** le déploiement Render sur `main` (API + admin) via `RENDER_API_KEY` + IDs de service.
- **mobile-aab** — AAB + Release GitHub + upload Play internal (si secrets keystore / Play présents).
- **Run workflow** manuel avec `force_deploy_web` / `force_mobile_aab`.

Render migre toujours au démarrage (`startCommand: npm run migrate && npm start` dans `render.yaml`). Le backup CI est donc le filet de sécurité côté GitHub avant le trigger.

---

## Variables d’environnement

### Obligatoires

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | Connexion Postgres **`safealert-db`** (Blueprint : Internal / `connectionString`) |
| `DATABASE_URL_DIRECT` | Même URL Render (alias legacy pour migrations) |
| `JWT_SECRET` | Secret fort, 32+ caractères |
| `NODE_ENV` | `production` |
| `PORT` | `3000` (Render injecte aussi `PORT` automatiquement) |

Pour le backup CI depuis GitHub Actions, **ne pas** réutiliser l’URL Internal : copier l’**External Database URL** dans le secret GitHub `PROD_DATABASE_URL` (Dashboard → `safealert-db` → **Connect**). Détails : [CI.md](./CI.md).

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

## Comparaison Render vs VPS (déploiement alternatif)

| | Render (prod actuelle) | VPS + docker-compose |
|---|--------|-------------------------------|
| Postgres | Render `safealert-db` | Postgres local ou URL externe |
| Redis | Key Value / Upstash | Conteneur local |
| Déploiement | Git push / Blueprint + CI | GHCR + SSH |
| HTTPS | Automatique (`*.onrender.com`) | Caddy (profil `proxy`) |
| Coût entrée | Free (avec sleep) / ~7 $/mo Starter | Coût VPS |
| Latence RDC | Frankfurt (EU) | Configurable (région VPS) |
| Socket.io | 1 instance | 1 instance |

Pour la **production SOS en RDC**, un plan Render **Starter sans sleep** + région **Frankfurt**, ou un **VPS régional**, reste préférable au plan gratuit.

---

## Seed initial (numéros d’urgence)

Une fois l’API déployée, depuis votre machine locale :

```bash
cd backend
DATABASE_URL="postgresql://..." npm run seed
```

Ou via un one-off **Render Shell** sur `safealert-api` (variables déjà injectées).

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
| 503 sur `/health/ready` | Postgres `safealert-db` inaccessible ou mauvaise URL | Vérifier `DATABASE_URL` / statut du service DB |
| Migration échoue | Mauvaise URL ou DB suspendue | Vérifier logs Render + `safealert-db` |
| Cold start long | Plan free | Passer au plan Starter |
| WebSocket SOS instable | Scaling > 1 instance | Désactiver autoscaling ou ajouter Redis adapter Socket.io |
| OTP SMS échoue | Twilio trial / geo | Voir [EXTERNAL_APIS.md](./EXTERNAL_APIS.md) |
| CORS admin-web | Origine non listée | Ajouter l’URL dans `CORS_ORIGIN` |
| **Not Found** sur `safealert-admin.onrender.com` | Mauvais **Publish Directory** ou build échoué | Voir ci-dessous |
| **Not Found** sur `/annuaire`, `/ops`, etc. (racine OK) | Rewrite SPA manquant (`/*` → `/index.html`) | Voir « Routes SPA » ci-dessous |

### « Not Found » sur la console admin

Deux causes distinctes :

1. **Racine** (`/`) en Not Found → aucun `dist` publié (Publish Directory / build).
2. **Sous-routes** (`/annuaire`, `/ops`…) en Not Found alors que `/` marche → **rewrite SPA absent**. Render n’applique pas `public/_redirects` ; il faut une règle **Redirects/Rewrites** (Dashboard), `routes` dans `render.yaml` (Blueprint sync), ou l’API (`scripts/ensure-admin-spa-routes.sh` via CI).

**Vérifier dans Render → safealert-admin → Settings :**

| Paramètre | Valeur correcte |
|-----------|-----------------|
| Type | **Static Site** (pas Web Service) |
| Root Directory | `admin-web` |
| Build Command | `npm install && npm run build` |
| Publish Directory | `dist` (pas `admin-web/dist` si Root = `admin-web`) |

**Routes SPA** (Redirects/Rewrites) :

| Source | Destination | Action |
|--------|-------------|--------|
| `/*` | `/index.html` | **Rewrite** |

**Puis** : onglet **Events** ou **Logs** → le dernier deploy doit être **Live** (vert), pas **Failed**.

Si Root Directory est **vide** (racine du repo) :

| Paramètre | Valeur |
|-----------|--------|
| Build Command | `cd admin-web && npm install && npm run build` |
| Publish Directory | `admin-web/dist` |

Après correction → **Manual Deploy** → **Clear build cache & deploy**.
