# Istio Ambient on GKE

To demonstrate Ambient on a GKE cluster and comparing resources consumption and latency between ambient and sidecars.

## Requirements

- Install [istioctl](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/#install-hahahugoshortcode709s2hbhb)
- GCP Account

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
git clone https://github.com/GoogleCloudPlatform/bank-of-anthos.git
# Namespace bank-of-ambient
make app-ambient
# Namespace bank-of-sidecar
make app-sidecar
```

## Viewing your mesh dashboard

(Optional) Google Monitoring app metrics dashboard:

```sh
gcloud monitoring dashboards create --config-from-file=dashboard.json
```

Deploy Kiali, prometheus, grafana:

```sh
kubectl apply -f addons
```

Access dashboards:

```sh
istioctl dashboard kiali
```

```sh
istioctl dashboard grafana
```

Add the [grafana dashboard](./ambient-performance-analysis.json)

## Adding application to the mesh

Add the same application to the mesh using sidcecars in a different namespace:

```sh
kubectl label namespace bank-of-sidecar istio-injection=enabled
```

Restart pods:

```sh
kubectl -n bank-of-sidecar rollout restart deploy
```

Add your application to ambient
_Note that you can apply this label to a namespace or to a single spsecific pod_

```sh
kubectl label namespace bank-of-ambient istio.io/dataplane-mode=ambient
```

Deploy Gateway and VirtualService to access the frontend through the IngressGateway:

```sh
kubectl apply -f frontend-ingress.yaml -n bank-of-ambient
```

Check logs of Ztunnel

First install [stern](https://github.com/stern/stern) in your workstation.

```sh
stern ztunnel -n istio-system
```

Debbug Ztunnel:

```sh
istioctl ztunnel-config workloads
```

## Mesh in action

send traffic:

```sh
export GATEWAY_HOST_EXT=$(kubectl get service/istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' -n istio-ingress)
curl http://$GATEWAY_HOST_EXT
```

Access kiali and see the graph

```sh
istioctl dashboard kiali
```

Deploy the simple sleep service. This will be used to curl our frontend

```sh
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/sleep/sleep.yaml -n bank-of-ambient
```

Create an authorization policy to only allow calls from istio-ingress and sleep service:

```sh
kubectl apply -f authorization-policy.yaml
```

Compare resources consumption. Access grafana dashboard

```sh
istioctl dashboard grafana
```

## Waypoint proxies

Install Kubernetes Gateway API CRDs. Waypoint proxies uses Gateway APIs and acts as Gateways.

```sh
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v1.1.0" | kubectl apply -f -; }
```

Enable waypoint proxy

```sh
istioctl waypoint apply --enroll-namespace -n bank-of-ambient --wait
```

Validate a Pod and a Gateway is created for waypoint proxy

```sh
kubectl get pods -n bank-of-ambient
kubectl get gtw -n bank-of-ambient
```

Autorization policy

```sh
kubectl apply -f L7-policy.yaml
```

Verify the new waypoint proxy is enforcing the authorization policy:

```sh
export SLEEP_POD=$(kubectl get pods -n bank-of-ambient -l app=sleep -o 'jsonpath={.items[0].metadata.name}')
kubectl exec -it $SLEEP_POD -n bank-of-ambient -- curl frontend -X DELETE
```

## Performance testing

We will use [Fortio](https://fortio.org/), which is a load testing tool developed by Istio.

```sh
kubectl apply -f fortio.yaml
```

Launch Fortio web interface to configure and perform latency tests:

```sh
kubectl port-forward svc/fortio 8080:8080
```
