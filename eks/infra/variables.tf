variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all AWS resources."
  default     = {}
}

variable "friendly_name_prefix" {
  type        = string
  description = "Friendly name prefix used for uniquely naming all AWS resources for this deployment. Must differ from the EC2 deployment's prefix to avoid resource name collisions in the same account."
}

variable "tfe_fqdn" {
  type        = string
  description = "Fully qualified domain name (FQDN) of the TFE instance (e.g. tfe-eks.example.com). Must differ from the EC2 deployment's FQDN. Exposed as an output so the tfe layer reads it from remote state — set it only on this workspace."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-\\.]{0,251}[a-z0-9])?$", var.tfe_fqdn))
    error_message = "tfe_fqdn must be a valid fully qualified domain name."
  }
}

variable "route53_tfe_hosted_zone_name" {
  type        = string
  description = "The name of the public Route 53 hosted zone external-dns manages records in (e.g. example.com)."
}

variable "secret_prefix" {
  type        = string
  default     = "tfe-demo"
  description = "Prefix for the TFE secret names in AWS Secrets Manager (matches SECRET_PREFIX in scripts/create_tfe_secrets.sh)."
}
