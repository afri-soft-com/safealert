# Point d'arrêt — session du 12 juin 2026

Document de reprise pour continuer le travail sur **admin-web** et le déploiement Render sans perdre le contexte.

---

## Objectif de la session

Mettre en ligne et automatiser la **console d'administration web** (`admin-web/`) pour les comptes `platform_admin`.

---

## Ce qui est fait et fonctionnel

### Console admin en ligne

| Élément | Valeur |
|---------|--------|
| URL | https://safealert-admin.onrender.com |
| Type Render | **Static Site** `safealert-admin` |
| Service ID Render | `srv-d8ltt3nlk1mc73bl4c9g` |
| Root Directory | `admin-web` |
| Publish Directory | `dist` |
| Build Command | `npm install && npm run build` |
| Variable build | `VITE_API_BASE_URL=https://safealert-api.onrender.com/api` |

La page de connexion SafeAlert s'affiche correctement (HTTP 200).

### API backend

| Élément | Valeur |
|---------|--------|
| URL | https://safealert-api.onrender.com |
| Service ID Render | `srv-d8le8e8js32c7397i4tg` |
| Type | Web Service Node (pas Docker) |
| Plan | Free (cold start ~30–60 s) |
| CORS | `CORS_ORIGIN=https://safealert-admin.onrender.com` (configuré sur Render) |

### CI/CD GitHub

Fichier : `.github/workflows/ci.yml`

- Job **admin-web** : `npm ci` + `npm run build` à chaque push / PR
- Job **deploy-admin-render** : sur push `main`, si `admin-web/**` ou `render.yaml` change → deploy hook Render (si secret configuré)
- Job **docker-build** : attend aussi le succès de **admin-web**

### Blueprint Render

Fichier : `render.yaml` — service `safealert-admin` activé (Static Site + routes SPA `/* → /index.html`).

### GitHub — déjà poussé sur `main`

Commit : **`30e8211`** — `feat: CI admin-web et déploiement Render automatique sur main`

Fichiers inclus :
- `render.yaml`
- `.github/workflows/ci.yml`
- `docs/DOCUMENTATION_VIVANTE.md`

Repo : https://github.com/afri-soft-com/safealert

---

## Ce qui n'est PAS encore poussé (local uniquement)

| Fichier | Contenu |
|---------|---------|
| `admin-web/public/_redirects` | Réécriture SPA pour Render (`/* → /index.html`) |
| `docs/RENDER_DEPLOY.md` | Section dépannage « Not Found » + note CI/CD |
| `frontend/.metadata` | Changement Flutter sans lien avec admin — **ne pas committer** sauf intention |

---

## Ce qui n'a pas été testé de bout en bout

- [ ] Connexion OTP sur https://safealert-admin.onrender.com avec un compte `platform_admin`
- [ ] Navigation complète (utilisateurs, partenaires, incidents, groupes, annuaire)
- [ ] Secret GitHub `RENDER_DEPLOY_HOOK_ADMIN` (optionnel — deploy hook Render)
- [ ] Synchronisation Blueprint Render si d'autres services doivent être alignés sur `render.yaml`

### Promouvoir un admin (si pas encore fait)

```sql
UPDATE users SET role = 'platform_admin' WHERE phone = '+243XXXXXXXXX';
```

Puis se reconnecter pour obtenir un JWT avec le bon rôle.

---

## Comment reprendre en local

```powershell
# Terminal 1 — API
cd backend
npm run dev

# Terminal 2 — Admin
cd admin-web
copy .env.example .env
npm install
npm run dev
# → http://localhost:5173
```

---

## Opérations Render (session précédente)

Le MCP `user-render` n'était **pas connecté** dans Cursor ; les opérations ont été faites via l'**API Render** (`RENDER_API_KEY`).

Actions réalisées :
1. Création du Static Site `safealert-admin` (il n'existait pas — le domaine renvoyait « Not Found »)
2. Configuration `VITE_API_BASE_URL` et `CORS_ORIGIN`
3. Redéploiements admin + API → statut **Live**

Pour les prochaines sessions : activer **Cursor → Settings → MCP → user-render** avec `RENDER_API_KEY`.

---

## Prochaines étapes suggérées (quand on continue)

1. Committer et pousser `admin-web/public/_redirects` + mise à jour `docs/RENDER_DEPLOY.md`
2. Tester la connexion admin en production (OTP + rôle `platform_admin`)
3. Ajouter le secret GitHub `RENDER_DEPLOY_HOOK_ADMIN` (Deploy Hook dans Render → safealert-admin → Settings)
4. Vérifier que l'API Render est à jour avec le dernier commit `main` (dernier deploy API réussi après restauration des variables d'environnement)
5. Documenter l'URL admin dans `COMMERCIALISATION_APIS.md` ou fiche prod si besoin

---

## Références utiles

| Document | Sujet |
|----------|--------|
| [ADMIN_WEB.md](./ADMIN_WEB.md) | Démarrage local, fonctionnalités |
| [RENDER_DEPLOY.md](./RENDER_DEPLOY.md) | Déploiement Render, dépannage |
| [DOCUMENTATION_VIVANTE.md](./DOCUMENTATION_VIVANTE.md) | CI/CD, architecture |
| [PROVENANCE_DONNEES_ET_ROLES.md](./PROVENANCE_DONNEES_ET_ROLES.md) | Rôles et clés API partenaires |

---

*Dernière mise à jour : 12 juin 2026 — arrêt demandé par l'utilisateur après confirmation que la page admin s'affiche en ligne.*
