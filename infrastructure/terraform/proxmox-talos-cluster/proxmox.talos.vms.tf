#---- VM definitions

locals {
  talos_gateway = "10.1.0.1"

  talos_vms = {

    ## Control Plane Nodes

    cp_1 = {
      hostname   = "talos-cp-1"
      tags       = ["k8s-control-plane", "talos"]
      ip_address = "10.1.0.11/24"
      cpu_cores  = 4
      memory     = { dedicated = 2048, floating = 2048 } # Avoid using lower floating memory as it just confuses k8s
      disks      = [{ interface = "scsi0", size = 20 }]
    }
    cp_2 = {
      hostname   = "talos-cp-2"
      tags       = ["k8s-control-plane", "talos"]
      ip_address = "10.1.0.12/24"
      cpu_cores  = 4
      memory     = { dedicated = 2048, floating = 2048 } # Avoid using lower floating memory as it just confuses k8s
      disks      = [{ interface = "scsi0", size = 20 }]
    }
    cp_3 = {
      hostname   = "talos-cp-3"
      tags       = ["k8s-control-plane", "talos"]
      ip_address = "10.1.0.13/24"
      cpu_cores  = 4
      memory     = { dedicated = 2048, floating = 2048 } # Avoid using lower floating memory as it just confuses k8s
      disks      = [{ interface = "scsi0", size = 20 }]
    }

    ## Worker Nodes

    worker_1 = {
      hostname   = "talos-worker-1"
      tags       = ["k8s-worker", "talos"]
      ip_address = "10.1.0.21/24"
      cpu_cores  = 4
      memory     = { dedicated = 4096, floating = 4096 } # Avoid using lower floating memory as it just confuses k8s
      disks = [
        { interface = "scsi0", size = 30 },  # OS Disk
        { interface = "scsi1", size = 100 }, # Data Disk
      ]
    }
    worker_2 = {
      hostname   = "talos-worker-2"
      tags       = ["k8s-worker", "talos"]
      ip_address = "10.1.0.22/24"
      cpu_cores  = 4
      memory     = { dedicated = 4096, floating = 4096 } # Avoid using lower floating memory as it just confuses k8s
      disks = [
        { interface = "scsi0", size = 30 },  # OS Disk
        { interface = "scsi1", size = 100 }, # Data Disk
      ]
    }
    worker_3 = {
      hostname   = "talos-worker-3"
      tags       = ["k8s-worker", "talos"]
      ip_address = "10.1.0.23/24"
      cpu_cores  = 4
      memory     = { dedicated = 4096, floating = 4096 } # Avoid using lower floating memory as it just confuses k8s
      disks = [
        { interface = "scsi0", size = 30 },  # OS Disk
        { interface = "scsi1", size = 100 }, # Data Disk
      ]
    }
  }
}

#------ Create VMs

resource "proxmox_virtual_environment_vm" "talos_vm" {
  for_each = local.talos_vms

  name        = each.value.hostname
  description = "Managed by Terraform. Talos ${contains(each.value.tags, "k8s-control-plane") ? "Control Plane" : "Worker"} Node"
  tags        = each.value.tags
  node_name   = var.proxmox_node
  on_boot     = false
  started     = true

  #scsi_hardware = "virtio-scsi-single"
  scsi_hardware = "virtio-scsi-pci"
  machine       = "q35"
  operating_system {
    type = "l26"
  }

  # Stop the VM before destroying it (default is shutdown which takes longer and doesn't always work)
  stop_on_destroy = true

  boot_order = ["scsi0", "ide2"] # boot from cdrom only if OS hasn't been installed
  bios       = "ovmf"
  efi_disk {
    datastore_id      = "local-lvm"
    file_format       = "raw"
    pre_enrolled_keys = false # talos ISO isn't signed by the standard keys
    type              = "4m"
  }

  agent {
    # read 'Qemu guest agent' section, change to true only when ready
    enabled = true
    trim    = true
  }

  cpu {
    sockets = 1
    cores   = each.value.cpu_cores
    type    = "x86-64-v3"
    #flags        = []
    #hotplugged   = 0
    #limit        = 0
    #numa         = false
    #units        = 0
  }

  memory {
    dedicated = each.value.memory.dedicated
    floating  = each.value.memory.floating
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id #e.g. local:iso/talos-1.13.5.iso
    interface = "ide2"
  }

  dynamic "disk" {
    for_each = each.value.disks
    content {
      datastore_id = "local-lvm"
      discard      = "on"
      file_format  = "raw"
      interface    = disk.value.interface
      size         = disk.value.size #in GB
    }
  }

  network_device {
    bridge   = proxmox_sdn_vnet.talos_sdn_vnet.id
    firewall = true
  }

  initialization {
    datastore_id = "local-lvm"
    interface    = "ide0"
    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = local.talos_gateway
      }
    }
  }

  #hook_script_file_id
  # (Optional) The identifier for a file containing a hook script (needs to be executable,
  # e.g. by using the proxmox_virtual_environment_file.file_mode attribute).

}


# ------ Output

output "talos_vm_info" {
  description = "Hostname and IP address of each Talos VM."
  value = {
    for k, v in proxmox_virtual_environment_vm.talos_vm : k => {
      hostname = v.name
      ip       = split("/", v.initialization[0].ip_config[0].ipv4[0].address)[0]
      role     = contains(v.tags, "k8s-control-plane") ? "Control Plane" : "Worker"
    }
  }
}