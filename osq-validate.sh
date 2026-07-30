#!/bin/bash
# osquery BSM process_events validation on macOS 26. Run: sudo bash osq-validate.sh
set +e
OSQD=/opt/osquery/lib/osquery.app/Contents/MacOS/osqueryd
[ -x "$OSQD" ] || OSQD=$(command -v osqueryd)
echo "===== osqueryd: $OSQD ====="; "$OSQD" --version

echo "===== audit flags ====="; grep -E '^flags|^naflags' /etc/security/audit_control 2>/dev/null || echo "audit_control missing"
echo "===== enabling kernel auditing (was AUC_NOAUDIT) ====="
launchctl enable system/com.apple.auditd 2>/dev/null
launchctl kickstart -k system/com.apple.auditd 2>&1 | head -1
audit -s 2>&1 | head -2
sleep 2
echo -n "audit condition now: "; audit -c 2>&1 | head -1
ls -l /dev/auditpipe 2>&1 | head -1

mkdir -p /var/osquery /var/log/osquery
cat > /var/osquery/osquery-test.conf <<'JSON'
{ "options": { "disable_audit": "false", "audit_allow_process_events": "true", "disable_events": "false", "events_expiry": "60" },
  "schedule": { "pe": { "query": "SELECT pid,path,cmdline,auid FROM process_events;", "interval": 3 } } }
JSON
rm -f /var/log/osquery/osqueryd.results.log

echo "===== starting osqueryd for ~20s ====="
"$OSQD" --config_path=/var/osquery/osquery-test.conf --logger_path=/var/log/osquery \
  --database_path=/var/osquery/osq-test.db --pidfile=/var/osquery/osqtest.pid \
  --disable_watchdog --verbose > /tmp/osqtest.out 2>&1 &
OSQPID=$!
sleep 8
echo ">> firing techniques (T1033/T1087/T1518/T1217)"
whoami >/dev/null; /usr/bin/id -un >/dev/null
/usr/bin/dscl . -list /Users >/dev/null 2>&1
/bin/cat "$HOME/Library/Safari/Bookmarks.plist" >/dev/null 2>&1
/bin/ls /tmp >/dev/null 2>&1
sleep 12
kill "$OSQPID" 2>/dev/null; sleep 1

echo "===== process_events result batches captured ====="
grep -hc '"name":"pe"' /var/log/osquery/osqueryd.results.log 2>/dev/null || echo 0
echo "===== distinct exec paths captured (sample) ====="
grep -hoE '"path":"[^"]*"' /var/log/osquery/osqueryd.results.log 2>/dev/null | sort | uniq -c | sort -rn | head -20
echo "===== our techniques captured? ====="
grep -hoE '"(path|cmdline)":"[^"]*"' /var/log/osquery/osqueryd.results.log 2>/dev/null | grep -iE 'whoami|dscl|/usr/bin/id|Bookmarks|/bin/ls|/bin/cat' | head
echo "===== osqueryd errors/denials (look for audit/permission) ====="
grep -iE 'error|denied|permission|audit|bsm|endpoint' /tmp/osqtest.out | head -15
echo "===== DONE $(date '+%H:%M:%S') ====="
