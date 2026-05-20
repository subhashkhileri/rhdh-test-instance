#!/bin/bash
set -e

# Installs the RHDH operator on the cluster (one-time setup).
# Usage: ./operator/install-operator.sh <version>

version="$1"

if [[ -z "$version" ]]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.9"
    echo "         $0 next"
    exit 1
fi

# Determine branch and version argument based on version type
# Semantic versions (e.g., "1.9") use release branches; "next" uses main
if [[ "$version" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    branch="release-${version}"
    version_arg="-v ${version}"
elif [[ "$version" == "next" ]]; then
    branch="main"
    version_arg="--next"
else
    echo "Error: Invalid version '${version}'. Use semantic version (e.g., '1.9') or 'next'."
    exit 1
fi

echo "Using operator branch: ${branch}, version arg: ${version_arg}"

# Check if RHDH operator is already installed (CRD exists AND operator CSV is present)
if oc get crd/backstages.rhdh.redhat.com &>/dev/null && oc get csv --all-namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | grep -q rhdh-operator; then
    echo "RHDH operator is already installed. Skipping."
    exit 0
fi

# Workaround for pushing to ARO cluster registries: https://access.redhat.com/solutions/6022011
# TODO: remove this when this is done by the install-rhdh-catalog-source.sh script
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"disableRedirect":true}}' --type=merge

# Downloads and runs install script for CatalogSource
curl -LO "https://raw.githubusercontent.com/redhat-developer/rhdh-operator/refs/heads/${branch}/.rhdh/scripts/install-rhdh-catalog-source.sh"
chmod +x install-rhdh-catalog-source.sh
# Fix hardcoded 'kubeadmin' username — on ARO clusters the admin user is
# 'kube:admin' and the colon breaks HTTP Basic Auth in skopeo/docker-registry.
# Use a dummy username since the internal registry validates the OAuth token, not the username.
CURRENT_USER=$(oc whoami)
if [[ "$CURRENT_USER" != "kubeadmin" ]]; then
    echo "Patching install script for non-kubeadmin cluster (user: ${CURRENT_USER})..."
    sed -i 's/skopeo login -u kubeadmin/skopeo login -u openshift/g' install-rhdh-catalog-source.sh
    sed -i 's/--docker-username=kubeadmin/--docker-username=openshift/g' install-rhdh-catalog-source.sh
    chmod +x install-rhdh-catalog-source.sh
fi
./install-rhdh-catalog-source.sh ${version_arg} --install-operator rhdh
rm install-rhdh-catalog-source.sh

# Wait for the CRD to be available
timeout 300 bash -c '
while ! oc get crd/backstages.rhdh.redhat.com >/dev/null 2>&1; do
    echo "Waiting for Backstage CRD to be created..."
    sleep 20
done
echo "Backstage CRD is created."
' || echo "Error: Timed out waiting for Backstage CRD creation."

echo "RHDH operator installed successfully."
