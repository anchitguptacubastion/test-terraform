#################################
# PROVIDER
#################################
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

#################################
# VARIABLES
#################################

variable "resource_group_name" {}
variable "location" {
  default = "Central India"
}

#################################
# POLICY DEFINITIONS
#################################

# Mandatory Tags
resource "azurerm_policy_definition" "mandatory_tags" {
  name         = "mandatory-tags"
  policy_type = "Custom"
  mode        = "Indexed"
  display_name = "Require Business Unit and Cost Center tags"

  policy_rule = jsonencode({
    if = {
      anyOf = [
        { field = "tags['Business Unit']", exists = "false" },
        { field = "tags['Cost Center']", exists = "false" }
      ]
    }
    then = { effect = "deny" }
  })
}

# No Public IP on NIC
resource "azurerm_policy_definition" "deny_public_ip_nic" {
  name         = "deny-public-ip-nic"
  policy_type = "Custom"
  mode        = "All"
  display_name = "Deny Public IP on NIC"

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Network/networkInterfaces" },
        { field = "Microsoft.Network/networkInterfaces/ipConfigurations[*].publicIpAddress.id", exists = "true" }
      ]
    }
    then = { effect = "deny" }
  })
}

# Allowed Locations
resource "azurerm_policy_definition" "allowed_locations" {
  name         = "allowed-locations"
  policy_type = "Custom"
  mode        = "All"
  display_name = "Allowed Locations Policy"

  policy_rule = jsonencode({
    if = {
      not = {
        field = "location"
        in = ["centralindia", "southindia"]
      }
    }
    then = { effect = "deny" }
  })
}

#################################
# POLICY ASSIGNMENTS
#################################
resource "azurerm_policy_assignment" "mandatory_tags" {
  name                 = "mandatory-tags-assignment"
  policy_definition_id = azurerm_policy_definition.mandatory_tags.id
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

resource "azurerm_policy_assignment" "deny_public_ip" {
  name                 = "deny-public-ip-nic-assignment"
  policy_definition_id = azurerm_policy_definition.deny_public_ip_nic.id
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

resource "azurerm_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations-assignment"
  policy_definition_id = azurerm_policy_definition.allowed_locations.id
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

#################################
# VNET
#################################
resource "azurerm_virtual_network" "vnet" {
  name                = "core-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.0.0.0/16"]

  tags = {
    "Business Unit" = "IT"
    "Cost Center"   = "1234"
  }
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
# ACR
#################################
resource "azurerm_container_registry" "acr" {
  name                = "acrdevopsdemo123"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Premium"
  admin_enabled       = false
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

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = ["Get", "Set", "List"]
  }

  tags = {
    "Business Unit" = "IT"
    "Cost Center"   = "1234"
  }
}

#################################
# POSTGRES FLEXIBLE SERVER
#################################
resource "azurerm_postgresql_flexible_server" "psql" {
  name                   = "employee-psql"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "16"
  delegated_subnet_id    = azurerm_subnet.psql.id
  private_dns_zone_id    = null
  administrator_login    = "pgadmin"
  administrator_password = "Password@123!"

  storage_mb = 32768
  sku_name   = "B_Standard_B1ms"

  tags = {
    "Business Unit" = "IT"
    "Cost Center"   = "1234"
  }
}

resource "azurerm_postgresql_flexible_server_database" "employee_db" {
  name      = "employee"
  server_id = azurerm_postgresql_flexible_server.psql.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

#################################
# AKS (PRIVATE)
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
  }

  tags = {
    "Business Unit" = "IT"
    "Cost Center"   = "1234"
  }
}

#################################
# ACI (VNET INTEGRATED)
#################################
resource "azurerm_container_group" "aci" {
  name                = "employee-aci"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_address_type     = "Private"
  os_type             = "Linux"
  subnet_ids          = [azurerm_subnet.aci.id]

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

  tags = {
    "Business Unit" = "IT"
    "Cost Center"   = "1234"
  }
}


