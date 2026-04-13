# Environment.json Guide — CX Agent Studio

## Overview

When you export a CX Agent Studio application, the download archive includes
an `environment.json` file at the root. This file centralizes environment-specific
settings that differ between dev, staging, and production.

## What It Contains

```json
{
  "storageSettings": {
    "audioRecordingBucket": "gs://my-project-dev-audio",
    "knowledgeBaseBucket": "gs://my-project-dev-kb"
  },
  "serviceEndpoints": {
    "orderServiceUrl": "https://dev.orders.example.com",
    "crmApiUrl": "https://dev.crm.example.com"
  },
  "dataStoreUris": {
    "faqDataStore": "projects/dev-proj/locations/us/collections/default/dataStores/faq-dev"
  }
}
```

## Why It Matters for CI/CD

When promoting from dev → staging → prod, you need to swap out
environment-specific values:

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| Audio bucket | `gs://dev-audio` | `gs://stg-audio` | `gs://prod-audio` |
| Order API | `dev.orders.com` | `stg.orders.com` | `orders.com` |
| Data store | `...dataStores/faq-dev` | `...dataStores/faq-stg` | `...dataStores/faq-prod` |

## Using with the Promote Script

Create environment-specific JSON overrides:

```bash
# environments/staging/environment.json
# environments/prod/environment.json
```

Then pass to the promote script:

```bash
./scripts/cxas-promote.sh \
  --src-project=dev-proj --src-app=app-dev \
  --dst-project=prod-proj --dst-app=app-prod \
  --bucket=exports-bucket \
  --env-json=environments/prod/environment.json
```

The promote script will:
1. Export the source app to GCS
2. Download the archive
3. Replace `environment.json` with your override
4. Re-upload the modified archive
5. Import into the target app

## Benefits

- **Improved Portability**: One file to change between environments
- **Centralized Configuration**: All external dependencies in one place
- **Reduced Errors**: No manual editing across multiple resource files
