#!/usr/bin/env bash
# Pre-migrate Postgres dump for SafeAlert (Render Postgres / any Postgres URL).
# Usage (CI or local):
#   DATABASE_URL='postgresql://...' ./scripts/db-backup.sh
#   PROD_DATABASE_URL='...' ./scripts/db-backup.sh [output.sql.gz]
#
# Prefers PROD_DATABASE_URL, then DATABASE_URL_DIRECT, then DATABASE_URL.
# From GitHub Actions: set PROD_DATABASE_URL to the Render Postgres
# External Database URL (not Internal — runners are outside Render's private network).
set -euo pipefail

OUT="${1:-}"
URL="${PROD_DATABASE_URL:-${DATABASE_URL_DIRECT:-${DATABASE_URL:-}}}"

if [ -z "${URL}" ]; then
  echo "::warning::No PROD_DATABASE_URL / DATABASE_URL_DIRECT / DATABASE_URL — skipping DB backup."
  exit 0
fi

if ! command -v pg_dump >/dev/null 2>&1; then
  echo "pg_dump not found; install postgresql-client."
  exit 1
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
if [ -z "${OUT}" ]; then
  mkdir -p backups
  OUT="backups/safealert-${STAMP}.sql.gz"
fi

mkdir -p "$(dirname "${OUT}")"

echo "→ pg_dump → ${OUT}"
# Render Postgres External URL usually includes sslmode=require.
pg_dump \
  --dbname="${URL}" \
  --no-owner \
  --no-acl \
  --clean \
  --if-exists \
  --format=plain \
  | gzip -c > "${OUT}"

SIZE="$(wc -c < "${OUT}" | tr -d ' ')"
if [ "${SIZE}" -lt 100 ]; then
  echo "Backup suspiciously small (${SIZE} bytes) — failing."
  exit 1
fi

echo "✓ Backup OK (${SIZE} bytes): ${OUT}"
echo "BACKUP_FILE=${OUT}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "file=${OUT}" >> "${GITHUB_OUTPUT}"
fi
