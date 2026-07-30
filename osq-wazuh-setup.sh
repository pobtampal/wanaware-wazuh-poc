#!/bin/bash
# Wire osquery (EndpointSecurity process_events) into the Wazuh agent. Run: sudo bash osq-wazuh-setup.sh
set +e
CONF=/Library/Ossec/etc/ossec.conf
OSQD_DIR=/opt/osquery/lib/osquery.app/Contents/MacOS   # Wazuh appends /osqueryd to this

echo "===== 1) write persistent osquery ES config ====="
mkdir -p /var/osquery /var/log/osquery
rm -f /var/log/osquery/osqueryd.results.log   # clear stale results so we can measure new flow
cat > /var/osquery/osquery.conf <<'JSON'
{
  "options": { "disable_endpointsecurity": "false", "disable_events": "false", "events_expiry": "60" },
  "schedule": {
    "process_events": {
      "query": "SELECT pid,path,cmdline,parent,uid,time FROM es_process_events;",
      "interval": 5,
      "description": "macOS EndpointSecurity exec events (MITRE discovery visibility)"
    }
  }
}
JSON
echo "wrote /var/osquery/osquery.conf"

echo "===== 2) enable Wazuh osquery wodle (backup first) ====="
cp "$CONF" "$CONF.bak.$(date +%s)"
/usr/bin/python3 - "$OSQD_DIR" <<'PY'
import re,sys
osqd=sys.argv[1]
p="/Library/Ossec/etc/ossec.conf"
s=open(p).read()
wodle=('  <wodle name="osquery">\n'
       '    <disabled>no</disabled>\n'
       '    <run_daemon>yes</run_daemon>\n'
       '    <bin_path>%s</bin_path>\n'
       '    <log_path>/var/log/osquery/osqueryd.results.log</log_path>\n'
       '    <config_path>/var/osquery/osquery.conf</config_path>\n'
       '    <add_labels>yes</add_labels>\n'
       '  </wodle>\n') % osqd
pat=re.compile(r'[ \t]*<wodle name="osquery">.*?</wodle>\n', re.S)
if pat.search(s):
    s=pat.sub(wodle, s, count=1); print("replaced existing osquery wodle")
else:
    s=s.replace("</ossec_config>", wodle+"</ossec_config>", 1); print("inserted osquery wodle")
open(p,"w").write(s)
PY

echo "===== 3) restart agent ====="
/Library/Ossec/bin/wazuh-control restart >/dev/null 2>&1
sleep 4
/Library/Ossec/bin/wazuh-control status | grep -E "modulesd|agentd"
echo "===== 4) confirm osqueryd launched by Wazuh + results flowing ====="
sleep 6
echo -n "osqueryd procs: "; pgrep -fl osqueryd | head -3
echo -n "results log lines: "; wc -l < /var/log/osquery/osqueryd.results.log 2>/dev/null || echo "no log yet"
echo "===== DONE $(date '+%H:%M:%S') ====="
