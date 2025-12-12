resource "azurerm_kubernetes_cluster" "k8s" {
  location            = "West Europe"
  name                = "aks1234"
  resource_group_name = "test1"
  dns_prefix          = "dns"

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name       = "agentpool"
    vm_size    = "Standard_D2_v2"
    node_count = 1
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }
}


resource "random_pet" "rg_name" {
  prefix = var.resource_group_name_prefix
}

resource "azurerm_resource_group" "rg" {
  name     = random_pet.rg_name.id
  location = var.resource_group_location
}

resource "random_string" "container_name" {
  length  = 25
  lower   = true
  upper   = false
  special = false
}

resource "azurerm_container_group" "container" {
  name                = ""
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Public"
  os_type             = "Linux"
  restart_policy      = var.restart_policy
  zones               = var.zone != "" ? [ var.zone ] : null

  container {
    name   = "${var.container_name_prefix}-${random_string.container_name.result}"
    image  = var.image
    cpu    = 1
    memory = 4

    ports {
      port     = 80
      protocol = "TCP"
    }
  }
}

resource "azurerm_container_registry" "example" {
  name = docker"
  resource_group_name = "test1"
  location = "West Europe"
  sku = "Basic"
}





# Manages the Virtual Network
resource "azurerm_virtual_network" "default" {
  address_space       = ["10.0.0.0/16"]
  location            = "West Europe"
  name                = "vnet-test123"
  resource_group_name = "test1"

# Manages the Subnet
resource "azurerm_subnet" "default" {
  address_prefixes     = ["10.0.2.0/24"]
  name                 = "subnet-test123"
  resource_group_name  = "test1"
  virtual_network_name = "vnet-test1"
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "fs"

    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Enables you to manage Private DNS zones within Azure DNS
resource "azurerm_private_dns_zone" "default" {
  name                = "test1123.mysql.database.azure.com"
  resource_group_name = "test1"
}

# Enables you to manage Private DNS zone Virtual Network Links
resource "azurerm_private_dns_zone_virtual_network_link" "default" {
  name                  = "mysqlfsVnetZonetest12344.com"
  private_dns_zone_name = azurerm_private_dns_zone.default.name
  resource_group_name   = "test1"
  virtual_network_id    = azurerm_virtual_network.default.id

  depends_on = [azurerm_subnet.default]
}

# Manages the MySQL Flexible Server
resource "azurerm_mysql_flexible_server" "default" {
  location                     = "West Europe"
  name                         = "mysqlfs-123412"
  resource_group_name          = "test1"
  administrator_login          = "sadmin"
  administrator_password       = "j\T160K/zMfa"
  backup_retention_days        = 7
  delegated_subnet_id          = azurerm_subnet.default.id
  geo_redundant_backup_enabled = false
  private_dns_zone_id          = azurerm_private_dns_zone.default.id
  sku_name                     = "GP_Standard_D2ds_v4"
  version                      = "8.0.21"

  high_availability {
    mode                      = "SameZone"
  }
  maintenance_window {
    day_of_week  = 0
    start_hour   = 8
    start_minute = 0
  }
  storage {
    iops    = 360
    size_gb = 20
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.default]
}