locals {
  tags = {
    managed-by  = "terraform/infra"
    environment = var.environment
  }
}

# Data sources: read things bootstrap owns. Terraform never changes them.
data "azurerm_resource_group" "this" {
  name = "rg-livepoll-${var.environment}"
}

data "azurerm_user_assigned_identity" "app" {
  name                = "id-livepoll-app-${var.environment}" # already has its table role, granted by bootstrap
  resource_group_name = data.azurerm_resource_group.this.name
}

# --- The vote store -----------------------------------------------------------

resource "azurerm_storage_account" "votes" {
  name                     = var.storage_account_name
  resource_group_name      = data.azurerm_resource_group.this.name
  location                 = data.azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false # no keys: the app logs in with its managed identity
  allow_nested_items_to_be_public = false

  tags = local.tags
}

resource "azurerm_storage_table" "votes" {
  name               = "votes"
  storage_account_id = azurerm_storage_account.votes.id # a reference: Terraform creates the account first
}

# --- The app ------------------------------------------------------------------

resource "azurerm_container_app_environment" "this" {
  name                = "cae-livepoll-${var.environment}"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_container_app" "poll" {
  name                         = "ca-livepoll-${var.environment}"
  resource_group_name          = data.azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.app.id] # the app runs as this identity
  }

  ingress {
    external_enabled = true # reachable from the internet, so phones can vote
    target_port      = 8000
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0 # scale to zero when nobody votes
    max_replicas = 1

    container {
      name   = "poll"
      image  = "ghcr.io/jidarwish/terraform-live-poll-demo:${var.app_image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "POLL_QUESTION"
        value = var.poll_question
      }
      env {
        name  = "POLL_OPTIONS"
        value = join("|", var.poll_options)
      }
      env {
        name  = "POLL_COLOR"
        value = var.poll_color
      }
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.votes.name
      }
      env {
        name  = "TABLE_NAME"
        value = azurerm_storage_table.votes.name
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = data.azurerm_user_assigned_identity.app.client_id # which identity to log in as
      }
    }
  }
}
