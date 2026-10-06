# The three GitHub Actions variables. Set them once, see README.

output "azure_client_id" {
  value = azurerm_user_assigned_identity.github.client_id
}

output "azure_tenant_id" {
  value = azurerm_user_assigned_identity.github.tenant_id
}

output "azure_subscription_id" {
  value = var.subscription_id
}
