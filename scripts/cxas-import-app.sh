#!/usr/bin/env bash
# =============================================================================
# cxas-import-app.sh
# Imports (restores) a CX Agent Studio application from a GCS export archive.
#
# API Reference:
#   POST https://ces.googleapis.com/v1/{name=projects/*/locations/*/apps/*}:importApp
#
# The import uses environment.json in the archive root for environment-specific
# settings (GCS buckets, service endpoints, data store URIs), enabling
# portable dev → staging → prod promotion.
#
# Usage:
#   ./cxas-import-app.sh \
#     --project-id=MY_PROJECT \
#     --region=us \
#     --app-id=MY_TARGET_APP \
#     --gcs-uri=gs://my-bucket/exports/app-v1.2.3.zip
# =============================================================================
set -euo pipefail

PROJECT_ID=""
REGION="us"
APP_ID=""
GCS_URI=""
LOCAL_FILE=""

for arg in "$@"; do
  case $arg in
    --project-id=*)   PROJECT_ID="${arg#*=}" ;;
    --region=*)       REGION="${arg#*=}" ;;
    --app-id=*)       APP_ID="${arg#*=}" ;;
    --gcs-uri=*)      GCS_URI="${arg#*=}" ;;
    --local-file=*)   LOCAL_FILE="${arg#*=}" ;;
    *)                echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

[[ -z "$PROJECT_ID" || -z "$APP_ID" ]] && {
  echo "Usage: $0 --project-id=<id> --region=<r> --app-id=<id> --gcs-uri=<uri>"
  exit 1
}

TOKEN=$(gcloud auth print-access-token)
APP_NAME="projects/${PROJECT_ID}/locations/${REGION}/apps/${APP_ID}"
API_URL="https://ces.googleapis.com/v1/${APP_NAME}:importApp"

echo "=============================================="
echo " CX Agent Studio — Import Application"
echo "=============================================="
echo " Target App: ${APP_NAME}"
echo " Source:     ${GCS_URI:-$LOCAL_FILE}"
echo "=============================================="

# Build payload
if [[ -n "$GCS_URI" ]]; then
  PAYLOAD=$(cat <<EOF
{
  "agentUri": "${GCS_URI}"
}
EOF
)
elif [[ -n "$LOCAL_FILE" && -f "$LOCAL_FILE" ]]; then
  AGENT_CONTENT=$(base64 -w 0 "$LOCAL_FILE")
  PAYLOAD=$(cat <<EOF
{
  "agentContent": "${AGENT_CONTENT}"
}
EOF
)
else
  echo "ERROR: Provide --gcs-uri or --local-file"
  exit 1
fi

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${API_URL}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "SUCCESS: Import initiated (HTTP ${HTTP_CODE})"

  # Poll LRO
  OP_NAME=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || true)

  if [[ -n "$OP_NAME" && "$OP_NAME" == *"operations"* ]]; then
    echo "Long-running operation: ${OP_NAME}"
    echo "Polling for completion..."

    for i in $(seq 1 60); do
      sleep 5
      OP_RESP=$(curl -s \
        -X GET "https://ces.googleapis.com/v1/${OP_NAME}" \
        -H "Authorization: Bearer ${TOKEN}")

      DONE=$(echo "$OP_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('done', False))" 2>/dev/null || echo "False")

      if [[ "$DONE" == "True" ]]; then
        ERROR=$(echo "$OP_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('message',''))" 2>/dev/null || true)
        if [[ -n "$ERROR" ]]; then
          echo "ERROR: Import completed with error: ${ERROR}"
          exit 1
        fi
        echo "Import completed successfully!"
        break
      fi
      echo "  ...still running (attempt ${i}/60)"
    done

    if [[ "$DONE" != "True" ]]; then
      echo "WARNING: Operation did not complete within timeout (5 min)."
      echo "  Operation: ${OP_NAME}"
      exit 1
    fi
  else
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
  fi

  # GitHub Actions output
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "import_status=success" >> "$GITHUB_OUTPUT"
  fi
else
  echo "ERROR: Import failed (HTTP ${HTTP_CODE})"
  echo "$BODY"
  exit 1
fi
