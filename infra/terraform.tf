terraform {
  required_version = "~> 1.16"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }

  # Remote state, partial config: where the state file lives comes per env from envs/{env}.backend.hcl.
  #   terraform init -backend-config=envs/dev.backend.hcl
  backend "azurerm" {
    use_azuread_auth = true # log in with Entra ID: the state account has no keys
  }
}

# The subscription comes from ARM_SUBSCRIPTION_ID, not from a committed file.
provider "azurerm" {
  features {}
  storage_use_azuread = true # the vote account has no keys either, so Terraform uses Entra ID for the table
}
