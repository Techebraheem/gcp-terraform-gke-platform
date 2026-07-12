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

# Binary Authorization: enforce that only images which passed the attestation/scan
# policy can actually be deployed to GKE. This is the "policy enforcement" gate —
# it stops a bad image from ever running, not just from being flagged after the fact.
resource "google_binary_authorization_policy" "policy" {
  project = var.project_id

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = [
      google_binary_authorization_attestor.build_attestor.name
    ]
  }

  # Allow official Google system images (needed for GKE system pods) to bypass
  admission_whitelist_patterns {
    name_pattern = "gcr.io/gke-release/*"
  }
}

resource "google_binary_authorization_attestor" "build_attestor" {
  name        = "cloudbuild-passed-attestor"
  description = "Attests an image passed the Cloud Build test + scan stages"

  attestation_authority_note {
    note_reference = google_container_analysis_note.build_note.name
    public_keys {
      ascii_armored_pgp_public_key = var.attestor_public_key
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
