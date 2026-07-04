# Deployment Steps

## 1. Install local talosctl, kubectl, and helm commands

- **terraform** is for provisioning proxmox resources
- **talosctl** is for configuring talos nodes - our infrastructure.
- **kubectl** for managing kubernetes - our services.
- **helm** for deploying services as packages.

```shell

# terraform
# See https://developer.hashicorp.com/terraform/install for the latest instructions
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

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

## 2. Create DNS records (optional)

  This is mostly for convenience so I can use a single FQDN with the cluster, and let my local DNS server round-robin the control lane IPs.

  I'm using [Technitium](https://technitium.com) in my homelab, and the records below were added to my Forwarder subdomain zone.

  Below is what I configured in my lab:

```text
k8s.internal.salesulhoa.com  IN  A  192.168.0.10
k8s.internal.salesulhoa.com  IN  A  192.168.0.11
k8s.internal.salesulhoa.com  IN  A  192.168.0.12
```

## 3. Download Talos ISO

```shell
TALOS_VERSION="v1.13.4"
curl https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-amd64.iso -L -o talos-${TALOS_VERSION}.iso
```

  I used the proxmox UI to download the ISO directly to the ISO storage, but the ISO can also be downloaded and uploaded manually.

  Which 1.13.x version of this ISO doesn't matter, as we'll use it only for the initial bootstrap of each Talos VM. In the next steps we'll handle the custom ISO version we'll want to run in our lab.
  
## 4. Generate custom Talos ISO

  Since Talos Linux is immutable, any non-default packages that the OS requires needs to be included in the ISO, for which we'll use the [Talos Linux Image Factory](https://factory.talos.dev/) website to create.
  
  Settings used:

- **Hardware type**: Cloud Server (recommended for Proxmox)
- **Talos version**: 1.13.5
- **Cloud**: Nocloud (recommended for Proxmox)
- **Machine Architecture**: amd64 (Secureboot disabled)
- **System Extensions**:
  - siderolabs/qemu-guest-agent: used to improve proxmox management experience. Without it memory usage will always report as 100%
  - siderolabs/iscsi-tools: required by LongHorn
  - siderolabs/util-linux-tools: required by LongHorn and also for fstrim to discard unused blocks (great to keep our thin-provisioned disks optimized in terms of actual disk usage)
  - siderolabs/nfsd: NFS server (optional for future usage)
- **Customization**: default options

  After selecting the options above, the final page will contain links and ids. Copy the id string in "Initial Installation" section:

```text
factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.13.4
```

## 5. Generate Talos machine config (mc) files

  The commands below generate the initial machine configurations. Make sure to:

- Change the "--install-image" value to the custom image ID generated previously;
- Change the "--dns-domain" value to the desired FQDN, or just remove this optional setting.

```shell
talosctl gen secrets -o secrets.yaml

talosctl gen config talos https://k8s.internal.salesulhoa.com:6443 --install-image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.4 --dns-domain k8s.internal.salesulhoa.com --with-secrets secrets.yaml
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
    image: factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.4
```

> [!WARNING]
> Nodes that have had an image already installed require the use of the command `talosctl upgrade` to update.
> Just applying an updated machine config is not sufficient.

## 6. Talos machine config changes

  Manually edit the `controlplane.yaml` with the following:

- Set the `Cluster` parameter `allowSchedulingOnControlPlanes` to `true`
  - This allows Control Plane nodes to act as worker nodes.

  Cilium CNI: Manually edit both the `controlplane.yaml` and `worker.yaml` to add the following configurations required for Cilium CNI. Note that kube-proxy is going to be disabled and we'll need to install Cilium shortly after bootstrapping etcd so that the cluster has connectivity.

```yaml
cluster:
  network:
    cni:
      name: none
  proxy:
    disabled: true
```

  Longhorn: Manually edit both the `controlplane.yaml` and `worker.yaml` to add the following kernel modules required for longhorn:

```yaml
machine:
  kernel:
    modules:
      - name: nbd
      - name: iscsi_tcp
      - name: configfs
```

  Metrics Server: Manually edit both the `controlplane.yaml` and `worker.yaml` to add the following configurations:

```yaml
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: true
cluster:
  extraManifests:
    - https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml
    - https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
```
  
  Also Manually edit both the `controlplane.yaml` to add the following configurations:

```yaml
cluster:
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
```

## 7. Prepare talosctl environment

  When machine configs are created by talosctl, it also creates a talosconfig file for the cluster that can be merged into the default `~/talos/config`

```shell
talosctl config merge ./talosconfig
```

  Make sure to add the cluster endpoints and nodes that will be configured.

```shell
talosctl config endpoint 10.2.0.11 10.2.0.12 10.2.0.13
talosctl config node 10.2.0.11 10.2.0.12 10.2.0.13
```

> [!IMPORTANT]
> Do note that "config node" sets all the listed nodes as default values when running any command with talosctl
> At the same time that this makes it easier to send commands to every node,
> it also means that commands like `talosctl shutdown` are sent to every node, WITHOUT asking for confirmation
>
> Handle with care...

## 8. Provision VMs

  Create 3 VMs using the settings below:

  | Setting   | Used values       | Notes            |
  | --------- | ----------------- | ---------------- |
  |BIOS       | SeaBIOS                                     | Security is a minor concern. Otherwise we would be using UEFI |
  |Machine | q35                                         | Modern PCIe-based machine type with better device support |
  |Qemu Agent | enabled                                       | |
  |CPU Type | host                                         | Enables advanced instruction sets (AVX-512, etc.), best performance. Obs: May prevent live-migration in the future |
  |CPU Cores | 8 cores                                       | Minimum 2 cores required |
  |Memory     | 8GB                                         | Minimum 2GB required |
  |Disk Controller | VirtIO SCSI (NOT "VirtIO SCSI Single")   | Single controller can cause bootstrap hangs (#11173) |
  |Disk Format | Raw (performance) or QCOW2 (features/snapshots) | Raw preferred for performance |
  |Disk Cache  | No Cache (Default)                           | My proxmox server doesn't have an UPS, so no caching reducing potential performance but minimizes risk of dataloss |
  |Disk features | Discard enabled                            | |
  |Network Model | virtio                                     | Paravirtualized driver, best performance (up to 10 Gbit) |
  |Memory  | Ballooning Disabled | Talos doesn't support memory hotplug |

  Reference: <https://docs.siderolabs.com/talos/v1.12/platform-specific-installations/virtualized-platforms/proxmox>

  Boot using talos ISO that was downloaded previously (not the custom ISO).

  Make sure to use to console to configure the desired static IP, gateway, and network DNS server for each node.

  In an enterprise environment, the desired IP would be assigned automatically using DHCP.

## 9. Applying Machine configurations

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

## 10. Initializing the cluster's etcd (bootstrapping)

  On ONLY one node run:

```shell
talosctl bootstrap --nodes 10.2.0.11
```

  Wait a few minutes and monitor the console for when node is flagged as healthy in green

## 11. Configure kubectl

```shell
# update kubeconfig file for use with kubectl
talosctl kubeconfig --nodes 10.2.0.11

# Command below should return that all nodes are "Ready"
kubectl get nodes
```

## 12. Configuring Cilium CNI

```shell

helm repo add cilium https://helm.cilium.io/
helm repo update

helm install \
    cilium \
    cilium/cilium \
    --version 1.18.7 \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445
    --set=gatewayAPI.enabled=true \
    --set=gatewayAPI.enableAlpn=true \
    --set=gatewayAPI.enableAppProtocol=true

# Wait for all pods to enter a Running stage. Multiple pod errors and restarts are expected during the process.
kubectl get pods -A -w

```

## 13. Configuring MetalLB

Since we're using control plane nodes as workers, we need to remove the label that excludes control plane from load balancers. Create a patch file `controlplane-patch3-loadbalancer.yaml` with the following:

```yaml
machine:
  nodeLabels:
    node.kubernetes.io/exclude-from-external-load-balancers:
      $patch: delete
```

and apply it to the cluster:

```shell
talosctl apply-config --nodes 10.2.0.11,10.2.0.12,10.2.0.13 --patch controlplane-patch3-loadbalancer.yaml
```

And now to deploy MetalLB:

```shell
# Create the namespace with required permission labels
kubectl apply -f k8s/metallb/namespace_metallb-system.yaml

# Prep helm with metallb repository
helm repo add metallb https://metallb.github.io/metallb && helm repo update

# Deploy metallb
helm install metallb metallb/metallb \
    --version 0.15.3 \
    --namespace metallb-system

# Configure IP Address pool and L2Advertisement.
#   Address pool defines available IP ranges
#   Advertisement is necessary for network connectivity.
kubectl apply -f IPAddressPool.yaml
```

## 14. Configuring Longhorn

```shell
# Create and mount volume /var/mnt/longhorn using an available disk (our VM should have 2 disks, with 1 available)
talosctl patch mc --patch @controlplane-patch2-longhorn-volume.yaml

# Check if a "u-longhorn" (u for user volume) was mounted in each node
talosctl get volumestatus | grep longhorn

# Check if "u-longhorn" was mounted as "/var/mnt/longhorn" on each node
talosctl get mounts | grep longhorn

#talosctl wipe disk sdb1 --drop-partition
```

```shell
# Create the longhorn namespace with pod security labels that it requires to function properly

kubectl apply -f k8s/longhorn/namespace_longhorn-system.yaml

helm repo add longhorn https://charts.longhorn.io && helm repo update

helm install longhorn longhorn/longhorn --version 1.11.0 --namespace longhorn-system --values=k8s/longhorn/helm_values.yaml 

# Wait for all pods to reach a running state
kubectl -n longhorn-system get pod -w

# longhorn should be the default storage class
kubectl get storageclass

# In case longhorn isn't the default, the patch command below can be used to make it sot.
kubectl patch storageclass longhorn \
#  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'


kubectl port-forward service/longhorn-frontend 8080:80 -n longhorn-system
#  access the UI from <http://localhost:8080>
```

## 15. Configuring Metric Server

It should have been automatically deployed during the bootstrap based on the defined machine configurations. Use the following to test:

```shell
kubectl top nodes
# It should output something like the below:
#NAME     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%   
#node11   530m         6%     3618Mi          49%       
#node12   432m         5%     2700Mi          36%       
#node13   1311m        16%    1429Mi          19%  
#
# If a node reports unknown or an the metric api is unavailable, the deployment failed

# Use the below to get prometheus style export of all metrics
curl 10.2.0.11:2381/metrics
```

In case the case the metric server wasn't auto deployed during the bootstrap, use the following:

```shell
kubectl apply -f https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
