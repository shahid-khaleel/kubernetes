#!/usr/bin/env bash
# Fires N requests at the in-cluster Service so kube-proxy round-robins
# across all Pod replicas. This is important: `kubectl port-forward` to a
# Service sticks to a single backend pod for the whole session, so it
# CANNOT show you a mix of old/new responses during a rollout - only
# hitting the Service from inside the cluster (or a real LoadBalancer/
# Ingress from outside) reveals that.
# Usage: ./scripts/observe.sh [count] [delaySeconds]
set -euo pipefail

NAMESPACE=configmap-rotations
COUNT="${1:-30}"
DELAY="${2:-0.5}"

kubectl run config-demo-observer --rm -i --restart=Never \
  --image=curlimages/curl -n "$NAMESPACE" -- \
  sh -c "for i in \$(seq 1 $COUNT); do curl -s http://config-demo/feature; echo; sleep $DELAY; done"
