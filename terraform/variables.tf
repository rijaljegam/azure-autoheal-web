variable "tenant_id" {
  description = <<-EOT
    Entra tenant. Set explicitly rather than inherited from the az CLI context,
    so an apply cannot land in whichever tenant you happened to log into last.
  EOT
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

# ---------------------------------------------------------------------------
# Naming and tagging
# ---------------------------------------------------------------------------
# Resource names are composed as {type}-{workload}-{env}-{loc}-{instance},
# e.g. rg-autoheal-dev-aue-001. Nothing is hardcoded; change these and every
# resource follows.

variable "workload" {
  description = "Short workload name used in every resource name."
  type        = string
  default     = "autoheal"

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.workload))
    error_message = "workload must be 2-12 lowercase alphanumeric characters — it feeds storage-style names with tight rules."
  }
}

variable "environment" {
  description = "Environment code: dev, tst, stg or prd."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "tst", "stg", "prd"], var.environment)
    error_message = "environment must be one of dev, tst, stg, prd."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "australiaeast"
}

variable "location_code" {
  description = "Short region code used in resource names, e.g. aue for australiaeast."
  type        = string
  default     = "aue"
}

variable "instance" {
  description = "Instance number, zero-padded, allowing a second parallel stack."
  type        = string
  default     = "001"
}

variable "owner" {
  description = "Owner tag — who to contact about this stack."
  type        = string
  default     = "jrijal@profectusgroup.com"
}

variable "cost_centre" {
  description = "Cost centre tag."
  type        = string
  default     = "personal"
}

variable "extra_tags" {
  description = "Additional tags merged over the defaults."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space for the VNet."
  type        = list(string)
  default     = ["10.60.0.0/22"]
}

variable "web_subnet_prefix" {
  description = "Address prefix for the web subnet. Must sit inside vnet_address_space."
  type        = string
  default     = "10.60.0.0/24"
}

variable "allowed_http_source" {
  description = <<-EOT
    Source allowed to reach port 80. "Internet" makes the page public, which is
    the point of the exercise. Narrow this to your own IP/CIDR if you would
    rather not publish it.
  EOT
  type        = string
  default     = "Internet"
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "container_image" {
  description = <<-EOT
    Docker Hub image each instance pulls and runs, e.g.
    docker.io/<your-user>/autoheal-web:1.0.0

    Must be public — cloud-init performs an unauthenticated pull. Use an
    immutable tag rather than :latest, so a replaced instance serves exactly
    what the others are serving.
  EOT
  type        = string

  validation {
    condition     = can(regex(":[^:/]+$", var.container_image))
    error_message = "container_image must carry an explicit tag. An untagged image resolves to :latest, so a replacement instance can silently serve different content."
  }
}

variable "instance_count" {
  description = <<-EOT
    Starting instance count, and the autoscale minimum. Must be at least 2 so
    losing one instance leaves the site serving (the n+1 requirement).
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 2
    error_message = "instance_count must be >= 2 — a single instance cannot survive losing an instance."
  }
}

variable "instance_count_max" {
  description = "Autoscale maximum."
  type        = number
  default     = 4
}

variable "vm_sku" {
  description = <<-EOT
    VM size for scale set instances. B1s (1 vCPU / 1 GiB) is ample for Docker
    plus an nginx container serving a static page, and is the cheapest size that
    comfortably fits both. B1ls (0.5 GiB) is cheaper again but the Docker daemon
    plus Ubuntu leaves almost no headroom, and an OOM during cloud-init presents
    as an instance that never becomes healthy.
  EOT
  type        = string
  default     = "Standard_B1s"
}

variable "os_disk_type" {
  description = <<-EOT
    OS disk type. StandardSSD_LRS costs a little more than Standard_LRS (HDD)
    but boots noticeably faster, which matters here: a slow boot eats into the
    instance-repair grace period and makes healing take longer.
  EOT
  type        = string
  default     = "StandardSSD_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS"], var.os_disk_type)
    error_message = "os_disk_type must be Standard_LRS, StandardSSD_LRS or Premium_LRS."
  }
}

variable "admin_username" {
  description = "Admin username on each instance."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = <<-EOT
    SSH public key for the admin user. Required — password auth is disabled.
    There is no inbound SSH rule; reach instances via Azure Bastion or a
    temporary NSG rule if you need to debug.
  EOT
  type        = string

  # Checks the key DATA, not just the prefix. A prefix-only check lets a
  # placeholder like "ssh-ed25519 AAAA_REPLACE_ME" through, and the provider
  # then fails at plan time with an opaque "decoding public key data" error.
  validation {
    condition = can(regex(
      "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/]{60,}={0,3}( .*)?$",
      var.admin_ssh_public_key
    ))
    error_message = "admin_ssh_public_key must be a complete OpenSSH public key — the contents of your .pub file, not a path or a placeholder. Generate one with: ssh-keygen -t ed25519 -f ~/.ssh/autoheal -N \"\""
  }
}

variable "availability_zones" {
  description = <<-EOT
    Zones to spread SCALE SET INSTANCES across. Two or more means a zone outage
    cannot take the whole tier down.

    Set to [] when a region has no zone support, or when zonal capacity is
    restricted for the chosen VM size — B-series in particular is frequently
    unavailable zonally in busy regions, which surfaces as SkuNotAvailable /
    "Capacity Restrictions" at scale set creation. Regional allocation usually
    succeeds where zonal does not.
  EOT
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "lb_frontend_zones" {
  description = <<-EOT
    Zones for the load balancer's public IP. Deliberately separate from
    availability_zones: a zone-redundant frontend has no compute capacity
    constraint, so it can stay zone-redundant even when instances have to fall
    back to regional allocation.

    Also note `zones` forces replacement of the public IP, which cascades to the
    load balancer — so changing this on a live stack is disruptive.
  EOT
  type        = list(string)
  default     = ["1", "2", "3"]
}
