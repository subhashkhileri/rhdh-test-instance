#!/bin/bash
set -e

# Parse arguments
namespace="$1"
version="$2"

if [[ -z "$namespace" || -z "$version" ]]; then
    echo "Usage: $0 <namespace> <version>"
    exit 1
fi

# Downloads and runs install script for CatalogSource
curl -LO https://raw.githubusercontent.com/redhat-developer/rhdh-operator/refs/heads/release-$version/.rhdh/scripts/install-rhdh-catalog-source.sh
chmod +x install-rhdh-catalog-source.sh
./install-rhdh-catalog-source.sh -v $version --install-operator rhdh
rm install-rhdh-catalog-source.sh

# Install orchestrator infrastructure if requested
if [[ "${WITH_ORCHESTRATOR}" == "1" ]]; then
    echo "Installing orchestrator infrastructure via plugin-infra.sh..."
    curl -LO "https://raw.githubusercontent.com/redhat-developer/rhdh-operator/refs/heads/release-${version}/config/profile/rhdh/plugin-infra/plugin-infra.sh"
    chmod +x plugin-infra.sh
    ./plugin-infra.sh
    rm plugin-infra.sh
    echo "Orchestrator infrastructure installed successfully."
fi

export RHDH_BASE_URL="http://backstage-developer-hub-${namespace}.${CLUSTER_ROUTER_BASE}"

# Apply secrets
envsubst < config/rhdh-secrets.yaml | oc apply -f - --namespace="$namespace"

# Create dynamic-plugins ConfigMap
if [[ "${WITH_ORCHESTRATOR}" == "1" ]]; then
    echo "Merging orchestrator plugins into dynamic-plugins configuration..."
    ORCH_PLUGINS=$(cat config/orchestrator-dynamic-plugins.yaml | grep -A 100 '^plugins:' | tail -n +2)
    oc create configmap dynamic-plugins \
        --from-file=dynamic-plugins.yaml=<(cat config/dynamic-plugins.yaml; echo ""; echo "$ORCH_PLUGINS") \
        --namespace="$namespace" \
        --dry-run=client -o yaml | oc apply -f -
else
    oc create configmap dynamic-plugins \
        --from-file="config/dynamic-plugins.yaml" \
        --namespace="$namespace" \
        --dry-run=client -o yaml | oc apply -f -
fi

timeout 300 bash -c '
while ! oc get crd/backstages.rhdh.redhat.com -n "${namespace}" >/dev/null 2>&1; do
    echo "Waiting for Backstage CRD to be created..."
    sleep 20
done
echo "Backstage CRD is created."
' || echo "Error: Timed out waiting for Backstage CRD creation."

oc apply -f "operator/subscription.yaml" -n "$namespace"
