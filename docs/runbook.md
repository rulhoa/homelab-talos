# Runbook

## Maintenance

### Updating local commands

#### Terraform

Repo was added to apt.
See <https://developer.hashicorp.com/terraform/install> for the latest instructions

```shell
sudo apt update && sudo apt install terraform
```

#### talosctl

Installed using script (alternative is using brew)
See <https://docs.siderolabs.com/talos/v1.13/getting-started/talosctl#talosctl> for the latest instructions
The talosctl version (talosctl version --client) should match the Talos OS version installed on your nodes. If you are using a newer version of talosctl to generate configurations for an older Talos OS, use the --talos-version flag to ensure compatibility. For example, to generate a configuration compatible with Talos v1.13:

```shell
curl -sL https://talos.dev/install | sh
```

#### kubectl

You must use a kubectl version that is within one minor version difference of your cluster. For example, a v1.36 client can communicate with v1.35, v1.36, and v1.37 control planes. Using the latest compatible version of kubectl helps avoid unforeseen issues.
See <https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/> for the latest instructions.

Latest stable:
```shell
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```

Specific major release
See <https://dl.k8s.io/release/stable.txt> for the latest stable version
Minor releases are included in the same repo, using the same GPG key, of the major release.

```shell
kubernetes_version="v1.36"

# GPG key (new one for every major release)
curl -fsSL https://pkgs.k8s.io/core:/stable:/$(echo $kubernetes_version | cut -d"." -f1-2)/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring

### apt repo config (for specific minor release)
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$(echo $kubernetes_version | cut -d"." -f1-2)/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list # allow unprivileged programs to read the file

sudo apt-get update
sudo apt-get install -y kubectl
```

#### helm

Repo was added to apt.
See <https://helm.sh/docs/intro/install/> for the latest instructions

```shell
sudo apt update && sudo apt install helm
```

### Checking Talos system extensions

System extensions are defined in images, which can be created using <https://factory.talos.dev>.

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
talosctl upgrade --nodes 10.2.0.11,10.2.0.12,10.2.0.13 --image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.4
```

Wait for all nodes to finish with the status "post check passed".

To avoid unavailability of services, apply the upgrade incrementally.

> [!TIP]
> Since the upgrade process might change between minor releases, always check the documentation to see if intermediary upgrade steps are required.

Note that Kubernetes is not upgraded automatically, with image updates on an existing cluster, to avoid issues.

### Removing context from kubectl

Useful if the previous cluster was discontinued and/or configurations are no longer valid.

```shell
kubectl config get-clusters
# for each run: kubectl config delete-cluster <name>

kubectl config get-contexts
# for each run: kubectl config delete-context <name>

kubectl config get-users
# for each run: kubectl config delete-users <name>

kubectl config current-context
kubectl config unset current-context
```



## Troubleshooting

### /dev/sda not being found

As per the talos documentation, it will by default try to install to /dev/sda. Depending on the virtual disk setup it may be mounted differently (e.g: /dev/vda)

To check the current disks on a node use the command below:

```shell
# Uninstalled nodes
talosctl get disks --insecure --nodes <ip>

# Installed nodes
talosctl get disks --nodes <ip>
```
