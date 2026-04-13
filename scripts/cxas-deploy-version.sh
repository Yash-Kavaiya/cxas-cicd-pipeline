#!/usr/bin/env bash
# =============================================================================
# cxas-deploy-version.sh
# Associates a CX Agent Studio version with a deployment, making it live.
#
# API Reference:
#   PATCH https://ces.googleapis.com/v1/{deployment.name=.../deployments/*}
#
# A deployment represents an immutable, queryable version of the app.
# Updating the deployment's version field switches live traffic to that version.
#
# Usage:
#   ./cxas-deploy-version.sh \
#     --project-id=MY_PROJECT \
#     --region=us \
#     --app-id=MY_APP \
#     --deployment-id=prod-deployment \
#     --version-name=projects/x/locations/us/apps/y/versions/z
# =============================================================================
set -euo pipefail

PROJECT_ID=""
REGION="us"
APP_ID=""
DEPLOYMENT_ID=""
VERSION_NAME=""

for arg in "$@"; do
  case $arg in
    --project-id=*)     PROJECT_ID="${arg#*=}" ;;
    --region=*)         REGION="${arg#*=}" ;;
    --app-id=*)         APP_ID="${arg#*=}" ;;
    --deployment-id=*)  DEPLOYMENT_ID="${arg#*=}" ;;
    --version-name=*)   VERSION_NAME="${arg#*=}" ;;
    *)                  echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

[[ -z "$PROJECT_ID" || -z "$APP_ID" || -z "$DEPLOYMENT_ID" || -z "$VERSION_NAME" ]] && {
  echo "Usage: $0 --project-id=<id> --region=<r> --app-id=<id> --deployment-id=<id> --version-name=<full-name>"
  exit 1
}

TOKEN=$(gcloud auth print-access-token)
DEPLOYMENT_RESOURCE="projects/${PROJECT_ID}/locations/${REGION}/apps/${APP_ID}/deployments/${DEPLOYMENT_ID}"
API_URL="https://ces.googleapis.com/v1/${DEPLOYMENT_RESOURCE}?updateMask=version"

echo "=============================================="
echo " CX Agent Studio — Deploy Version"
echo "=============================================="
echo " Deployment: ${DEPLOYMENT_RESOURCE}"
echo " Version:    ${VERSION_NAME}"
echo "=============================================="

PAYLOAD=$(cat <<EOF
{
  "name": "${DEPLOYMENT_RESOURCE}",
  "version": "${VERSION_NAME}"
}
EOF
)

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X PATCH "${API_URL}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "SUCCESS: Deployment updated (HTTP ${HTTP_CODE})"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"

  # GitHub Actions output
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "deploy_status=success" >> "$GITHUB_OUTPUT"
    echo "deployment_name=${DEPLOYMENT_RESOURCE}" >> "$GITHUB_OUTPUT"
  fi
else
  echo "ERROR: Deployment update failed (HTTP ${HTTP_CODE})"
  echo "$BODY"
  exit 1
fi
