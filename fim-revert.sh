#!/bin/bash
# FIM rehearsal REVERT — run: sudo bash fim-revert.sh
# Backs up, restores the <syscheck> frequency to 43200s (baseline), restarts the agent.
set -e
CONF=/Library/Ossec/etc/ossec.conf
BAK="$CONF.bak.revert.$(date +%s)"

echo "== 1) backup + verify =="
cp "$CONF" "$BAK"
[ -s "$BAK" ] || { echo "ABORT: backup not created"; exit 1; }
echo "  backup OK: $BAK"

echo "== 2) restore <syscheck> frequency to 43200 =="
/usr/bin/python3 - <<'PY'
import re
p="/Library/Ossec/etc/ossec.conf"; s=open(p).read()
m=re.search(r"(<syscheck>.*?</syscheck>)", s, re.S)
blk=m.group(1); blk2=re.sub(r"<frequency>\d+</frequency>", "<frequency>43200</frequency>", blk, count=1)
s=s[:m.start(1)]+blk2+s[m.end(1):]; open(p,"w").write(s)
f=re.search(r"<frequency>(\d+)</frequency>", re.search(r"<syscheck>.*?</syscheck>", s, re.S).group(0))
print("  syscheck <frequency> now =", f.group(1))
PY

echo "== 3) restart agent =="
/Library/Ossec/bin/wazuh-control restart
sleep 4
/Library/Ossec/bin/wazuh-control status | grep -E "syscheckd|agentd"
echo "== DONE — reverted to 43200. Tell Claude to VERIFY freq=43200 via the API. =="
