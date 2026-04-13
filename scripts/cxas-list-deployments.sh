#!/usr/bin/env bash
# =============================================================================
# cxas-list-deployments.sh
# Lists all deployments for a CX Agent Studio application.
#
# API Reference:
#   GET https://ces.googleapis.com/v1/{parent}/deployments
#
# Usage:
#   ./cxas-list-deployments.sh --project-id=MY_PROJECT --region=us --app-id=MY_APP
# =============================================================================
set -euo pipefail

PROJECT_ID=""
REGION="us"
APP_ID=""

for arg in "$@"; do
  case $arg in
    --project-id=*)   PROJECT_ID="${arg#*=}" ;;
    --region=*)       REGION="${arg#*=}" ;;
    --app-id=*)       APP_ID="${arg#*=}" ;;
    *)                echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

[[ -z "$PROJECT_ID" || -z "$APP_ID" ]] && {
  echo "Usage: $0 --project-id=<id> --region=<r> --app-id=<id>"
  exit 1
}

TOKEN=$(gcloud auth print-access-token)
APP_PARENT="projects/${PROJECT_ID}/locations/${REGION}/apps/${APP_ID}"
API_URL="https://ces.googleapis.com/v1/${APP_PARENT}/deployments"

echo "=============================================="
echo " CX Agent Studio — List Deployments"
echo "=============================================="
echo " App: ${APP_PARENT}"
echo "=============================================="

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X GET "${API_URL}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"

  echo ""
  echo "--- Deployment Summary ---"
  echo "$BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
deployments = data.get('deployments', [])
if not deployments:
    print('  No deployments found.')
else:
    print(f'  Total: {len(deployments)} deployment(s)')
    for d in deployments:
        name = d.get('name', 'N/A').split('/')[-1]
        version = d.get('version', 'N/A')
        state = d.get('state', 'N/A')
        print(f'  [{name}] version={version} state={state}')
" 2>/dev/null || true
else
  echo "ERROR: Failed to list deployments (HTTP ${HTTP_CODE})"
  echo "$BODY"
  exit 1
fi
