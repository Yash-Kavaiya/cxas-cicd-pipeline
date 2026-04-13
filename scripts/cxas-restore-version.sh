#!/usr/bin/env bash
# =============================================================================
# cxas-restore-version.sh
# Restores a CX Agent Studio application to a previously saved version.
#
# When restoring, if there are unsaved changes since the last version,
# the system automatically creates a system version (authored by
# system@google.com) to preserve unsaved work before restoring.
#
# API Reference:
#   POST https://ces.googleapis.com/v1/{name=.../versions/*}:restore
#
# Usage:
#   ./cxas-restore-version.sh \
#     --project-id=MY_PROJECT \
#     --region=us \
#     --app-id=MY_APP \
#     --version-id=VERSION_ID
# =============================================================================
set -euo pipefail

PROJECT_ID=""
REGION="us"
APP_ID=""
VERSION_ID=""

for arg in "$@"; do
  case $arg in
    --project-id=*)   PROJECT_ID="${arg#*=}" ;;
    --region=*)       REGION="${arg#*=}" ;;
    --app-id=*)       APP_ID="${arg#*=}" ;;
    --version-id=*)   VERSION_ID="${arg#*=}" ;;
    *)                echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

[[ -z "$PROJECT_ID" || -z "$APP_ID" || -z "$VERSION_ID" ]] && {
  echo "Usage: $0 --project-id=<id> --region=<r> --app-id=<id> --version-id=<id>"
  exit 1
}

TOKEN=$(gcloud auth print-access-token)
VERSION_RESOURCE="projects/${PROJECT_ID}/locations/${REGION}/apps/${APP_ID}/versions/${VERSION_ID}"
API_URL="https://ces.googleapis.com/v1/${VERSION_RESOURCE}:restore"

echo "=============================================="
echo " CX Agent Studio — Restore Version"
echo "=============================================="
echo " Version: ${VERSION_RESOURCE}"
echo "=============================================="
echo ""
echo "WARNING: This will restore the application to this version."
echo "         Any unsaved changes will be auto-saved as a system version."
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${API_URL}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "SUCCESS: Version restored (HTTP ${HTTP_CODE})"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "restore_status=success" >> "$GITHUB_OUTPUT"
    echo "restored_version=${VERSION_RESOURCE}" >> "$GITHUB_OUTPUT"
  fi
else
  echo "ERROR: Restore failed (HTTP ${HTTP_CODE})"
  echo "$BODY"
  exit 1
fi
