output "tfe_url" {
  description = "TFE — create the first admin user at /admin/account/new with the IACT token (see README)."
  value       = "https://${local.tfe_fqdn}"
}

output "tfe_s3_bucket" {
  description = "TFE object storage bucket."
  value       = aws_s3_bucket.tfe.bucket
}
