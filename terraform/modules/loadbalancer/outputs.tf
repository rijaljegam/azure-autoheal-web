output "public_ip_address" {
  value = azurerm_public_ip.this.ip_address
}

output "loadbalancer_id" {
  value = azurerm_lb.this.id
}

output "backend_address_pool_id" {
  value = azurerm_lb_backend_address_pool.this.id
}

output "health_probe_id" {
  description = "Passed to the scale set so instance repair uses the same health signal as traffic routing."
  value       = azurerm_lb_probe.http.id
}
