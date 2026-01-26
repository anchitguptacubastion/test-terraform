#################################
# TERRAFORM
#################################
terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
  }
}

#################################
# PROVIDER
#################################
provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

locals {
  subscription_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"

  tags = {
    "Business Unit" = "IT"
    "Cost Center"   = "1234"
  }
}

#################################
# VARIABLES
#################################
variable "resource_group_name" {}
variable "location" {
  default = "Central India"
}

#################################
# EXISTING POLICIES (DATA ONLY)
#################################
data "azurerm_policy_definition" "mandatory_tags" {
  name = "mandatory-tags"
}

data "azurerm_policy_definition" "deny_public_ip_nic" {
  name = "deny-public-ip-nic"
}

data "azurerm_policy_definition" "allowed_locations" {
  name = "allowed-locations"
}

#################################
# POLICY ASSIGNMENTS
#################################
resource "azurerm_subscription_policy_assignment" "mandatory_tags" {
  name                 = "mandatory-tags-assignment"
  policy_definition_id = data.azurerm_policy_definition.mandatory_tags.id
  subscription_id      = local.subscription_id
}

resource "azurerm_subscription_policy_assignment" "deny_public_ip" {
  name                 = "deny-public-ip-nic-assignment"
  policy_definition_id = data.azurerm_policy_definition.deny_public_ip_nic.id
  subscription_id      = local.subscription_id
}

resource "azurerm_subscription_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations-assignment"
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id
  subscription_id      = local.subscription_id
}

#################################
# ACR
#################################
resource "azurerm_container_registry" "acr" {
  name                = "acrdevopsdemo123"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Premium"
  admin_enabled       = false
  tags                = local.tags
}

#################################
# NETWORK
#################################
resource "azurerm_virtual_network" "vnet" {
  name                = "core-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "aci" {
  name                 = "aci-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "aci"
    service_delegation {
      name = "Microsoft.ContainerInstance/containerGroups"
    }
  }
}

resource "azurerm_subnet" "psql" {
  name                 = "psql-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]

  delegation {
    name = "psql"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
    }
  }
}

#################################
# PRIVATE DNS
#################################
resource "azurerm_private_dns_zone" "psql" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "psql" {
  name                  = "psql-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.psql.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

#################################
# AKS
#################################
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "private-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "privateaks"
  private_cluster_enabled = true

  default_node_pool {
    name           = "system"
    node_count     = 2
    vm_size        = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.1.0.0/16"
    dns_service_ip = "10.1.0.10"
  }

  tags = local.tags
}

#################################
# ACI
#################################
resource "azurerm_container_group" "aci" {
  name                = "employee-aci"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_address_type     = "Private"
  os_type             = "Linux"
  subnet_ids          = [azurerm_subnet.aci.id]
  tags                = local.tags

  container {
    name   = "employee"
    image  = "nginx"
    cpu    = 0.5
    memory = 1

    ports {
      port     = 80
      protocol = "TCP"
    }
  }
}

#################################
# POSTGRES
#################################
resource "azurerm_postgresql_flexible_server" "psql" {
  name                   = "employee-psql"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "16"
  delegated_subnet_id    = azurerm_subnet.psql.id
  private_dns_zone_id    = azurerm_private_dns_zone.psql.id
  administrator_login    = "pgadmin"
  administrator_password = "Password@123!"
  sku_name               = "B_Standard_B1ms"
  storage_mb             = 32768
  tags                   = local.tags
}

resource "azurerm_postgresql_flexible_server_database" "employee_db" {
  name      = "employee"
  server_id = azurerm_postgresql_flexible_server.psql.id
}

#################################
# KEY VAULT
#################################
resource "azurerm_key_vault" "kv" {
  name                        = "kv-devops-demo"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = true
  soft_delete_retention_days  = 7
  tags                        = local.tags

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "Set", "List"]
  }
}


