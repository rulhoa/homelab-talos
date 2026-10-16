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
  url                = "https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.14.2/nocloud-amd64.iso"
  file_name          = "talos-1.14.2.iso"
}