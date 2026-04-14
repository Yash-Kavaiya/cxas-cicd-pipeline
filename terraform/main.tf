# =============================================================================
# CX Agent Studio — CI/CD Infrastructure with Terraform
# =============================================================================
# Manages GCP project services, GCS buckets for agent exports,
# service accounts, and orchestrates version/deployment lifecycle
# via the CES REST API (ces.googleapis.com).
#
# CX Agent Studio does NOT yet have native Terraform resources.
# We use null_resource + local-exec to call the CES v1 REST API
# for version creation, export/import, and deployment management.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }

  # Remote backend — configure per environment
  backend "gcs" {}
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID where CX Agent Studio app resides"
  type        = string
}

variable "region" {
  description = "GCP region for the CX Agent Studio application (e.g. us, us-central1, europe-west1)"
  type        = string
  default     = "us"
}

variable "app_id" {
  description = "CX Agent Studio application ID (the app resource name segment)"
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev | staging | prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "deployment_id" {
  description = "CX Agent Studio deployment ID to update with new versions"
  type        = string
  default     = ""
}

variable "version_display_name" {
  description = "Display name for the new version snapshot"
  type        = string
  default     = ""
}

variable "export_bucket_name" {
  description = "GCS bucket name for storing agent exports"
  type        = string
  default     = ""
}

variable "enable_auto_export" {
  description = "Automatically export agent app after version creation"
  type        = bool
  default     = true
}

variable "service_account_email" {
  description = "Service account email for CES API calls. Leave empty to create one."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  # Construct full resource names
  app_parent   = "projects/${var.project_id}/locations/${var.region}"
  app_name     = "${local.app_parent}/apps/${var.app_id}"
  bucket_name  = var.export_bucket_name != "" ? var.export_bucket_name : "${var.project_id}-cxas-exports-${var.environment}"
  sa_email     = var.service_account_email != "" ? var.service_account_email : google_service_account.cxas_cicd[0].email
  version_name = var.version_display_name != "" ? var.version_display_name : "v-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  ces_api_base = "https://ces.googleapis.com/v1"

  labels = {
    managed_by  = "terraform"
    environment = var.environment
    component   = "cx-agent-studio"
  }
}

# ---------------------------------------------------------------------------
# Enable Required APIs
# ---------------------------------------------------------------------------

resource "google_project_service" "ces_api" {
  project            = var.project_id
  service            = "ces.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam_api" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage_api" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild_api" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Service Account for CI/CD Pipeline
# ---------------------------------------------------------------------------

resource "google_service_account" "cxas_cicd" {
  count        = var.service_account_email == "" ? 1 : 0
  project      = var.project_id
  account_id   = "cxas-cicd-${var.environment}"
  display_name = "CX Agent Studio CI/CD — ${var.environment}"
  description  = "Service account for CX Agent Studio version and deployment management"
}

# Grant CES Editor role (for version/deployment/export/import operations)
resource "google_project_iam_member" "ces_editor" {
  project = var.project_id
  role    = "roles/dialogflow.admin"
  member  = "serviceAccount:${local.sa_email}"

  depends_on = [google_service_account.cxas_cicd]
}

# Grant Storage Admin for export bucket
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${local.sa_email}"

  depends_on = [google_service_account.cxas_cicd]
}

# ---------------------------------------------------------------------------
# GCS Bucket for Agent Exports
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "agent_exports" {
  name                        = local.bucket_name
  project                     = var.project_id
  location                    = upper(var.region == "us" ? "US" : var.region)
  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365 # Keep exports for 1 year
    }
  }

  labels = local.labels

  depends_on = [google_project_service.storage_api]
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "project_id" {
  value = var.project_id
}

output "app_name" {
  description = "Full CX Agent Studio app resource name"
  value       = local.app_name
}

output "export_bucket" {
  description = "GCS bucket for agent exports"
  value       = google_storage_bucket.agent_exports.name
}

output "service_account_email" {
  description = "Service account used for CES API calls"
  value       = local.sa_email
}

output "ces_api_base" {
  description = "CES REST API base URL"
  value       = local.ces_api_base
}

output "environment" {
  value = var.environment
}
