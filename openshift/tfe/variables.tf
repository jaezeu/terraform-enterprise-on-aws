# Cluster auth: base64 PEM from install-dir/auth/kubeconfig, uploaded as
# sensitive workspace variables by scripts/set-cluster-auth.sh. Empty
# defaults let empty-workspace destroys plan before the script has run.
variable "cluster_ca_certificate" {
  type        = string
  sensitive   = true
  default     = ""
  description = "certificate-authority-data of the cluster (base64 PEM)."
}

variable "cluster_client_certificate" {
  type        = string
  sensitive   = true
  default     = ""
  description = "client-certificate-data of the system:admin user (base64 PEM)."
}

variable "cluster_client_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "client-key-data of the system:admin user (base64 PEM)."
}

variable "secret_prefix" {
  type        = string
  default     = "tfe-demo"
  description = "Prefix for the TFE secret names in AWS Secrets Manager (matches SECRET_PREFIX in scripts/create_tfe_secrets.sh). Same secrets as the ec2/ and eks/ stacks."
}

variable "tfe_image_tag" {
  type        = string
  default     = "v202505-1"
  description = "Tag (TFE release version) of the terraform-enterprise container image to deploy. See https://developer.hashicorp.com/terraform/enterprise/releases."
}

variable "tfe_hostname_label" {
  type        = string
  default     = "tfe-openshift"
  description = "Single DNS label for TFE under the base domain (the wildcard TLS cert covers *.<base_domain> only, and the label must not collide with the cluster's own <cluster_name> subdomain)."
}
