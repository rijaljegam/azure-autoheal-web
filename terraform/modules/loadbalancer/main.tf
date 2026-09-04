# =============================================================================
# Standard Load Balancer — public frontend, HTTP probe, outbound SNAT
# =============================================================================
# Standard SKU (not Basic): Basic is retired, has no zone redundancy, and no
# explicit outbound rules.
#
# Standard SKU is also "secure by default" — it provides NO implicit outbound
# internet access. Without the outbound rule at the bottom of this file the
# instances cannot reach Docker Hub, cloud-init fails to pull the image, and
# every instance comes up unhealthy. That is the single most common way this
# design fails on the first apply.
# =============================================================================

resource "azurerm_public_ip" "this" {
  name                = "pip-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  allocation_method = "Static" # Standard SKU requires Static
  sku               = "Standard"
  zones             = var.frontend_zones

  tags = var.tags
}

resource "azurerm_lb" "this" {
  name                = "lb-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "frontend-public"
    public_ip_address_id = azurerm_public_ip.this.id
  }

  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "this" {
  name            = "bepool-${var.suffix}"
  loadbalancer_id = azurerm_lb.this.id
}

# The probe is what makes healing possible: it decides which instances receive
# traffic, and the scale set reuses it to decide which instances to repair.
# HTTP against "/" rather than a bare TCP check — a TCP probe succeeds as soon
# as something is listening on 80, including an nginx that is serving errors.
resource "azurerm_lb_probe" "http" {
  name            = "probe-http-${var.suffix}"
  loadbalancer_id = azurerm_lb.this.id

  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http" {
  name            = "rule-http-${var.suffix}"
  loadbalancer_id = azurerm_lb.this.id

  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend-public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this.id]
  probe_id                       = azurerm_lb_probe.http.id

  # Required when an explicit outbound rule exists on the same frontend —
  # leaving the implicit SNAT enabled alongside one is unsupported.
  disable_outbound_snat = true
}

# Egress so instances can pull from Docker Hub and reach the apt repositories.
#
# A NAT Gateway is the more robust choice at scale — it has a far larger SNAT
# port budget and does not share a frontend with inbound traffic — but it is a
# separately billed resource. For two instances this rule is sufficient and
# costs nothing beyond the load balancer that already exists.
resource "azurerm_lb_outbound_rule" "internet" {
  name            = "outbound-internet-${var.suffix}"
  loadbalancer_id = azurerm_lb.this.id

  protocol                 = "All"
  backend_address_pool_id  = azurerm_lb_backend_address_pool.this.id
  idle_timeout_in_minutes  = 4
  allocated_outbound_ports = 1024

  frontend_ip_configuration {
    name = "frontend-public"
  }
}
