terraform {
  required_version = "~> 1.16"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }

  # Bootstrap keeps its own state in the container it creates.
  # First run only: a gitignored local_override.tf swaps this for a local backend (see README).
  backend "azurerm" {
    resource_group_name  = "rg-livepoll-tfstate"
    storage_account_name = "stlivepolltfjd01" # a backend block can't use variables
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true # account keys are off on the state account
}
