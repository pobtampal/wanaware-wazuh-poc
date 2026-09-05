#!/bin/bash
# FIM rehearsal PRE-STAGE — run: sudo bash fim-prestage.sh
# Backs up the agent ossec.conf, lowers ONLY the <syscheck> frequency to 120s, restarts the agent.
set -e
CONF=/Library/Ossec/etc/ossec.conf
BAK="$CONF.bak.premeeting.$(date +%s)"

echo "== 1) backup + verify =="
cp "$CONF" "$BAK"
[ -s "$BAK" ] || { echo "ABORT: backup not created"; exit 1; }
echo "  backup OK: $BAK ($(wc -c < "$BAK") bytes)"

echo "== 2) current syscheck frequency (before) =="
/usr/bin/python3 - <<'PY'
import re
s=open("/Library/Ossec/etc/ossec.conf").read()
m=re.search(r"<syscheck>.*?</syscheck>", s, re.S)
f=re.search(r"<frequency>(\d+)</frequency>", m.group(0))
print("  syscheck <frequency> =", f.group(1) if f else "not found")
PY

echo "== 3) lower ONLY the <syscheck> block frequency to 120 =="
/usr/bin/python3 - <<'PY'
import re
p="/Library/Ossec/etc/ossec.conf"; s=open(p).read()
m=re.search(r"(<syscheck>.*?</syscheck>)", s, re.S)
blk=m.group(1); blk2=re.sub(r"<frequency>\d+</frequency>", "<frequency>120</frequency>", blk, count=1)
if blk2==blk: print("  WARN: no <frequency> changed inside <syscheck>")
s=s[:m.start(1)]+blk2+s[m.end(1):]; open(p,"w").write(s)
f=re.search(r"<frequency>(\d+)</frequency>", re.search(r"<syscheck>.*?</syscheck>", s, re.S).group(0))
print("  syscheck <frequency> now =", f.group(1))
PY

echo "== 4) restart agent =="
/Library/Ossec/bin/wazuh-control restart
sleep 4
/Library/Ossec/bin/wazuh-control status | grep -E "syscheckd|agentd"
echo "== DONE — pre-stage applied. Tell Claude to verify freq=120 via the API. =="
