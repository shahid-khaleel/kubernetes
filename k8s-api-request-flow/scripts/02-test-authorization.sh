#!/usr/bin/env bash
# Stage 2: Authorization (RBAC).
# Creates a ServiceAccount bound to a Role that can only get/list/watch pods,
# then proves the RBAC boundary by (a) successfully listing pods and
# (b) being denied when trying to create one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GEN_DIR="${PROJECT_DIR}/.generated"
KUBECONFIG_VIEWER="${GEN_DIR}/viewer.kubeconfig"

mkdir -p "${GEN_DIR}"

echo "== Applying ServiceAccount + Role + RoleBinding =="
kubectl apply -f "${PROJECT_DIR}/manifests/01-rbac-viewer-sa.yaml"

echo
echo "== Minting a short-lived token for the 'viewer' ServiceAccount =="
TOKEN=$(kubectl create token viewer --namespace default --duration=1h)

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
      namespace: default
current-context: viewer-context
EOF

echo "Wrote ${KUBECONFIG_VIEWER}"
echo
echo "== As 'viewer': GET pods (allowed by the Role) =="
kubectl --kubeconfig="${KUBECONFIG_VIEWER}" get pods

echo
echo "== As 'viewer': CREATE a pod (NOT allowed by the Role) =="
kubectl --kubeconfig="${KUBECONFIG_VIEWER}" apply -f "${PROJECT_DIR}/manifests/02-test-pod.yaml" 2>&1 || true

echo
echo "Expected: pods listed successfully, but the create is rejected with"
echo "'Forbidden ... cannot create resource \"pods\"' -- Authentication succeeded"
echo "(the token was valid), but Authorization (RBAC) denied this specific verb."
