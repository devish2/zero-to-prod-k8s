#!/usr/bin/env bash
set -euo pipefail
CLUSTER_NAME=${KIND_CLUSTER_NAME:-uptime-dev}
docker network connect 'kind' registry 2>/dev/null || true
for node in $(kind get nodes --name "$CLUSTER_NAME"); do
kubectl annotate node "$node" kind.x-k8s.io/registry=localhost:5001 --overwrite
done
kubectl apply -f - <<CM
apiVersion: v1
kind: ConfigMap
metadata:
name: local-registry-hosting
namespace: kube-public
data:
localRegistryHosting.v1: |
host: "localhost:5001"
CM
echo '✓ Registry wired to cluster'