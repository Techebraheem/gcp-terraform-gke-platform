resource "google_artifact_registry_repository" "flask_app_repo" {
  location      = var.region
  repository_id = "flask-app"
  description   = "Container images for the flask-app service"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-last-10-tagged"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-untagged-after-14d"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "1209600s" # 14 days
    }
  }
}

# Enables automatic vulnerability scanning on every image push to this registry
resource "google_project_service" "container_scanning" {
  project = var.project_id
  service = "containerscanning.googleapis.com"
  disable_on_destroy = false
}

# Cloud KMS: keyring + asymmetric signing key for Binary Authorization
resource "google_kms_key_ring" "binauthz" {
  name     = "binauthz-keyring"
  location = "global" # Binary Authorization attestors require a global-location KMS key
}

resource "google_kms_crypto_key" "attestor_key" {
  name     = "attestor-key"
  key_ring = google_kms_key_ring.binauthz.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm = "RSA_SIGN_PKCS1_2048_SHA256" # matches the signature_algorithm set on the attestor's public key below
  }

  # Prevents `terraform destroy` from deleting key material outright — GCP KMS
  # keys are cheap to keep and expensive to lose (any images already attested
  # under this key become unverifiable if the key is gone). Purely a safety
  # rail for this reference project; remove if you genuinely want easy teardown.
  lifecycle {
    prevent_destroy = false
  }
}

# Grants ONLY the deploy pipeline's SA permission to sign with this key —
# nobody else, no other service account, can produce a valid attestation.
resource "google_kms_crypto_key_iam_member" "cloudbuild_signer" {
  crypto_key_id = google_kms_crypto_key.attestor_key.id
  role          = "roles/cloudkms.signerVerifier"
  member        = "serviceAccount:${var.cloudbuild_deployer_sa_email}"
}

# Binary Authorization: enforce that only images which passed the attestation/scan
# policy can actually be deployed to GKE. This is the "policy enforcement" gate —
# it stops a bad image from ever running, not just from being flagged after the fact.
resource "google_binary_authorization_policy" "policy" {
  count   = var.attestor_public_key_pem != "" ? 1 : 0
  project = var.project_id

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = [
      google_binary_authorization_attestor.build_attestor[0].name
    ]
  }

  # Allow official Google system images (needed for GKE system pods) to bypass
  admission_whitelist_patterns {
    name_pattern = "gcr.io/gke-release/*"
  }
}

resource "google_binary_authorization_attestor" "build_attestor" {
  count       = var.attestor_public_key_pem != "" ? 1 : 0
  name        = "cloudbuild-passed-attestor"
  description = "Attests an image passed the Cloud Build test + scan stages"

  attestation_authority_note {
    note_reference = google_container_analysis_note.build_note.name
    public_keys {
      # PKIX (KMS-backed) public key, not PGP. signature_algorithm MUST match
      # the KMS key's version_template.algorithm above exactly, or verification
      # will fail even though the key itself is valid.
      pkix_public_key {
        public_key_pem      = var.attestor_public_key_pem
        signature_algorithm = "RSA_SIGN_PKCS1_2048_SHA256"
      }
    }
  }
}

resource "google_container_analysis_note" "build_note" {
  name = "cloudbuild-passed-note"
  attestation_authority {
    hint {
      human_readable_name = "Passed Cloud Build test + Trivy scan stage"
    }
  }
}