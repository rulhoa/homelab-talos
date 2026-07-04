terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  insecure = false
  api_token = var.proxmox_api_token
  
  random_vm_ids = true
  random_vm_id_start = 1000
  random_vm_id_end   = 9999
}
