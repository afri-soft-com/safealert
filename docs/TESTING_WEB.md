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
# optionnel : OTP_BYPASS_CODE=123456   # sinon code aléatoire à chaque demande
PLATFORM_ADMIN_PHONE=+243971163574
```

Le flag suffit même si `TWILIO_*` est encore présent (ex. Trial qui n’envoie pas vers +243). Préférer vider les clés SMS en parallèle. **Retirer le flag** dès que le SMS fonctionne.

Après `POST /api/auth/request-code` :
- réponse JSON : `{ "devCode": "XXXXXX", ... }`
- logs Render : `[DEV OTP] +243… → XXXXXX` (`console.warn`)
- admin-web : hint « Code de test : XXXXXX » (même en build prod)

Admin URL : `https://safealert-admin.onrender.com`  
Numéro de test documenté : `+243971163574`

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
