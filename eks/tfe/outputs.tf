output "tfe_url" {
  description = "HTTPS URL of the TFE instance (record created by external-dns)."
  value       = "https://${local.infra.tfe_fqdn}"
}
