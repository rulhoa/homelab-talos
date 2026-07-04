# Homelab: Talos Kubernetes Cluster

Homelab deployment of a Kubernetes cluster using Talos OS on Proxmox.

The infrastructure on Proxmox is provisioned using IaC with Terraform.
The Talos cluster configurations are done with talosctl, kubectl, and helm.

## Stack

- **Virtualization:** [Proxmox](https://www.proxmox.com/en/)
- **IaC:** [Terraform](https://developer.hashicorp.com/terraform)
- **Kubernetes distribution:** [Talos OS](https://docs.siderolabs.com/talos/v1.13/overview/what-is-talos)
  - **Container Runtime Interface (CRI):** containerd (Talos default)
  - **Container Network Interface (CNI):** [Cilium](https://docs.cilium.io/en/stable/overview/intro/)
  - **Container Storage Interface (CSI):** Longhorn
- **Load Balancer:** MetalLB (planned to be replaced with [Cilium LB IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/))
- **Ingress:** Traefik (planned)
- **Metrics:** Metrics Server

## Requirements

- A pre-configured Proxmox 9.1+ cluster.
  - Only 1 node is sufficient
- A Linux VM to run commands from
  - On Windows, wsl works great!
  - This VM must have access to proxmox and the Talos VMs (and network) that will be provisioned

## Docs

- [Architecture](docs/architecture.md) - topology, node specs, component choices.
- [Deployment](docs/deployment.md) - Step-by-step deployment instructions.
- [Runbook](docs/runbook.md) - Additional operational and troubleshooting procedures.
