output "cloudbuild_sa_email" {
  value = google_service_account.cloudbuild_sa.email
}

output "cloudbuild_pr_sa_email" {
  value = google_service_account.cloudbuild_pr_sa.email
}

output "flask_app_sa_email" {
  value = google_service_account.flask_app_sa.email
}
