#!/bin/bash
# osquery EndpointSecurity process_events validation on macOS 26.
# PREREQ: Full Disk Access granted to /opt/osquery/lib/osquery.app/Contents/MacOS/osqueryd
# Run: sudo bash osq-validate-es.sh
set +e
OSQD=/opt/osquery/lib/osquery.app/Contents/MacOS/osqueryd
echo "===== osqueryd: $OSQD ====="; "$OSQD" --version

mkdir -p /var/osquery /var/log/osquery
cat > /var/osquery/osquery-es-test.conf <<'JSON'
{ "options": { "disable_endpointsecurity": "false", "disable_events": "false", "events_expiry": "60" },
  "schedule": { "espe": { "query": "SELECT pid,path,cmdline,parent FROM es_process_events;", "interval": 3 } } }
JSON
rm -f /var/log/osquery/osqueryd.results.log

echo "===== starting osqueryd (ES mode) for ~20s ====="
"$OSQD" --config_path=/var/osquery/osquery-es-test.conf --logger_path=/var/log/osquery \
  --database_path=/var/osquery/osq-es.db --pidfile=/var/osquery/osqes.pid \
  --disable_watchdog --verbose > /tmp/osqes.out 2>&1 &
OSQPID=$!
sleep 8
echo ">> firing techniques (T1033/T1087/T1518/T1217)"
whoami >/dev/null; /usr/bin/id -un >/dev/null
/usr/bin/dscl . -list /Users >/dev/null 2>&1
/bin/cat "$HOME/Library/Safari/Bookmarks.plist" >/dev/null 2>&1
/bin/ls /tmp >/dev/null 2>&1
sleep 12
kill "$OSQPID" 2>/dev/null; sleep 1

echo "===== es_process_events batches captured ====="
grep -hc '"name":"espe"' /var/log/osquery/osqueryd.results.log 2>/dev/null || echo 0
echo "===== our techniques captured? ====="
grep -hoE '"(path|cmdline)":"[^"]*"' /var/log/osquery/osqueryd.results.log 2>/dev/null | grep -iE 'whoami|dscl|/usr/bin/id|Bookmarks|/bin/ls|/bin/cat' | head
echo "===== ES status / TCC errors (look for endpointsecurity / not permitted) ====="
grep -iE 'endpointsecurity|full disk|not permitted|denied|es_|error' /tmp/osqes.out | head -15
echo "===== DONE $(date '+%H:%M:%S') ====="
