#!/usr/bin/env bash
# Premier déploiement SafeAlert sur VPS (Ubuntu/Debian)
set -euo pipefail

DEPLOY_PATH="${DEPLOY_PATH:-/opt/safealert}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.neon.yml}"
REPO_URL="${REPO_URL:-}"

echo "=== SafeAlert — déploiement VPS ==="
echo "    Compose : ${COMPOSE_FILE}"

if [ ! -f .env.production ]; then
  echo "Copiez .env.production.example vers .env.production et éditez les secrets."
  cp .env.production.example .env.production
  echo "Éditez .env.production puis relancez ce script."
  exit 1
fi

set -a
source .env.production
set +a

if ! command -v docker &>/dev/null; then
  echo "Docker requis. Installez-le : https://docs.docker.com/engine/install/"
  exit 1
fi

COMPOSE=(docker compose -f "$COMPOSE_FILE" --env-file .env.production)

if [ "$COMPOSE_FILE" = "docker-compose.neon.yml" ]; then
  if [ -z "${DATABASE_URL:-}" ]; then
    echo "DATABASE_URL requis pour docker-compose.neon.yml (Neon)."
    exit 1
  fi
  echo "→ Mode Neon : PostgreSQL externe, Redis + API sur ce VPS"
  echo "→ Pull image GHCR..."
  "${COMPOSE[@]}" pull api 2>/dev/null || true
  echo "→ Démarrage Redis + API..."
  "${COMPOSE[@]}" up -d redis api
else
  echo "→ Pull / build des images..."
  "${COMPOSE[@]}" pull api 2>/dev/null || true
  "${COMPOSE[@]}" build api
  echo "→ Démarrage PostgreSQL + API..."
  "${COMPOSE[@]}" up -d db api
fi

echo "→ Attente readiness API..."
for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${PORT:-3000}/health/ready" >/dev/null; then
    echo "API prête."
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "Timeout — vérifiez les logs : docker compose -f ${COMPOSE_FILE} logs api"
    exit 1
  fi
done

echo "→ Seed initial (profile init)..."
"${COMPOSE[@]}" --profile init run --rm seed || true

if [ -n "${DOMAIN:-}" ] && [ "${DOMAIN}" != "localhost" ]; then
  echo "→ Démarrage proxy Caddy (TLS)..."
  "${COMPOSE[@]}" --profile proxy up -d
fi

echo ""
echo "✅ Déploiement terminé."
echo "   Health : http://127.0.0.1:${PORT:-3000}/health"
if [ -n "${DOMAIN:-}" ] && [ "${DOMAIN}" != "localhost" ]; then
  echo "   Public : https://${DOMAIN}/health"
fi
echo ""
echo "Prochaines étapes :"
echo "  1. Configurer Firebase (FCM) et SMS (Twilio ou Africa's Talking)"
echo "  2. flutter build apk --dart-define=API_BASE_URL=https://${DOMAIN:-votre-api}/api"
