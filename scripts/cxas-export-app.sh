#!/usr/bin/env bash
# =============================================================================
# cxas-export-app.sh
# Exports a CX Agent Studio application (full agent definition + environment.json)
# to a GCS bucket or downloads locally.
#
# API Reference:
#   POST https://ces.googleapis.com/v1/{name=projects/*/locations/*/apps/*}:exportApp
#
# The export includes an environment.json for environment-specific settings,
# improving portability across dev/staging/prod.
#
# Usage:
#   ./cxas-export-app.sh \
#     --project-id=MY_PROJECT \
#     --region=us \
#     --app-id=MY_APP \
#     --gcs-uri=gs://my-bucket/exports/app-v1.2.3.zip
# =============================================================================
set -euo pipefail

PROJECT_ID=""
REGION="us"
APP_ID=""
GCS_URI=""
LOCAL_PATH=""

for arg in "$@"; do
  case $arg in
    --project-id=*)   PROJECT_ID="${arg#*=}" ;;
    --region=*)       REGION="${arg#*=}" ;;
    --app-id=*)       APP_ID="${arg#*=}" ;;
    --gcs-uri=*)      GCS_URI="${arg#*=}" ;;
    --local-path=*)   LOCAL_PATH="${arg#*=}" ;;
    *)                echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

[[ -z "$PROJECT_ID" || -z "$APP_ID" ]] && {
  echo "Usage: $0 --project-id=<id> --region=<r> --app-id=<id> [--gcs-uri=<uri>] [--local-path=<path>]"
  exit 1
}

TOKEN=$(gcloud auth print-access-token)
APP_NAME="projects/${PROJECT_ID}/locations/${REGION}/apps/${APP_ID}"
API_URL="https://ces.googleapis.com/v1/${APP_NAME}:exportApp"

echo "=============================================="
echo " CX Agent Studio — Export Application"
echo "=============================================="
echo " App:     ${APP_NAME}"
echo " GCS URI: ${GCS_URI:-'(download mode)'}"
echo "=============================================="

# Build payload based on export target
if [[ -n "$GCS_URI" ]]; then
  PAYLOAD=$(cat <<EOF
{
  "agentUri": "${GCS_URI}"
}
EOF
)
else
  # Empty payload = download mode (returns base64 content in response)
  PAYLOAD="{}"
fi

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${API_URL}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "SUCCESS: Export initiated (HTTP ${HTTP_CODE})"

  # Check if this is a Long Running Operation (LRO)
  OP_NAME=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || true)

  if [[ -n "$OP_NAME" && "$OP_NAME" == *"operations"* ]]; then
    echo "Long-running operation: ${OP_NAME}"
    echo "Polling for completion..."

    for i in $(seq 1 30); do
      sleep 5
      OP_RESP=$(curl -s \
        -X GET "https://ces.googleapis.com/v1/${OP_NAME}" \
        -H "Authorization: Bearer ${TOKEN}")

      DONE=$(echo "$OP_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('done', False))" 2>/dev/null || echo "False")

      if [[ "$DONE" == "True" ]]; then
        echo "Export completed!"
        echo "$OP_RESP" | python3 -m json.tool 2>/dev/null || echo "$OP_RESP"
        break
      fi
      echo "  ...still running (attempt ${i}/30)"
    done

    if [[ "$DONE" != "True" ]]; then
      echo "WARNING: Operation did not complete within timeout. Check manually:"
      echo "  Operation: ${OP_NAME}"
    fi
  else
    # Immediate response (download mode)
    if [[ -n "$LOCAL_PATH" ]]; then
      echo "$BODY" | python3 -c "
import sys, json, base64
data = json.load(sys.stdin)
content = data.get('agentContent', '')
if content:
    with open('${LOCAL_PATH}', 'wb') as f:
        f.write(base64.b64decode(content))
    print(f'Saved to: ${LOCAL_PATH}')
else:
    print('No agentContent in response')
" 2>/dev/null || echo "$BODY"
    else
      echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    fi
  fi

  # GitHub Actions output
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "export_gcs_uri=${GCS_URI}" >> "$GITHUB_OUTPUT"
    echo "export_status=success" >> "$GITHUB_OUTPUT"
  fi
else
  echo "ERROR: Export failed (HTTP ${HTTP_CODE})"
  echo "$BODY"
  exit 1
fi
