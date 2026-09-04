# =============================================================================
# Auto-healing web tier — Azure
# =============================================================================
# Two or more VM Scale Set instances, each running the same container, behind a
# Standard Load Balancer. Losing an instance does not lose the site, and the
# platform rebuilds it without intervention.
#
# This file wires modules together; every resource lives in ./modules.
# =============================================================================

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.suffix}"
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "./modules/network"

  suffix              = local.suffix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  address_space       = var.vnet_address_space
  web_subnet_prefix   = var.web_subnet_prefix
  allowed_http_source = var.allowed_http_source

  tags = local.tags
}

module "loadbalancer" {
  source = "./modules/loadbalancer"

  suffix              = local.suffix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  # Zone-redundant frontend. Kept separate from the scale set's zones because a
  # public IP has no compute capacity constraint — the frontend can stay
  # zone-redundant even when instances fall back to regional allocation.
  frontend_zones = var.lb_frontend_zones

  tags = local.tags
}

module "web" {
  source = "./modules/web_vmss"

  suffix              = local.suffix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  subnet_id               = module.network.web_subnet_id
  backend_address_pool_id = module.loadbalancer.backend_address_pool_id
  health_probe_id         = module.loadbalancer.health_probe_id

  container_image      = var.container_image
  vm_sku               = var.vm_sku
  os_disk_type         = var.os_disk_type
  instance_count       = var.instance_count
  instance_count_max   = var.instance_count_max
  admin_username       = var.admin_username
  admin_ssh_public_key = var.admin_ssh_public_key
  zones                = var.availability_zones

  tags = local.tags

  # Azure rejects a probe as a VMSS health_probe_id unless a load balancing
  # RULE already references that probe and targets the backend pool
  # (CannotUseInactiveHealthProbe). Passing the pool and probe IDs only orders
  # the scale set after those two resources, not after the rule — so the rule
  # can still be created in parallel, and the scale set loses the race.
  #
  # Depending on the whole module guarantees the rule exists first.
  depends_on = [module.loadbalancer]
}
