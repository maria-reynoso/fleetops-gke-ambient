# Istio Ambient on GKE


## Deploy cluster

TODO: Deploy with Makefile
```sh
export PROJECT_ID=`gcloud config get-value project` && \
export M_TYPE=n1-standard-2 && \
export ZONE=europe-west2-a && \
export CLUSTER_NAME="ambient-mode" && \
gcloud services enable container.googleapis.com && \
gcloud container clusters create $CLUSTER_NAME \
  --cluster-version latest \
  --machine-type=$M_TYPE \
  --num-nodes 4 \
  --zone $ZONE \
  --project $PROJECT_ID
```

Retrieve credentials:

```sh
gcloud container clusters get-credentials $CLUSTER_NAME
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
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v1.1.0" | kubectl apply -f -; }
```

```sh
# The base chart contains the basic CRDs and cluster roles required to set up Istio
helm upgrade -i istio-base istio/base --version 1.22 -n istio-system --set defaultRevision=default
# Install CNI
helm install istio-cni istio/cni -n istio-system --set profile=ambient --version 1.22 --wait
# Install Istiod
helm upgrade -i istiod istio/istiod --namespace istio-system --set profile=ambient --version 1.22 -f charts/istio/values.yaml --wait
# Install the ztunnel component
helm upgrade -i ztunnel istio/ztunnel -n istio-system -f charts/istio/ztunnel-values.yaml --version 1.22 --wait
```

## Deploy app

```sh
kubectl apply -f samples/bookinfo.yaml
kubectl apply -f samples/bookinfo-versions.yaml
```

sleep and notsleep are two simple applications that can serve as curl clients

```sh
kubectl apply -f samples/sleep.yaml
kubectl apply -f samples/notsleep.yaml
```

Create a Kubernetes Gateway and HTTPRoute:

```sh
kubectl apply -f samples/bookinfo-gateway.yaml
```

Add applicatioin to ambient

```sh
kubectl label namespace default istio.io/dataplane-mode=ambient
```

traffic test:

```sh
kubectl exec deploy/sleep -- curl -s "http://$GATEWAY_HOST/productpage" | grep -o "<title>.*</title>"
kubectl exec deploy/sleep -- curl -s http://productpage:9080/ | grep -o "<title>.*</title>"
kubectl exec deploy/notsleep -- curl -s http://productpage:9080/ | grep -o "<title>.*</title>"
# output: <title>Simple Bookstore App</title>
```