variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

#variable "master_cidr" {
 # type    = string
 # default = "172.16.0.0/28"
#}

variable "authorized_network_cidr" {
  type        = string
  description = "CIDR allowed to reach the GKE control plane API (your office IP or Cloud Build's range)"
}

variable "node_sa_email" {
  type        = string
  description = "Dedicated (non-default) service account for GKE nodes — never use the Compute default SA in production"
}

variable "min_node_count" {
  type    = number
  default = 1
}

variable "max_node_count" {
  type    = number
  default = 3
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}
