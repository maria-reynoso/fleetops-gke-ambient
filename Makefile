.DEFAULT_GOAL := help

CLUSTER_NAME := ambient
PROJECT_ID := "$(shell gcloud config get-value project)
M_TYPE := n1-standard-2
ZONE := europe-west2-a

cluster: ## Setup cluster
	gcloud services enable container.googleapis.com
	gcloud container clusters describe ${CLUSTER_NAME} || gcloud container clusters create ${CLUSTER_NAME} \
		--cluster-version latest \
		--machine-type=${M_TYPE} \
		--num-nodes 4 \
		--zone ${ZONE} \
		--project ${PROJECT_ID}
	gcloud container clusters get-credentials ${CLUSTER_NAME}

ambient: ## Install Istio with ambient profile
	helm upgrade -i istio-base istio/base --version 1.22 -n istio-system --set defaultRevision=default 
	helm install istio-cni istio/cni -n istio-system --set profile=ambient --version 1.22 --wait
	helm upgrade -i istiod istio/istiod --namespace istio-system --set profile=ambient --version 1.22 -f charts/istio/values.yaml --wait
	helm upgrade -i ztunnel istio/ztunnel -n istio-system -f charts/istio/ztunnel-values.yaml --version 1.22 --wait
	helm install istio-ingress istio/gateway --namespace istio-ingress --version 1.22 --wait

app: ## Deploy bank of anthos
	kubectl create namespace bank-of-anthos
	kubectl apply -f bank-of-anthos/extras/jwt/jwt-secret.yaml -n bank-of-anthos
	kubectl apply -f bank-of-anthos/kubernetes-manifests -n bank-of-anthos

cleanup: ## Cleaup
	gcloud container clusters delete ${CLUSTER_NAME}

help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m \t%s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
