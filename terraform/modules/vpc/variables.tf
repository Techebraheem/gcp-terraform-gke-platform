variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/20" # node IPs — small on purpose, nodes are cheap to re-range
}

variable "pods_cidr" {
  type    = string
  default = "10.4.0.0/14" # large range — every pod gets a real IP under VPC-native networking
}

variable "services_cidr" {
  type    = string
  default = "10.8.0.0/20"
}

variable "master_cidr" {
  type    = string
  default = "172.16.0.0/28" # GKE control plane range for private clusters, must be /28
}
