#!/usr/bin/env bash
# Ensure Render Static Site SPA fallback: /* → /index.html (rewrite).
# _redirects is NOT applied by Render CDN; Dashboard / Blueprint / this API is required.
set -euo pipefail

if [ -z "${RENDER_API_KEY:-}" ] || [ -z "${SERVICE_ID:-}" ]; then
  echo "RENDER_API_KEY et SERVICE_ID requis"
  exit 1
fi

echo "Liste des routes actuelles (safealert-admin)…"
curl -fsS \
  -H "Authorization: Bearer ${RENDER_API_KEY}" \
  -H "Accept: application/json" \
  "https://api.render.com/v1/services/${SERVICE_ID}/routes" \
  | jq . || true

echo "Application rewrite SPA /* → /index.html…"
curl -fsS -X PUT \
  -H "Authorization: Bearer ${RENDER_API_KEY}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '[{"type":"rewrite","source":"/*","destination":"/index.html"}]' \
  "https://api.render.com/v1/services/${SERVICE_ID}/routes" \
  | jq .

echo "Routes SPA OK"
