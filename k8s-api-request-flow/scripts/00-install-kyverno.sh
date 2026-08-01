#!/usr/bin/env bash
# Installs Kyverno (the admission webhook engine for stage 4 of the flow).
# Run once. Idempotent -- safe to re-run.
set -euo pipefail

echo "== Installing Kyverno =="
# --server-side is required: Kyverno's largest CRDs exceed the annotation
# size limit that client-side `kubectl apply` hits via last-applied-configuration.
kubectl apply --server-side --force-conflicts -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml

echo
echo "== Waiting for Kyverno pods to become Ready (this can take a couple minutes) =="
kubectl -n kyverno wait --for=condition=Ready pod --all --timeout=300s

echo
echo "Kyverno is installed. It registered itself as a ValidatingWebhookConfiguration"
echo "(and MutatingWebhookConfiguration) -- this is the exact 'Webhook (OPA/Kyverno)'"
echo "stage in the request flow diagram."
kubectl get validatingwebhookconfigurations 2>&1 | grep -i kyverno || true
