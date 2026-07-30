#!/bin/bash
# Diagnose why the Wazuh-launched osqueryd isn't running. Run: sudo bash osq-diag.sh
set +e
echo "===== 1) osquery/wodle lines in agent ossec.log (tail) ====="
grep -iE "osquery|wm_exec|modules" /Library/Ossec/logs/ossec.log | tail -30

echo "===== 2) any osqueryd process running now? ====="
pgrep -fl osqueryd || echo "NONE running"

echo "===== 3) manual launch with the wodle's exact config (10s), whoami fired ====="
rm -f /var/log/osquery/osqueryd.results.log
/opt/osquery/lib/osquery.app/Contents/MacOS/osqueryd \
  --config_path=/var/osquery/osquery.conf --logger_path=/var/log/osquery \
  --pidfile=/var/osquery/osquery-diag.pid --database_path=/var/osquery/osquery-diag.db \
  --verbose > /tmp/osqdiag.out 2>&1 &
P=$!
sleep 7
/usr/bin/whoami >/dev/null; /usr/bin/id -un >/dev/null
sleep 4
kill "$P" 2>/dev/null; sleep 1
echo "--- ES init / errors from manual launch ---"
grep -iE "error|denied|not permitted|endpointsecurity|publisher|Executing scheduled" /tmp/osqdiag.out | head -15
echo "--- es_process_events captured by manual launch ---"
grep -hc es_process_events /var/log/osquery/osqueryd.results.log 2>/dev/null || echo 0
echo "===== DONE $(date '+%H:%M:%S') ====="
