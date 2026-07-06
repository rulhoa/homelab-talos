# Deployment Steps

## Installing local commands

We'll use these to provision and configure the cluster

- **terraform** is for provisioning proxmox resources (network, initial Talos ISO, VMs)
- **talosctl** is for configuring talos nodes
- **kubectl** for managing kubernetes.
- **helm** for deploying manifests as packages.

Obs.: I used Ubuntu24.04 running through Windows WSL.

Terraform:

```shell
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

talosctl:

```shell
curl -sL https://talos.dev/install | sh
```

kubectl:

```shell
# Dependencies
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
# Install latest
## GPG key (new one for every major release)
curl -fsSL "https://pkgs.k8s.io/core:/stable:/$(curl -L -s https://dl.k8s.io/release/stable.txt | cut -d"." -f1-2)/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring
## apt repo config
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$(curl -L -s https://dl.k8s.io/release/stable.txt | cut -d"." -f1-2)/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps unprivileged commands to work correctly
### Update cache and install
sudo apt-get update
sudo apt-get install -y kubectl
```

helm:

```shell
sudo apt-get install -y curl gpg apt-transport-https
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```

## Create DNS records (optional)

This is mostly for convenience so I can use a single FQDN with the cluster, and let my local DNS server round-robin the control plane IPs.

I'm using [Technitium](https://technitium.com) in my homelab, and the records below were added to my Forwarder subdomain zone:

```text
k8s.internal.salesulhoa.com  IN  A  10.1.0.11
k8s.internal.salesulhoa.com  IN  A  10.1.0.12
k8s.internal.salesulhoa.com  IN  A  10.1.0.13
```

## Talos ISO

We'll need two versions.

The first is just for the initial boot of the VMs and has already been set in [proxmox.talos.iso.tf](infrastructure/terraform/proxmos-talos-cluster/proxmox.talos.iso.tf). The actual version of this ISO doesn't matter, as long as it's not unreasonably old. The VMs will boot from it and wait for us to apply the first machine configuration which will containing the second version...

THe second version is what we actually want the cluster install and run. Since Talos Linux is immutable, any non-default packages that the OS requires needs to be included in the ISO, for which we'll use the [Talos Linux Image Factory](https://factory.talos.dev/) website to create.
  
Settings used:

- **Hardware type**: Cloud Server (recommended for Proxmox)
- **Talos version**: 1.13.5
- **Cloud**: Nocloud (recommended for Proxmox)
- **Machine Architecture**: amd64 (Secureboot disabled)
- **System Extensions**:
  - siderolabs/qemu-guest-agent: used to improve proxmox management experience. Without it memory usage will always report as 100%
  - siderolabs/iscsi-tools: required by LongHorn
  - siderolabs/util-linux-tools: required by LongHorn and also for fstrim to discard unused blocks (great to keep our thin-provisioned disks optimized in terms of actual disk usage)
- **Customization**: default options

After selecting the options above, the final page will contain links and ids. Copy the id string in "Initial Installation" section:

```text
factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.13.5 
```

## Talos machine config (mc) files

The files in the folder [infrastructure/talos]([infrastructure/talos]) are included as a reference. It's recommended to generate new files with your own secrets.

### Generate Talos machine config (mc) files

The commands below generate the initial machine configurations.

> [!IMPORTANT]
> The talosctl version (talosctl version --client) should match the Talos OS version installed on your nodes.
> If you are using a newer version of talosctl to generate configurations for an older Talos OS, use the --talos-version flag to ensure compatibility. For example, to generate a configuration compatible with Talos v1.13 use --talos-version v1.13

```shell
# Generate secrets
talosctl gen secrets -o secrets.yaml

# Generate initial machine configs
## Change "talos" to whatever is the desired cluster name
## change "k8s.internal.salesulhoa.com" to whatever IP/FQDN is being used
## Change the "--install-image" value to the custom image ID generated previously;
## Change the "--dns-domain" value to the desired FQDN, or just remove this optional setting.
talosctl gen config talos https://k8s.internal.salesulhoa.com:6443 --dns-domain k8s.internal.salesulhoa.com --install-image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.13.5 --with-secrets secrets.yaml
```

The following "machine config" files should have been generated:

- controlplane.yaml
- worker.yaml

For future reference, the desired image can be updated manually in each of the machine configuration jsons by editing the section:

```yaml
machine:
  install:
    image: <desired image id>
```

example:

```yaml
machine:
  install:
    image: factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.4
```

> [!WARNING]
> Nodes that have had an image already installed require the use of the command `talosctl upgrade` to update.
> Just applying an updated machine config is not sufficient.

### mc config changes

Manually edit the mc files with the following:

> [!TIP]
> To allow Control Plan nodes to act as worker nodes, set the `Cluster` parameter `allowSchedulingOnControlPlanes` to `true`

#### Cilium CNI

Manually edit both the `controlplane.yaml` to add the following configurations required for Cilium CNI. It disables kube-proxy so we can fully use Cilium later in the guide.

```yaml
cluster:
  network:
    cni:
      name: none
  proxy:
    disabled: true
```

#### Longhorn

Since only the worker nodes will be running LongHorn, manually edit the `worker.yaml` to add the following required kernel modules:

```yaml
machine:
  kernel:
    modules:
      - name: nbd
      - name: iscsi_tcp
      - name: configfs
```

#### Metric Server

Edit the `controlplane.yaml` to add the following configurations:

```yaml
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: true
cluster:
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
  extraManifests:
    - https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml
    - https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Edit the `worker.yaml` to add the following configurations:

```yaml
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: true
```

## Prepare talosctl environment

When machine configs are created by talosctl, it also creates a `talosconfig` file for the cluster that can be merged into the default `~/talos/config`

```shell
talosctl config merge ./talosconfig
```

Now we configure the cluster endpoints and nodes in talosctl.

```shell
# Endpoints are nodes that talosctl communicates via API. Typically control plane nodes, as they can be used as a "proxy" to other nodes.
# Trying to add worker nodes will likely lead to "permission denied" error messages when trying to use them to communicatae with a different node.
talosctl config endpoint 10.1.0.11 10.1.0.12 10.1.0.13

# Nodes are the list of nodes that we want to interact with through the endpoint(s).
talosctl config node 10.1.0.11 10.1.0.12 10.1.0.13 10.1.0.21 10.1.0.22 10.1.0.23
```

> [!IMPORTANT]
> Do note that "talosctl config node" sets all the listed nodes as the default target when running any command with talosctl
> This means that any talosctl command will, by default, send any request to ALL the configured nodes - unless an override flag is specified.
> At the same time that this makes it easier to send commands to every node,
> it also means that commands like `talosctl shutdown` are sent to every node, WITHOUT asking for confirmation
>
> Handle with care...

## Provisioning VMs

Terraform

## Applying Machine configurations

  Apply control plane configuration to each node:

```shell
# Con
talosctl apply-config --insecure --nodes 10.1.0.11 --file controlplane.yaml
talosctl apply-config --insecure --nodes 10.1.0.12 --file controlplane.yaml
talosctl apply-config --insecure --nodes 10.1.0.13 --file controlplane.yaml

talosctl apply-config --insecure --nodes 10.1.0.21 --file worker.yaml
talosctl apply-config --insecure --nodes 10.1.0.22 --file worker.yaml
talosctl apply-config --insecure --nodes 10.1.0.23 --file worker.yaml
```

The "--insecure" flag only works on nodes booting from the ISO and not yet installed to disk, which is our case.
You'll get the following error if Talos has already been installed: `error applying new configuration: rpc error: code = Unavailable desc = connection error: desc = "error reading server preface: remote error: tls: certificate required"`.

Monitor each node's console to wait for them to finish installing/rebooting before continuing.

> [!TIP]
> New nodes can be added to the cluster in the future by running the `apply-config` command above.
> Once the node becomes healthly - after the installation, it'll automatically have been added to the cluster.

## Initializing the cluster's etcd (bootstrapping)

On ONLY one control plane node run:

```shell
talosctl bootstrap --nodes 10.1.0.11 --endpoints 10.1.0.11
```

Wait until STAGE is flagged as Running.

Once the bootstrap process finishes, the other nodes are notified and automatically added to the cluster since they share the same secrets and are on the same network.

## 11. Configure kubectl

```shell
# update kubeconfig file for use with kubectl
talosctl kubeconfig --nodes 10.1.0.11

# Command below should normally return that all nodes are "Ready"
# Since we disabled kube-proxy there isn't any communication within kubernetes and the command will fail.
# Once Cilium is installed, the command below should eventually report all our nodes with a healthy state.
kubectl get nodes
```

## Configuring Cilium CNI

```shell
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install \
    cilium \
    cilium/cilium \
    --version 1.19.5 \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445

# It'll take several minutes for the etcd configuration to propogate, for Cilium to enter a running state, and for the cluster to estabilish communication within kubernetes.

# You'll know it's ready when all nodes have READY = True

# Wait for all nodes to be healthy and pods to enter a Running stage.
# Multiple pod errors and restarts are expected during the process
kubectl get nodes
kubectl get pods -A -w
```

## Configuring Longhorn on worker nodes

I'm using V1 Data Engine.
June 2 2026 update: The V2 Data Engine went GA with Longhorn 1.12 but I'm opting to wait longer before using it

```shell
cd infrastructure/talos

# Create and mount volume /var/mnt/longhorn using an available disk (our VM should have 2 disks, with 1 available)
talosctl patch mc --patch @controlplane-patch2-longhorn-volume.yaml --nodes 10.1.0.21,10.1.0.22,10.1.0.23

# Check if a "u-longhorn" (u for user volume) was mounted in each node
talosctl get volumestatus | grep longhorn

# Check if "u-longhorn" was mounted as "/var/mnt/longhorn" on each node
talosctl get mounts | grep longhorn

# Use this in case something went wrong and you need to "reset" the disk
#talosctl wipe disk sdb1 --drop-partition
```

```shell
# Create the longhorn namespace with pod security labels that it requires to function properly
kubectl apply -f k8s/longhorn/namespace_longhorn-system.yaml

helm repo add longhorn https://charts.longhorn.io && helm repo update

helm install longhorn longhorn/longhorn --version 1.12.0 --namespace longhorn-system --values=k8s/longhorn/helm_values.yaml 

# Wait for all pods to reach a running state
kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer
kubectl get pods -n longhorn-system -w

# longhorn should be the default storage class
kubectl get storageclass

# In case longhorn isn't the default, the patch command below can be used to make it sot.
kubectl patch storageclass longhorn \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# To connect to the longhorn Web UI:
kubectl port-forward service/longhorn-frontend 8080:80 -n longhorn-system
#  access the UI from <http://localhost:8080>
```

Test Longhorn by creating a PesistantVolumeClaim

```shell
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

# It should report with status Bound. If it's stuck on Pending, check if all the Longhorn pods are running
kubectl get pvc longhorn-test-pvc

# Cleanup
kubectl delete pvc longhorn-test-pvc
```

## Configuring Metric Server

It should have been automatically deployed during the bootstrap based on the defined machine configurations. Use the following to test:

```shell
kubectl top nodes
# It should output something like the below:
#NAME     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%   
#node11   530m         6%     3618Mi          49%       
#node12   432m         5%     2700Mi          36%       
#node13   1311m        16%    1429Mi          19%  
#
# If the metric api is unavailable, the metric server wasn't deployed.
# If some nodes are unknown, the nodes are probably missing the "rotate-server-certificates : true" parameter

# Use the below to get prometheus style export of all metrics
curl 10.1.0.11:2381/metrics
```

In case the case the metric server wasn't auto deployed during the bootstrap, use the following:

```shell
kubectl apply -f https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
