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
- **Talos version**: 1.14.2
- **Cloud**: Nocloud (recommended for Proxmox)
- **Machine Architecture**: amd64 (Secureboot disabled)
- **System Extensions**:
  - siderolabs/qemu-guest-agent: used to improve proxmox management experience. Without it memory usage will always report as 100%
  - siderolabs/iscsi-tools: required by LongHorn
  - siderolabs/util-linux-tools: required by LongHorn and also for fstrim to discard unused blocks (great to keep our thin-provisioned disks optimized in terms of actual disk usage)
- **Customization**: default options

After selecting the options above, the final page will contain links and ids. Copy the id string in "Initial Installation" section:

Example:

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
## Change the "--install-image" value to the custom image ID generated previously;
talosctl gen config talos https://k8s.internal.salesulhoa.com:6443 --install-image factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.14.2 --with-secrets secrets.yaml
```

The following "machine config" files should have been generated:

- controlplane.yaml
- worker.yaml

> [!WARNING]
> Nodes that have had an image already installed require the use of the command `talosctl upgrade` to update.
> Just applying an updated machine config is not sufficient.

### mc config changes

Manually edit the mc files with the following:

> [!TIP]
> To allow Control Plan nodes to act as worker nodes, set the `Cluster` parameter `allowSchedulingOnControlPlanes` to `true`

#### Cilium CNI

Manually edit the end of `controlplane.yaml` to add the following configurations required for Cilium CNI. It disables kube-proxy so we can fully use Cilium later in the guide.

```yaml
---
apiVersion: v1alpha1
kind: KubeFlannelCNIConfig
$patch: delete
---
apiVersion: v1alpha1
kind: KubeProxyConfig
enabled: false
```

#### Longhorn

Since only the worker nodes will be running LongHorn, manually edit the `worker.yaml` to add the following required kernel modules to the end of the file as a patch:

```yaml
---
apiVersion: v1alpha1
kind: SysctlConfig
params:
    vm.nr_hugepages: "1024"
---
apiVersion: v1alpha1
kind: KernelModuleConfig
name: nvme_tcp
---
apiVersion: v1alpha1
kind: KernelModuleConfig
name: vfio_pci
---
apiVersion: v1alpha1
kind: KernelModuleConfig
name: uio_pci_generic
---
apiVersion: v1alpha1
kind: KernelModuleConfig
name: ublk_drv

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

We'll use Terraform

```shell
cd infrastructure/terraform/proxmos-talos-cluster

# Download and cache providers
terraform init

# Validate necessary changes
terraform plan

# Apply changes
terraform apply

# Delete all previously created resources
#terraform destroy

# Import into state file an existing resource that wasn't created by terraform
# Resource must have been defined in a *.tf file
#terraform import <resource_type.resource_name> <name_in_destination>
```

Wait for talos to finish booting in each VM, in a few minutes

## Applying Machine configurations

  Apply control plane configuration to each node:

```shell
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

Note that if kube-proxy is disabled (what we're doing in this guide), it won't ready a Ready state until we deploy cilium.

## Configure kubectl

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
    --set prometheus.enabled=true \
    --set operator.prometheus.enabled=true \

# It'll take several minutes for the etcd configuration to propogate, for Cilium to enter a running state, and for the cluster to estabilish communication within kubernetes.

# You'll know it's ready when all nodes have READY = True

# Wait for all nodes to be healthy and pods to enter a Running stage.
# Multiple pod errors and restarts are expected during the process
kubectl get nodes
kubectl get pods -A -w
```

> [!WARNING]
> The Cilium project is now recommending the use of OCI images is place of helm repos for better security.

Enable Hubble which is observability layer of Cilium.

```shell
helm upgrade cilium cilium/cilium --version 1.19.5 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.relay.enabled=true
```

Enable Cilium as a loadbalancer service.
We need to enable and configure IPAM and L2 announcements (to respond to arp "how has the IP" requests)

```shell
helm upgrade cilium cilium/cilium --version 1.19.5 \
   --namespace kube-system \
   --reuse-values \
   --set nodeIPAM.enabled=true \
   --set l2announcements.enabled=true

kubectl -n kube-system rollout restart ds/cilium
kubectl -n kube-system rollout restart deployment/cilium-operator
kubectl -n kube-system rollout status ds/cilium

# Check if the L2 announcement has been enabled
kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all | grep EnableL2Announcements
# should print: EnableL2Announcements   : true

# Apply the loadbalancer IP pool. Edit as necessary
kubectl apply -f k8s/cilium/cilium-loadbalancer-ip-pool.yaml
# The CiliumLoadBalancerIPPool is a cluster-scoped resource, and doesn't live within any particular namespace

# Enable L2 announcement to external and loadbalancer IPs
kubectl apply -f l2-announcement-policy.yaml
```

Test the loadbalancer with:

```shell
# Create an nginx pod
kubectl run nginx --image=nginx:1.27 --port=80 --labels=app=nginx

# Create the LoadBalancer service, targeting pods with label app=nginx
kubectl expose pod nginx --name=nginx-lb --port=80 --target-port=80 --type=LoadBalancer

# check if the service got an external-ip
kubectl get service | grep nginx
# make note of the external-ip

# From a different machine execute
curl -fsSL <external-ip>:80
# You should get a standard new nginx welcome html

# Cleanup
kubectl delete svc nginx-lb
kubectl delete pod nginx
```

### Upgrading from Cilium 1.19.5 to 1.20.1 (release upgrade)

Source: [Cilium 1.20 upgrade notes](https://docs.cilium.io/en/v1.20/operations/upgrade/#upgrade-notes)

```shell
# Make sure helm repos are updated
helm repo update

# Pre-flight setup so that images are pre-downloaded and validated before network is cut-out when cilium is being upgraded
helm template cilium/cilium --version 1.20.1 \
   --namespace kube-system \
   --set preflight.enabled=true \
   --set agent=false \
   --set operator.enabled=false \
   --set k8sServiceHost=localhost \
   --set k8sServicePort=7445 \
   > cilium-preflight.yaml
kubectl create -f cilium-preflight.yaml

# Check if the pre-flight daemonset is fully running and have the same number of ready and available pods as the other pre-existing cilium daemonsets
kubectl get daemonset -n kube-system | sed -n '1p;/cilium/p'

# Cleanup
kubectl delete -f cilium-preflight.yaml

# To upgrade using helm, we can't use the "--reuse-values" flag as it ignores new values introduced in new charts, which WILL cause issues
# To the the existing list of set values we can use:
# helm get values cilium --namespace=kube-system -o yaml > old-values.yaml

helm upgrade cilium cilium/cilium --version 1.20.1 \
   --namespace kube-system \
   --set upgradeCompatibility=1.19.5 \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set hubble.relay.enabled=true \
    --set nodeIPAM.enabled=true \
    --set l2announcements.enabled=true \
    --set prometheus.enabled=true \
    --set operator.prometheus.enabled=true
```

### Upgrading from Cilium 1.20.1 to 1.20.2 (patch upgrade)

```shell
# Make sure helm repos are updated
helm repo update

# Pre-flight setup so that images are pre-downloaded and validated before network is cut-out when cilium is being upgraded
helm template cilium/cilium --version 1.20.2 \
   --namespace kube-system \
   --set preflight.enabled=true \
   --set agent=false \
   --set operator.enabled=false \
   --set k8sServiceHost=localhost \
   --set k8sServicePort=7445 \
   > cilium-preflight.yaml
kubectl create -f cilium-preflight.yaml

# Check if the pre-flight daemonset is fully running and have the same number of ready and available pods as the other pre-existing cilium daemonsets
kubectl get daemonset -n kube-system | sed -n '1p;/cilium/p'

# Cleanup
kubectl delete -f cilium-preflight.yaml

# To upgrade using helm, we can't use the "--reuse-values" flag as it ignores new values introduced in new charts, which WILL cause issues
# To the the existing list of set values we can use:
# helm get values cilium --namespace=kube-system -o yaml > old-values.yaml

helm upgrade cilium cilium/cilium --version 1.20.2 \
   --namespace kube-system \
   --set upgradeCompatibility=1.20.1 \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set hubble.relay.enabled=true \
    --set nodeIPAM.enabled=true \
    --set l2announcements.enabled=true \
    --set prometheus.enabled=true \
    --set operator.prometheus.enabled=true
```

## Configuring Longhorn on worker nodes

I'm using the LongHorn V2 Data Engine that went GA with v1.12 on June 2 2026.

```shell
cd infrastructure/talos

# Create and mount volume /var/mnt/longhorn using an available disk (our VM should have 2 disks, with 1 available)
talosctl patch mc --patch @patch-controlplane-longhorn-volume.yaml --nodes 10.1.0.21,10.1.0.22,10.1.0.23

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

helm install longhorn longhorn/longhorn --version 1.13.0 --namespace longhorn-system --values=k8s/longhorn/helm_values.yaml 

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

Create the following patch file `patch-all-cert-rotation-enable.yaml`:

```yaml
apiVersion: v1alpha1
kind: KubeletConfig
extraArgs:
  rotate-server-certificates: true
```

apply the patch on all nodes:

```shell
talosctl patch mc --patch patch-all-cert-rotation-enable.yaml
```

Install the metric server

```shell
kubectl apply -f https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Testing if it's working:

```shell

kubectl get deployment metrics-server -n kube-system

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

## ArgoCD

```shell

kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Check if different pods are running
kubectl get pods -n argocd

# Use this to get the latest events in the argocd namespace to troubleshoot if necessary
kubectl -n argocd get events --sort-by=.lastTimestamp | tail

# Get the initial admin password
# This secret will only be created if argocd has been able to successfully deploy
kubectl get secret argocd-initial-admin-secret -n argocd -o json | jq .data.password  -r | base64 -d

# Give ArgoCD an external IP
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
# Or just do port forwarding with: kubectl port-forward svc/argocd-server -n argocd 8080:443

# use this to obtain the external IP
kubectl get service argocd-server -n argocd -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Using the browser, connect to `https://<ip>`
Login using `admin` and the initial password.
