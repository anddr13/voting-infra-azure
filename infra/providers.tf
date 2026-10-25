# Subscription and credentials come from ARM_* environment variables (OIDC in GitHub Actions,
# `az login` locally).
provider "azurerm" {
  features {}

  # Since azurerm 5.0 nothing is registered implicitly; a fresh subscription needs these.
  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.ContainerService",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
  ]
}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}
