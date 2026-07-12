/*
  IAM MODULE
  ----------
  The single biggest mental model shift coming from Azure:

  Azure IAM = Management Group -> Subscription -> Resource Group -> Resource
  GCP  IAM = Organization -> Folder -> Project -> Resource

  Roles are bound at any level of that hierarchy and INHERIT DOWNWARD, same idea as
  Azure RBAC inheritance from a Resource Group. The difference that trips people up:
  GCP has three role types —
    1. Basic roles (Owner/Editor/Viewer) — broad, legacy, avoid in production
    2. Predefined roles (e.g. roles/artifactregistry.reader) — curated, least-privilege,
       this is what you should default to
    3. Custom roles — you define the exact permission set when predefined roles are
       too broad. Same idea as a custom Azure role definition JSON.

  THE PATTERN BELOW: one dedicated service account per workload/pipeline stage,
  each with only the roles it needs. Never reuse a single "deploy-sa" for everything —
  that's the GCP equivalent of giving every pipeline Contributor on the subscription.
*/

# --- Cloud Build service account: builds and pushes images, deploys to GKE ---
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "cloudbuild-deployer"
  display_name = "Cloud Build - Flask App Deployer"
  description  = "Least-privilege SA used only by the Cloud Build pipeline"
}

resource "google_project_iam_member" "cloudbuild_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

resource "google_project_iam_member" "cloudbuild_gke_deployer" {
  project = var.project_id
  role    = "roles/container.developer" # can deploy workloads, NOT cluster-admin
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

resource "google_project_iam_member" "cloudbuild_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

resource "google_project_iam_member" "cloudbuild_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# --- Workload Identity: the GKE-native way for a Pod to act as a GCP service account ---
# This replaces the old pattern of mounting SA key JSON files into pods (which is exactly
# the kind of static-credential sprawl least-privilege reviews flag).
resource "google_service_account" "flask_app_sa" {
  account_id   = "flask-app-workload"
  display_name = "Flask App - Workload Identity SA"
  description  = "Bound to the app's Kubernetes ServiceAccount via Workload Identity"
}

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.flask_app_sa.name
  role                = "roles/iam.workloadIdentityUser"
  # This member string format is how GKE proves "this exact KSA in this exact
  # namespace is allowed to impersonate this exact GSA" — the binding IS the
  # least-privilege boundary.
  member = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account}]"
}

resource "google_project_iam_member" "flask_app_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.flask_app_sa.email}"
}

resource "google_project_iam_member" "flask_app_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.flask_app_sa.email}"
}

resource "google_project_iam_member" "flask_app_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.flask_app_sa.email}"
}

# --- Custom role example: narrower than any predefined role, for a "release approver" persona ---
resource "google_project_iam_custom_role" "release_approver" {
  role_id     = "releaseApprover"
  title       = "Release Approver"
  description = "Can approve Cloud Build manual approval gates only — no deploy, no build trigger edit"
  permissions = [
    "cloudbuild.builds.approve",
    "cloudbuild.builds.get",
    "cloudbuild.builds.list",
  ]
}
