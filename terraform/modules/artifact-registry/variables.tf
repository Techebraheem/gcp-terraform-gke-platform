variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "attestor_public_key_pem" {
  type        = string
  default     = ""
  description = "PEM-encoded public key exported from the Cloud KMS signing key, via: gcloud kms keys versions get-public-key 1 --key=attestor-key --keyring=binauthz-keyring --location=global --format='value(pem)'. Leave empty on the FIRST apply (creates the KMS key only); fill in and re-apply to create the attestor + policy."
}

variable "cloudbuild_deployer_sa_email" {
  type        = string
  description = "Email of the Cloud Build deploy service account (from the iam module) — granted signer permission on the KMS attestor key."
}
