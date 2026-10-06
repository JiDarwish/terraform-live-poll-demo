terraform {
  required_version = "~> 1.16"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }

  # Remote state, partial config: where state lives is shared, the file name (key) comes per env.
  #   terraform init -backend-config=envs/dev.backend.hcl
  backend "azurerm" {
    resource_group_name  = "rg-livepoll-tfstate"
    storage_account_name = "stlivepolltfjd01"
    container_name       = "tfstate"
    use_azuread_auth     = true # log in with Entra ID: the state account has no keys
  }
}

# The subscription comes from ARM_SUBSCRIPTION_ID, not from a committed file.
provider "azurerm" {
  features {}
  storage_use_azuread = true # the vote account has no keys either, so Terraform uses Entra ID for the table
}
