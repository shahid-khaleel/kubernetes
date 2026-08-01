#!/usr/bin/env bash
# Stage 3: Built-in Admission Controllers.
# Two demos in the deployed environment's namespace:
#  (a) LimitRanger (mutating) injects default resource requests/limits onto
#      a pod that specified none.
#  (b) ResourceQuota (validating) blocks a pod once the namespace's pod-count
#      quota is exhausted -- quota size varies by environment (dev=3,
#      staging=2, prod=1), so this fills any remaining headroom with filler
#      pods first, then always attempts exactly one pod over the limit.
#
# Usage: bash scripts/04-test-admission-controller.sh [dev|staging|prod]  (defaults to dev)
# Requires: scripts/01-deploy.sh <env> already run.
set -euo pipefail

ENV="${1:-dev}"
NAMESPACE="k8s-flow-${ENV}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
F="${PROJECT_DIR}/fixtures"

echo "== Clearing any pods left over from a previous run (keeps this script order-independent) =="
kubectl delete pod --all -n "${NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null

echo
echo "== (a) MUTATING: creating a pod with NO resources specified, in ${NAMESPACE} =="
kubectl apply -n "${NAMESPACE}" -f "${F}/bare-pod.yaml"
echo
echo "-- What actually got created (resources injected by LimitRanger) --"
kubectl get pod bare-pod -n "${NAMESPACE}" -o jsonpath='{.spec.containers[0].resources}'
echo
echo "Expected: requests/limits appear even though bare-pod.yaml specified none."
echo "This is the LimitRanger admission controller *mutating* the object before storage."

echo
echo "== (b) VALIDATING: filling remaining quota headroom, then exceeding it by one =="
QUOTA_LIMIT=$(kubectl get resourcequota pod-count-quota -n "${NAMESPACE}" -o jsonpath='{.status.hard.pods}')
USED=$(kubectl get resourcequota pod-count-quota -n "${NAMESPACE}" -o jsonpath='{.status.used.pods}')
echo "Quota: ${USED}/${QUOTA_LIMIT} pods currently used in ${NAMESPACE}."

FILLER_COUNT=$(( QUOTA_LIMIT - USED ))
for i in $(seq 1 "${FILLER_COUNT}"); do
  kubectl run "filler-${i}" --image=nginx:alpine --labels=team=platform -n "${NAMESPACE}" >/dev/null
done
echo "Created ${FILLER_COUNT} filler pod(s) to consume remaining headroom."

echo
echo "-- Now attempting bare-pod-2, one pod over the ${QUOTA_LIMIT}-pod limit --"
kubectl apply -n "${NAMESPACE}" -f "${F}/bare-pod-2.yaml" 2>&1 || true
echo
echo "Expected: 'exceeded quota: pod-count-quota, requested: pods=1, used: pods=${QUOTA_LIMIT}, limited: pods=${QUOTA_LIMIT}'"
echo "This is the ResourceQuota admission controller *validating* (blocking) the request."
