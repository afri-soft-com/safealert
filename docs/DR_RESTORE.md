# Disaster recovery — restore dry-run (SafeAlert)

## Objectif

Vérifier qu’un dump Postgres produit par [`scripts/db-backup.sh`](../scripts/db-backup.sh) est **lisible et restaurable**, sans toucher à la production.

## Prérequis

- Un artifact CI `db-backup-<sha>` ou un fichier local `backups/safealert-*.sql.gz`
- `postgresql-client` (`pg_dump`, `psql`, `gzip`)
- Une base **temporaire** locale (jamais l’URL External Render de prod)

## Procédure dry-run

```bash
# 1) Contrôle d’intégrité seul
./scripts/db-restore-dry-run.sh backups/safealert-YYYYMMDDTHHMMSSZ.sql.gz

# 2) Restauration dans une base jetable
createdb safealert_restore_test   # ou équivalent
DRY_RUN_DATABASE_URL='postgresql://postgres:postgres@localhost:5432/safealert_restore_test' \
  ./scripts/db-restore-dry-run.sh backups/safealert-….sql.gz
```

Le script refuse par défaut les hôtes cloud (`render.com`, etc.).  
Ne forcez `ALLOW_PROD_DRY_RUN=1` que pour un exercice contrôlé hors trafic.

## CI (optionnel)

Le job `db-backup` du workflow CI produit déjà l’artifact. Un dry-run automatique n’est **pas** obligatoire à chaque push (coût + secrets).  
Pour un exercice périodique :

1. Télécharger l’artifact `db-backup-<sha>` depuis Actions
2. Lancer le script en local ou sur un runner avec Postgres éphémère
3. Noter le résultat dans l’issue / runbook ops

## Après un incident réel

1. Mettre `FEATURE_MAINTENANCE_MODE=true` (bannière + SOS soft-off via `FEATURE_SOS_ENABLED` si besoin)
2. Restaurer depuis le dernier artifact `db-backup-*` vers une instance staging
3. Valider `/health/ready`, login OTP, déclenchement SOS test
4. Couper la maintenance et basculer le DNS / Render si applicable

Voir aussi [`docs/CI.md`](CI.md) et [`docs/RENDER_DEPLOY.md`](RENDER_DEPLOY.md).

## Déclenchement manuel (rappel)

- `force_deploy_web` — backend + admin + Render  
- `force_mobile_aab` — AAB (+ Play internal si secrets)

Restore dry-run : [`docs/DR_RESTORE.md`](DR_RESTORE.md).
