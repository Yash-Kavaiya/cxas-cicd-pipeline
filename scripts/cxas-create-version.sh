#!/usr/bin/env bash
# =============================================================================
# cxas-create-version.sh
# Creates an immutable version snapshot of a CX Agent Studio application
# using the CES v1 REST API.
#
# API Reference:
#   POST https://ces.googleapis.com/v1/{parent=projects/*/locations/*/apps/*}/versions
#
# Usage:
#   ./cxas-create-version.sh \
#     --project-id=MY_PROJECT \
#     --region=us \
#     --app-id=MY_APP_ID \
#     --display-name="v1.2.3-rc1"
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults & argument parsing
# ---------------------------------------------------------------------------
PROJECT_ID=""
REGION="us"
APP_ID=""
DISPLAY_NAME=""
DESCRIPTION=""

usage() {
  echo "Usage: $0 --project-id=<id> --region=<region> --app-id=<id> [--display-name=<name>] [--description=<desc>]"
  exit 1
}

for arg in "$@"; do
  case $arg in
    --project-id=*)   PROJECT_ID="${arg#*=}" ;;
    --region=*)       REGION="${arg#*=}" ;;
    --app-id=*)       APP_ID="${arg#*=}" ;;
    --display-name=*) DISPLAY_NAME="${arg#*=}" ;;
    --description=*)  DESCRIPTION="${arg#*=}" ;;
    --help|-h)        usage ;;
    *)                echo "Unknown arg: $arg"; usage ;;
  esac
done

[[ -z "$PROJECT_ID" || -z "$APP_ID" ]] && usage

# Auto-generate display name if not provided
if [[ -z "$DISPLAY_NAME" ]]; then
  DISPLAY_NAME="v-$(date +%Y%m%d-%H%M%S)"
fi

if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="CI/CD auto-generated version: ${DISPLAY_NAME}"
fi

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: Unable to obtain access token. Run 'gcloud auth login' or configure ADC."
  exit 1
fi

# ---------------------------------------------------------------------------
# Create Version
# ---------------------------------------------------------------------------
APP_PARENT="projects/${PROJECT_ID}/locations/${REGION}/apps/${APP_ID}"
API_URL="https://ces.googleapis.com/v1/${APP_PARENT}/versions"

echo "=============================================="
echo " CX Agent Studio — Create Version"
echo "=============================================="
echo " App:          ${APP_PARENT}"
echo " Display Name: ${DISPLAY_NAME}"
echo " Description:  ${DESCRIPTION}"
echo "=============================================="

PAYLOAD=$(cat <<EOF
{
  "displayName": "${DISPLAY_NAME}",
  "description": "${DESCRIPTION}"
}
EOF
)

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${API_URL}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "SUCCESS: Version created (HTTP ${HTTP_CODE})"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"

  # Extract version name for downstream use
  VERSION_NAME=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || true)
  if [[ -n "$VERSION_NAME" ]]; then
    echo ""
    echo "VERSION_NAME=${VERSION_NAME}"
    # Write to GitHub Actions output if running in CI
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "version_name=${VERSION_NAME}" >> "$GITHUB_OUTPUT"
      echo "version_display_name=${DISPLAY_NAME}" >> "$GITHUB_OUTPUT"
    fi
  fi
else
  echo "ERROR: Failed to create version (HTTP ${HTTP_CODE})"
  echo "$BODY"
  exit 1
fi
