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
make ambient
```

## Deploy app

```sh
make app
```

Add applicatioin to ambient

```sh
kubectl label namespace bank-of-anthos istio.io/dataplane-mode=ambient
```

_Note that you can apply this label to a namespace or to a single spsecific pod_

traffic test:

```sh
# TODO
```