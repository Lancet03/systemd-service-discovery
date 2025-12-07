#!/usr/bin/env bash
set -e

DISCOVERY_URL="${DISCOVERY_URL:-http://127.0.0.1:8080}"
SERVICE_ID="${SERVICE_ID:-worker_1}"

echo "[heartbeat] sending heartbeat to ${DISCOVERY_URL} for id=${SERVICE_ID}"

curl -sS -X POST "${DISCOVERY_URL}/heartbeat" \
  -H 'Content-Type: application/json' \
  -d "{
    \"id\": \"${SERVICE_ID}\"
  }" || echo "[heartbeat] failed"
