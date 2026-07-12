variable "project_id" {
  type = string
}

variable "k8s_namespace" {
  type    = string
  default = "flask-app"
}

variable "k8s_service_account" {
  type    = string
  default = "flask-app-ksa"
}
