# =============================================================================
# VM Scale Set — the self-healing part
# =============================================================================
# Two mechanisms, covering two different failures:
#
#   1. automatic_instance_repair — an instance that is RUNNING but UNHEALTHY
#      (container crashed, nginx serving errors, disk full) is deleted and
#      recreated by the platform. Driven by the load balancer probe.
#
#   2. autoscale with a minimum — an instance that is DELETED reduces the scale
#      set's capacity, and nothing in the scale set itself restores it.
#      Autoscale notices capacity is below minimum and creates a replacement.
#
# Only having (1) means `az vmss delete-instances` permanently shrinks the tier.
# Only having (2) means a wedged-but-running instance keeps serving errors.
# =============================================================================

resource "azurerm_linux_virtual_machine_scale_set" "this" {
  name                = "vmss-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku       = var.vm_sku
  instances = var.instance_count
  zones     = var.zones

  # Listing zones already gives best-effort spread across them. zone_balance
  # makes that balance STRICT: the platform fails a scale operation it cannot
  # place evenly rather than placing it unevenly. Not worth it at 2 instances
  # under a 4 vCPU quota, where it can only turn a degraded placement into a
  # failed one. The property is also immutable — changing it destroys and
  # recreates the scale set.
  zone_balance = false

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    storage_account_type = var.os_disk_type
    caching              = "ReadWrite"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    container_image = var.container_image
  }))

  network_interface {
    name    = "nic-${var.suffix}"
    primary = true

    ip_configuration {
      name                                   = "ipconfig-primary"
      primary                                = true
      subnet_id                              = var.subnet_id
      load_balancer_backend_address_pool_ids = [var.backend_address_pool_id]
    }
  }

  # Ties instance health to the same probe that decides traffic routing, so an
  # instance the load balancer will not send traffic to is also one the platform
  # will rebuild. Without this, automatic_instance_repair has no health signal
  # and silently does nothing.
  health_probe_id = var.health_probe_id

  # Rolling rather than Automatic: replacements happen a batch at a time with
  # the probe gating each batch, so an image that fails to start cannot take
  # every instance down at once.
  upgrade_mode = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 50
    max_unhealthy_instance_percent          = 50
    max_unhealthy_upgraded_instance_percent = 50
    pause_time_between_batches              = "PT2M"
  }

  automatic_instance_repair {
    enabled = true
    # Time an instance gets to become healthy before it counts as failed.
    # Must comfortably exceed cloud-init: apt update, docker install, and an
    # image pull is typically 60-90 seconds. Too short and the platform kills
    # instances that were about to succeed, in a loop.
    grace_period = "PT10M"
  }

  # Serial console output — the first place to look when an instance comes up
  # unhealthy, since cloud-init failures are otherwise invisible.
  boot_diagnostics {}

  tags = var.tags

  lifecycle {
    # Autoscale owns the instance count at runtime. Without this, every plan
    # after a scale event shows a diff and every apply fights the autoscaler —
    # which breaks the "a second run makes no changes" requirement.
    ignore_changes = [instances]
  }
}

# The piece that makes a DELETED instance come back.
resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.this.id

  profile {
    name = "default"

    capacity {
      default = var.instance_count
      minimum = var.instance_count
      maximum = var.instance_count_max
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  tags = var.tags
}
