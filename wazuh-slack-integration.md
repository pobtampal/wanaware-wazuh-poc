# Wazuh → Slack Alerting Integration (POC)

**Environment:** Wazuh v4.14.5, single-node Docker, MacBook Air (localhost). Integration lives on the **manager** side.
**Agent:** `Pobtams-MacBook-Air.local` (agent 001, macOS).
**Purpose:** near-realtime Slack notifications for medium+ severity detections, for a working demo.

> **Secrets:** the Slack webhook URL is a credential (anyone with it can post to the channel). It is stored only in the manager's `ossec.conf` and is **not** reproduced in this document — placeholder `<SLACK_WEBHOOK_URL>` is used. Rotate/revoke from the Slack app's *Incoming Webhooks* page if exposed.

---

## 1. Slack webhook setup (reproducible on a shared host)

**Plan:** Free tier is sufficient. You need permission to install/create apps in the workspace (corporate workspaces may require admin approval).

1. Go to **https://api.slack.com/apps** → **Create New App** → **From scratch**.
2. Name it (e.g. `wazuhpoc`), select the workspace → **Create App**.
3. Left sidebar → **Features → Incoming Webhooks** → toggle **Activate Incoming Webhooks = On**.
4. **Add New Webhook to Workspace** → choose the target channel (e.g. `#wazuh-alerts`) → **Allow**.
5. Copy the **Webhook URL**.

**Scope required:** only `incoming-webhook` (auto-requested; posts to the one authorized channel). No bot token / `chat:write` needed. One webhook = one channel; create additional webhooks for additional channels.

**URL format** (verify before use):
```
https://hooks.slack.com/services/Txxxxxxxx/Bxxxxxxxx/xxxxxxxxxxxxxxxxxxxxxxxx
```

**Standalone test:**
```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Wazuh POC webhook test :white_check_mark:"}' '<SLACK_WEBHOOK_URL>'
```

---

## 2. Integration config (manager `ossec.conf`)

Appended as a new `<ossec_config>` block to `/var/ossec/etc/ossec.conf` inside the `wazuh.manager` container (backup: `ossec.conf.bak.slack.*`):

```xml
<ossec_config>
  <integration>
    <name>slack</name>
    <hook_url>SLACK_WEBHOOK_URL</hook_url>
    <level>7</level>
    <alert_format>json</alert_format>
  </integration>
</ossec_config>
```

- `level 7` → only alerts of **level ≥ 7** are sent (filters routine low-severity/informational noise, incl. osquery rule 24010 at level 3).
- `alert_format json` → the alert is passed to `slack.py` as full JSON, so the message includes rule description, level, agent, location, rule id, and groups.
- No `<group>`/`<rule_id>` filter → **all groups** at level ≥ 7 (per "all groups initially, tune later").

**Apply / reload:**
```bash
cd /Users/pobtampal/Desktop/wazuhPOC/wazuh-docker/single-node
docker compose restart wazuh.manager          # or: docker compose exec wazuh.manager /var/ossec/bin/wazuh-control restart
docker compose exec wazuh.manager bash -c "/var/ossec/bin/wazuh-control status | grep integrator"
```
Verified on load: `wazuh-integratord: INFO: Enabling integration for: 'slack'.` (no errors).

**Note on dashboard deep-links:** the stock `slack` integration does **not** emit a per-alert permalink into the Wazuh dashboard (not reliably supported). The message contains rule id + fields; to investigate, open the dashboard and filter by rule id / time. A per-alert deep link would require a custom integration script.

---

## 3. Test results

| Test | Rule | Level | Reached Slack? | Notes |
|---|---|---|---|---|
| **Threshold** — 3× failed `sudo` | 5401 | 5 | ❌ **No** (correct) | Confirms the level-7 filter works — level-5 events are excluded. |
| **Pipeline** — new listening port opened | 533 | 7 | ✅ **Yes** | End-to-end delivery confirmed. |

**Time-to-Slack (rule 533):** port opened → alert → Slack ≈ **5.5 min**, virtually all of which is the **6-min netstat check interval** on the agent. The integratord → Slack step itself is near-instant (seconds) once the alert fires. So realtime-ness is gated by *how often the triggering check runs*, not by the Slack path.

**Message format (confirmed in Slack, app `wazuhpoc`):** Title **"WAZUH Alert"**; body includes rule description, the event log (e.g. netstat output), **Agent** (001 – Pobtams-MacBook-Air.local), **Location**, **Rule ID + Level**; timestamped, "Added by wazuhpoc". Clean and readable.

---

## 4. Tuning decisions

### Decision 1 — filter out rule 533 (netstat port change) from Slack
**Problem:** rule 533 (level 7) fires **every ~6 min** on this host (Docker + normal port churn) → spammy for a demo channel.

**Why not an integration-level exclude:** Wazuh's integratord filters are **include-only** (`level`, `group`, `rule_id`) — there is no "exclude rule X". The standard fix is a **local rule that downgrades 533 below the level-7 threshold.**

Added to `/var/ossec/etc/rules/local_rules.xml` (backup `.bak.*`):
```xml
<group name="local,netstat_tuning,">
  <rule id="100533" level="3">
    <if_sid>533</if_sid>
    <description>Listened ports status changed - downgraded to level 3 (routine churn on POC host; kept below the level-7 Slack notification threshold).</description>
    <group>netstat,noise_tuned,</group>
  </rule>
</group>
```
**Effect:** netstat port-change events now alert as **rule 100533, level 3** → below the level-7 Slack threshold → **not sent to Slack.** **Verified:** after the change, opening a listening port produced a `100533 (level 3)` alert and `integrations.log` did **not** increment (stayed at 208 lines) — no Slack invocation. (For context, `integrations.log` had reached **208 invocations** — rule 533 firing every ~6 min for ~2 days pre-fix — which quantifies the spam this eliminates.)

**Side effect (documented):** this downgrade is **global**, not Slack-only — the event now shows as level 3 in the dashboard and to any other consumer too. Acceptable here because netstat churn on a POC host is genuinely low-value; revisit for production if listening-port changes are security-relevant in that environment (a *new* unexpected listener is a real backdoor signal — see demo scenario 2).

### Decision 2 — keep level-7 threshold (vs group allowlist)
Kept the simple **level ≥ 7, all-groups** filter (minus 533) for the main channel. It is the least-surprising default and, with 533 downgraded, is already clean. A group allowlist (e.g. `authentication,syscheck,attack`) is available if the channel later gets noisy from another source — change is a one-line `<group>` addition to the integration block.

### Decision 3 — second webhook for a dedicated demo channel (IMPLEMENTED)
A **second integration → `#wazuh-demo`** was added so the main channel stays production-clean (level 7, no 533) while the demo channel catches instant, controllable low-level triggers. Appended as a separate `<ossec_config>` block (backup `ossec.conf.bak.slackdemo.*`):

```xml
<ossec_config>
  <!-- DEMO CHANNEL (#wazuh-demo): lower threshold, scoped to high-signal groups only -->
  <integration>
    <name>slack</name>
    <hook_url>SLACK_DEMO_WEBHOOK_URL</hook_url>
    <level>5</level>
    <group>sudo,syscheck</group>
    <alert_format>json</alert_format>
  </integration>
</ossec_config>
```

**Group-name correction (important, verified against indexed alerts):** on macOS, Wazuh tags failed-sudo (rule 5401) under groups **`sudo`, `syslog`** — **not** `authentication_failed`. Scoping to `authentication_failed` (the intuitive guess) would silently miss the sudo demo. Confirmed scope: **`sudo`** (failed sudo, level 5) + **`syscheck`** (FIM, level 7).

**Verified end-to-end:** 3 failed sudo → rule 5401 (level 5) → **3 invocations of the demo webhook only** (confirmed by webhook token in `integrations.log`); the main level-7 channel did **not** fire. Latency ~3 s. The two integrations are independent — the main channel is unaffected.

---

## 5. Recommended demo scenarios

Honest constraint note: our validated, reliable triggers are limited by the current stack — the fastest instant trigger (`sudo`) is level 5 (below threshold), FIM is level 7 but gated by a 12-h scheduled scan (syscheck frequency is fixed per POC constraints), and VirusTotal is neutralized. The scenarios below are ranked by how well they demo *given those realities*, with the config each needs.

### Scenario 1 — Failed privilege escalation (BEST for a live "wow" moment) — ✅ WIRED & TESTED
- **Channel:** `#wazuh-demo` (second webhook, level 5, group `sudo,syscheck`).
- **Trigger (instant, on-demand), paste in terminal:**
  ```bash
  for n in 1 2 3; do echo x | sudo -S -k -p "" id; done
  ```
- **Detection:** rule **5401**, MITRE **T1548.003**, **~3 s to Slack** (verified in this phase).
- **Story:** "Someone is attempting unauthorized privilege escalation on the endpoint" — clear cause→effect for a live audience (type wrong password → Slack lights up in seconds).
- **Status:** fully working; posts to `#wazuh-demo` only, not the main channel. **Most reliable + controllable live demo.**

### Scenario 2 — New listening port / backdoor detection
- **Trigger (on-demand, ≤6 min):** `python3 -m http.server 4444 --bind 127.0.0.1` (a "C2 listener").
- **Detection:** rule 533, level 7 — **but now downgraded to 100533/level 3** by Decision 1, so it no longer posts to the main channel.
- **Story:** "Malware opened a listening port for command-and-control — detected in near-realtime." Compelling and visual.
- **Config needed:** route it to the demo channel by adding `<rule_id>533</rule_id>` (or `100533`) with an appropriate level to the *second* integration, OR temporarily raise 100533's level. Latency ≤6 min (netstat interval).

### Scenario 3 — Real vulnerability findings (no trigger needed)
- **Trigger:** none — the Vulnerability Detector continuously matches the host's installed packages against the CVE feed.
- **Detection:** vulnerability alerts (levels vary, frequently ≥7 for high-CVSS CVEs) — these are **real findings on the actual host**, not synthetic.
- **Story:** "Wazuh flagged actual known-vulnerable software on this endpoint, with CVE references." Strong for credibility.
- **Note:** not on-demand (inventory-driven); check for already-present alerts and showcase them. Good complement to the live triggers above.

**Suggested demo flow:** open with Scenario 3 (real findings → credibility), then Scenario 1 live (type a wrong `sudo` password → watch Slack light up in seconds → clear cause/effect), optionally Scenario 2 for the backdoor narrative.

---

## 5b. FIM demo runbook (macOS) — file-tampering → Slack

**What it shows:** modifying a monitored file → Wazuh File Integrity Monitoring detects it (rule **550**, level 7, "Integrity checksum changed") → Slack. Because rule 550 is in the `syscheck` group at level 7, it posts to **both `#wazuh-demo`** (level 5, `syscheck`) **and `#wazuh-alerts`** (level 7, all groups).

**Why pre-staging is needed on macOS:** macOS has **no realtime FIM** (Apple's EndpointSecurity FIM is not wired into the OSS agent; there is no inotify), so FIM only runs on the **scheduled scan** — 12 h by default. For a live demo we temporarily drop the scan interval to 120 s. The watched dir `/Users/Shared/wazuh_fim_test` is already in the agent config but was deleted from disk in an earlier cleanup, so pre-staging recreates it (this keeps the live trigger sudo-free).

> ⚠️ **The frequency change below is TEMPORARY.** It is the only permitted change to `syscheck` frequency and **must be reverted after the demo** with the Post-demo block. It edits the agent config (`/Library/Ossec/etc/ossec.conf`) and targets only the `<syscheck>` block's `<frequency>` (there are 3 `<frequency>` tags — rootcheck/syscheck/SCA — so it is matched by block, not blindly).

### PRE-STAGING — run ~3 minutes before the demo (needs sudo)
```bash
# (a) recreate the watched dir + baseline file (user-owned, so the live trigger needs no sudo)
mkdir -p /Users/Shared/wazuh_fim_test
echo "baseline $(date)" > /Users/Shared/wazuh_fim_test/watched.txt

# (b) TEMPORARILY lower ONLY the syscheck scan frequency to 120s (backup first)
sudo cp /Library/Ossec/etc/ossec.conf /Library/Ossec/etc/ossec.conf.bak.fimdemo.$(date +%s)
sudo /usr/bin/python3 - <<'PY'
import re
p="/Library/Ossec/etc/ossec.conf"; s=open(p).read()
m=re.search(r"(<syscheck>.*?</syscheck>)", s, re.S)          # match the syscheck block only
blk=m.group(1); blk2=re.sub(r"<frequency>\d+</frequency>", "<frequency>120</frequency>", blk, count=1)
s=s[:m.start(1)]+blk2+s[m.end(1):]; open(p,"w").write(s)
print("syscheck <frequency> -> 120s (TEMPORARY)")
PY

# (c) restart the agent so the baseline scan runs now and records watched.txt
sudo /Library/Ossec/bin/wazuh-control restart
sleep 5; sudo /Library/Ossec/bin/wazuh-control status | grep syscheck
echo ">> Pre-staging done. WAIT ~2 min for the baseline scan to finish BEFORE the live trigger."
```
*(Why wait: on macOS, restarting the agent re-baselines FIM — if you modify the file before the baseline scan finishes, the change is absorbed silently instead of alerting. The 3-minute lead time covers this.)*

### LIVE TRIGGER — during the demo (NO sudo)
```bash
echo "# demo change $(date)" >> /Users/Shared/wazuh_fim_test/watched.txt
```
- **Expected:** the next scheduled scan (≤120 s) detects the checksum change → **rule 550, level 7, "Integrity checksum changed"** → posts to **#wazuh-demo** (and #wazuh-alerts) within **~2 minutes**.
- **Slack message:** Title "WAZUH Alert"; rule description *Integrity checksum changed*; the changed path `/Users/Shared/wazuh_fim_test/watched.txt`; Agent `001 – Pobtams-MacBook-Air.local`; Rule ID 550 (Level 7). With `report_changes` on this path, the alert also includes a before/after diff of the file content.

### POST-DEMO REVERT — run after the demo (needs sudo) — REQUIRED
```bash
sudo /usr/bin/python3 - <<'PY'
import re
p="/Library/Ossec/etc/ossec.conf"; s=open(p).read()
m=re.search(r"(<syscheck>.*?</syscheck>)", s, re.S)
blk=m.group(1); blk2=re.sub(r"<frequency>\d+</frequency>", "<frequency>43200</frequency>", blk, count=1)
s=s[:m.start(1)]+blk2+s[m.end(1):]; open(p,"w").write(s)
print("syscheck <frequency> restored -> 43200s (default)")
PY
sudo /Library/Ossec/bin/wazuh-control restart
rm -rf /Users/Shared/wazuh_fim_test    # optional: remove the demo watch dir
echo ">> Reverted to default 12h syscheck frequency."
```

### Linux note
On **Linux** endpoints, FIM is **realtime (sub-second, via inotify)** — **no pre-staging, no frequency change, no 2-minute wait**. Modifying a monitored file alerts almost immediately. The 120 s pre-staging dance is a **macOS-only** constraint (no realtime FIM backend in the OSS agent). Frame this in the demo: "on the Linux fleet this is instant; on macOS it's scan-interval-bound."

---

## 6. Re-application note

**This integration will need to be re-applied when the stack moves to a shared host** — the webhook URL and config block are documented here for that purpose. Specifically, re-apply on the new manager:
1. §2 main `<integration>` block into the manager `ossec.conf` (level 7, real `<hook_url>`).
2. §4 Decision 3 **demo** `<integration>` block (level 5, `group sudo,syscheck`, its own `<hook_url>` → `#wazuh-demo`).
3. §4 Decision 1 local rule `100533` into `local_rules.xml` (if the netstat noise reappears).
4. Restart the manager and confirm `Enabling integration for: 'slack'` appears **twice** (main + demo).
5. Both webhook URLs are secrets — store outside this doc; rotate if exposed.

---

## 7. Webhook rotation log

**Both webhook URLs were rotated on 2026-07-17** after being exposed in screenshots during the POC:
- Old webhooks revoked in Slack (app `wazuhpoc` → **Incoming Webhooks** / **Revoke All OAuth Tokens** → reinstall), and new webhooks generated for `#wazuh-alerts` and `#wazuh-demo`.
- Both `hook_url` values swapped **atomically** in the manager `ossec.conf` (single script; backup `ossec.conf.bak.rotate.*`). Guard asserted each old URL matched exactly once and that no old token remained.
- **Verified:** old tokens absent from config; both integrations reloaded (`Enabling integration for: 'slack'` ×2, no errors); a fresh failed-sudo smoke test invoked the **new** demo webhook token (old demo token no longer invoked).
- **The actual URLs are NOT stored in this document** (secrets) — live values exist only in the manager `ossec.conf`. Rotate again immediately if either is exposed.

---

## 8. Phase 8 complete — sign-off

- ✅ **Main channel (`#wazuh-alerts`):** level 7+, all groups, rule 533 downgraded (→ 100533/level 3), production-clean.
- ✅ **Demo channel (`#wazuh-demo`):** level 5+, `sudo`+`syscheck` groups; **instant sudo trigger (~3 s)**; **FIM trigger (pre-staged, ~2 min)** — runbook in §5b.
- ✅ **Both webhook URLs rotated** after exposure (§7), config updated, old tokens confirmed retired.
- ✅ **End-to-end verified:** event → Wazuh → Slack — confirmed for sudo (rule 5401) and netstat (rule 533); post-rotation smoke test confirmed both at the manager (new webhook token invoked) **and Slack-side (message received in `#wazuh-demo` via the new webhook, 2026-07-17)**.
- ⏳ **Re-application needed when the stack moves to a shared host** — webhook URLs (secrets, applied separately) + all integration/rule config documented in this file (§2, §4, §5b, §6).

**FIM demo caveat (macOS):** the FIM scenario requires temporary pre-staging (syscheck frequency 43200s → 120s, reverted after — §5b). This is macOS-only; Linux FIM is realtime.
