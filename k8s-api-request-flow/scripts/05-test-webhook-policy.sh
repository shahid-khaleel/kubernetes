#!/usr/bin/env bash
# Stage 4: Webhook (Kyverno).
# The ClusterPolicy requiring every Pod in the deployed namespace to carry a
# 'team' label was already applied by scripts/01-deploy.sh (as
# require-team-label-<env>). This proves it by creating a non-compliant pod
# and a compliant one.
#
# Usage: bash scripts/05-test-webhook-policy.sh [dev|staging|prod]  (defaults to dev)
# Requires: scripts/01-deploy.sh <env> already run (installs the ClusterPolicy too).
set -euo pipefail

ENV="${1:-dev}"
NAMESPACE="k8s-flow-${ENV}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
F="${PROJECT_DIR}/fixtures"

echo "== Clearing any pods left over from a previous run (keeps this script order-independent) =="
kubectl delete pod --all -n "${NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null

MODE=$(kubectl get clusterpolicy "require-team-label-${ENV}" -o jsonpath='{.spec.validationFailureAction}' 2>&1)
echo
echo "Policy require-team-label-${ENV} is in '${MODE}' mode."
if [ "$MODE" = "Audit" ]; then
  echo "(dev only enforces this policy in Audit mode -- non-compliant pods are"
  echo " logged/reported but NOT blocked. staging/prod use Enforce, which blocks.)"
fi

echo
echo "== Pod WITHOUT the required 'team' label =="
kubectl apply -n "${NAMESPACE}" -f "${F}/pod-missing-label.yaml" 2>&1 || true
echo
if [ "$MODE" = "Enforce" ]; then
  echo "Expected: blocked with a message from 'require-team-label-${ENV}' policy,"
  echo "'Every pod must have a team label so we know who owns it.'"
else
  echo "Expected: created anyway (Audit mode doesn't block) -- check"
  echo "'kubectl get policyreport -n ${NAMESPACE}' to see the violation was still recorded."
fi

echo
echo "== Pod WITH the required 'team' label =="
kubectl apply -n "${NAMESPACE}" -f "${F}/pod-with-label.yaml"
echo
echo "Expected: created successfully. This request passed Authentication,"
echo "Authorization, built-in Admission Controllers, AND the Kyverno webhook --"
echo "the full pipeline, ending in 'Pod Created'."
