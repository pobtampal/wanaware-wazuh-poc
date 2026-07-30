#!/bin/bash
# Tune osquery process_events to an allowlist of high-risk locations + shells/interpreters.
# Run: sudo bash osq-tune.sh
set +e
CONF=/var/osquery/osquery.conf

echo "===== 1) backup current config ====="
cp "$CONF" "$CONF.bak.$(date +%s)" && echo "backed up to $CONF.bak.*"

echo "===== 2) write tuned config (allowlist) ====="
cat > "$CONF" <<'JSON'
{
  "options": {
    "disable_endpointsecurity": "false",
    "disable_events": "false",
    "events_expiry": "60"
  },
  "schedule": {
    "process_events": {
      "query": "SELECT pid,path,cmdline,parent,uid,time FROM es_process_events WHERE path LIKE '/tmp/%' OR path LIKE '/private/tmp/%' OR path LIKE '/Users/%' OR path LIKE '/private/var/folders/%' OR path LIKE '/var/folders/%' OR path LIKE '%/bash' OR path LIKE '%/zsh' OR path LIKE '%/sh' OR path LIKE '%/dash' OR path LIKE '%/ksh' OR path LIKE '%/tcsh' OR path LIKE '%/csh' OR path LIKE '%/python' OR path LIKE '%/python3' OR path LIKE '%/perl' OR path LIKE '%/ruby' OR path LIKE '%/node' OR path LIKE '%/php' OR path LIKE '%/env' OR path = '/usr/bin/osascript';",
      "interval": 30,
      "description": "macOS ES exec events. ALLOWLIST: high-risk dirs (/tmp, /private/tmp, /Users, /var/folders, /private/var/folders) + shells/interpreters (bash,zsh,sh,dash,ksh,tcsh,csh,python,python3,perl,ruby,node,php,env,osascript) anywhere. BLIND BY DESIGN to system paths (/usr/libexec, /System, /usr/bin non-interpreters, etc.). Interval is flush cadence (evented table), not a sampling rate."
    }
  }
}
JSON

echo "===== 3) validate JSON ====="
/usr/bin/python3 -c "import json;json.load(open('$CONF'));print('JSON valid')" || { echo "INVALID JSON - not restarting"; exit 1; }

echo "===== 4) restart agent ====="
/Library/Ossec/bin/wazuh-control restart >/dev/null 2>&1
sleep 5
echo -n "osqueryd running: "; pgrep -fl osqueryd | head -2 || echo "NONE"
echo "===== DONE $(date '+%H:%M:%S') ====="
