# One-time setup, run from a laptop with local state after `az login` (see README):
#   - Storage Account for the main stack's state (Entra ID auth only, no access keys);
#   - Entra ID app with a federated credential for GitHub Actions, so no client secret
#     is stored in GitHub.
# Costs ~$0 and is meant to stay; only infra/ is created and destroyed daily.

terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.ContainerService",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.Storage",
  ]
}

provider "azuread" {}

data "azurerm_subscription" "current" {}

data "azuread_client_config" "current" {}

# --- Terraform state -------------------------------------------------------------

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "state" {
  name     = "voting-tfstate-rg"
  location = var.location
}

resource "azurerm_storage_account" "state" {
  name                            = "votingtfstate${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# You, so that infra/ can also be run from the laptop.
resource "azurerm_role_assignment" "state_me" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_client_config.current.object_id
}

# --- GitHub Actions identity ---------------------------------------------------------

resource "azuread_application_registration" "github" {
  display_name = "voting-infra-azure-github"
}

resource "azuread_service_principal" "github" {
  client_id = azuread_application_registration.github.client_id
}

# Only workflows running on main of this one repository can get a token.
resource "azuread_application_federated_identity_credential" "main" {
  application_id = azuread_application_registration.github.id
  display_name   = "github-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = local.github_subject # immutable format, see github.tf
}

resource "azurerm_role_assignment" "github" {
  # Contributor creates resources; RBAC Administrator lets the stack grant the AKS identity
  # access to its VNet. Broad on purpose for a sandbox subscription.
  for_each = toset(["Contributor", "Role Based Access Control Administrator"])

  scope                = data.azurerm_subscription.current.id
  role_definition_name = each.value
  principal_id         = azuread_service_principal.github.object_id
}

resource "azurerm_role_assignment" "state_github" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github.object_id
}

# --- Wiring for infra/ ---------------------------------------------------------------

resource "local_file" "backend" {
  filename        = "${path.module}/../infra/backend.hcl"
  file_permission = "0644"
  content         = <<-EOT
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.state.name}"
    key                  = "voting/${var.env}.tfstate"
    use_azuread_auth     = true
  EOT
}
