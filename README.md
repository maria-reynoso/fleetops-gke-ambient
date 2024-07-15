# Istio Ambient on GKE


## Deploy cluster

```sh
make cluster
```

## Install Istio with ambient mode

By default in GKE, only kube-system has a defined ResourceQuota for the node-critical class. istio-cni and ztunnel both require the node-critical class, check the [docs](https://istio.io/latest/docs/ambient/install/platform-prerequisites/#google-kubernetes-engine-gke)

Create ResourceQuota into istio-system namespace:

```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gcp-critical-pods
  namespace: istio-system
spec:
  hard:
    pods: 1000
  scopeSelector:
    matchExpressions:
    - operator: In
      scopeName: PriorityClass
      values:
      - system-node-critical
EOF
```

Install the Kubernetes Gateway API CRDs:

```sh
make ambient
```

## Deploy app

Deploy bank of anthos app in 2 different namespaces, one for ambient mode and the other one for sidecar mode:

```sh
# Namespace bank-of-ambient
make app-ambient
```

```sh
# Namespace bank-of-sidecar
make app-sidecar
```

Add applicatioin to ambient

```sh
kubectl label namespace bank-of-ambient istio.io/dataplane-mode=ambient
```

Add applicatioin to the mesh using sidcecars

```sh
kubectl label namespace bank-of-sidecar istio-injection=enabled
```

_Note that you can apply this label to a namespace or to a single spsecific pod_

traffic test:

```sh
# TODO
```