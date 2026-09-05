# SafeAlert — CI/CD (GitHub Actions)

## Workflows

| Workflow | Fichier | Déclencheurs |
|----------|---------|--------------|
| **CI** (tests + Render + AAB) | `.github/workflows/ci.yml` | push `main`/`develop`, PR → `main`, **Run workflow** manuel |
| **Deploy** (GHCR + SSH VPS) | `.github/workflows/deploy.yml` | tags `v*`, **Run workflow** manuel |

## Ordre des jobs (CI sur `main`)

```
changes
  ├─ backend ──┬─ docker-build
  │            └─ db-backup ──┐
  ├─ admin-web ───────────────┼─ deploy-render → smoke /health/ready
  └─ frontend ────────────────┴─ mobile-aab (AAB + Release + Play internal,production)
```

1. **changes** — filtres de chemins (`backend`, `frontend`, `admin`, `deploy_web`).
2. **backend / frontend / admin-web** — tests / analyze / build (selon chemins).
3. **db-backup** — `pg_dump` **avant** le deploy Render si `backend/**` a changé.
4. **deploy-render** — déclenche Render API (+ admin) puis attend `live` + smoke.
5. **mobile-aab** — build AAB si `frontend/**` a changé **et** les tests Flutter ont réussi.

Render exécute encore `npm run migrate && npm start` au démarrage du conteneur (`render.yaml`). Le job `db-backup` compense en dumpant la prod **depuis GitHub** juste avant le trigger Render.

## Backup avant migrate

Script : [`scripts/db-backup.sh`](../scripts/db-backup.sh) — `pg_dump` générique (Postgres / Render).

Ordre des variables (première non vide) :

1. `PROD_DATABASE_URL` (**recommandé**)
2. `DATABASE_URL_DIRECT` (fallback legacy)
3. `DATABASE_URL` (fallback)

### Secret `PROD_DATABASE_URL` (Render Postgres)

Les runners GitHub Actions sont **hors** du réseau privé Render. Il faut l’**External Database URL** (pas l’Internal) :

1. [Render Dashboard](https://dashboard.render.com) → service PostgreSQL **`safealert-db`**
2. Onglet **Connect** → **External Database URL**
3. Copier l’URL (généralement avec `sslmode=require`)
4. GitHub → Settings → Secrets → Actions → secret `PROD_DATABASE_URL`

| URL Render | Utilisable depuis GH Actions ? |
|------------|--------------------------------|
| **External Database URL** | ✅ Oui (requis pour `db-backup`) |
| **Internal Database URL** | ❌ Non — réservée au réseau privé Render (API ↔ DB) |

| Chemin | Comportement |
|--------|----------------|
| CI → Render | Job `db-backup` → artifact `db-backup-<sha>` (rétention 14 j). **Skip + warning** si aucun secret DB. |
| Deploy → SSH VPS | Job `db-backup` (artifact) **puis** `pg_dump` sur le VPS dans `backups/pre-migrate-*.sql.gz` **avant** `npm run migrate`. Si le dump VPS échoue → migrate annulé. |

> Le endpoint `/api/backup/contacts` de l’app est une **feature contacts chiffrés**, pas un dump Postgres.

## Secrets GitHub utiles

| Secret | Rôle |
|--------|------|
| `PROD_DATABASE_URL` | Dump prod — **External Database URL** de `safealert-db` (+ SSL) |
| `DATABASE_URL_DIRECT` / `DATABASE_URL` | Fallbacks pour le dump (éviter l’URL Internal) |
| `RENDER_API_KEY` | Deploy API Render |
| `RENDER_API_SERVICE_ID` | ID service `safealert-api` |
| `RENDER_ADMIN_SERVICE_ID` | ID service `safealert-admin` |
| `PRODUCTION_URL` | Smoke test (défaut `https://safealert-api.onrender.com`) |
| `ANDROID_KEYSTORE_BASE64` + `ANDROID_KEY_PROPERTIES` | Signature Play de l’AAB |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Upload Play **internal,production** (un seul edit, `status: completed`) |
| `DEPLOY_HOST` / `DEPLOY_USER` / `DEPLOY_SSH_KEY` | Deploy SSH (workflow Deploy) |

## Déclenchement manuel (CI)

GitHub → **Actions** → **CI** → **Run workflow** :

- `force_deploy_web` (défaut **true**) — force backend + admin + deploy Render
- `force_mobile_aab` (défaut **false**) — force build AAB

Restore dry-run (hors CI obligatoire) : [`docs/DR_RESTORE.md`](DR_RESTORE.md) + `scripts/db-restore-dry-run.sh`.

## Vérifier

1. Actions → dernier run `CI` sur `main` : jobs `db-backup` puis `deploy-render`.
2. Si secret DB configuré : artifact `db-backup-<sha>` téléchargeable.
3. Sans secret : warning jaune « skipping DB backup », deploy non bloqué.
4. Frontend : `mobile-aab` vert uniquement si `frontend` est **success**.
5. Manuel : **Run workflow** avec `force_deploy_web` pour re-déployer sans nouveau commit applicatif.
