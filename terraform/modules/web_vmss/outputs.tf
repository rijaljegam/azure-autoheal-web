output "scale_set_id" {
  value = azurerm_linux_virtual_machine_scale_set.this.id
}

output "scale_set_name" {
  value = azurerm_linux_virtual_machine_scale_set.this.name
}

output "principal_id" {
  description = "Null unless a managed identity is added to the scale set."
  value       = try(azurerm_linux_virtual_machine_scale_set.this.identity[0].principal_id, null)
}
