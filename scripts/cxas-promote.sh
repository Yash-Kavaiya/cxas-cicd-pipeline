#!/usr/bin/env bash
# =============================================================================
# cxas-promote.sh
# Promotes a CX Agent Studio application from one environment to another.
#
# Workflow:
#   1. Create a version in the source environment
#   2. Export the source app to GCS
#   3. (Optional) Modify environment.json for target-specific settings
#   4. Import the exported app into the target environment
#   5. Create a version in the target environment
#   6. Update the target deployment to use the new version
#
# Usage:
#   ./cxas-promote.sh \
#     --src-project=dev-project --src-app=app-dev --src-region=us \
#     --dst-project=prod-project --dst-app=app-prod --dst-region=us \
#     --dst-deployment=prod-deployment \
#     --bucket=my-exports-bucket \
#     --version-label="v1.2.3"
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SRC_PROJECT=""
SRC_APP=""
SRC_REGION="us"
DST_PROJECT=""
DST_APP=""
DST_REGION="us"
DST_DEPLOYMENT=""
BUCKET=""
VERSION_LABEL=""
ENV_JSON_OVERRIDE=""

for arg in "$@"; do
  case $arg in
    --src-project=*)      SRC_PROJECT="${arg#*=}" ;;
    --src-app=*)          SRC_APP="${arg#*=}" ;;
    --src-region=*)       SRC_REGION="${arg#*=}" ;;
    --dst-project=*)      DST_PROJECT="${arg#*=}" ;;
    --dst-app=*)          DST_APP="${arg#*=}" ;;
    --dst-region=*)       DST_REGION="${arg#*=}" ;;
    --dst-deployment=*)   DST_DEPLOYMENT="${arg#*=}" ;;
    --bucket=*)           BUCKET="${arg#*=}" ;;
    --version-label=*)    VERSION_LABEL="${arg#*=}" ;;
    --env-json=*)         ENV_JSON_OVERRIDE="${arg#*=}" ;;
    *)                    echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

[[ -z "$SRC_PROJECT" || -z "$SRC_APP" || -z "$DST_PROJECT" || -z "$DST_APP" || -z "$BUCKET" ]] && {
  echo "Usage: $0 --src-project=P --src-app=A --dst-project=P --dst-app=A --bucket=B [opts]"
  exit 1
}

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
VERSION_LABEL="${VERSION_LABEL:-promote-${TIMESTAMP}}"
EXPORT_URI="gs://${BUCKET}/promotions/${VERSION_LABEL}/export.zip"

echo "============================================================"
echo " CX Agent Studio — Cross-Environment Promotion"
echo "============================================================"
echo " Source:  ${SRC_PROJECT}/${SRC_APP} (${SRC_REGION})"
echo " Target:  ${DST_PROJECT}/${DST_APP} (${DST_REGION})"
echo " Version: ${VERSION_LABEL}"
echo " Export:  ${EXPORT_URI}"
echo "============================================================"

# Step 1: Create version in source
echo ""
echo "=== Step 1/5: Create source version ==="
bash "${SCRIPT_DIR}/cxas-create-version.sh" \
  --project-id="${SRC_PROJECT}" \
  --region="${SRC_REGION}" \
  --app-id="${SRC_APP}" \
  --display-name="${VERSION_LABEL}-src" \
  --description="Pre-promotion snapshot for ${VERSION_LABEL}"

# Step 2: Export source app
echo ""
echo "=== Step 2/5: Export source application ==="
bash "${SCRIPT_DIR}/cxas-export-app.sh" \
  --project-id="${SRC_PROJECT}" \
  --region="${SRC_REGION}" \
  --app-id="${SRC_APP}" \
  --gcs-uri="${EXPORT_URI}"

# Step 3: (Optional) Override environment.json
if [[ -n "$ENV_JSON_OVERRIDE" && -f "$ENV_JSON_OVERRIDE" ]]; then
  echo ""
  echo "=== Step 3/5: Override environment.json ==="
  TMPDIR=$(mktemp -d)
  gsutil cp "${EXPORT_URI}" "${TMPDIR}/export.zip"
  cd "${TMPDIR}"
  unzip -q export.zip -d export_contents/
  cp "${ENV_JSON_OVERRIDE}" export_contents/environment.json
  cd export_contents && zip -qr ../export_modified.zip . && cd ..
  gsutil cp export_modified.zip "${EXPORT_URI}"
  rm -rf "${TMPDIR}"
  echo "  environment.json overridden for target environment."
else
  echo ""
  echo "=== Step 3/5: Skip environment.json override ==="
fi

# Step 4: Import into target
echo ""
echo "=== Step 4/5: Import into target application ==="
bash "${SCRIPT_DIR}/cxas-import-app.sh" \
  --project-id="${DST_PROJECT}" \
  --region="${DST_REGION}" \
  --app-id="${DST_APP}" \
  --gcs-uri="${EXPORT_URI}"

# Step 5: Create version + deploy in target
echo ""
echo "=== Step 5/5: Create target version ==="
bash "${SCRIPT_DIR}/cxas-create-version.sh" \
  --project-id="${DST_PROJECT}" \
  --region="${DST_REGION}" \
  --app-id="${DST_APP}" \
  --display-name="${VERSION_LABEL}" \
  --description="Promoted from ${SRC_PROJECT}/${SRC_APP}"

if [[ -n "$DST_DEPLOYMENT" ]]; then
  echo ""
  echo "=== Bonus: Update target deployment ==="
  # Get the latest version name
  TOKEN=$(gcloud auth print-access-token)
  DST_PARENT="projects/${DST_PROJECT}/locations/${DST_REGION}/apps/${DST_APP}"
  VERSIONS_RESP=$(curl -s \
    -X GET "https://ces.googleapis.com/v1/${DST_PARENT}/versions?pageSize=1" \
    -H "Authorization: Bearer ${TOKEN}")

  LATEST_VERSION=$(echo "$VERSIONS_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
versions = data.get('versions', [])
print(versions[0]['name'] if versions else '')
" 2>/dev/null || true)

  if [[ -n "$LATEST_VERSION" ]]; then
    bash "${SCRIPT_DIR}/cxas-deploy-version.sh" \
      --project-id="${DST_PROJECT}" \
      --region="${DST_REGION}" \
      --app-id="${DST_APP}" \
      --deployment-id="${DST_DEPLOYMENT}" \
      --version-name="${LATEST_VERSION}"
  else
    echo "WARNING: Could not determine latest version for deployment update."
  fi
fi

echo ""
echo "============================================================"
echo " Promotion Complete!"
echo " ${SRC_PROJECT}/${SRC_APP} → ${DST_PROJECT}/${DST_APP}"
echo "============================================================"
