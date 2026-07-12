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
