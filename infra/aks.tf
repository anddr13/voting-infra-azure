# The cluster's own identity. It must be able to manage the VNet (public IPs and load-balancer
# rules for LoadBalancer Services), and the role must exist before the cluster does,
# hence a user-assigned identity instead of a system-assigned one.
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.name}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "${local.name}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = local.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free" # no control plane fee
  node_resource_group = "${local.name}-aks-nodes-rg"

  # Required since azurerm 5.0. Manual = classic node pools (no Node Auto Provisioning).
  node_provisioning_profile {
    mode = "Manual"
  }

  # The system pool cannot be spot in AKS, so the workloads run on it as well.
  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    node_count                  = var.node_count
    vnet_subnet_id              = azurerm_subnet.nodes.id
    os_disk_size_gb             = 64
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = "192.168.0.0/16"
    load_balancer_sku   = "standard"
  }

  depends_on = [azurerm_role_assignment.aks_network]
}
