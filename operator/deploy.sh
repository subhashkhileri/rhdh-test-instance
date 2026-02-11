#!/bin/bash
set -e

# Deploys an RHDH instance via the operator.
# Assumes the operator is already installed (run install-operator.sh first).

namespace="$1"
version="$2"

if [[ -z "$namespace" || -z "$version" ]]; then
    echo "Usage: $0 <namespace> <version>"
    exit 1
fi

# Determine branch based on version type
# Semantic versions (e.g., "1.9") use release branches; "next" uses main
if [[ "$version" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    branch="release-${version}"
elif [[ "$version" == "next" ]]; then
    branch="main"
else
    echo "Error: Invalid version '${version}'. Use semantic version (e.g., '1.9') or 'next'."
    exit 1
fi

echo "Using operator branch: ${branch}"

# Ensure operator is installed
if ! oc get crd/backstages.rhdh.redhat.com &>/dev/null; then
    echo "Error: RHDH operator not found. Run 'make install-operator' first."
    exit 1
fi

# Install orchestrator infrastructure if requested
if [[ "${WITH_ORCHESTRATOR}" == "1" ]]; then
    if oc get pods -n openshift-serverless --no-headers 2>/dev/null | grep -q . && \
       oc get pods -n openshift-serverless-logic --no-headers 2>/dev/null | grep -q .; then
        echo "Serverless operators already running on cluster, skipping orchestrator infra."
    else
        echo "Installing orchestrator infrastructure via plugin-infra.sh..."
        curl -LO "https://raw.githubusercontent.com/redhat-developer/rhdh-operator/refs/heads/${branch}/config/profile/rhdh/plugin-infra/plugin-infra.sh"
        chmod +x plugin-infra.sh
        ./plugin-infra.sh --branch "${branch}"
        rm plugin-infra.sh
        echo "Orchestrator infrastructure installed successfully."
    fi
fi

# Catalog index tag defaults to the major.minor version, or "next" for next
if [[ "$version" == "next" ]]; then
    export CATALOG_INDEX_TAG="${CATALOG_INDEX_TAG:-next}"
else
    export CATALOG_INDEX_TAG="${CATALOG_INDEX_TAG:-$(echo "$version" | grep -oE '^[0-9]+\.[0-9]+')}"
fi
echo "Using catalog index tag: ${CATALOG_INDEX_TAG}"

# Detect protocol based on cluster route TLS configuration
if oc get route console -n openshift-console -o=jsonpath='{.spec.tls.termination}' 2>/dev/null | grep -q .; then
    RHDH_PROTOCOL="https"
else
    RHDH_PROTOCOL="http"
fi
export RHDH_BASE_URL="${RHDH_PROTOCOL}://backstage-developer-hub-${namespace}.${CLUSTER_ROUTER_BASE}"

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

envsubst < operator/subscription.yaml | oc apply -f - -n "$namespace"
