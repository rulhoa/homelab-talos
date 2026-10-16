#----- SDN Zones


#resource "proxmox_sdn_zone_simple" "talos_sdn" {
#  id    = "talos"
#  nodes = []
#  # Use [] to apply to all nodes
#  # for ['node-name'] to apply to a specific list of nodes

#   #mtu   = 1500 #optional

#   dhcp = "dnsmasq" # Enable automatic DHCP by proxmox
#   ipam = "pve" # Use Proxmox built-in IPAM to manage IP addresses

#   depends_on = [
#     proxmox_sdn_applier.finalizer
#   ]
# }

# resource "proxmox_sdn_zone_evpn" "talos_sdn" {
#   id    = "talos"
#   nodes = []
#   # Use [] to apply to all nodes
#   # for ['node-name'] to apply to a specific list of nodes
#   controller = "evpn-controller1"
#   vrf_vxlan  = 10000

#   advertise_subnets          = true
#   disable_arp_nd_suppression = true
#   exit_nodes                 = ["prox", "prox2"]
#   exit_nodes_local_routing   = false
#   #primary_exit_node          = "pve-exit1"
#   #rt_import                  = "65000:65000"
#   mtu                        = 1450

#   ipam = "pve" # Use Proxmox built-in IPAM to manage IP addresses

#   depends_on = [
#     proxmox_sdn_applier.finalizer
#   ]
# }


#----- VNets and subnets

# Basic VNet (Simple)
resource "proxmox_sdn_vnet" "talos_sdn_vnet" {
  id   = "talos1"
  # zone = proxmox_sdn_zone_evpn.talos_sdn.id
  zone = "evpn"
  alias = "Talos Cluster 1"
  isolate_ports = false
  vlan_aware    = false
  tag           = 10003 

  depends_on = [
    proxmox_sdn_applier.finalizer
  ]
}

resource "proxmox_sdn_subnet" "talos_sdn_vnet_subnet0" {
  cidr    = "10.1.0.0/24"
  vnet    = proxmox_sdn_vnet.talos_sdn_vnet.id
  gateway = "10.1.0.1"

  dhcp_range = {
    start_address = "10.1.0.100"
    end_address = "10.1.0.150"
  }

  depends_on = [
    proxmox_sdn_applier.finalizer
  ]
}

resource "proxmox_sdn_subnet" "talos_sdn_vnet_subnet1" {
  cidr    = "10.1.1.0/24"
  vnet    = proxmox_sdn_vnet.talos_sdn_vnet.id
  gateway = "10.1.1.1"

  depends_on = [
    proxmox_sdn_applier.finalizer
  ]
}



#----- Applies SDN updates (create/delete)

resource "proxmox_sdn_applier" "applier" {
  # lifecycle {
  #   replace_triggered_by = [
  #     proxmox_sdn_zone_evpn.talos_sdn
  #   ]
  # }

  # Every SDN change that requires a reapply if changed need to be added to this list:
  # SDN
  # vnet
  # subnet
  depends_on = [
    # proxmox_sdn_zone_evpn.talos_sdn,
    proxmox_sdn_vnet.talos_sdn_vnet,
    proxmox_sdn_subnet.talos_sdn_vnet_subnet0,
    proxmox_sdn_subnet.talos_sdn_vnet_subnet1
  ]
}

resource "proxmox_sdn_applier" "finalizer" {
}