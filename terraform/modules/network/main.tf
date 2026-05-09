locals {
  vnet_name   = "${var.name_prefix}-vnet-${var.environment}"
  module_tags = merge(var.tags, { Component = "network" })

  subnet_specs = {
    aks  = { name = "snet-aks", cidr = var.subnet_cidrs.aks }
    apps = { name = "snet-apps", cidr = var.subnet_cidrs.apps }
    mgmt = { name = "snet-mgmt", cidr = var.subnet_cidrs.mgmt }
  }
}

resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]
  tags                = local.module_tags
}

# AKS subnet — kubenet means pods are NOT on the VNet, so this subnet only sizes nodes.
resource "azurerm_subnet" "aks" {
  name                 = local.subnet_specs.aks.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_specs.aks.cidr]

  service_endpoints = [
    "Microsoft.ContainerRegistry",
    "Microsoft.KeyVault",
    "Microsoft.Storage",
  ]
}

# Apps subnet — reserved for internal LBs (Istio ingress) and private endpoints later.
resource "azurerm_subnet" "apps" {
  name                 = local.subnet_specs.apps.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_specs.apps.cidr]

  service_endpoints = [
    "Microsoft.ContainerRegistry",
    "Microsoft.KeyVault",
  ]
}

# Mgmt subnet — for an optional jumpbox VM if you ever switch to a private AKS API server.
resource "azurerm_subnet" "mgmt" {
  name                 = local.subnet_specs.mgmt.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_specs.mgmt.cidr]
}

# ---------------------------------------------------------------------------
# Network Security Groups — default-deny stance
#
# Azure's implicit rules already enforce DenyAllInBound at priority 65500,
# AllowVnetInBound at 65000, and AllowAzureLoadBalancerInBound at 65001.
# We add an EXPLICIT DenyAllInbound at priority 4000 for documentation /
# audit clarity and to leave room (1-3999) for environment-specific allows.
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "aks" {
  name                = "${var.name_prefix}-nsg-aks-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.module_tags

  # Allow VNet-internal traffic (pod-to-pod across nodes, kubelet, AKS control plane flows).
  # Without this, our explicit Deny at 4000 would override the implicit AllowVnetInBound (65000).
  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Azure Load Balancer health probes + traffic come from the AzureLoadBalancer service tag,
  # which is NOT inside VirtualNetwork. Without this, our explicit Deny at 4000 overrides
  # Azure's implicit AllowAzureLoadBalancerInBound (65001) and probes fail, marking backends unhealthy.
  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 1100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInboundExplicit"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_network_security_group" "apps" {
  name                = "${var.name_prefix}-nsg-apps-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.module_tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Azure Load Balancer health probes + traffic come from the AzureLoadBalancer service tag,
  # which is NOT inside VirtualNetwork. Without this, our explicit Deny at 4000 overrides
  # Azure's implicit AllowAzureLoadBalancerInBound (65001) and probes fail, marking backends unhealthy.
  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 1100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInboundExplicit"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "apps" {
  subnet_id                 = azurerm_subnet.apps.id
  network_security_group_id = azurerm_network_security_group.apps.id
}

resource "azurerm_network_security_group" "mgmt" {
  name                = "${var.name_prefix}-nsg-mgmt-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.module_tags

  security_rule {
    name                       = "AllowSSHFromAdmin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_ip_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Azure Load Balancer health probes + traffic come from the AzureLoadBalancer service tag,
  # which is NOT inside VirtualNetwork. Without this, our explicit Deny at 4000 overrides
  # Azure's implicit AllowAzureLoadBalancerInBound (65001) and probes fail, marking backends unhealthy.
  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 1100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInboundExplicit"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}
