#!/usr/bin/env bash
# Computes a sha256 checksum of the ConfigMap's CURRENT contents in the
# cluster (the source of truth) and injects it into the Deployment's pod
# template as a `checksum/config` annotation before applying. Because the
# pod template hash changes whenever the checksum changes, this alone is
# enough to force a rolling update on every ConfigMap edit - the same
# technique Helm charts use.
set -euo pipefail
cd "$(dirname "$0")/.."

NAMESPACE=configmap-rotations

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst is required (part of gettext). On Windows, run this from Git Bash/WSL." >&2
  exit 1
fi

CONFIG_CHECKSUM=$(kubectl get configmap config-demo-config -n "$NAMESPACE" -o jsonpath='{.data}' | sha256sum | cut -d' ' -f1)
export CONFIG_CHECKSUM

envsubst < k8s/deployment.yaml.tmpl | kubectl apply -f -

echo "Applied Deployment with checksum/config=${CONFIG_CHECKSUM}"
