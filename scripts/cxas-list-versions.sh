#!/usr/bin/env bash
# =============================================================================
# cxas-list-versions.sh
# Lists all versions of a CX Agent Studio application.
#
# API Reference:
#   GET https://ces.googleapis.com/v1/{parent}/versions
#
# Usage:
#   ./cxas-list-versions.sh --project-id=MY_PROJECT --region=us --app-id=MY_APP
# =============================================================================
set -euo pipefail

PROJECT_ID=""
REGION="us"
APP_ID=""
PAGE_SIZE=20

for arg in "$@"; do
  case $arg in
    --project-id=*)   PROJECT_ID="${arg#*=}" ;;
    --region=*)       REGION="${arg#*=}" ;;
    --app-id=*)       APP_ID="${arg#*=}" ;;
    --page-size=*)    PAGE_SIZE="${arg#*=}" ;;
    *)                echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

[[ -z "$PROJECT_ID" || -z "$APP_ID" ]] && { echo "Usage: $0 --project-id=<id> --region=<r> --app-id=<id>"; exit 1; }

TOKEN=$(gcloud auth print-access-token)
APP_PARENT="projects/${PROJECT_ID}/locations/${REGION}/apps/${APP_ID}"
API_URL="https://ces.googleapis.com/v1/${APP_PARENT}/versions?pageSize=${PAGE_SIZE}"

echo "=============================================="
echo " CX Agent Studio — List Versions"
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

  # Summary table
  echo ""
  echo "--- Version Summary ---"
  echo "$BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
versions = data.get('versions', [])
if not versions:
    print('  No versions found.')
else:
    print(f'  Total: {len(versions)} version(s)')
    for v in versions:
        name = v.get('name', 'N/A').split('/')[-1]
        display = v.get('displayName', 'N/A')
        create_time = v.get('createTime', 'N/A')
        print(f'  [{name}] {display} — created {create_time}')
" 2>/dev/null || true
else
  echo "ERROR: Failed to list versions (HTTP ${HTTP_CODE})"
  echo "$BODY"
  exit 1
fi
