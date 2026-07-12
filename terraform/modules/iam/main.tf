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

# --- Workload Identity ---
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

# --- Custom role: narrower than any predefined role, for a "release approver" persona ---
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
