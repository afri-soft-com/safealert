# SafeAlert — tester le web (admin) et l’API

Guide court pour valider la stack web. Détail produit / flux mobile : [FEATURES.md](./FEATURES.md), [ADMIN_WEB.md](./ADMIN_WEB.md).

## URLs production

| Service | URL |
|---------|-----|
| API | `https://safealert-api.onrender.com` |
| Admin (static) | `https://safealert-admin.onrender.com` |
| Health | `/health`, `/health/ready` |
| API prefix | `/api` |

Smoke :

```bash
curl https://safealert-api.onrender.com/health
curl https://safealert-api.onrender.com/health/ready
curl https://safealert-api.onrender.com/api/map/incidents
```

Attendu : `200` + `status:ok` / `db:ok` ; incidents `200` ou `401`.

> Plan free Render : cold start 30–60 s. Prod SOS → plan Starter (voir [RENDER_DEPLOY.md](./RENDER_DEPLOY.md)).

## Local

### 1. Base + API

```bash
docker compose up -d db

cd backend
cp .env.example .env   # DATABASE_URL, JWT_SECRET
npm install
npm run migrate
npm run seed
npm run dev            # http://localhost:3000
```

### 2. Console admin

```bash
cd admin-web
cp .env.example .env   # VITE_API_BASE_URL=http://localhost:3000/api
npm install
npm run dev            # http://localhost:5173
```

En dev, Vite peut proxifier `/api` vers le backend. OTP : log `[DEV OTP]` + champ `devCode` dans `POST /api/auth/request-code` (si aucun SMS configuré).

### Bypass OTP temporaire (prod sans Twilio)

**Sécurité :** jamais activé par défaut. À retirer dès que SerdiPay/Twilio est en place.

Sur Render → service **safealert-api** → Environment :

```env
ALLOW_DEV_OTP=true
OTP_BYPASS_CODE=123456   # recommandé pour tests : code fixe pour tous les numéros
PLATFORM_ADMIN_PHONE=+243971163574
```

Avec `ALLOW_DEV_OTP=true`, `devCode` est **toujours** renvoyé (UI « Code de test ») même si Twilio/SerdiPay est configuré ; le SMS est quand même tenté. `OTP_BYPASS_CODE=123456` évite un code aléatoire à chaque demande (pratique pour ~15 testeurs). **Retirer les deux flags** dès que le SMS fonctionne.

Après `POST /api/auth/request-code` :
- réponse JSON : `{ "devCode": "XXXXXX", ... }`
- logs Render : `[DEV OTP] +243… → XXXXXX` (`console.warn`)
- admin-web : hint « Code de test : XXXXXX » (même en build prod)

Admin URL : `https://safealert-admin.onrender.com`  
Numéro **admin** documenté : `+243971163574` — **ne pas** l’utiliser pour tester l’UX citoyen (Flutter).

#### Numéros client (Flutter) — hors admin

Avec `ALLOW_DEV_OTP=true`, **n’importe quel** numéro E.164 valide fonctionne : OTP renvoyé dans `devCode` + UI (« Code de test : … ») ; au premier login, cocher **Nouveau compte** + pseudo → rôle `citizen` par défaut.

| Numéro | Rôle suggéré | Usage |
|--------|--------------|--------|
| `+243810000001` | `citizen` | UX citoyen (défaut après signup) |
| `+243810000002` | `leader` | flux leader / secteur |
| `+243810000003` | `agent` | flux agent / terrain |

**Ne pas** tester le client avec `+243971163574` (`platform_admin`).

Promouvoir les rôles après création (ou upsert) :

```sql
-- Créer / promouvoir (Render Shell ou psql avec DATABASE_URL) :
INSERT INTO users (phone, pseudo, role) VALUES
  ('+243810000001', 'TestCitoyen', 'citizen'),
  ('+243810000002', 'TestLeader', 'leader'),
  ('+243810000003', 'TestAgent', 'agent')
ON CONFLICT (phone) DO UPDATE SET role = EXCLUDED.role, updated_at = NOW();
```

Ou via admin-web → Utilisateurs → changer le rôle (`citizen` / `leader` / `agent`).  
Script optionnel : `node backend/scripts/seed-client-test-phones.js` (avec `DATABASE_URL` prod).

APK / Play Internal pointant vers la prod :

```bash
cd frontend
flutter build apk --release --dart-define=API_BASE_URL=https://safealert-api.onrender.com/api
# ou appbundle (voir PLAY_STORE.md)
```

Promouvoir admin (une fois le compte créé via OTP) :

```bash
# Shell Render sur safealert-api, ou local avec DATABASE_URL prod :
PLATFORM_ADMIN_PHONE=+243971163574 npm run migrate
# ou SQL :
UPDATE users SET role = 'platform_admin' WHERE phone = '+243971163574';
```

Puis **supprimer** `ALLOW_DEV_OTP` (et `OTP_BYPASS_CODE`) sur Render.

### 3. Compte admin

```bash
# backend/
PLATFORM_ADMIN_PHONE=+243XXXXXXXXX npm run migrate
# ou : UPDATE users SET role = 'platform_admin' WHERE phone = '+243…';
```

Se reconnecter pour rafraîchir le JWT.

### 4. Mobile (optionnel, même API)

```bash
cd frontend
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<IP_LAN>:3000/api
```

## Checklist smoke

- [ ] `/health` et `/health/ready` OK (local ou prod)
- [ ] Admin : login OTP → tableau de bord
- [ ] Pages : Utilisateurs, Incidents, Annuaire, Groupes
- [ ] `/ops` : file SOS / SLA (rôle adapté)
- [ ] Portail partenaire : clé API + stats
- [ ] `CORS_ORIGIN` inclut l’URL admin en prod
- [ ] Auth mobile OTP → JWT
- [ ] SOS trigger / cancel (ou fausse alerte)
- [ ] Carte : liste + signalement incident
- [ ] CI `main` : `deploy-render` + smoke (voir [CI.md](./CI.md))

## Admin « Not Found » en prod

Vérifier Render → `safealert-admin` : Static Site, Root `admin-web`, Publish `dist`, dernier deploy Live. Détails : [RENDER_DEPLOY.md](./RENDER_DEPLOY.md).
