#!/bin/sh
set -eu
THRESHOLD="${SLO_THRESHOLD:-99}"
TOTAL=$(psql -tAc "SELECT COUNT(*) FROM checks WHERE ts > NOW() - INTERVAL '1 hour'"
2>/dev/null || echo 0)
OK=$(psql -tAc "SELECT COUNT(*) FROM checks WHERE ts > NOW() - INTERVAL '1 hour' AND
status='ok'" 2>/dev/null || echo 0)
if [ "$TOTAL" -eq 0 ]; then echo 'No data yet'; exit 0; fi
UPTIME_PCT=$(( OK * 100 / TOTAL ))
echo "Uptime: ${OK}/${TOTAL} = ${UPTIME_PCT}% (SLO threshold: ${THRESHOLD}%)"
if [ "$UPTIME_PCT" -lt "$THRESHOLD" ]; then
MSG="SLO BREACH: uptime ${UPTIME_PCT}% < threshold ${THRESHOLD}% (${OK}/${TOTAL} OK)"
echo "$MSG"
mkdir -p /output
echo "$(date -Iseconds) $MSG" >> /output/alerts.log
if [ -n "${WEBHOOK_URL:-}" ]; then
wget -qO- --post-data="{\"text\":\"$MSG\"}" \
--header='Content-Type: application/json' "$WEBHOOK_URL" || true
fi
fi