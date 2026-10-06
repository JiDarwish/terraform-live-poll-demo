terraform {
  required_version = "~> 1.16"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }

  # Bootstrap keeps its own state in the container it creates.
  # Partial config: a backend block can't use variables, so the values live in backend.hcl
  # (written by scripts/setup.sh):  terraform init -backend-config=backend.hcl
  # First run only: a gitignored local_override.tf swaps this for a local backend (see SETUP.md).
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true # account keys are off on the state account
}
