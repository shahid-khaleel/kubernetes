#!/usr/bin/env bash
# Stage 1: Authentication.
# Sends a raw request straight to the API server with a garbage bearer token
# (bypassing kubectl's local kubeconfig merging, which would otherwise fall
# back to your real client-certificate credentials). The API server cannot
# authenticate this token -> the request is rejected before Authorization,
# Admission Controllers, or any webhook ever see it.
set -euo pipefail

SERVER=$(kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')

echo "API server: ${SERVER}"
echo
echo "== Raw request with an invalid bearer token =="
curl -s -k -w "\nHTTP_STATUS:%{http_code}\n" \
  -H "Authorization: Bearer this-is-not-a-real-token" \
  "${SERVER}/api/v1/namespaces/default/pods"

echo
echo "Expected: HTTP_STATUS:401, reason: Unauthorized"
echo "This request was rejected during Authentication -- it never reached RBAC,"
echo "admission controllers, or any webhook."
