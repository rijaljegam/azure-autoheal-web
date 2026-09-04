terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Local state by design — this is a single-operator personal stack. For
  # anything shared, move to an azurerm backend so state is locked and not
  # sitting on one laptop.
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate-prd-aue-001"
  #   storage_account_name = "sttfstateprdaue001"
  #   container_name       = "tfstate"
  #   key                  = "autoheal-web.tfstate"
  # }
}

provider "azurerm" {
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

  # By default the provider attempts to register ~60 Azure resource providers on
  # every run, which is slow on a fresh subscription and fails outright if the
  # calls time out. This stack needs exactly three, registered once by hand:
  #
  #   az provider register --namespace Microsoft.Network
  #   az provider register --namespace Microsoft.Compute
  #   az provider register --namespace Microsoft.Insights
  #
  # If a resource later fails with "API version ... was not found for
  # Microsoft.Foo", that namespace needs registering too — the error is
  # misleading, it means unregistered rather than unsupported.
  resource_provider_registrations = "none"

  features {
    resource_group {
      # Refuse to delete a resource group that still contains resources
      # Terraform does not know about.
      prevent_deletion_if_contains_resources = true
    }
  }
}
