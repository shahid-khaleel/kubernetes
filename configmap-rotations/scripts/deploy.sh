#!/usr/bin/env bash
# Applies namespace, ConfigMap, Service, then renders + applies the
# Deployment (3 replicas) with a checksum/config annotation. Assumes the
# config-demo:latest image is already built and visible to the cluster -
# run scripts/build-image.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/service.yaml
./scripts/render-deployment.sh

echo
echo "Waiting for rollout..."
kubectl rollout status deployment/config-demo -n configmap-rotations
