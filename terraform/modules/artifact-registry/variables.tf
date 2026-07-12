variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "attestor_public_key" {
  type        = string
  description = "PGP public key of the CI signer, used to verify build attestations. Generate with gpg --export --armor."
}
