#!/usr/bin/env bash
set -e

DISCOVERY_URL="${DISCOVERY_URL:-http://127.0.0.1:8080}"
SERVICE_ID="${SERVICE_ID:-worker_1}"
SERVICE_DESCRIPTION="${SERVICE_DESCRIPTION:-Demo worker}"
SERVICE_PORT="${SERVICE_PORT:-8080}"

# IP контейнера (первый в списке)
SERVICE_IP=$(hostname -i | awk '{print $1}')

curl -sS -X POST "${DISCOVERY_URL}/register" \
  -H 'Content-Type: application/json' \
  -d "{
    \"id\": \"${SERVICE_ID}\",
    \"ip\": \"${SERVICE_IP}\",
    \"description\": \"${SERVICE_DESCRIPTION}\",
    \"port\": ${SERVICE_PORT},
    \"health_path\": \"/health\"
  }" || echo "[register] failed"
