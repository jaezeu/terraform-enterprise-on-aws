variable "region" {
  type        = string
  description = "AWS region to deploy TFE into."
  default     = "ap-southeast-1"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all AWS resources."
  default     = {}
}

variable "friendly_name_prefix" {
  type        = string
  description = "Friendly name prefix used for uniquely naming all AWS resources for this deployment."
  default     = "tfe"
}

variable "tfe_fqdn" {
  type        = string
  description = "Fully qualified domain name (FQDN) of the TFE instance (e.g. tfe.example.com)."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-\\.]{0,251}[a-z0-9])?$", var.tfe_fqdn))
    error_message = "tfe_fqdn must be a valid fully qualified domain name."
  }
}

variable "tfe_license_secret_arn" {
  type        = string
  sensitive   = true
  description = "ARN of the AWS Secrets Manager secret containing the TFE license file."

  validation {
    condition     = can(regex("^arn:aws:secretsmanager:", var.tfe_license_secret_arn))
    error_message = "Must be a valid AWS Secrets Manager ARN."
  }
}

variable "tfe_encryption_password_secret_arn" {
  type        = string
  sensitive   = true
  description = "ARN of the AWS Secrets Manager secret containing the TFE encryption password."

  validation {
    condition     = can(regex("^arn:aws:secretsmanager:", var.tfe_encryption_password_secret_arn))
    error_message = "Must be a valid AWS Secrets Manager ARN."
  }
}

variable "tfe_database_password_secret_arn" {
  type        = string
  sensitive   = true
  description = "ARN of the AWS Secrets Manager secret containing the TFE database password."

  validation {
    condition     = can(regex("^arn:aws:secretsmanager:", var.tfe_database_password_secret_arn))
    error_message = "Must be a valid AWS Secrets Manager ARN."
  }
}

variable "tfe_tls_cert_secret_arn" {
  type        = string
  sensitive   = true
  description = "ARN of the AWS Secrets Manager secret containing the TFE TLS certificate (PEM format)."

  validation {
    condition     = can(regex("^arn:aws:secretsmanager:", var.tfe_tls_cert_secret_arn))
    error_message = "Must be a valid AWS Secrets Manager ARN."
  }
}

variable "tfe_tls_privkey_secret_arn" {
  type        = string
  sensitive   = true
  description = "ARN of the AWS Secrets Manager secret containing the TFE TLS private key (PEM format)."

  validation {
    condition     = can(regex("^arn:aws:secretsmanager:", var.tfe_tls_privkey_secret_arn))
    error_message = "Must be a valid AWS Secrets Manager ARN."
  }
}

variable "tfe_tls_ca_bundle_secret_arn" {
  type        = string
  sensitive   = true
  description = "ARN of the AWS Secrets Manager secret containing the TLS CA bundle (PEM format)."

  validation {
    condition     = can(regex("^arn:aws:secretsmanager:", var.tfe_tls_ca_bundle_secret_arn))
    error_message = "Must be a valid AWS Secrets Manager ARN."
  }
}
