# Wazuh POC — Management-Meeting Demo Runsheet (TESTED)

**Rehearsed:** 2026-09-05 on Pobtams-MacBook-Air.local (single-node Docker v4.14.5, agent 001).
**Dashboard:** https://localhost:443 (log in with the admin account — credentials in your password manager, not written here).
**Everything below was run and verified. Timings are real, measured this session.**

> ⚠️ **One-time pre-check before the meeting:** confirm the stack is up (`docker ps` → 3 containers) and agent 001 is **active** in *Agents*. The watched FIM dir is already pre-staged (see §2), so meeting-day is just the triggers.

---

## 0. Signal-vs-noise note (say this once, up front)
This endpoint streams ~37k alerts/24h but **99.98% is level-3 osquery telemetry** — normal for a security-instrumented host. In every view, **filter `rule.level >= 7`** (or exclude `rule.id:24010`) to show the *actionable* signal. Have that filter ready in Discover.

## 1. Instant event-flow demo — "type a wrong password, watch it appear" ✅ TESTED
The reliable backbone. Shows collection → analysis → alert → Slack end-to-end in seconds.

**Trigger (in a terminal on the Mac):**
```bash
for n in 1 2 3; do echo "wrong_pw" | sudo -S -k -p "" id 2>&1 | head -1; done
```
- **Fires:** rule **5401 "Failed attempt to run sudo"**, level 5 (MITRE T1548.003).
- **Measured:** alert in ~**4 s**; **#wazuh-demo** Slack message in ~**2–5 s**.
- **Show:** *Threat Hunting* / Discover filtered to `rule.id:5401` (the new events), then the **#wazuh-demo** Slack channel lighting up. Expand one alert → `full_log`, `agent.name`, `rule.mitre`.
- *(3 attempts reliably land in #wazuh-demo; macOS may collapse rapid identical failures into 2 alerts — still lands.)*

## 2. FIM (file integrity) live demo — "change a file, it's caught" ✅ TESTED
**Pre-staged:** `/Users/Shared/wazuh_fim_test/watched.txt` already exists and is baselined. **Meeting-day is just the one line below.**

**Trigger:**
```bash
echo "# demo $(date)" >> /Users/Shared/wazuh_fim_test/watched.txt
```
- **Fires:** rule **550 "Integrity checksum changed"**, level 7, `event=modified`.
- **Measured:** ~**49 s** to alert (bounded by the scan interval). Level 7 → routes to **both #wazuh-alerts and #wazuh-demo**.
- **Show:** the *FIM / Integrity monitoring* view for agent 001 (1,270 monitored entries) + the alert with the before/after change.
- ⏱️ **Timing caveat for the room:** macOS FIM is **scan-based, not real-time** (Phase 2 finding). For the *live* demo the scan interval is temporarily short; **production default is 12 h**, and Linux endpoints get sub-second FIM via inotify. Trigger this one *early* in the demo so the alert lands by the time you circle back.

## 3. The data Wazuh collects (populated views to open — all have real data)
| View | What to point at (agent 001) |
|---|---|
| **Inventory** (syscollector) | 356 packages · 11 open ports · 431 processes |
| **Vulnerabilities** | 80 findings (CVE severity from CVSS) |
| **SCA** (config assessment) | CIS macOS 26.x — 41 pass / 25 fail (62%) — great "hardening posture" story |
| **MITRE ATT&CK** | 12 MITRE-tagged alerts in 24h — map detections to techniques |
| **FIM** | 1,270 monitored file entries |

## 4. Onboarding a new endpoint — narrative + command
Agent 001 enrolled via the manager's `authd` (auto-enrollment) on 2026-06-28 and reports to the manager. **The exact same package + one enrollment command onboards any new host.**

**macOS (Apple Silicon):**
```bash
sudo launchctl setenv WAZUH_MANAGER "<MANAGER_IP>"
sudo installer -pkg wazuh-agent-4.14.5-1.arm64.pkg -target /
sudo /Library/Ossec/bin/wazuh-control start    # group defaults to "default"
```
**Linux (Debian/Ubuntu):**
```bash
curl -sO https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.5-1_amd64.deb
sudo WAZUH_MANAGER="<MANAGER_IP>" WAZUH_AGENT_GROUP="default" dpkg -i wazuh-agent_4.14.5-1_amd64.deb
sudo systemctl daemon-reload && sudo systemctl enable --now wazuh-agent
```
- **⚠️ Reachability caveat (matters for a *live* remote demo):** this POC manager listens on **`127.0.0.1:1514` (loopback only)**. A second host on the same Mac would use `127.0.0.1`; a **real remote endpoint needs a network-reachable manager IP** — the loopback POC can't accept a remote enrollment as-is. Frame onboarding as "here's the one command" rather than enrolling a remote laptop live (unless we expose 1514 first).
- **NinjaOne angle:** the **same package + enrollment command is exactly what NinjaOne would push fleet-wide** as a deployment. On **macOS**, pair it with an **MDM-pushed PPPC / Full-Disk-Access profile** so osquery/EndpointSecurity can collect full process telemetry (Phase 2 finding) — otherwise macOS telemetry is degraded.

## 5. Antivirus approach — talking points (honest)
**What we found on THIS endpoint (measured today):** macOS 26.6.2 / arm64, and **no CrowdStrike Falcon, no Microsoft Defender, no Bitdefender detected** — this POC Mac currently has no third-party AV/EDR engine.

**What Wazuh contributes (complements, does NOT replace an AV engine):** FIM, SCA/hardening, vulnerability detection, inventory, log/behavioral detections (sudo, MITRE mapping), and known-malware flagging *if* VirusTotal is wired up (hash-reputation only — misses zero-days; currently neutralized).

**The honest line for the room:** Wazuh is **not** an AV/EDR replacement (no native anti-malware engine — Phase 2/4 finding). For CMMC SI-3-equivalent malware protection, a real AV/EDR (e.g. CrowdStrike) must remain the compensating control; Wazuh is the SIEM/visibility layer on top.

**🔴 Decision inputs Claude Code CANNOT gather here — bring these to the call (do not guess):**
- The **fleet-wide OS split** (how many Windows / macOS / Linux endpoints).
- Any **existing Bitdefender or Microsoft Defender licensing** already owned.
- Whether CrowdStrike Falcon is deployed **elsewhere in the fleet** (it isn't on this Mac).
These determine the AV strategy and can't be inferred from one endpoint.

---

## Fallbacks if something misbehaves
- **Slack didn't visibly fire:** show the alert in the dashboard/Discover instead — the detection is what matters; Slack is the delivery layer. (Manager-side firing is logged either way.)
- **FIM alert slow:** it's scan-bounded — that's why you trigger it early. Fall back to the instant sudo demo (§1), which is seconds.
- **Stack down:** `cd wazuh-docker/single-node && docker compose up -d`, wait ~2 min, re-check agent active.
