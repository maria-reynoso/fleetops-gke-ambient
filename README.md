# Istio Ambient on GKE


## Deploy cluster

```sh
make cluster
```

## Install Istio with ambient mode

By default in GKE, only kube-system has a defined ResourceQuota for the node-critical class. istio-cni and ztunnel both require the node-critical class, check the [docs](https://istio.io/latest/docs/ambient/install/platform-prerequisites/#google-kubernetes-engine-gke)

Create ResourceQuota into istio-system namespace:

```sh
kubectl create namespace istio-system
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

Add your application to ambient
_Note that you can apply this label to a namespace or to a single spsecific pod_

```sh
kubectl label namespace bank-of-ambient istio.io/dataplane-mode=ambient
```

Add the same application to the mesh using sidcecars in a different namespace:

```sh
kubectl label namespace bank-of-sidecar istio-injection=enabled
```

Restart pods:

```sh
kubectl -n bank-of-sidecar rollout restart deploy
```

Deploy Gateway and VirtualService to access the frontend through the IngressGateway:

```sh
kubectl apply -f frontend-ingress.yaml -n bank-of-ambient
```

Check logs of Ztunnel

```sh
kubectl logs -n istio-system $ZTUNNEL_POD
```

Debbug Ztunnel:

```sh
istioctl x ztunnel-config workloads
```

## Viewing your mesh dashboard

Google Monitoring app metrics dashboard:

```sh
gcloud monitoring dashboards create --config-from-file=dashboard.json
```

Deploy Kiali, prometheus, grafana:

```sh
kubectl apply -f addons
```

```sh
istioctl dashboard kiali
```

```sh
istioctl dashboard grafana
```

## Performance testing

We will use [Fortio](https://fortio.org/), which is a load testing tool developed by Istio.

Let's first deploy the Fortio operator:

```sh
kubectl create -f https://raw.githubusercontent.com/verfio/fortio-operator/master/deploy/fortio.yaml
```