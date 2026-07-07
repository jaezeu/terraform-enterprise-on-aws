output "tfe_url" {
  description = "HTTPS URL of the TFE instance (record created by external-dns)."
  value       = "https://${data.terraform_remote_state.infra.outputs.tfe_fqdn}"
}
