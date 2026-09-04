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

variable "address_space" {
  description = "VNet address space."
  type        = list(string)
}

variable "web_subnet_prefix" {
  description = "Address prefix for the web subnet."
  type        = string
}

variable "allowed_http_source" {
  description = "Source address prefix or service tag allowed to reach port 80."
  type        = string
  default     = "Internet"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
