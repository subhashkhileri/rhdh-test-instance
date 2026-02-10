NAMESPACE ?= rhdh
VERSION ?= 1.9
RUNNER_IMAGE ?= quay.io/rhdh-community/rhdh-e2e-runner:main
OC_LOGIN ?=

# ── Deploy ────────────────────────────────────────────────────────────────────

.PHONY: deploy-helm deploy-helm-orch deploy-operator deploy-operator-orch

deploy-helm: ## Deploy RHDH via Helm
	./deploy.sh helm $(VERSION) --namespace $(NAMESPACE)

deploy-helm-orch: ## Deploy RHDH via Helm with orchestrator
	./deploy.sh helm $(VERSION) --namespace $(NAMESPACE) --with-orchestrator

deploy-operator: ## Deploy RHDH via Operator (requires runner)
	$(MAKE) run-in-runner CMD="./deploy.sh operator $(VERSION) --namespace $(NAMESPACE)"

deploy-operator-orch: ## Deploy RHDH via Operator with orchestrator (requires runner)
	$(MAKE) run-in-runner CMD="./deploy.sh operator $(VERSION) --namespace $(NAMESPACE) --with-orchestrator"

# ── Cleanup ───────────────────────────────────────────────────────────────────

.PHONY: undeploy-helm undeploy-operator undeploy-infra clean

undeploy-helm: ## Uninstall Helm RHDH release
	helm uninstall redhat-developer-hub -n $(NAMESPACE) || true
	oc delete configmap app-config-rhdh -n $(NAMESPACE) --ignore-not-found
	oc delete secret rhdh-secrets -n $(NAMESPACE) --ignore-not-found

undeploy-operator: ## Remove Operator RHDH deployment
	oc delete backstage developer-hub -n $(NAMESPACE) --ignore-not-found
	oc delete configmap app-config-rhdh dynamic-plugins -n $(NAMESPACE) --ignore-not-found
	oc delete secret rhdh-secrets -n $(NAMESPACE) --ignore-not-found

undeploy-infra: ## Uninstall orchestrator infra chart
	helm uninstall orchestrator-infra -n $(NAMESPACE) || true

clean: ## Delete the entire namespace
	oc delete project $(NAMESPACE) --ignore-not-found

# ── Status ────────────────────────────────────────────────────────────────────

.PHONY: status logs url

status: ## Show deployment status
	@echo "=== Namespace: $(NAMESPACE) ==="
	@oc get pods -n $(NAMESPACE) 2>/dev/null || echo "Namespace not found"
	@echo ""
	@echo "=== Helm Releases ==="
	@helm list -n $(NAMESPACE) 2>/dev/null || true
	@echo ""
	@echo "=== Orchestrator Operators ==="
	@oc get csv -n openshift-serverless-logic -o custom-columns='NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase' 2>/dev/null || echo "Not installed"

logs: ## Tail RHDH pod logs
	oc logs -f -l 'app.kubernetes.io/name=developer-hub' -n $(NAMESPACE) --tail=100

url: ## Print the RHDH URL
	@CLUSTER_ROUTER_BASE=$$(oc get route console -n openshift-console -o=jsonpath='{.spec.host}' | sed 's/^[^.]*\.//'); \
	echo "http://redhat-developer-hub-$(NAMESPACE).$${CLUSTER_ROUTER_BASE}"

# ── Runner ────────────────────────────────────────────────────────────────────

.PHONY: run-in-runner

run-in-runner: ## Run a command inside the e2e-runner container (set CMD= and OC_LOGIN=)
ifndef OC_LOGIN
	$(error OC_LOGIN is required. Usage: make deploy-operator OC_LOGIN="oc login --token=... --server=...")
endif
ifndef CMD
	$(error CMD is required)
endif
	podman run --rm \
		-v $(CURDIR):/workspace:z \
		-w /workspace \
		-e KUBECONFIG=/tmp/.kube/config \
		$(RUNNER_IMAGE) \
		bash -c 'mkdir -p /tmp/.kube && $(OC_LOGIN) --insecure-skip-tls-verify=true && source .env && $(CMD)'

# ── Help ──────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
