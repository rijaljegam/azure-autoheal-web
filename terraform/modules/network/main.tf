# =============================================================================
# VNet, web subnet, and the NSG guarding it
# =============================================================================

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space

  tags = var.tags
}

resource "azurerm_subnet" "web" {
  name                 = "snet-web-${var.suffix}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.web_subnet_prefix]
}

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Inbound HTTP. With a Standard LB the probe and data-plane traffic arrive from
# AzureLoadBalancer and Internet respectively, so both need permitting — a rule
# that only allows AzureLoadBalancer passes health checks while serving nobody.
resource "azurerm_network_security_rule" "allow_http" {
  name                        = "allow-http-inbound"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.web.name

  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "80"
  source_address_prefix      = var.allowed_http_source
  destination_address_prefix = "*"
}

resource "azurerm_network_security_rule" "allow_lb_probe" {
  name                        = "allow-azure-lb-probe"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.web.name

  priority                   = 110
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "80"
  source_address_prefix      = "AzureLoadBalancer"
  destination_address_prefix = "*"
}

# Explicit deny above the default 65000 AllowVnetInBound, so nothing else in the
# VNet can reach these instances laterally.
resource "azurerm_network_security_rule" "deny_all_inbound" {
  name                        = "deny-all-inbound"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.web.name

  priority                   = 4000
  direction                  = "Inbound"
  access                     = "Deny"
  protocol                   = "*"
  source_port_range          = "*"
  destination_port_range     = "*"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}
