# Run once by the presenter. Everything infra/ needs before its first plan:
# a place for state, the two environment resource groups, a CI identity, the app identities,
# and every role assignment. infra/ creates no role assignments, so CI never needs to grant roles.

locals {
  tags = { managed-by = "terraform/bootstrap" }
}

# --- Resource groups ----------------------------------------------------------
# Owned here, so every role below is scoped to one resource group, not the subscription.

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-livepoll-${var.suffix}-tfstate"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "env" {
  for_each = toset(["dev", "prod"])

  name     = "rg-livepoll-${var.suffix}-${each.key}"
  location = var.location
  tags     = local.tags
}

# --- State storage ------------------------------------------------------------

resource "azurerm_storage_account" "tfstate" {
  name                     = "stlivepolltf${var.suffix}" # must match backend.hcl and infra/envs/*.backend.hcl
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false # Entra ID only: no account keys, no SAS
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true # the portal browses with Entra ID too

  blob_properties {
    versioning_enabled = true # every state write keeps the previous version
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags

  lifecycle {
    prevent_destroy = true # losing this account loses every state file
  }
}

resource "azurerm_storage_container" "tfstate" {
  name               = "tfstate"
  storage_account_id = azurerm_storage_account.tfstate.id
}

# --- CI identity: GitHub Actions logs in with OIDC, no secrets ----------------

resource "azurerm_user_assigned_identity" "github" {
  name                = "id-livepoll-github"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location
  tags                = local.tags
}

# Which GitHub runs may use it: PR plans, and applies from main.
resource "azurerm_federated_identity_credential" "github_pull_request" {
  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.github.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:${var.github_repository}:pull_request"
}

resource "azurerm_federated_identity_credential" "github_main" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.github.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:${var.github_repository}:ref:refs/heads/main"

  depends_on = [azurerm_federated_identity_credential.github_pull_request] # Azure rejects parallel writes (409)
}

# --- App identities: what the running app uses to reach its vote table ------------
# Created here, not in infra/: granting a role needs roleAssignments/write, which Contributor
# (CI's role) lacks. infra/ reads these with a data source. Bonus: the role has propagated
# long before the app is first deployed.

resource "azurerm_user_assigned_identity" "app" {
  for_each = azurerm_resource_group.env

  name                = "id-livepoll-app-${each.key}"
  resource_group_name = each.value.name
  location            = each.value.location
  tags                = local.tags
}

# --- Roles ----------------------------------------------------------------------
# The presenter is subscription Owner already, so only data-plane roles are added here.
# Owner and Contributor grant no access to the data inside storage.

locals {
  role_assignments = {
    # The app reads and writes votes. Scoped to the env RG: the vote account doesn't exist yet.
    app_dev_table  = { scope = azurerm_resource_group.env["dev"].id, role = "Storage Table Data Contributor", principal = azurerm_user_assigned_identity.app["dev"].principal_id }
    app_prod_table = { scope = azurerm_resource_group.env["prod"].id, role = "Storage Table Data Contributor", principal = azurerm_user_assigned_identity.app["prod"].principal_id }
    # CI deploys prod...
    ci_prod_contributor = { scope = azurerm_resource_group.env["prod"].id, role = "Contributor", principal = azurerm_user_assigned_identity.github.principal_id }
    ci_prod_table       = { scope = azurerm_resource_group.env["prod"].id, role = "Storage Table Data Contributor", principal = azurerm_user_assigned_identity.github.principal_id }
    ci_tfstate          = { scope = azurerm_storage_container.tfstate.id, role = "Storage Blob Data Contributor", principal = azurerm_user_assigned_identity.github.principal_id }
    # ...the presenter deploys dev and reads/writes state from the laptop.
    presenter_dev_table = { scope = azurerm_resource_group.env["dev"].id, role = "Storage Table Data Contributor", principal = var.presenter_object_id }
    presenter_tfstate   = { scope = azurerm_storage_container.tfstate.id, role = "Storage Blob Data Contributor", principal = var.presenter_object_id }
  }
}

resource "azurerm_role_assignment" "this" {
  for_each = local.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = each.value.principal
}
