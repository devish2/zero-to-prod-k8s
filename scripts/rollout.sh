#!/usr/bin/env bash
# Usage: ./scripts/rollout.sh <image-tag>
set -euo pipefail
TAG=${1:?'Usage: rollout.sh <tag>'}
NAMESPACE='uptime-dev'
REGISTRY='localhost:5001/uptime'
# Detect current active slot
CURRENT=$(kubectl get svc app -n $NAMESPACE -o jsonpath='{.spec.selector.slot}' 2>/dev/null
|| echo blue)
NEW_SLOT=$([ "$CURRENT" = 'blue' ] && echo green || echo blue)
echo "==> Deploying $TAG to slot=$NEW_SLOT (current=$CURRENT)"
# Deploy new image to inactive slot
kubectl set image deployment/app-$NEW_SLOT app=$REGISTRY/app:$TAG -n $NAMESPACE
kubectl rollout status deployment/app-$NEW_SLOT -n $NAMESPACE --timeout=120s
# Smoke test inactive slot via port-forward
kubectl port-forward deployment/app-$NEW_SLOT 9999:5000 -n $NAMESPACE &
PF_PID=$!; sleep 3
HTTP=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9999/health)
kill $PF_PID 2>/dev/null || true
[ "$HTTP" != '200' ] && { echo 'Smoke failed — aborting'; exit 1; }
echo ' ✓ New slot healthy'
# Switch traffic
kubectl patch svc app -n $NAMESPACE \
-p "{\"spec\":{\"selector\":{\"app\":\"flask-app\",\"slot\":\"$NEW_SLOT\"}}}"
echo "==> Traffic → $NEW_SLOT"
# Scale down old slot
sleep 10
kubectl scale deployment/app-$CURRENT --replicas=0 -n $NAMESPACE
echo '✓ Blue/green cutover complete'
