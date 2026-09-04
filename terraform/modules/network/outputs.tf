output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "web_subnet_id" {
  value = azurerm_subnet.web.id
}

output "nsg_id" {
  value = azurerm_network_security_group.web.id
}
