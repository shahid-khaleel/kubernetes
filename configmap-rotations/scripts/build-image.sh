#!/usr/bin/env bash
# Builds the app image and optionally loads it into a local kind/minikube
# cluster (skip the "docker push to a registry" step entirely for local demos).
# Usage: ./scripts/build-image.sh [kind|minikube|none]
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-none}"
IMAGE=config-demo:latest

docker build -t "$IMAGE" .

case "$TARGET" in
  kind)
    kind load docker-image "$IMAGE"
    ;;
  minikube)
    minikube image load "$IMAGE"
    ;;
  none)
    echo "Image built locally as $IMAGE."
    echo "If your cluster can't see local images, load/push it: 'kind load docker-image $IMAGE', 'minikube image load $IMAGE', or push to a registry and update k8s/deployment.yaml.tmpl's image field."
    ;;
  *)
    echo "Unknown target: $TARGET (expected kind|minikube|none)" >&2
    exit 1
    ;;
esac
