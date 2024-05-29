### Notes

Requirements
- have a cluster running a supported version of Kubernetes (1.27, 1.28, 1.29, 1.30), (GKE for this case)
- Install certmanager
  - self-signed root CA
  - Deploy a cert-manager Issuer
- Install istio-csr via Helm
- Create istio-system namespace
- Create a ResourceQuota on the istio-system namespace
- Install Istio ambient mode (https://istio.io/latest/docs/ambient/getting-started/)
  - Download latest Istio version (1.22)


Note that ambient mode currently requires the use of istio-cni to configure Kubernetes nodes, which must run as a privileged pod