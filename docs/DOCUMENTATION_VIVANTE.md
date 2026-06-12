# Documentation vivante — SafeAlert

Document technique maintenu au fil de l'évolution du code. À mettre à jour à chaque changement significatif.

---

## 1. Vue d'ensemble de l'architecture

```
┌─────────────────┐     HTTPS/REST      ┌──────────────────────────────┐
│  Flutter App    │ ◄──────────────────► │  API Node.js (Express)       │
│  Android / iOS  │     WebSocket (SOS)  │  Docker → GHCR → VPS         │
└────────┬────────┘                      └───────┬──────────┬───────────┘
         │ SQLite cache                         │          │
         │ offline-first                        ▼          ▼
         │                               ┌──────────┐ ┌────────┐
         │                               │ Neon     │ │ Redis  │
         │                               │ Postgres │ │ (VPS)  │
         │                               │ + PostGIS│ │ cache  │
         └─ FCM push ◄───────────────────┴──────────┘ └────────┘
                    Firebase
                    Twilio SMS (OTP, alertes)
```

| Composant | Rôle | Hébergement |
|-----------|------|-------------|
| **Frontend** | UI Flutter, cache SQLite, SOS discret | APK / Play Store |
| **Backend** | API REST, JWT, OTP, FCM, PDF | VPS Docker (image GHCR) |
| **Neon** | PostgreSQL managé + PostGIS | Cloud Neon |
| **Redis** | Cache sessions / rate-limit optionnel | VPS (docker-compose) |
| **Twilio** | SMS OTP et notifications | SaaS |
| **Firebase** | Push FCM | Google Cloud |

Référence détaillée des clés API : [EXTERNAL_APIS.md](EXTERNAL_APIS.md).

---

## 2. Exécution en local

### Prérequis

- Flutter 3.32+
- Node.js 20+
- Docker (Postgres local) ou compte Neon
- Téléphone Android physique (recommandé pour OTP / GPS / volume SOS)

### Backend (PC)

```bash
cd backend
cp .env.example .env
# DATABASE_URL, JWT_SECRET (32+ caractères)
npm install
npm run migrate
npm run seed   # optionnel
npm run dev    # http://localhost:3000
```

### Frontend (PC + appareil Android)

```bash
cd frontend
flutter pub get
# IP locale du PC (ipconfig / ifconfig), pas localhost :
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000/api
```

### Console admin web

```bash
cd admin-web
cp .env.example .env
npm install
npm run dev    # http://localhost:5173
```

Backend sur le port 3000 requis. CORS autorise `localhost:5173` en développement. Voir [ADMIN_WEB.md](ADMIN_WEB.md).

**Points importants :**

- PC et téléphone sur le **même Wi-Fi**.
- Autoriser le port **3000** dans le pare-feu Windows.
- Pour OTP sans Twilio : `NODE_ENV=development` + variables Twilio vides → code dans le terminal (`[DEV OTP]`) et champ `devCode` côté app (debug).

### Tests

```bash
cd backend && npm test
cd frontend && flutter analyze && flutter test
```

---

## 3. Variables d'environnement

Voir le tableau complet dans [EXTERNAL_APIS.md](EXTERNAL_APIS.md).

| Variable | Obligatoire prod | Description |
|----------|------------------|-------------|
| `DATABASE_URL` | Oui | Neon pooler ou Postgres local |
| `JWT_SECRET` | Oui (32+ chars) | Signature JWT |
| `TWILIO_*` | Recommandé | SMS OTP / alertes |
| `FCM_*` | Optionnel | Push notifications |
| `REDIS_URL` | Optionnel | Cache (`redis://redis:6379`) |
| `CORS_ORIGIN` | Prod | Origines autorisées |

Fichiers modèles : `backend/.env.example`, `.env.production.example`.

---

## 4. CI/CD

Fichiers : `.github/workflows/ci.yml`, `.github/workflows/deploy.yml`.

### Pipeline CI (chaque push / PR)

1. **Backend** : install → lint → migration test → `npm test` (Vitest + supertest, DB mockée).
2. **Frontend** : `flutter pub get` → `flutter analyze` → `flutter test`.
3. **Admin-web** : `npm ci` → `npm run build` (Vite + TypeScript).
4. **Docker** : build image API (smoke, sans push) après succès des trois jobs ci-dessus.

### Déploiement admin-web (Render Static Site)

Sur **push vers `main`** lorsque `admin-web/**` ou `render.yaml` change :

1. Le job **deploy-admin-render** déclenche le deploy hook Render (si configuré).
2. Sinon, Render peut déployer via l’intégration Git (auto-deploy du Blueprint).

**Secret GitHub optionnel** : `RENDER_DEPLOY_HOOK_ADMIN` — URL du deploy hook du service `safealert-admin` (Render Dashboard → service → Settings → Deploy Hook).

Variables Render (dashboard, pas GitHub) : `VITE_API_BASE_URL` sur le static site ; `CORS_ORIGIN` sur l’API.

### Pipeline Deploy (API backend)

- Déclenchement : tag `v*` ou `workflow_dispatch`.
- Build image Docker backend → push **GHCR** (`ghcr.io/...`).
- Déploiement SSH optionnel sur VPS (`deploy/deploy.sh`).

### Stack production (VPS)

```bash
docker compose --env-file .env.production up -d
# Neon : docker-compose.neon.yml
# TLS : docker compose --profile proxy up -d
```

---

## 5. Maintenir cette documentation

| Événement code | Action doc |
|----------------|------------|
| Nouvel écran / fonction utilisateur | Mettre à jour [MANUEL_UTILISATEUR.md](MANUEL_UTILISATEUR.md) |
| Nouvelle variable d'env ou API externe | Mettre à jour [EXTERNAL_APIS.md](EXTERNAL_APIS.md) |
| Changement architecture / déploiement | Mettre à jour ce fichier |
| Correctif ou feature livrée | Ajouter une entrée **Changelog** ci-dessous |
| Nouvelle route API | Mettre à jour `README.md` (table endpoints) |
| Nouvelle table ou changement de rôles | Mettre à jour [PROVENANCE_DONNEES_ET_ROLES.md](PROVENANCE_DONNEES_ET_ROLES.md) |

**Règle :** toute PR qui modifie le comportement visible ou le déploiement doit inclure la mise à jour doc associée.

---

## 6. État du projet (juin 2026)

| Domaine | Avancement | Notes |
|---------|------------|-------|
| Auth OTP téléphone | ~95 % | Normalisation E.164 (+243), Twilio + mode dev |
| SOS + annulation | ~90 % | GPS, FCM, contacts |
| Carte incidents | ~85 % | OSM, filtres, signalement |
| Contacts confiance | ~90 % | CRUD + cache offline |
| Annuaire urgence | ~95 % | Cache 24h |
| Groupes voisins | ~95 % | Membres, chat, alertes locales, discover join, SOS→groupes push |
| Mode discret | ~75 % | Calculatrice + volume Android |
| Leader / PDF | ~85 % | Filtrage secteur, gravité zones |
| Administration | ~90 % | Écran mobile + **console web** `admin-web/` |
| Géocodage zones | ~90 % | Nominatim OSM, cache rate-limit |
| Push FCM | ~60 % | Nécessite config Firebase |
| iOS volume SOS | ~20 % | Limitation plateforme |

### Lacunes connues (non bloquantes)

- Appels téléphoniques depuis l'annuaire (bouton numéro non câblé à `url_launcher`).
- Heatmap simplifiée (grille, pas de tuiles cartographiques).
- Pas de publication Play Store automatisée dans CI.
- iOS : pas de SOS discret par volume.

---

## 7. Changelog

### 2026-06-11 (console admin web)

- **admin-web/** : console Vite + React + TypeScript (thème sombre SafeAlert, UI français).
- Pages : connexion OTP, tableau de bord, utilisateurs, partenaires, annuaire urgence, incidents, groupes.
- **API** : `GET /api/admin/stats`, CRUD `/api/admin/emergency-numbers`, `GET /api/admin/incidents`, `GET /api/admin/groups`.
- CORS dev : `localhost:5173` ; option `ADMIN_WEB_DIST` pour servir le build depuis l'API.
- Doc : [ADMIN_WEB.md](ADMIN_WEB.md).

### 2026-06-11 (administration & zones)

- **Géocodage Nominatim** : `zone_name` auto à la création SOS/signalement ; cache + rate-limit.
- **Gravité** : 3 confirmations → `danger` ; résolution zone calme → `safe`.
- **Secteurs leaders** : `users.sector_name`, filtrage ILIKE côté `/api/leader`.
- **Admin** : rôle `platform_admin`, routes `/api/admin/*`, écran Flutter `admin_screen.dart`.
- **Partenaires** : enregistrement ouvert restreint aux admins.

### 2026-06-11

- **OTP E.164** : normalisation `+243` côté backend (`utils/phone.js`) et frontend (`lib/utils/phone.dart`).
- **Overflow UI** : corrections responsive sur login, top bar, nav bar, carte, annuaire, SOS, paramètres, groupes, leader, accueil ; tests widget 320dp et clavier.
- **Twilio / dev** : logs OTP dev via `logger.log` (pas de `console.log` direct en prod) ; `devCode` en développement uniquement.
- **Tests backend** : le serveur HTTP ne démarre plus sous Vitest (`NODE_ENV=test` / `VITEST`) — évite `EADDRINUSE` port 3000.
- **Docs** : ajout manuel utilisateur FR et documentation vivante.

### Historique antérieur

- Stack Neon + Redis VPS + déploiement GHCR.
- Cache SQLite offline-first (providers Flutter).
- CI GitHub Actions backend + frontend.

---

---

## 9. Administration et secteurs (juin 2026)

### Rôles utilisateur

| Rôle | Code | Capacités |
|------|------|-----------|
| Citoyen | `citizen` | SOS, signalements, carte |
| Responsable | `leader` | Mode responsable, PDF secteur |
| Agent | `agent` | Idem leader |
| Admin plateforme | `platform_admin` | Gestion utilisateurs + clés partenaires |

### Modèle secteur

- Colonne `users.sector_name` (nullable, VARCHAR 100).
- Leaders/agents avec secteur : incidents filtrés via `zone_name ILIKE '%secteur%'`.
- Assignation : `PATCH /api/admin/users/:id/sector` (admin uniquement).

### Géocodage inverse (zones)

- Service : `backend/src/services/geocode.js`
- API : Nominatim OSM (`/reverse?lat=&lon=&format=json`)
- User-Agent obligatoire : `NOMINATIM_USER_AGENT` ou défaut SafeAlert
- Cache mémoire + intervalle min 1,1 s entre requêtes
- Appelé à la création SOS et signalement carte → remplit `incidents.zone_name`

### Gravité après confirmations

- `verified_by >= 3` → `severity = danger`, `status = verified`
- Résolution leader sans autre incident actif 24 h dans la zone → `severity = safe`

### Endpoints admin (`/api/admin/*`)

Tous protégés par JWT + `requireRole('platform_admin')`.

| Méthode | Route | Action |
|---------|-------|--------|
| GET | `/users?page&limit` | Liste utilisateurs paginée |
| PATCH | `/users/:id/role` | `{ role }` |
| PATCH | `/users/:id/sector` | `{ sector_name }` |
| GET | `/partners` | Liste clés partenaires |
| POST | `/partners` | Créer clé (`partner_name`) |
| DELETE | `/partners/:id` | Révoquer (`is_active=false`) |
| GET | `/stats` | Métriques tableau de bord |
| GET/POST | `/emergency-numbers` | Liste / créer numéro urgence |
| PUT/DELETE | `/emergency-numbers/:id` | Modifier / supprimer |
| GET | `/incidents?page&limit&status&zone&from&to` | Tous les incidents (paginé) |
| GET | `/groups?page&limit` | Liste groupes voisins |

`POST /api/partner/register` est réservé aux `platform_admin` (alias admin POST partners).

### Console web (`admin-web/`)

- Stack : Vite + React + TypeScript, port dev **5173**.
- Auth : OTP téléphone via `/api/auth/*`, garde `platform_admin`.
- Guide : [ADMIN_WEB.md](ADMIN_WEB.md).

### Premier administrateur

```bash
# Option A — variable d'environnement (compte déjà créé)
PLATFORM_ADMIN_PHONE=+243812345678 npm run migrate

# Option B — SQL direct
UPDATE users SET role = 'platform_admin' WHERE phone = '+243812345678';
```

L'utilisateur doit se **reconnecter** pour obtenir un JWT avec le nouveau rôle.

---

## 8. Liens utiles

| Document | Public |
|----------|--------|
| [MANUEL_UTILISATEUR.md](MANUEL_UTILISATEUR.md) | Utilisateurs finaux |
| [EXTERNAL_APIS.md](EXTERNAL_APIS.md) | DevOps / intégrations |
| [NEON_SETUP.md](NEON_SETUP.md) | Configuration base Neon |
| [ADMIN_WEB.md](ADMIN_WEB.md) | Admin plateforme (console web) |
| [PROVENANCE_DONNEES_ET_ROLES.md](PROVENANCE_DONNEES_ET_ROLES.md) | Provenance des données et rôles |
| [README.md](../README.md) | Démarrage rapide développeur |

---

*Maintenu par l'équipe SafeAlert — dernière révision : 11 juin 2026*
