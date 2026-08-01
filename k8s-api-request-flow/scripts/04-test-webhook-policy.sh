#!/usr/bin/env bash
# Stage 4: Webhook (Kyverno).
# Applies a ClusterPolicy requiring every Pod in `webhook-demo` to carry a
# 'team' label, then proves it by creating a non-compliant pod (blocked) and
# a compliant one (allowed -> reaches "Pod Created").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
M="${PROJECT_DIR}/manifests"

echo "== Setting up namespace + Kyverno ClusterPolicy =="
kubectl apply -f "${M}/09-webhook-demo-namespace.yaml"
kubectl apply -f "${M}/08-kyverno-require-team-label.yaml"

echo
echo "Waiting a few seconds for the policy to become active..."
sleep 5

echo
echo "== Pod WITHOUT the required 'team' label =="
kubectl apply -f "${M}/10-pod-missing-label.yaml" 2>&1 || true
echo
echo "Expected: blocked with a message from 'require-team-label' policy,"
echo "'Every pod must have a team label so we know who owns it.'"

echo
echo "== Pod WITH the required 'team' label =="
kubectl apply -f "${M}/11-pod-with-label.yaml"
echo
echo "Expected: created successfully. This request passed Authentication,"
echo "Authorization, built-in Admission Controllers, AND the Kyverno webhook --"
echo "the full pipeline, ending in 'Pod Created'."
