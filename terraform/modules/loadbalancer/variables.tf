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

variable "frontend_zones" {
  description = <<-EOT
    Zones for the public IP. Listing more than one makes it zone-redundant, so
    the frontend survives a zone failure. Empty means no zone guarantee.
  EOT
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
