#!/usr/bin/env bash
# Installs OPA Gatekeeper (a second, independent admission webhook engine)
# so the same policy concept can be compared against Kyverno's approach.
# Run once. Idempotent -- safe to re-run.
set -euo pipefail

echo "== Installing OPA Gatekeeper =="
kubectl apply --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml

echo
echo "== Waiting for Gatekeeper pods to become Ready (this can take a couple minutes) =="
kubectl -n gatekeeper-system wait --for=condition=Ready pod --all --timeout=300s

echo
echo "Gatekeeper is installed. It registered its own"
echo "ValidatingWebhookConfiguration, independent of Kyverno's."
kubectl get validatingwebhookconfigurations 2>&1 | grep -i gatekeeper || true
