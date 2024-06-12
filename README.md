# fleetops-gke-ambient

## Pre-requisites
- Have a cluster running a supported version of Kubernetes (1.27, 1.28, 1.29, 1.30), (GKE for this case) which has outbound access to the internet, specifically using a tenant from the TLS Protect Cloud domain.
- A valid Venafi Cloud Firefly account. You can sign up for a 30 day trial [here](https://venafi.com/try-venafi/firefly/)
- Network access to our public ECR repository domain (registry.venafi.cloud/public/venafi-images) to pull our public image and OCI chart


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

## Installing cert-manager

```sh
# Helm setup
helm repo add jetstack https://charts.jetstack.io
helm repo update

# install cert-manager; this might take a little time
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.15.0 \
  --set crds.enabled=true

# We need this namespace to exist since our cert will be placed there
kubectl create namespace istio-system
```

## TLS Protect Cloud setup

Alternative elevate tool can be used in order to configure TLS Protect Cloud:
```sh
docker run -v ${PWD}:<your_directory> mattiasgees/elevate:latest add -f <your_directory>/config.yaml --api-address https://api.eu.venafi.cloud -s <private_key_path> --api-key ${TLSPC_API_KEY} -t <TEAM> -p <subCA> --force


-t is for team....the SA will be named after that
-p is the subCA to use
--force to create subCA if doesn't exits
-s private key path
```

1. Signup for a [Venafi account](https://venafi.com/try-venafi/firefly/) if you don't have one

2. Generate an RSA public private pem key pair using OpenSSL:

  ```sh
  openssl genrsa -out key.pem
  openssl rsa -in key.pem -outform PEM -pubout -out public.pem
  ```

3. Create a service account in the Firefly UI using the RSA public key you generated above. You can refer to the [documentation](https://docs.venafi.cloud/firefly/service-accounts/#create-a-new-service-account) for more details.

Copy the CLIENT_ID from the service account just created.

```sh
CLIENT_ID=39687224-228e-11ef-abc9-9618982ef33c
```

4. Create workload certificate policy: https://docs.venafi.cloud/firefly/policies/

Add the following values

Subject Alternative Names (SAN):
 
```sh
# DNS
istiod-basic.istio-system.svc
istiod.istio-system.svc
istio-csr.istio-system.svc
cert-manager-istio-csr.istio-system.svc
```

We will set a URI SPIFFE SAN since Istio follows the SPIFFE standard for workload identity.

```sh
# URI Address (SAN)
^spiffe://cluster\.local/ns/.*/sa/.*
```

5. Create sub-ca provider: https://docs.venafi.cloud/firefly/policies/#to-create-a-policy

6. Create configuration: https://docs.venafi.cloud/firefly/configurations/#create-a-configuration

## Firefly Helm chart installation

```sh
kubectl create ns venafi
kubectl create secret generic -n venafi venafi-credentials --from-file=svc-acct.key=key.pem
```

Setup Firefly-values.yaml

```yaml
# -- Setting acceptTerms to true is required to consent to the terms and conditions
acceptTerms: true
deployment:
  image: registry.venafi.cloud/public/venafi-images/firefly
  # -- Toggle for running the firefly controller inside the kubernetes
  # cluster as an in-cluster Certificate Authority (CA).
  enabled: true
  # -- (string) REQUIRED: The ClientID of a your TLS Protect Cloud service account associated with the desired configuration.                                                          
  venafiClientID: "<REPLACE_WITH_CLIENT_ID_OF_THE_SERVICEACCOUNT>"
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      add: ["IPC_LOCK"]
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 1001
crd:
  # -- Installs the CRD in the cluster. Required to enable firefly with
  # the given group.
  enabled: true
  # -- Group name of the issuer.
  groupName: firefly.venafi.com  
approver:
    # -- Enable or disable the creation of a ClusterRole and ClusterRoleBinding
    # to allow an approver to approve CertificateRequest resources which use
    # the Firefly issuer group name.
    enabled: true
    # -- The subject which will be granted permission to approve
    # CertifcateRequest resources which use the Firefly issuer group.
    subject:
      kind: ServiceAccount
      namespace: cert-manager
      name: cert-manager-approver-policy
```

Install Firefly:

```sh
helm upgrade firefly oci://registry.venafi.cloud/public/venafi-images/helm/firefly \
  --install \
  --create-namespace \
  --namespace venafi \
  --values charts/firefly/values.yaml \
  --version v1.2.1
```

Update vass endpoint in the firefly-config configmap:

```sh
kubectl edit cm firefly-config -n venafi
```

```yaml
# This will fixed by merging this PR: https://gitlab.com/venafi/vaas/applications/tls-protect/dmi/cli/firefly-ca/-/merge_requests/343
apiVersion: v1
data:
  config.yaml: |-
    bootstrap:
      vaas:
        url: https://api.eu.venafi.cloud.
        auth:
          privateKeyFile: /var/run/secrets/firefly.venafi.com/svc-acct.key
```

Check readness status in the logs to confirm that it bootstrapped itself an issuer certificate successfully!:

```sh
I0713 13:55:15.444872       1 vaas.go:123] agent/bootstrap/vaas "msg"="issued intermediate certificate from VaaS" "CN=firefly.."
```

## Istio-csr setup

helm chart values:

```yaml
replicaCount: 3
image:
  repository: quay.io/jetstack/cert-manager-istio-csr
  tag: v0.7.0
  pullPolicy: IfNotPresent
app:
  certmanager:
    namespace: istio-system
    preserveCertificateRequests: false
    additionalAnnotations:
    - name: firefly.venafi.com/policy-name
      value: <REPLACE_WITH_POLICY_NAME_FROM_TLSPROTECT_CLOUD>
    issuer:
      group: firefly.venafi.com
      kind: Issuer
      name: firefly-istio
  controller:
    configmapNamespaceSelector: "maistra.io/member-of=istio-system"
    leaderElectionNamespace: istio-system
  istio:
    namespace: istio-system
    revisions: ["basic"]

  tls:
    trustDomain: cluster.local
    certificateDNSNames:
    - istio-csr.istio-system.svc
    - cert-manager-istio-csr.istio-system.svc
    rootCAFile: /etc/tls/root-cert.pem
  server:
    maxCertificateDuration: 1h
    serving:
      address: 0.0.0.0
      port: 6443
# -- Optional extra volumes. Useful for mounting custom root CAs
volumes:
- name: root-ca
  secret:
    secretName: root-cert

# -- Optional extra volume mounts. Useful for mounting custom root CAs
volumeMounts:
- name: root-ca
  mountPath: /etc/tls
```

Before you apply the above, you need to create the root of trust. You can download this from CA Account -> Built-in CA -> Download chain -> Root certificate first.

Take the first certificate that you downloaded, the root and save it to a file root.pem.

This will be the mesh’s root of trust and will be managed by istio-csr through the usual istio-ca-root-cert.

You can now run the installation:

```sh
kubectl create ns istio-system
kubectl create secret generic -n istio-system root-cert --from-file=root-cert.pem=root-cert.pem
helm upgrade -i -n istio-system cert-manager-istio-csr jetstack/cert-manager-istio-csr -f charts/istio-csr/values.yaml
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