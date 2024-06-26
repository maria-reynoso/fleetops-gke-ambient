# gcloud
export CLUSTER_NAME = fleetops

##@ Help
help: ## Show this screen (default behaviour of `make`)
	@echo ${PURPOSE}
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

# deploy-prometheus: ## Deploy Promtheus
# 	kubectl apply -f prometheus

# deploy-alertmanager: ## Deploy Alertmanager
# 	kubectl apply -f alertmanager

cleanup: ## Cleaup
	$(CURDIR)/cleanup.sh

