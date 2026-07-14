output "repo_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.flask_app_repo.repository_id}"
}

output "kms_key_ring_id" {
  value = google_kms_key_ring.binauthz.id
}

output "kms_crypto_key_id" {
  value = google_kms_crypto_key.attestor_key.id
}

# Full resource path Cloud Build's `binauthz attestations sign-and-create --keyversion`
# flag needs. Version "1" assumed since this is the key's first (and typically only)
# version in this reference setup — confirm with `gcloud kms keys versions list`
# if you ever rotate it.
output "kms_key_version_path" {
  value = "${google_kms_crypto_key.attestor_key.id}/cryptoKeyVersions/1"
}
