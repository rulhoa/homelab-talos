# Architecture

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

### Virtualization

Proxmox is an open-source virtualization platform based on KVM and used in enterprise and homelab settings.

I used my pre-existing local Proxmox cluster to setup this project.

### IaC

Terraform was picked for convenience, but the used syntax and provider are also applicable for those that prefer to use OpenTofu.

### Kubernetes (k8s)

Talos OS is an immutable Linux distribution optimized for provisioning kubernetes.

This means that it is lightweight, SSH and shell are not available, the OS filesystem can't be changed, and no package managers are included.

This makes provisioning it much more secure and predictable in relation to other distributions of Linux and K8S. Node version upgrades are actually reinstallations using a newer ISO, which must include all desired Linux extensions (drivers, libraries, etc) and customizations.

All management must be done via authenticated API, which the "talosctl" command utilizes and follows the "every-as-code" mindset.

#### Container Runtime Interface (CRI)

Used the Talos default of **containerd** as it's sufficient for all but specialized workloads.

#### Container Network Interface (CNI)

This is for the internal network between k8s nodes

**CNI**: Cilium for eBPF native routing. kube-proxy disabled

- **Hubble**: Cilium observability

The default **kube-proxy** is great for small labs, but doesn't scale in enterprise settings
Calico, Flannel, Cilium, and Canal.


### Ingress & Services

- **Load Balancer**: MetalLB (Layer 2 advertisement)

Future plan:

- **Ingress Controller**: Traefik

### Storage Layer (CSI)

**Engine**: Longhorn distributed block storage:

- Picked for simplicity. Important to note that Longhorn can't reliably handle high workloads.
- Production environments we would use Ceph or OpenEBS

Setup:

- **Disk**: Dedicated storage disk on each node
- **Replication**: 3 replicas across nodes
- **Storage Overcommit**: 500%
  - Not expecting all services to fully use allocated space.
  - This is a study lab and right sizing is not a priority.

## Disclaimers

> [!IMPORTANT]
> This cluster should NOT be exposed to the Internet.
> Its goal is for homelabbing for studying purposes, and internet facing service require additional security measures and tools beyond the scope of this project.

## Cluster Topology

All nodes configured as control planes and workers to save resources.

Segregated network for cluster is 10.2.0.0/24

- 10.2.0.1: network gateway
- 10.2.0.10: Cluster's VIP (virtual IP)
- 10.2.0.11-49: IPs for nodes
- 10.2.0.50-250: IPs for pod LoadBalancer services

> [!TIP]
> Choices were made to make it easier to remember IP roles at-a-glance, and simplify administration.
> An enterprise deployment would segregate IP roles into different private and public networks.

## Node configurations

Nodes are VMs running in Proxmox.

VM naming convention in Proxmox:

- k8s.node\[IP\]
  - IP: last octet number (e.g. 10 for 10.2.0.10).
  - e.g.: k8s.node10

Node DNS names:

- node\[ip\].k8s.internal.\[my-domain\].com

Node hostname:

- node\[ip\]

All nodes have the same configuration

- vCPU 4
- RAM 8192 MB
- Disk
  - OS: 32 GB
  - Storage: 32GB
