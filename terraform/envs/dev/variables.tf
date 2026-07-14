variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "authorized_network_cidr" {
  type        = string
  description = "CIDR permitted to reach the GKE control plane (your IP/32 for testing)"
}

variable "attestor_public_key_pem" {
  type        = string
  default     = ""
  description = "Leave empty on first apply. See terraform/modules/artifact-registry/variables.tf for the gcloud export command to run after the first apply creates the KMS key."
}