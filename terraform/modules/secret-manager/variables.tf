variable "environment" {
  type    = string
  default = "dev"
}

variable "flask_app_sa_email" {
  type        = string
  description = "Email of the Workload Identity SA that the Flask app runs as"
}
