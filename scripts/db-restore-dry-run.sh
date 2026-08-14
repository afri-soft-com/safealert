#!/usr/bin/env bash
# Disaster-recovery restore DRY-RUN for SafeAlert Postgres backups.
#
# Does NOT write to production. It:
#  1) Verifies a .sql.gz (or .sql) backup is readable
#  2) Optionally restores into a throwaway local/temp database (DRY_RUN_DATABASE_URL)
#
# Usage:
#   ./scripts/db-restore-dry-run.sh backups/safealert-XXXX.sql.gz
#   DRY_RUN_DATABASE_URL='postgresql://…/safealert_restore_test' ./scripts/db-restore-dry-run.sh file.sql.gz
#
# See docs/DR_RESTORE.md for the full runbook.
set -euo pipefail

BACKUP="${1:-}"
if [ -z "${BACKUP}" ] || [ ! -f "${BACKUP}" ]; then
  echo "Usage: $0 <backup.sql.gz|backup.sql>"
  echo "Optional: DRY_RUN_DATABASE_URL=postgresql://… (temp DB only — never prod)"
  exit 1
fi

echo "→ Checking backup integrity: ${BACKUP}"
if [[ "${BACKUP}" == *.gz ]]; then
  gzip -t "${BACKUP}"
  echo "  gzip OK"
  ROW_HINT="$(gzip -dc "${BACKUP}" | head -c 200000 | grep -c "CREATE TABLE\|COPY \|INSERT INTO" || true)"
else
  ROW_HINT="$(head -c 200000 "${BACKUP}" | grep -c "CREATE TABLE\|COPY \|INSERT INTO" || true)"
fi
echo "  schema/data markers found (sample): ${ROW_HINT}"

TARGET="${DRY_RUN_DATABASE_URL:-}"
if [ -z "${TARGET}" ]; then
  echo "→ DRY_RUN_DATABASE_URL not set — integrity check only (no restore)."
  echo "  To exercise a full restore into a TEMP database:"
  echo "    DRY_RUN_DATABASE_URL='postgresql://user:pass@localhost:5432/safealert_restore_test' $0 ${BACKUP}"
  exit 0
fi

# Safety: refuse obvious production hostnames unless ALLOW_PROD_DRY_RUN=1 (still discouraged)
if echo "${TARGET}" | grep -Eqi 'render\.com|amazonaws\.com|neon\.tech' && [ "${ALLOW_PROD_DRY_RUN:-}" != "1" ]; then
  echo "Refusing restore to a cloud host. Use a local temp DB, or set ALLOW_PROD_DRY_RUN=1 knowingly."
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql not found; install postgresql-client."
  exit 1
fi

echo "→ Restoring into DRY_RUN_DATABASE_URL (temp)…"
if [[ "${BACKUP}" == *.gz ]]; then
  gzip -dc "${BACKUP}" | psql --dbname="${TARGET}" --set ON_ERROR_STOP=1 -v ON_ERROR_STOP=1
else
  psql --dbname="${TARGET}" --set ON_ERROR_STOP=1 -v ON_ERROR_STOP=1 -f "${BACKUP}"
fi

echo "→ Spot-check tables"
psql --dbname="${TARGET}" -c "SELECT COUNT(*) AS users FROM users;" || true
psql --dbname="${TARGET}" -c "SELECT COUNT(*) AS incidents FROM incidents;" || true
echo "✅ Dry-run restore finished."
