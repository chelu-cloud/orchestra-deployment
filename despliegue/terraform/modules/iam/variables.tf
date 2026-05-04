variable "db_arn" {
    type = string
    description = "Arn from db"
}

variable "oidc_provider_arn" {
  description = "ARN del proveedor OIDC del cluster EKS"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL del proveedor OIDC del cluster EKS (sin https://)"
  type        = string
}
