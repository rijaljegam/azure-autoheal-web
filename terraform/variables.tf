# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

# Set explicitly rather than inherited from the az CLI context, so an apply
# cannot land in whichever tenant you happened to log into last.
variable "tenant_id" {
  description = "Entra tenant ID."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

# ---------------------------------------------------------------------------
# Naming and tagging
# ---------------------------------------------------------------------------
# Names are composed as {type}-{workload}-{env}-{loc}-{instance},
# e.g. rg-autoheal-dev-aue-001. Nothing is hardcoded — change these and every
# resource follows.

variable "workload" {
  description = "Short workload name used in every resource name."
  type        = string
  default     = "autoheal"

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.workload))
    error_message = "workload must be 2-12 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Environment code."
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
  description = "Short region code used in names, e.g. aue for australiaeast."
  type        = string
  default     = "aue"
}

# Bump to 002 to run a second stack alongside this one in the same subscription.
variable "instance" {
  description = "Instance number, zero-padded."
  type        = string
  default     = "001"
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "rijalejgam@gmail.com"
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

# Must sit inside vnet_address_space.
variable "web_subnet_prefix" {
  description = "Address prefix for the web subnet."
  type        = string
  default     = "10.60.0.0/24"
}

# "Internet" makes the page public, which is the point of the exercise.
# Narrow to your own IP/CIDR to keep it private.
variable "allowed_http_source" {
  description = "Source allowed to reach port 80."
  type        = string
  default     = "Internet"
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

# Must be a PUBLIC repo — cloud-init pulls without credentials.
variable "container_image" {
  description = "Docker Hub image each instance pulls and runs."
  type        = string

  # An untagged image resolves to :latest, so a replacement instance could
  # serve different content from the ones beside it.
  validation {
    condition     = can(regex(":[^:/]+$", var.container_image))
    error_message = "container_image must carry an explicit tag."
  }
}

# Also the autoscale minimum — the minimum is what rebuilds a deleted instance.
variable "instance_count" {
  description = "Starting instance count."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 2
    error_message = "instance_count must be >= 2 for n+1 redundancy."
  }
}

# max x vCPUs-per-SKU must fit the subscription's regional vCPU quota, or a
# scale-out is rejected by Azure and the rule can never succeed.
variable "instance_count_max" {
  description = "Autoscale maximum."
  type        = number
  default     = 2
}

# B2ats_v2 is x86-64, 2 vCPU / 1 GiB, and had capacity in Australia East where
# Standard_B1s did not. Avoid Bpsv2 sizes — those are ARM64 and the amd64
# container image fails on them with an exec format error.
variable "vm_sku" {
  description = "VM size for scale set instances."
  type        = string
  default     = "Standard_B2ats_v2"
}

# Standard_LRS is cheaper but boots slower, which lengthens healing time.
variable "os_disk_type" {
  description = "OS disk storage account type."
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

# Azure requires a key to create a Linux VM, but there is no inbound SSH rule
# and no public IP on the instances — so this cannot actually be used for
# access. Debug via `az vmss run-command invoke`.
variable "admin_ssh_public_key" {
  description = "SSH public key for the admin user. Must be ssh-rsa."
  type        = string

  # Checks the key data, not just the prefix — a prefix-only check lets a
  # placeholder through, and the provider then fails with an opaque
  # "decoding public key data" error at plan time.
  validation {
    condition = can(regex(
      "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/]{60,}={0,3}( .*)?$",
      var.admin_ssh_public_key
    ))
    error_message = "admin_ssh_public_key must be a complete OpenSSH public key, not a path or placeholder."
  }
}

# Empty means regional allocation, which is the default because B-series sizes
# often have no zonal capacity. Set to ["1", "2", "3"] if your vm_sku does.
variable "availability_zones" {
  description = "Zones to spread scale set instances across."
  type        = list(string)
  default     = []
}

# Separate from availability_zones on purpose: a public IP has no compute
# capacity constraint, so the frontend stays zone-redundant even when the
# instances fall back to regional allocation.
variable "lb_frontend_zones" {
  description = "Zones for the load balancer public IP."
  type        = list(string)
  default     = ["1", "2", "3"]
}
