terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Remote state is mandatory for any team pipeline — never local state once
  # more than one person or one pipeline touches this. This is the GCS
  # equivalent of the Azure Storage Account backend you already use.
  backend "gcs" {
    bucket = "REPLACE_ME_terraform-state-bucket"
    prefix = "gcp-reference-project/dev"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Enable required APIs first; everything downstream depends on these ---
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "binaryauthorization.googleapis.com",
    "containeranalysis.googleapis.com",
    "containerscanning.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

module "vpc" {
  source     = "../../modules/vpc"
  project_id = var.project_id
  region     = var.region

  depends_on = [google_project_service.apis]
}

module "iam" {
  source     = "../../modules/iam"
  project_id = var.project_id

  depends_on = [google_project_service.apis]
}

# Dedicated SA for GKE nodes — never the Compute Engine default SA
resource "google_service_account" "gke_node_sa" {
  account_id   = "gke-node-sa"
  display_name = "GKE Node Service Account"
}

resource "google_project_iam_member" "node_sa_minimal" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader", # nodes need to pull images, nothing more
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

module "artifact_registry" {
  source               = "../../modules/artifact-registry"
  project_id           = var.project_id
  region               = var.region
  attestor_public_key  = var.attestor_public_key
}

module "gke" {
  source                   = "../../modules/gke"
  project_id               = var.project_id
  region                   = var.region
  network_id               = module.vpc.network_id
  subnet_id                = module.vpc.subnet_id
  pods_range_name          = module.vpc.pods_range_name
  services_range_name      = module.vpc.services_range_name
  authorized_network_cidr  = var.authorized_network_cidr
  node_sa_email            = google_service_account.gke_node_sa.email
}

module "secret_manager" {
  source              = "../../modules/secret-manager"
  environment         = "dev"
  flask_app_sa_email  = module.iam.flask_app_sa_email
}
