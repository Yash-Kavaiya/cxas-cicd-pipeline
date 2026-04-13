# CX Agent Studio — CI/CD Pipeline with Terraform & GitHub Actions

> **Production-grade CI/CD pipeline for Google Cloud CX Agent Studio**
> Version management, export/import, cross-environment promotion, and automated deployments.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                            │
│  terraform/  ─── Infrastructure as Code (APIs, buckets, IAM)        │
│  scripts/    ─── CES REST API automation scripts                    │
│  .github/    ─── CI/CD workflow definitions                         │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────────┐
        │                  │                      │
        ▼                  ▼                      ▼
┌──────────────┐  ┌──────────────────┐  ┌──────────────────┐
│   DEV        │  │   STAGING        │  │   PRODUCTION     │
│  GCP Project │  │   GCP Project    │  │   GCP Project    │
│              │  │                  │  │                  │
│ ┌──────────┐ │  │ ┌──────────────┐ │  │ ┌──────────────┐ │
│ │ CX Agent │ │  │ │  CX Agent    │ │  │ │  CX Agent    │ │
│ │ Studio   │─┼──┤▶│  Studio      │─┼──┤▶│  Studio      │ │
│ │ App      │ │  │ │  App         │ │  │ │  App         │ │
│ └──────────┘ │  │ └──────────────┘ │  │ └──────────────┘ │
│ ┌──────────┐ │  │ ┌──────────────┐ │  │ ┌──────────────┐ │
│ │ GCS      │ │  │ │ GCS          │ │  │ │ GCS          │ │
│ │ Exports  │ │  │ │ Exports      │ │  │ │ Exports      │ │
│ └──────────┘ │  │ └──────────────┘ │  │ └──────────────┘ │
└──────────────┘  └──────────────────┘  └──────────────────┘
       │                   │                      │
       └───────────────────┴──────────────────────┘
                           │
                    CES REST API v1
              ces.googleapis.com/v1
```

## CES REST API Endpoints Used

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Create Version | `POST` | `/v1/{parent}/versions` |
| List Versions | `GET` | `/v1/{parent}/versions` |
| Restore Version | `POST` | `/v1/{name}:restore` |
| Export App | `POST` | `/v1/{name}:exportApp` |
| Import App | `POST` | `/v1/{name}:importApp` |
| List Deployments | `GET` | `/v1/{parent}/deployments` |
| Update Deployment | `PATCH` | `/v1/{deployment.name}` |

Where `parent = projects/{P}/locations/{R}/apps/{A}`

## Project Structure

```
cxas-cicd/
├── terraform/
│   ├── main.tf                          # Core infra: APIs, GCS, IAM, SA
│   └── environments/
│       ├── dev/
│       │   ├── terraform.tfvars         # Dev-specific variables
│       │   └── backend.hcl             # Dev state backend
│       ├── staging/
│       │   ├── terraform.tfvars
│       │   └── backend.hcl
│       └── prod/
│           ├── terraform.tfvars
│           └── backend.hcl
├── scripts/
│   ├── cxas-create-version.sh           # Create immutable version snapshot
│   ├── cxas-list-versions.sh            # List all versions
│   ├── cxas-restore-version.sh          # Restore (rollback) to a version
│   ├── cxas-export-app.sh              # Export agent app to GCS
│   ├── cxas-import-app.sh              # Import agent app from GCS
│   ├── cxas-deploy-version.sh          # Update deployment with version
│   ├── cxas-list-deployments.sh        # List all deployments
│   └── cxas-promote.sh                 # Cross-env promotion orchestrator
├── .github/workflows/
│   ├── ci.yml                           # CI: validate + version + export
│   ├── cd.yml                           # CD: promote + deploy
│   └── rollback.yml                     # Emergency rollback
├── docs/
│   └── environment-json-guide.md       # Guide for environment.json
└── README.md
```

## Quick Start

### Prerequisites

1. **GCP Projects** configured for each environment (dev, staging, prod)
2. **CX Agent Studio API** (`ces.googleapis.com`) enabled in each project
3. **gcloud CLI** installed and authenticated
4. **Terraform** >= 1.5.0 installed
5. **GitHub repository** with Actions enabled

### Step 1: Configure Terraform Variables

Edit each environment's `terraform.tfvars`:

```hcl
# terraform/environments/dev/terraform.tfvars
project_id  = "my-cxas-dev-project"
region      = "us"
app_id      = "abc123def456"     # Your CX Agent Studio app ID
environment = "dev"
deployment_id = "dev-deployment"  # Your deployment channel ID
```

### Step 2: Initialize & Apply Terraform

```bash
cd terraform

# Dev environment
terraform init -backend-config=environments/dev/backend.hcl
terraform apply -var-file=environments/dev/terraform.tfvars
```

This creates:
- Enables `ces.googleapis.com`, IAM, Storage, Cloud Build APIs
- Creates a GCS bucket for agent exports (with versioning)
- Creates a service account with CES + Storage permissions

### Step 3: Configure GitHub Secrets & Variables

**Repository Secrets:**

| Secret | Description |
|--------|-------------|
| `WIF_PROVIDER` | Workload Identity Federation provider |
| `GCP_SA_EMAIL` | Service account email for CI/CD |

**Environment Variables (per GitHub environment):**

| Variable | Dev | Staging | Prod |
|----------|-----|---------|------|
| `GCP_PROJECT_ID` | `my-dev-proj` | `my-staging-proj` | `my-prod-proj` |
| `CXAS_APP_ID` | `app-dev-id` | `app-stg-id` | `app-prod-id` |
| `CXAS_REGION` | `us` | `us` | `us` |
| `DEV_PROJECT_ID` | `my-dev-proj` | `my-dev-proj` | — |
| `STAGING_PROJECT_ID` | — | `my-staging-proj` | `my-staging-proj` |
| `PROD_PROJECT_ID` | — | — | `my-prod-proj` |
| `EXPORTS_BUCKET` | `my-exports` | `my-exports` | `my-exports` |

### Step 4: Run the Pipeline

**Automatic (CI):** Push to `main` triggers version creation + export in dev.

**Manual (CD):** Use the "CD — CXAS Promote & Deploy" workflow dispatch:
1. Go to Actions → "CD — CXAS Promote & Deploy"
2. Select target environment (staging or prod)
3. Optionally provide a version label
4. Click "Run workflow"

## Workflows

### CI Pipeline (Automatic)

```
Push to main
    │
    ▼
┌─────────────────────────┐
│ Terraform Validate      │──── All 3 environments validated
│ (dev, staging, prod)    │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Terraform Apply (dev)   │──── APIs, buckets, IAM
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Create Version          │──── Immutable snapshot in dev
│ (CES REST API)          │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Export to GCS           │──── Backup + Git SHA tagged
│ (CES REST API)          │
└─────────────────────────┘
```

### CD Pipeline (Manual Dispatch)

```
Manual Trigger (staging or prod)
    │
    ▼
┌─────────────────────────┐
│ 1. Create src version   │──── Snapshot source app
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ 2. Export src → GCS     │──── Archive to shared bucket
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ 3. (Optional) Override  │──── Swap environment.json
│    environment.json     │     for target-specific config
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ 4. Import → target      │──── Restore into target app
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ 5. Create target ver    │──── Immutable snapshot
│ 6. Update deployment    │──── Switch live traffic
└─────────────────────────┘
```

### Rollback Pipeline (Emergency)

Two methods:
1. **Restore Version** — Reverts the app to a specific version ID
2. **Import Backup** — Imports from a GCS export archive

## Scripts Reference

All scripts support `--help` and write to `$GITHUB_OUTPUT` when in CI.

```bash
# Create a version
./scripts/cxas-create-version.sh \
  --project-id=my-project --region=us --app-id=my-app \
  --display-name="v1.2.3"

# List versions
./scripts/cxas-list-versions.sh \
  --project-id=my-project --region=us --app-id=my-app

# Export to GCS
./scripts/cxas-export-app.sh \
  --project-id=my-project --region=us --app-id=my-app \
  --gcs-uri=gs://my-bucket/exports/v1.2.3.zip

# Import from GCS
./scripts/cxas-import-app.sh \
  --project-id=my-project --region=us --app-id=my-app \
  --gcs-uri=gs://my-bucket/exports/v1.2.3.zip

# Deploy a version to a deployment channel
./scripts/cxas-deploy-version.sh \
  --project-id=my-project --region=us --app-id=my-app \
  --deployment-id=prod-deployment \
  --version-name=projects/x/locations/us/apps/y/versions/z

# Full cross-environment promotion
./scripts/cxas-promote.sh \
  --src-project=dev-proj --src-app=app-dev --src-region=us \
  --dst-project=prod-proj --dst-app=app-prod --dst-region=us \
  --dst-deployment=prod-deployment \
  --bucket=my-exports --version-label="v1.2.3"

# Restore (rollback) to a specific version
./scripts/cxas-restore-version.sh \
  --project-id=my-project --region=us --app-id=my-app \
  --version-id=VERSION_ID
```

## Environment.json

When exporting a CX Agent Studio app, an `environment.json` file is included
in the root of the archive. This file centralizes environment-specific settings:

- Cloud Storage bucket URIs
- Service endpoints
- Data store URIs

To promote across environments, you can override this file with
target-specific values using the `--env-json` flag in `cxas-promote.sh`.

## Why Terraform + REST API (Not Native TF Resources)?

CX Agent Studio is a newer Google Cloud product (evolved from Dialogflow CX).
As of April 2026, there are **no native Terraform resources** for CX Agent
Studio (`ces.googleapis.com`). The Terraform Google provider supports legacy
Dialogflow CX resources (`google_dialogflow_cx_agent`, etc.) but not the
CES v1 API.

Our approach:
- **Terraform** manages the surrounding infrastructure (APIs, GCS, IAM, SA)
- **Shell scripts** call the CES REST API for version/deployment/export/import
- **GitHub Actions** orchestrates the full CI/CD pipeline

When native Terraform resources become available, the scripts can be replaced
with `google_ces_app_version`, `google_ces_deployment`, etc.

## IAM Roles Required

| Role | Purpose |
|------|---------|
| `roles/dialogflow.admin` | CX Agent Studio full access (versions, deployments, export/import) |
| `roles/storage.admin` | Read/write GCS export buckets |
| `roles/iam.serviceAccountTokenCreator` | Generate access tokens for SA |

## License

Apache 2.0
