#!/usr/bin/env bash
# Flips feature.enabled in k8s/configmap.yaml and applies it - this alone
# updates the ConfigMap object and (within seconds) the file mounted inside
# every pod, but does NOT change what any already-running pod returns from
# /feature, since Spring Boot only reads application.yaml at startup.
# Usage: ./scripts/update-configmap.sh true|false
set -euo pipefail
cd "$(dirname "$0")/.."

VALUE="${1:?usage: update-configmap.sh <true|false>}"

if [[ "$VALUE" != "true" && "$VALUE" != "false" ]]; then
  echo "Value must be 'true' or 'false', got: $VALUE" >&2
  exit 1
fi

# Anchored to exactly 2-space indent so this only ever matches the
# top-level `feature: / enabled: <bool>` line, not any other `enabled:`
# key that might exist elsewhere in the file (e.g. actuator settings).
sed -i -E "s/^  enabled: (true|false)$/  enabled: ${VALUE}/" k8s/configmap.yaml
kubectl apply -f k8s/configmap.yaml

cat <<EOF

ConfigMap updated: feature.enabled=${VALUE}

The mounted file inside existing pods will update on its own shortly
(kubelet syncs it via a watch, typically within seconds to ~1 minute).
Verify with:
  kubectl exec -n configmap-rotations deploy/config-demo -- cat /config/application.yaml

But the running JVMs will keep serving the OLD value until they restart.
Verify with:
  curl.exe http://localhost:8080/feature   (after: kubectl port-forward -n configmap-rotations svc/config-demo 8080:80)

To make pods pick up the new value, choose one of:
  ./scripts/render-deployment.sh                 # checksum/config annotation -> forces rollout
  kubectl rollout restart deployment/config-demo -n configmap-rotations
  (or let Stakater Reloader do it automatically - see README)
EOF
