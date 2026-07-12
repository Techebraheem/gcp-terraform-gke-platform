/*
  SECRET MANAGER MODULE
  ----------------------
  Equivalent of Azure Key Vault. The pattern to know cold for interviews:

  1. Secret is created here (empty container + replication policy).
  2. The SECRET VALUE is never put in Terraform state — it's added out-of-band
     (gcloud secrets versions add, or via Cloud Build using --set-secrets, or via
     a sealed-secrets/external-secrets-operator pattern in GitOps).
  3. Access is granted via IAM (roles/secretmanager.secretAccessor) bound to a
     specific service account — same secretAccessor-per-workload least-privilege
     pattern as the IAM module.
  4. In GKE, the app reads secrets either via the Secret Manager CSI driver
     (mounts as a volume, no code changes) or the Python/Go client library.
     CSI driver is the standard so app code stays cloud-agnostic-ish and
     secrets never sit in env vars or ConfigMaps.
*/

resource "google_secret_manager_secret" "flask_secret_key" {
  secret_id = "flask-app-secret-key"

  replication {
    auto {} # Google manages regional replication; use user_managed {} if data residency requires it
  }

  labels = {
    app = "flask-app"
    env = var.environment
  }
}

resource "google_secret_manager_secret" "db_connection_string" {
  secret_id = "flask-app-db-connection"

  replication {
    auto {}
  }

  labels = {
    app = "flask-app"
    env = var.environment
  }
}

# Grants only the flask-app workload SA read access — nothing else can read these
resource "google_secret_manager_secret_iam_member" "app_reads_secret_key" {
  secret_id = google_secret_manager_secret.flask_secret_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.flask_app_sa_email}"
}

resource "google_secret_manager_secret_iam_member" "app_reads_db_conn" {
  secret_id = google_secret_manager_secret.db_connection_string.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.flask_app_sa_email}"
}
