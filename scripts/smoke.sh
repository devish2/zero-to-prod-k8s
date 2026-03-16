set -euo pipefail
HOST=${SMOKE_HOST:-uptime.local}
MAX_LATENCY=${MAX_LATENCY_MS:-500}
RETRIES=5
grep -q "$HOST" /etc/hosts || echo '127.0.0.1 $HOST' >> /etc/hosts
for i in $(seq 1 $RETRIES); do
echo " Attempt $i/$RETRIES..."
HTTP=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "https://$HOST/health" ||
echo '000')
RT_MS=$(curl -sk -o /dev/null -w '%{time_total}' --max-time 5 "https://$HOST/health" |
awk '{printf "%d",$1*1000}')
if [ "$HTTP" = '200' ]; then
echo "✓ HTTP $HTTP in ${RT_MS}ms"
[ "$RT_MS" -gt "$MAX_LATENCY" ] && echo 'WARN: latency exceeds SLO'
echo 'Smoke test PASSED'
exit 0
fi
echo "HTTP $HTTP — retrying in 5s..."
sleep 5
done
echo 'Smoke test FAILED'
exit 1
