variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west2"
}

variable "authorized_network_cidr" {
  type        = string
  description = "CIDR permitted to reach the GKE control plane (your IP/32 for testing)"
}

variable "attestor_public_key" {
  type = string
}
