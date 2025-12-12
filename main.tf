resource "azurerm_kubernetes_cluster" "k8s" {
  location            = "West Europe"
  name                = "aks123423"
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
