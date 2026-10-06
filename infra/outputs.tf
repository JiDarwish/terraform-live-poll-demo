output "poll_url" {
  description = "Where phones vote. The QR code on /results points here."
  value       = "https://${azurerm_container_app.poll.ingress[0].fqdn}"
}

output "results_url" {
  description = "The projector page."
  value       = "https://${azurerm_container_app.poll.ingress[0].fqdn}/results"
}
