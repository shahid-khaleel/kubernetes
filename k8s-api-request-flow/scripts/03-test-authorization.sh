#!/usr/bin/env bash
# Stage 2: Authorization (RBAC).
# Uses the 'viewer' ServiceAccount deployed by scripts/01-deploy.sh (Role:
# get/list/watch pods only), mints it a real token, and proves the RBAC
# boundary: listing pods succeeds, creating one is denied.
#
# Usage: bash scripts/03-test-authorization.sh [dev|staging|prod]  (defaults to dev)
# Requires: scripts/01-deploy.sh <env> already run.
set -euo pipefail

ENV="${1:-dev}"
NAMESPACE="k8s-flow-${ENV}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GEN_DIR="${PROJECT_DIR}/.generated"
KUBECONFIG_VIEWER="${GEN_DIR}/viewer-${ENV}.kubeconfig"

mkdir -p "${GEN_DIR}"

echo "== Minting a short-lived token for 'viewer' in ${NAMESPACE} =="
TOKEN=$(kubectl create token viewer --namespace "${NAMESPACE}" --duration=1h)

SERVER=$(kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat > "${KUBECONFIG_VIEWER}" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: minikube
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA_DATA}
users:
  - name: viewer
    user:
      token: ${TOKEN}
contexts:
  - name: viewer-context
    context:
      cluster: minikube
      user: viewer
      namespace: ${NAMESPACE}
current-context: viewer-context
EOF

echo "Wrote ${KUBECONFIG_VIEWER}"
echo
echo "== As 'viewer': GET pods in ${NAMESPACE} (allowed by the Role) =="
kubectl --kubeconfig="${KUBECONFIG_VIEWER}" get pods

echo
echo "== As 'viewer': CREATE a pod in ${NAMESPACE} (NOT allowed by the Role) =="
kubectl --kubeconfig="${KUBECONFIG_VIEWER}" apply -n "${NAMESPACE}" -f "${PROJECT_DIR}/fixtures/test-pod.yaml" 2>&1 || true

echo
echo "Expected: pods listed successfully, but the create is rejected with"
echo "'Forbidden ... cannot create resource \"pods\"' -- Authentication succeeded"
echo "(the token was valid), but Authorization (RBAC) denied this specific verb."
