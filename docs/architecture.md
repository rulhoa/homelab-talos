# Architecture

## Stack

- **Virtualization:** [Proxmox](https://www.proxmox.com/en/)
- **IaC:** [Terraform](https://developer.hashicorp.com/terraform)
- **Kubernetes distribution:** [Talos OS](https://docs.siderolabs.com/talos/v1.13/overview/what-is-talos)
  - **Container Runtime Interface (CRI):** containerd (Talos default)
  - **Container Network Interface (CNI):** [Cilium](https://docs.cilium.io/en/stable/overview/intro/)
  - **Container Storage Interface (CSI):** Longhorn
- **Load Balancer:**  [Cilium LB IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/) (planned)
- **Ingress:** Traefik (planned)
- **Metrics:** Metrics Server

## Virtualization

Proxmox is an open-source virtualization platform based on KVM and used in enterprise and homelab settings.

I used my pre-existing local Proxmox cluster to setup this project.

## IaC

Terraform was picked for convenience, but the used syntax and provider are also applicable for those that prefer to use OpenTofu.

## Kubernetes (k8s)

Talos OS (by Sidero) is an immutable Linux distribution optimized for provisioning kubernetes.

Immutable means that the OS filesystem can't be changed after installation, and it also doesn't contain any package manager, terminal, or SSH access. All management must be done via authenticated API, which the "talosctl" command utilizes and follows the GotOps "everything-as-code" mindset. Node version upgrades are actually reinstallations using a newer ISO, which must include all desired Linux extensions (drivers, libraries, etc) and customizations.

Optimized means that it is lightweight, more secure, and predictable in relation to other distributions of Linux and K8S.

### Container Runtime Interface (CRI)

Used the Talos default of **containerd** as it's sufficient for all but specialized workloads.

## Networking

### Container Network Interface (CNI)

This is for the internal network between k8s nodes.

The default **kube-proxy** (although no technically a CNI) is great for small labs, but doesn't scale in enterprise settings, and it can be easily disabled in favor of using, as I picked, **Cilium** due to native eBPF routing.

Other alternatives are Flannel, Calico, kube-router, and Multus (among others) as described in the [Sidero kubernetes guide documentation](https://docs.siderolabs.com/kubernetes-guides/overview/kubernetes-guides-overview).

As a bonus, Cilium comes with **Hubble** that provides observability of Cilium itself.

### Ingress & Services

Future plan:

- **Load Balancer**: [Cilium LB IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/)
- **Ingress Controller**: Traefik
- **Gateway API**

## Storage Layer (CSI)

**Engine**: Longhorn distributed block storage:

- Picked for simplicity. Important to note that Longhorn can't reliably handle high workloads.
- Production environments would use Ceph or OpenEBS

Setup:

- **Disk**: Dedicated storage disk on each worker node
- **Replication**: 3 replicas across nodes
- **Storage Overcommit**: 500%
  - Not expecting all services to fully use allocated space.
  - This is a study lab and right sizing is not a priority.

## Cluster Topology

Segregated network for cluster is 10.1.0.0/24

- 10.1.0.1: network gateway
- 10.1.0.10: Cluster's VIP (virtual IP)
- 10.1.0.11-19: Control Plane node IPs
- 10.1.0.21-100: Worker node IPs

A second network for LoadBalancer services are available in 10.1.1.0/24 with gateway 10.1.1.1

> [!TIP]
> Choices were made to make it easier to remember IP roles at-a-glance, and simplify administration.
> An enterprise deployment may segregate IP roles into different private and public networks.

## Disclaimers

> [!IMPORTANT]
> This cluster should NOT be exposed to the Internet.
> Its goal is for homelabbing for studying purposes, and internet facing service require additional security measures and tools beyond the scope of this project.
