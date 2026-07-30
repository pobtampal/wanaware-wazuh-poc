# Wazuh vs CrowdStrike — macOS EDR Feasibility POC

**Host:** Pobtams-MacBook-Air.local (Apple Silicon / arm64, macOS, SIP **enabled**)
**Wazuh:** Manager v4.14.5 (Docker, single-node) · Agent v4.14.5 (id `001`, status **active**)
**Date:** 2026-06-28 · All verification via Manager REST API (`:55000`) + Indexer (`:9200`)

---

## Test results

| # | Scenario | Detected? | Rule / Alert ID | Time-to-alert | False negative / caveat |
|---|----------|-----------|-----------------|---------------|--------------------------|
| 1 | **EICAR** — initial (default config) | ❌ **No** | — | n/a | Default Wazuh has no AV/content-scanning engine; file in an unmonitored path (`~/Downloads`, `/tmp`) is invisible. |
| 1b | **EICAR** — after wiring **FIM + VirusTotal** (Phase 2) | ✅ **Yes** | **87105** "VirusTotal: Alert — 65 engines detected" (level 12) | **~80 s** | **Gap closed.** Requires: file in a FIM-monitored dir + VT integration + API key + manager internet. Detection latency = FIM scan interval (80 s here at 120 s freq; **up to 12 h at default**). **Hash-reputation only** — a novel/zero-day hash returns "no records" (rule 87102), *not* a detection; VT free tier = 4 req/min, 500/day; file hashes are sent to a third party. |
| 2 | **FIM** — modify file in monitored dir | ✅ **Yes** | **550** "Integrity checksum changed" (lvl 7) | **~117 s** (= scan interval) | Only via **scheduled scan**. macOS **has no realtime FIM** (`realtime="yes"` silently dropped → `realtime: None`). Default interval is **43200 s (12 h)** — I lowered it to 120 s to test. Forcing a scan via agent *restart* re-baselines instead of alerting. |
| 3 | **Sudo** — 3 failed sudo auths | ✅ **Yes** | **5401** "Failed attempt to run sudo" (lvl 5, MITRE **T1548.003**); also **5403** "First time user executed sudo" | **~3 s** | Near-realtime (unified-logging stream). Repeated *successful* sudo within ~5 min is **not** re-alerted (sudo credential caching = no new auth log). 3 failures did **not** escalate to a "3 failed attempts" composite. |
| 4 | **MITRE discovery** T1033/T1087.001/T1518.001/T1217 — default config | ❌ **No** | — | n/a | **Architectural false negative.** Wazuh on macOS has **no process-execution telemetry** by default — discovery commands generate no collected log. ART *does* support macOS, but its runner (`pwsh`) is not installed; techniques were run manually. |
| 4b | **MITRE discovery** — after adding **osquery + EndpointSecurity** (Phase 2) | ⚠️ **Visible, NOT detected** | **24010** "osquery: process_events query result" (level **3**) | **~2 s** | **Visibility gap closed:** all four techniques now captured with full `cmdline` + parent PID. **But**: rule 24010 is *generic telemetry that fires for every exec on the host* — no ATT&CK classification, no malicious/discovery detection. Turning it into real detections needs **custom rule authoring**. **Severe volume:** ~8,910 osquery alerts in 5 min (every system process, incl. Docker/bash), which floods the indexer unfiltered. |

---

## Wazuh vs CrowdStrike comparison

> ⚠️ **The CrowdStrike column below is DRAFTED FROM PUBLIC DOCS — VERIFY AGAINST ACTUAL FALCON CONSOLE/POLICY.**
> It reflects Falcon's *publicly documented* capabilities, **not** our specific tenant, licensed modules, or policy
> configuration (which this POC has no visibility into). Behavior is described qualitatively on purpose — **no Falcon
> detection names, IDs, severities, or timings are invented**. For each row, pull the real detection name / severity /
> time-to-detect from our own Falcon console to make this apples-to-apples. Whether a given capability is active also
> depends on which **modules are licensed** (e.g. NGAV, Insight/EDR, FileVantage, RTR) and how prevention/detection
> policies are tuned.

| Scenario | Wazuh (v4.14.5, macOS) — observed | CrowdStrike Falcon — expected *(drafted from public docs — verify)* |
|----------|-----------------------------------|----------------------------------------------------------------------|
| **EICAR / known-malware file** | ❌ Not detected. No AV engine; requires FIM + VirusTotal/ClamAV integration. | Falcon's on-sensor **NGAV (signature + ML/IOA)** would be expected to flag EICAR on file write/access — EICAR is a standard AV test string. Likely quarantined/blocked if prevention policy is enabled, vs detect-only if not. *Verify: actual detection name, severity, prevention action, and time-to-detect in our console; confirm NGAV/prevention policy is on for macOS hosts.* |
| **File Integrity Monitoring** | ✅ Detected (rule 550), but scheduled-scan only, ~12 h default latency; no realtime on macOS. | FIM/compliance monitoring is **not** core Falcon EDR — it's a **separate licensed module (Falcon FileVantage)**. The base sensor captures file-write *telemetry* but does not do compliance-style integrity baselining out of the box. *Verify: whether FileVantage is licensed; if so its monitored paths and alerting latency on macOS.* |
| **Failed sudo / privilege misuse** | ✅ Detected (rule 5401, ~3 s, MITRE-mapped T1548.003). | Falcon captures **process + privilege-escalation telemetry**; suspicious sudo/privesc patterns can raise **IOA-based detections**. A single failed sudo may be telemetry-only rather than a detection. *Verify: whether failed/anomalous sudo raises a detection vs just appearing in the event stream, and the mapped IOA/ATT&CK technique in console.* |
| **Behavioral / MITRE discovery (T1033/T1087/T1518/T1217)** | ❌ Not detected by default (no process/command-line telemetry on macOS). | This is **Falcon's core strength**: full process-execution telemetry via the macOS **Endpoint Security Framework**, with command lines and parent-child lineage. Discovery techniques are expected to appear as **telemetry**, and some raise **IOA detections** mapped to ATT&CK. *Verify: which of these four techniques produce an actual detection vs telemetry-only, and the detection names, in our console.* |
| **Process tree / parent-child lineage** | ❌ Not available by default (no ESF/eBPF-equiv sensor). | Expected to be available natively — full **process lineage / graph** is a baseline Falcon EDR (Insight) feature. *Verify: requires the EDR/Insight module licensed, not NGAV-only.* |
| **Realtime response / containment** | ⚠️ Active-Response exists but limited on macOS. | Expected via **Real Time Response (RTR)** and **network containment**. *Verify: RTR module licensed and role-permissioned; confirm macOS support for the specific response actions you need.* |

---

## macOS-specific limitations (would NOT apply on a Linux endpoint)

These matter because the comparison fleet is mixed-OS — several Wazuh weaknesses here are **macOS-only** and disappear on Linux:

1. **No realtime FIM on macOS.** Realtime/whodata is Linux (inotify) / Windows only; macOS silently falls back to scheduled scans (empirically confirmed: `realtime: None` on all dirs). **On Linux, FIM is sub-second.** Biggest functional gap found.
2. **No process/behavioral telemetry by default on macOS.** No Endpoint Security Framework / eBPF-equivalent sensor in the OSS agent. Discovery & most ATT&CK behavioral techniques are invisible out of the box. **Phase 2 closed the *visibility* gap** via osquery + EndpointSecurity (see "Gap-closing effort" below) — but only to raw telemetry (rule 24010), not classified detections, and at high volume. **On Linux, the Wazuh `auditd` integration gives real syscall/exec visibility natively — no third-party agent, no TCC grant.** This is the single largest macOS-specific weakness.
   - **macOS 26 platform note:** the classic **OpenBSM audit subsystem is effectively removed** — `/etc/security/audit_control` is absent and the `com.apple.auditd` LaunchDaemon no longer exists (`audit -s` → `AUC_NOAUDIT`). So the lightweight `auditpipe`/osquery-BSM path that works on older macOS is **dead here**; the only remaining exec-telemetry source is EndpointSecurity, which is entitlement-gated.
3. **Userland agent, no kernel/System Extension.** Lighter install than Falcon (which needs an MDM-approved System Extension) but correspondingly shallower kernel visibility. Architecture-level difference, not just config.
4. **SIP** (confirmed enabled) — does **not** block FIM *reading* of system paths (`/etc/hosts`, `/usr/bin` hash fine). It blocks *modification*, not the agent's read access. Not a blocker for FIM.
5. **TCC / Full Disk Access** — **central, not incidental.** Getting process telemetry (Phase 2) *required* granting Full Disk Access to the osqueryd binary via a **GUI action** that cannot be scripted. At fleet scale this means an **MDM-pushed PPPC/TCC profile** per endpoint. Also relevant to any FIM scope touching protected user-data paths (`~/Library/Mail`, Messages, etc.).
6. **No native AV** on any OS — EICAR gap (Test 1) is **not** macOS-specific; it's a Wazuh-wide design point vs Falcon's built-in NGAV/ML.

---

## Gap-closing effort & complexity (Phase 2) — a "Manageability" data point

What it actually took to close the Test 1 and Test 4 gaps — relevant because operational cost is part of the migration decision:

| Gap | Fix | Effort / complexity | Ongoing cost |
|-----|-----|---------------------|--------------|
| **Test 1 — malware (EICAR)** | FIM (monitored dir) + **VirusTotal integration** on the manager (API key) | **Low.** ~10 min, manager-side config only, no endpoint change. | VT free tier **4 req/min, 500/day**; **hash-reputation only** (misses zero-days → rule 87102 "no records"); file hashes sent to a 3rd party; detection latency = FIM scan interval (up to 12 h default). |
| **Test 4 — process visibility** | **osquery** (official ES-entitled build) + **EndpointSecurity** `es_process_events`, ingested via Wazuh **osquery wodle** | **High.** Required: (1) install osquery cask; (2) discover that **OpenBSM is dead on macOS 26**; (3) fall back to EndpointSecurity; (4) **GUI Full Disk Access grant** to osqueryd (un-scriptable); (5) fix the wodle `bin_path` (folder, not binary). Multiple iterations. | Third-party agent to maintain; **MDM PPPC/TCC profile** per host at scale; **very high event volume** needing filtering; telemetry only — **custom rules required** to get ATT&CK detections. |

**Bottom line for manageability:** malware detection is a cheap manager-side add-on; **process/behavioral visibility on macOS is a genuine project** — an entitled third-party binary, a per-endpoint MDM TCC profile, event-volume tuning, and custom detection engineering — versus CrowdStrike, where equivalent telemetry + behavioral IOAs ship in the sensor. On **Linux** this gap largely evaporates (native `auditd` integration).

## Recommendations / follow-ups
- **Author detection rules** on top of the osquery telemetry (map `es_process_events` cmdline patterns to ATT&CK) — telemetry alone is not detection. Filter the `es_process_events` query to cut the ~8,900-alerts/5-min noise before this is usable.
- Re-run the **full Atomic Red Team macOS pack** (install `pwsh` + `Invoke-AtomicRedTeam`) now that process telemetry exists — current run was manual/representative.
- Fill the **CrowdStrike column** from the actual Falcon console (see verify banner above).
- For **zero-day** coverage (VT only does known hashes), evaluate ClamAV or a real NGAV — VT integration does not replace on-sensor ML.

## ⚠️ Live test config — NOT yet reverted (revert in one batch when testing is done)

**Agent (`/Library/Ossec/etc/ossec.conf`, macOS host):**
1. syscheck `<frequency>` = **120 s** (default 43200 s / 12 h)
2. Two extra FIM dirs: `/Users/Shared/wazuh_fim_test`, `/etc/hosts`
3. **osquery wodle enabled** (`<disabled>no</disabled>`, ES `es_process_events`, 5 s interval) — currently spawning osqueryd continuously at high event volume
4. Backups: `/Library/Ossec/etc/ossec.conf.bak.*`

**macOS host (system-level):**
5. **osquery** installed (Homebrew cask, 5.23.1)
6. **Full Disk Access** granted to `/opt/osquery/lib/osquery.app/Contents/MacOS/osqueryd` (TCC)
7. `/etc/security/audit_control` created (inert — auditd is dead on macOS 26)
8. Config/log files under `/var/osquery/` and `/var/log/osquery/`

**Manager (Dockerized `wazuh.manager`):**
9. **VirusTotal integration** in the manager `ossec.conf` (contains the API key — **rotate after POC**); backups `ossec.conf.bak.*`

**Test artifacts:** EICAR content currently sits in `/Users/Shared/wazuh_fim_test/watched.txt`; helper scripts in the project root (`osq-*.sh`).

> Per instructions, **nothing above has been reverted** — testing is still active. I'll remind you again before Phase 5/6 (which also touch this agent), and provide a single batched revert block when you're ready.
