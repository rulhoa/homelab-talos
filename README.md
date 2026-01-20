# Homelab: Talos Kubernetes Cluster

> [!IMPORTANT]
> This cluster setup does not prioritise security and is not (and should not be) exposed to the Internet.
> Its goal is for homelabbing for studying purposes.


## Cluster Topology

All nodes configured as control planes and workers to save resources.

Segregated network for cluster is 10.2.0.0/24

- 10.2.0.1: network gateway
- 10.2.0.10: Cluster's VIP (virtual IP)
- 10.2.0.11-49: IPs for nodes
- 10.2.0.50-250: IPs for pod LoadBalancer services

obs: choices were made to make it easier to remember IP roles at-a-glance.

## Node configurations

Nodes are VMs running in Proxmox.

VM naming convention in Proxmox:

- k8s.node\[IP\]
  - IP: last octet number (e.g. 10 for 10.2.0.10).
  - e.g.: k8s.node10

Node DNS names:
- node\[ip\].k8s.internal.\[my-domain\].com

Node hsotname:
- node\[ip\]


All nodes have the same configuration

- vCPU 4
- RAM 8192 MB
- Disk
  - OS: 32 GB
  - Storage: 32GB

## Component Stack

### Networking Layer

- **Service VIP**: kube-vip (managed by control plane nodes)

Future plan:
- **CNI**: Cilium with eBPF and native routing. kube-proxy disabled.
  - **Hubble**: Cilium observability



### Ingress & Services

- **Ingress Controller**: Traefik
- **Load Balancer**: MetalLB (Layer 2 advertisement)

### Storage Layer

- **Engine**: Longhorn distributed block storage
- **Disk**: Dedicated storage disk on each node
- **Replication**: 3 replicas across nodes
- **Storage Overcommit**: 500%
  - Not expecting all services to fully use allocated space.
  - This is a study lab and right sizing is not a priority.

## Deployment Steps


1. Install talosctl

```shell
curl -sL https://talos.dev/install | sh
```

1. generate dns record

k8s.internal.salesulhoa.com  IN  A  192.168.0.10
k8s.internal.salesulhoa.com  IN  A  192.168.0.11
k8s.internal.salesulhoa.com  IN  A  192.168.0.12



2. generate config files


```shell
talosctl gen secrets -o secrets.yaml

talosctl gen config talos https://k8s.internal.salesulhoa.com:6443 --install-image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.1 --dns-domain k8s.internal.salesulhoa.com --with-secrets secrets.yaml
```





```shell
talosctl config merge ./talosconfig

talosctl config endpoint 10.2.0.11 10.2.0.12 10.2.0.13
talosctl config node 10.2.0.11 10.2.0.12 10.2.0.13

```

2. Download Talos ISO

```shell
curl https://github.com/siderolabs/talos/releases/download/v1.12.1/metal-amd64.iso -L -o talos-v1.12.1.iso
```

or

use proxmox UI to download the ISO directly and save to ISO storage.

obs: v1.12.1 was released on 2026-01-05 and was the latest stable release on 2026-01-14


Your image schematic ID is: 88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b
https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.12.1/nocloud-amd64.iso

obs: nocloud is the recommended for onprem virtualization.

https://factory.talos.dev/?arch=amd64&bootloader=auto&cmdline-set=true&extensions=-&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Fqemu-guest-agent&extensions=siderolabs%2Futil-linux-tools&platform=nocloud&target=cloud&version=1.12.1

```yaml
customization:
    systemExtensions:
        officialExtensions:
            - siderolabs/iscsi-tools
            - siderolabs/qemu-guest-agent
            - siderolabs/util-linux-tools
```



3. Provision VMs

| Setting   | Used values       | Notes            |
| --------- | ----------------- | ---------------- |
|BIOS       | SeaBIOS	                                    | Security is a minor concern. Otherwise we would be using UEFI |
|Machine	| q35	                                        | Modern PCIe-based machine type with better device support |
|Qemu Agent | enabled                                       | |
|CPU Type	| host	                                        | Enables advanced instruction sets (AVX-512, etc.), best performance. Obs: May prevent live-migration in the future |
|CPU Cores	| 8 cores                                       | Minimum 2 cores required |
|Memory	    | 8GB	                                        | Minimum 2GB required |
|Disk Controller | VirtIO SCSI (NOT “VirtIO SCSI Single”)   | Single controller can cause bootstrap hangs (#11173) |
|Disk Format | Raw (performance) or QCOW2 (features/snapshots) | Raw preferred for performance |
|Disk Cache  | No Cache (Default)                           | My proxmox server doesn't have an UPS, so no caching reducing potential performance but minimizes risk of dataloss |
|Disk features | Discard enabled                            | |
|Network Model | virtio                                     | Paravirtualized driver, best performance (up to 10 Gbit) |
|Memory  | Ballooning Disabled | Talos doesn’t support memory hotplug |

Reference: <https://docs.siderolabs.com/talos/v1.12/platform-specific-installations/virtualized-platforms/proxmox>

Boot using talos ISO.

NTP server: a.st1.ntp.br

4. Take note of VM's IP

5. Applying

```shell
talosctl apply-config --insecure --nodes 10.2.0.11 --file controlplane.yaml
talosctl apply-config --insecure --nodes 10.2.0.12 --file controlplane.yaml
talosctl apply-config --insecure --nodes 10.2.0.13 --file controlplane.yaml


talosctl bootstrap --nodes 10.2.0.11

# Wait a few minutes and check console for when node is healthy

# update kubeconfig file for use with kubectl
talosctl kubeconfig --nodes 10.2.0.11

kubectl get nodes

```

6. Patch Virtual IP

```shell
talosctl machineconfig patch controlplane.yaml -p controlplane-patch1-enable-vip.yaml -o controlplane-v2.yaml

talosctl apply-config --nodes 10.2.0.11,10.2.0.12,10.2.0.13 --file controlplane-v2.yaml
```











## Additional commands

### /dev/sda not being found

As per the talos documentation, it will by default try to install to /dev/sda. Depending on the virtual disk setup it may be mounted differently (e.g: /dev/vda)

To check the current disks on a node use the command below:
```shell
talosctl get disks --insecure --nodes <ip>
```

### Checking system extensions

System extensions are defined in images, which can be created using https://factory.talos.dev.

They can also be created using the command line by following whats described in the talos documentation @ <https://docs.siderolabs.com/talos/v1.12/platform-specific-installations/boot-assets>

To check which extensions are enabled on each node, use:

```shell
talosctl get extensions
```


### Adding a patch

Updating full machineconfig with a patch, and then apply to a node:

```shell
talosctl machineconfig patch controlplane.yaml -p controlplane-patch1-enable-vip.yaml -o controlplane-v2.yaml

talosctl apply-config --nodes 10.2.0.11 --file controlplane-v2.yaml
```

Apply just a patch to a node:

```shell
talosctl patch mc --nodes 10.2.0.11 --patch patch.yaml
```