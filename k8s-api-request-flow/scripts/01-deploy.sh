#!/usr/bin/env bash
# Deploys the scaffolding (namespace, RBAC, LimitRange, ResourceQuota) and
# the Kyverno ClusterPolicy for one environment.
#
# Usage: bash scripts/01-deploy.sh [dev|staging|prod]   (defaults to dev)
set -euo pipefail

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

case "$ENV" in
  dev|staging|prod) ;;
  *) echo "Unknown environment '$ENV' (expected dev|staging|prod)" >&2; exit 1 ;;
esac

echo "== Deploying overlays/${ENV} =="
kubectl apply -k "${PROJECT_DIR}/overlays/${ENV}"

echo
echo "== Deploying overlays/${ENV}/cluster-policy (requires Kyverno installed -- see scripts/00-install-kyverno.sh) =="
kubectl apply -k "${PROJECT_DIR}/overlays/${ENV}/cluster-policy"

echo
echo "Namespace k8s-flow-${ENV} is ready."
