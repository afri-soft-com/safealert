# SafeAlert — base de données Neon

## État actuel

| Élément | Valeur |
|---------|--------|
| Projet Neon | `super-bread-07647037` (nom console : **educongo**) |
| Branche | `production` (`br-divine-wind-apvm8782`) |
| Base de données | `safealert` |
| Région | `aws-us-east-1` |
| PostgreSQL | 18.4 (Neon — PostGIS 3.6 activé) |
| Endpoint compute | `ep-twilight-sea-apcojpgg` |

> **Note :** le serveur MCP Neon est limité au projet `educongo`. Un projet Neon dédié « SafeAlert » n’a pas pu être créé via MCP (outil `create_project` absent). La base `safealert` a été créée dans le projet existant.

## PostGIS

L’extension est installée sur la base `safealert` :

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
```

Vérification : `SELECT PostGIS_Version();` — requis pour les colonnes `GEOGRAPHY` et les requêtes `ST_DWithin`.

## Chaînes de connexion (placeholders)

Récupérer le mot de passe du rôle `neondb_owner` dans [console.neon.tech](https://console.neon.tech) → projet → Connection details.

**Poolée (runtime API)** :

```
postgresql://neondb_owner:PASSWORD@ep-twilight-sea-apcojpgg-pooler.c-7.us-east-1.aws.neon.tech/safealert?sslmode=require
```

**Directe (migrations / DDL)** :

```
postgresql://neondb_owner:PASSWORD@ep-twilight-sea-apcojpgg.c-7.us-east-1.aws.neon.tech/safealert?sslmode=require
```

Ne jamais committer de vrais mots de passe. Copier vers `.env.production` (gitignored) ou secrets GitHub.

## Schéma applicatif

Migrations appliquées via `backend/src/config/migrate.js` (PostGIS + tables métier).

Tables présentes : `users`, `trust_contacts`, `emergency_numbers`, `incidents`, `neighborhood_groups`, `group_members`, `otp_codes`, `incident_verifications`, `partner_api_keys` (+ tables/vues PostGIS).

## Prochaines étapes

1. Copier `.env.production.example` → `.env.production` et renseigner `PASSWORD` (ou coller l’URL complète depuis la console).
2. Secrets GitHub Actions : `DATABASE_URL`, `DATABASE_URL_DIRECT`, `JWT_SECRET`, etc.
3. **Optionnel — seed :** `DATABASE_URL=... npm run seed` dans `backend/` pour les numéros d’urgence.
4. **Optionnel — projet Neon dédié SafeAlert :** créer un nouveau projet dans la console Neon, puis retirer le paramètre `projectId` de l’URL du serveur MCP Neon dans Cursor (déconnexion/reconnexion OAuth si besoin) pour permettre la gestion multi-projets.

## Tests avant déploiement

Suite automatisée (Windows) :

```powershell
.\scripts\pre-deploy-test.ps1
```

Vérifications manuelles rapides (API locale + Neon) :

```powershell
cd backend
# DATABASE_URL = URL poolée Neon dans backend\.env
$env:NODE_ENV = "development"
$env:JWT_SECRET = "votre-secret-dev-32-caracteres-minimum"
node src/server.js
```

Dans un autre terminal :

```powershell
Invoke-RestMethod http://localhost:3000/health
Invoke-RestMethod http://localhost:3000/health/ready   # db: ok si Neon accessible
Invoke-RestMethod http://localhost:3000/api/map/incidents   # GET public, pas d'auth
```

`POST /api/map/incidents` et les routes `/stats` nécessitent un JWT (`Authorization: Bearer …`).

## Limitations MCP constatées

- Pas d’outil `list_projects` ni `create_project` dans la configuration actuelle.
- Scope forcé sur `super-bread-07647037` (educongo).
- Pas d’outil `create_database` dédié — création via `run_sql` : `CREATE DATABASE safealert;`.
- `get_connection_string` renvoie l’endpoint poolé par défaut ; l’endpoint direct est dérivé du host sans `-pooler`.
