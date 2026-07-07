variable "secret_prefix" {
  type        = string
  default     = "tfe-demo"
  description = "Prefix for the TFE secret names in AWS Secrets Manager (matches SECRET_PREFIX in scripts/create_tfe_secrets.sh). Secret values are read and injected into Kubernetes secrets for the Helm chart."
}

variable "tfe_image_tag" {
  type        = string
  default     = "v202505-1"
  description = "Tag (TFE release version) of the terraform-enterprise container image to deploy. See https://developer.hashicorp.com/terraform/enterprise/releases."
}
