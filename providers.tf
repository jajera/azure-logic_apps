terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.10.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">=3.1.2"
    }
  }
}

provider "azurerm" {
  features {}
}
