variable "proxmox_api_url" {
  description = "The URL for the Proxmox API"
  type        = string
  sensitive   = false
}

variable "proxmox_api_token" {
  description = "API Token"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox Node name"
  type        = string
  sensitive   = false
  default = "pve"
}