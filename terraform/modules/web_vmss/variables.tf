variable "suffix" {
  description = "Naming suffix: {workload}-{env}-{loc}-{instance}."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the instances join."
  type        = string
}

variable "backend_address_pool_id" {
  description = "Load balancer backend pool the instances register into."
  type        = string
}

variable "health_probe_id" {
  description = <<-EOT
    Load balancer probe used for instance health. Required for
    automatic_instance_repair — without it the repair policy has no signal and
    never fires.
  EOT
  type        = string
}

variable "container_image" {
  description = "Docker Hub image to pull and run on each instance."
  type        = string
}

variable "vm_sku" {
  description = "VM size."
  type        = string
  default     = "Standard_B1s"
}

variable "os_disk_type" {
  description = "OS disk storage account type."
  type        = string
  default     = "StandardSSD_LRS"
}

variable "instance_count" {
  description = "Initial and minimum instance count."
  type        = number
  default     = 2
}

variable "instance_count_max" {
  description = "Autoscale maximum."
  type        = number
  default     = 4
}

variable "admin_username" {
  description = "Admin username."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "OpenSSH public key for the admin user."
  type        = string
}

variable "zones" {
  description = "Availability zones to spread instances across."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
