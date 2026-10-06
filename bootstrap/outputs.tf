# The three GitHub Actions variables. Set them once, see SETUP.md.

output "azure_client_id" {
  value = azurerm_user_assigned_identity.github.client_id
}

output "azure_tenant_id" {
  value = azurerm_user_assigned_identity.github.tenant_id
}

output "azure_subscription_id" {
  value = var.subscription_id
}

output "state_storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

output "resource_group_names" {
  value = { for env, rg in azurerm_resource_group.env : env => rg.name }
}
