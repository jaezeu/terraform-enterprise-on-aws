output "console_url" {
  description = "OpenShift web console (resolves via the *.apps record)."
  value       = "https://console-openshift-console.apps.${local.cluster.cluster_domain}"
}
