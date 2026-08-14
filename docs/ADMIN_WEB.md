# Console d'administration web — SafeAlert

Interface web pour les **administrateurs plateforme** (`platform_admin`). Complète l'écran admin Flutter par une console bureau adaptée à la gestion quotidienne.

## Prérequis

- Node.js 20+
- Backend SafeAlert en cours d'exécution (`http://localhost:3000`)
- Compte utilisateur avec rôle `platform_admin`

## Démarrage rapide

```bash
# Terminal 1 — API
cd backend
npm run dev

# Terminal 2 — Console admin
cd admin-web
cp .env.example .env
npm install
npm run dev
```

Ouvrir **http://localhost:5173**

En développement, Vite proxifie `/api` vers le backend. Vous pouvez aussi définir :

```env
VITE_API_BASE_URL=http://localhost:3000/api
```

## Connexion

1. Saisir le numéro de téléphone au format international (`+243971163574`)
2. Recevoir le code OTP par SMS (ou, sans SMS : terminal / logs Render `[DEV OTP]` / champ `devCode` — voir bypass ci-dessous)
3. Seuls les comptes `platform_admin` accèdent à la console

**Production :** [https://safealert-admin.onrender.com](https://safealert-admin.onrender.com)

### Bypass OTP temporaire (sans Twilio)

Sur l’API Render (`safealert-api`) :

```env
ALLOW_DEV_OTP=true
OTP_BYPASS_CODE=123456
```

Puis demander un code avec `+243971163574` : le code apparaît dans la réponse API, l’UI admin (« Code de test : … ») et les logs Render (avec bypass fixe : toujours `123456`). **Supprimer `ALLOW_DEV_OTP` / `OTP_BYPASS_CODE` dès que le SMS fonctionne.**

### Promouvoir un administrateur

```bash
# Compte déjà créé via l'app mobile (ou après un OTP réussi)
PLATFORM_ADMIN_PHONE=+243971163574 npm run migrate

# Ou SQL direct
UPDATE users SET role = 'platform_admin' WHERE phone = '+243971163574';
```

L'utilisateur doit **se reconnecter** pour obtenir un JWT avec le nouveau rôle.

## Fonctionnalités

| Page | Description |
|------|-------------|
| **Tableau de bord** | Utilisateurs, incidents, partenaires actifs, groupes |
| **Ops temps réel** | File SOS, délais de prise en charge, zones actives, export CSV/PDF (JWT) |
| **Utilisateurs** | Liste, recherche serveur (téléphone / pseudo / secteur), rôles et secteurs |
| **Partenaires API** | Création de clés (affichées une seule fois), révocation |
| **Annuaire d'urgence** | CRUD des numéros d'urgence |
| **Incidents** | Liste paginée, filtres, panneau de détail (description, **nom du lieu**, GPS / coordonnées, signaleur) |
| **Groupes** | Vue des groupes de voisins |
| **Journal d'audit** | Historique des actions admin (`FEATURE_AUDIT_LOG`) — rôles, partenaires, annuaire… |
| **Aide** | Rappel des rôles et liens vers la documentation |

### Portail partenaire (hors console admin)

URL publique : **`/portail-partenaire`**. Les partenaires s'authentifient avec leur **clé API** (pas d'OTP admin). Lien également depuis la page de connexion et le pied de menu admin.

## Production

```bash
cd admin-web
npm run build   # → dist/
```

### Option A — Servir depuis l'API

```env
# backend/.env
ADMIN_WEB_DIST=../admin-web/dist
CORS_ORIGIN=https://admin.votredomaine.com
```

L'interface sera accessible sur `https://api.votredomaine.com/admin/`

### Option B — Hébergement statique séparé

Déployer `admin-web/dist/` sur Nginx, Netlify, etc. avec :

```env
VITE_API_BASE_URL=https://api.votredomaine.com/api
```

## Sécurité

- JWT stocké en `localStorage` (usage admin interne)
- Toutes les routes `/api/admin/*` exigent `platform_admin`
- Ne jamais committer `.env` ni clés API partenaires

## Stack

- Vite 6 + React 19 + TypeScript
- React Router 7
- Thème sombre SafeAlert (accent rouge `#CC1C1C`)
