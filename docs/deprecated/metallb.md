## Configuring MetalLB

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
