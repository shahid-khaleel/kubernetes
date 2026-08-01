#!/usr/bin/env bash
# Stage 4c: Webhook (OPA Gatekeeper), same policy as Kyverno's, for comparison.
# Applies a ConstraintTemplate (the reusable Rego rule) + a Constraint
# (the specific instance: Pods in opa-demo must have a 'team' label), then
# proves it the same way the Kyverno demo did.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
M="${PROJECT_DIR}/manifests"

echo "== Setting up namespace + ConstraintTemplate + Constraint =="
kubectl apply -f "${M}/12-opa-demo-namespace.yaml"
kubectl apply -f "${M}/13-gatekeeper-constrainttemplate.yaml"

echo
echo "Waiting for Gatekeeper to generate the ConstraintTemplate's CRD..."
# `kubectl wait` requires the resource to already exist -- Gatekeeper's
# controller creates this CRD asynchronously after the ConstraintTemplate is
# applied, so poll for its existence first.
for i in $(seq 1 30); do
  if kubectl get crd k8srequiredlabels.constraints.gatekeeper.sh >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
kubectl wait --for=condition=Established crd/k8srequiredlabels.constraints.gatekeeper.sh --timeout=60s

kubectl apply -f "${M}/14-gatekeeper-constraint.yaml"

echo
echo "Waiting a few seconds for the constraint to become active..."
sleep 5

echo
echo "== Pod WITHOUT the required 'team' label =="
kubectl apply -f "${M}/15-pod-missing-label-opa.yaml" 2>&1 || true
echo
echo "Expected: blocked by admission webhook 'validation.gatekeeper.sh',"
echo "message 'you must provide labels: {\"team\"}'"

echo
echo "== Pod WITH the required 'team' label =="
kubectl apply -f "${M}/16-pod-with-label-opa.yaml"
echo
echo "Expected: created successfully -- same outcome as the Kyverno demo,"
echo "reached via a Rego rule instead of a Kyverno YAML pattern."
