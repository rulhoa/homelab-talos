resource "proxmox_download_file" "talos_iso" {
  node_name          = var.proxmox_node
  content_type       = "iso"
  datastore_id       = "local"
  
  # Don't use the metal*.iso as it doesn't support cloudinit.
  # Use https://factory.talos.dev to generate the Talos ISO with the following options:
  #  hardware type: cloud server
  #  talos version: latest
  #  cloud server: nocloud
  #  system extensions: qemu-guest-agent
  #  bootloader: auto
  url                = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.13.5/nocloud-amd64.iso"
  file_name          = "talos-1.13.5.iso"
}