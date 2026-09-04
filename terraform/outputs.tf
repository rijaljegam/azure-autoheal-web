output "site_url" {
  description = "Open this once the instances finish cloud-init (2-3 minutes after apply)."
  value       = "http://${module.loadbalancer.public_ip_address}"
}

output "public_ip_address" {
  description = "Load balancer frontend IP."
  value       = module.loadbalancer.public_ip_address
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "scale_set_name" {
  description = "Use with `az vmss list-instances` to see or delete instances."
  value       = module.web.scale_set_name
}

output "healing_test_command" {
  description = "Delete one instance and watch autoscale rebuild it."
  value       = <<-EOT
    az vmss list-instances -g ${azurerm_resource_group.this.name} -n ${module.web.scale_set_name} -o table
    az vmss delete-instances -g ${azurerm_resource_group.this.name} -n ${module.web.scale_set_name} --instance-ids <id>
  EOT
}
