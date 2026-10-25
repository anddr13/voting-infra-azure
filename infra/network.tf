locals {
  name = "voting-${var.env}"
}

resource "azurerm_resource_group" "this" {
  name     = "${local.name}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = "${local.name}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.10.0.0/16"]
}

# With Azure CNI Overlay only the nodes take addresses from the VNet; pods get theirs
# from a separate overlay range, so a small subnet is enough.
resource "azurerm_subnet" "nodes" {
  name                 = "aks-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.10.0.0/22"]
}
