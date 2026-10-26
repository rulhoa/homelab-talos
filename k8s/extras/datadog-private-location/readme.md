
# Commands

Obtain the worker-config-*.json file from the datadog UI, update it below accordingly, and run the command.

```shell
kubectl create secret generic private-location-worker-config --from-file=worker-config-datadog-private-location-talos-ef8c2830a95c9b1f1cad3179f8e6dd5b.json -n datadog-private-location
```
