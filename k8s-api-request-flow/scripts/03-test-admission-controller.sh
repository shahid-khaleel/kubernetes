#!/usr/bin/env bash
# Stage 3: Built-in Admission Controllers.
# Two demos in the same namespace:
#  (a) LimitRanger (mutating) injects default resource requests/limits onto
#      a pod that specified none.
#  (b) ResourceQuota (validating) blocks a pod once the namespace's pod-count
#      quota is exhausted.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
M="${PROJECT_DIR}/manifests"

echo "== Setting up namespace, LimitRange, ResourceQuota =="
kubectl apply -f "${M}/03-admission-namespace.yaml"
kubectl apply -f "${M}/04-limitrange.yaml"
kubectl apply -f "${M}/05-resourcequota.yaml"

echo
echo "== (a) MUTATING: creating a pod with NO resources specified =="
kubectl apply -f "${M}/06-bare-pod.yaml"
echo
echo "-- What actually got created (resources injected by LimitRanger) --"
kubectl get pod bare-pod -n admission-demo -o jsonpath='{.spec.containers[0].resources}'
echo
echo "Expected: requests/limits appear even though 06-bare-pod.yaml specified none."
echo "This is the LimitRanger admission controller *mutating* the object before storage."

echo
echo "== (b) VALIDATING: creating a second pod when quota only allows 1 =="
kubectl apply -f "${M}/07-bare-pod-2.yaml" 2>&1 || true
echo
echo "Expected: 'exceeded quota: pod-count-quota, requested: pods=1, used: pods=1, limited: pods=1'"
echo "This is the ResourceQuota admission controller *validating* (blocking) the request."
