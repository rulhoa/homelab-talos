# Homelab: Talos Kubernetes Cluster

Homelab deployment of a Kubernetes cluster using Talos OS.

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

### 1. Install local talosctl, kubectl, and helm commands

- **talosctl** is for configuring talos nodes - our infrastructure.
- **kubectl** for managing kubernetes - our services.
- **helm** for deploying services as packages.

```shell
# talosctl
curl -sL https://talos.dev/install | sh

# kubectl
kubernetes_version="v1.34"
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
curl -fsSL https://pkgs.k8s.io/core:/stable:/${kubernetes_version}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${kubernetes_version}/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly
sudo apt-get update
sudo apt-get install -y kubectl

# helm for Debian/Ubuntu
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```

### 2. Create DNS records (optional)

  This is mostly for convenience so I can use a single FQDN with the cluster, and let my local DNS server round-robin the control lane IPs.

  I'm using (Technitium)[https://technitium.com] in my homelab, and the records below were added to my Forwarder subdomain zone.

  Below is what I configured in my lab:

```text
k8s.internal.salesulhoa.com  IN  A  192.168.0.10
k8s.internal.salesulhoa.com  IN  A  192.168.0.11
k8s.internal.salesulhoa.com  IN  A  192.168.0.12
```

### 3. Download Talos ISO

```shell
curl https://github.com/siderolabs/talos/releases/download/v1.12.2/metal-amd64.iso -L -o talos-v1.12.2.iso
```

  I used the proxmox UI to download the ISO directly to the ISO storage, but the ISO can also be downloaded and uploaded manually.

  Which 1.12.x version of this ISO doesn't matter, as we'll use it only for the initial bootstrap of each Talos VM. In the next steps we'll handle the custom ISO version we'll want to run in our lab.
  
### 4. Generate custom Talos ISO

  Since Talos Linux is immutable, any non-default packages that the OS requires needs to be included in the ISO, for which we'll use the [Talos Linux Image Factory](https://factory.talos.dev/) website to create.
  
  Settings used:

- **Hardware type**: Cloud Server (recommended for Proxmox)
- **Talos version**: 1.12.2
- **Cloud**: Nocloud (recommended for Proxmox)
- **Machine Architecture**: amd64 (Secureboot disabled)
- **System Extensions**:
  - siderolabs/qemu-guest-agent: used to improve proxmox management experience. Without it memory usage will always report as 100%
  - siderolabs/iscsi-tools: required by LongHorn
  - siderolabs/util-linux-tools: required by LongHorn
- **Customization**: default options

  After selecting the options above, the final page will contain links and ids. Copy the id string in "Initial Installation" section:

```text
factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.2
```

### 5. Generate Talos machine config files

  The commands below generate the initial machine configurations. Make sure to:

- Change the "--install-image" value to the custom image ID generated previously;
- Change the "--dns-domain" value to the desired FQDN, or just remove this optional setting.

```shell
talosctl gen secrets -o secrets.yaml

talosctl gen config talos https://k8s.internal.salesulhoa.com:6443 --install-image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.2 --dns-domain k8s.internal.salesulhoa.com --with-secrets secrets.yaml
```

  In the future, the desired image can be updated manually in each of the machine configuration jsons by editing the section:

```json
machine:
  install:
    image: <desired image id>
```

  example:

```json
machine:
  install:
    image: factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.2
```

> [!WARNING]
> Nodes that have had an image already installed require the use of the command `talosctl upgrade` to update.
> Just applying an updated machine config is not sufficient.

### 6. Talos machine config changes

  Manually edit the `controlplane.yaml` with the following:

- Set the `Cluster` parameter `allowSchedulingOnControlPlanes` to `true`
  - This allows Control Plane nodes to act as worker nodes.

### 7. Prepare talosctl environment

  When machine configs are created by talosctl, it also creates a talosconfig file for the cluster that can be merged into the default `~/talos/config`

```shell
talosctl config merge ./talosconfig
```

  Make sure to add the cluster endpoints and nodes that will be configured.

```shell
talosctl config endpoint 10.2.0.11 10.2.0.12 10.2.0.13
talosctl config node 10.2.0.11 10.2.0.12 10.2.0.13
```

### 8. Provision VMs

  Create 3 VMs using the settings below:

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

  Boot using talos ISO that was downloaded previously (not the custom ISO).

  Make sure to use to console to configure the desired static IP, gateway, and network DNS server for each node.

  In an enterprise environment, the desired IP would be assigned automatically using DHCP.

### 9. Applying Machine configurations

  Apply control plane configuration to each node:

```shell
talosctl apply-config --insecure --nodes 10.2.0.11 --file controlplane.yaml
talosctl apply-config --insecure --nodes 10.2.0.12 --file controlplane.yaml
talosctl apply-config --insecure --nodes 10.2.0.13 --file controlplane.yaml
```

  Obs: the "--insecure" flag only works on nodes booting from the ISO and not yet installed to disk, which is our case.

  Monitor each node's console to wait for them to finish installing/rebooting before continuing.

> [!TIP]
> New nodes can be added to the cluster in the future by running the `apply-config` command above.
> Once the node becomes healthly - after the installation, it'll automatically be used for workloads.

### 10. Initializing the cluster's etcd

  On ONLY one node run:

```shell
talosctl bootstrap --nodes 10.2.0.11
```

  Wait a few minutes and monitor the console for when node is flagged as healthy in green

### 11. Configure kubectl

```shell
# update kubeconfig file for use with kubectl
talosctl kubeconfig --nodes 10.2.0.11

# Command below should return that all nodes are "Ready"
kubectl get nodes
```

## Additional commands
<details>
<summary>Useful management commands section</summary>

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

### Applying a Talos Patch

After creating the yaml with the new definitions, apply it to a node.

```shell
talosctl patch mc --nodes 10.2.0.11 --patch patch.yaml
```

Apply it to all relevant nodes in the cluster.

Alternatively, the full machineconfig can be updated with the patch, and then used to applied to nodes:

```shell
# Merge patch "controlplane-patch1-enable-vip.yaml" into the machineconfig "controlplane.yaml" and export the new machineconfig as "controlplane-v2.yaml"
talosctl machineconfig patch controlplane.yaml -p controlplane-patch1-enable-vip.yaml -o controlplane-v2.yaml

# Apply the new and full machine config to a node
talosctl apply-config --nodes 10.2.0.11,10.2.0.12,10.2.0.13 --file controlplane-v2.yaml
```

### Creating a Service Account and a bearer token

```shell
kubectl create serviceaccount <service-account-name>

# This creates a temporary token (duration follows server defaults)
kubectl create token <service-account-name>

# This creates a temporary token for 24 hours.
kubectl create token <service-account-name> --duration=24h
```

Since kubernetes v1.24, creating a long lived tokens are no longer allowed.
For a more persistant token, we need to use secrets with the type of "kubernetes.io/service-account-token":

```shell
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: <service-account-name>-secret
  annotations:
    kubernetes.io/service-account.name: <service-account-name>
EOF

# To get the generated token (and ca.crt) - note that they are both in base64
kubectl get secret/<service-account-name>-secret -o yaml

# Retrieves the token in pure text
kubectl describe secret/<service-account-name>-secret
```

### Managing Cluster Role Bindings

#### Managing Cluster Role Bindings: Applying Read-Only Roles

The "view" role allows the read-only **get**, **list**, and **watch** actions on all namespaces.

To apply it to an account:

```shell
kubectl create clusterrolebinding <service-account-name>-view \
  --clusterrole=view \
  --serviceaccount=default:<service-account-name>
```

Talos doesn't have a native readonly role (**get** and **list** verbs) for Nodes.
It can be created using [system-node-readonly.json](k8s/ClusterRoles/system-node-readonly.json), and used to create a Cluster Role:

```shell
# Create ClusterRole for node/cluster get, list, and watch
kubectl apply -f k8s/ClusterRoles/system-node-readonly.json

# Associate new ClusterRole to an account
kubectl create clusterrolebinding <service-account-name>-node-readonly \
  --clusterrole=system:node-readonly \
  --serviceaccount=default:<service-account-name>
```

#### Managing Cluster Role Bindings: Inspecting Roles and Bindings

Cluster Roles:

```shell
# Get full list of existing Cluster Roles with creation dates
kubectl get ClusterRole

# Get the json definition of the role "view"
kubectl get ClusterRole view -o json

# Get table of resources and permissions (verbs) defined in the "view" (can be more convenient than reading the json)
kubectl describe clusterrole view
```

Cluster Role Bindings:

```shell
# Get full list of existing Cluster Role Bindings
kubectl get clusterrolebinding

# Describe the mapping between account and roles defined in the binding "system:basic-user"
kubectl describe clusterrolebinding system:basic-user
```

#### Managing Cluster Role Bindings: Deleting

Role bindings can be deleted with:

```shell
kubectl delete clusterrolebinding <service-account-name>-node-readonly
```

### Updating talos image on nodes


```shell
talosctl upgrade --nodes 10.2.0.11,10.2.0.12,10.2.0.13 --image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.2
```

Wait for all nodes to finish with the status "post check passed".

To avoid unavailability of services, apply the upgrade incrementally.

> [!TIP]
> Since the upgrade process might change between minor releases, always check the documentation to see if intermediary upgrade steps are required.

Note that Kubernetes is not upgraded automatically, with image updates on an existing cluster, to avoid issues.


</details>
