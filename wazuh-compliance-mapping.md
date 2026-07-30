# Wazuh Compliance Mapping — POC Phase 4 (ISO 27001:2022 / CMMC 2.0 Level 2)

**Prepared for:** WanAware Wazuh POC (Request for POC dated 2026-06-05) — vs CrowdStrike XDR/SIEM evaluation
**Environment:** single-node Docker (v4.14.5), MacBook Air (macOS 26.5.1); agent 001 v4.14.5
**Date:** 2026-07-30
**Scope:** gap analysis mapping Wazuh's **POC-demonstrated** capabilities (not vendor marketing) against the ISO 27001:2022 Annex A controls and CMMC 2.0 Level 2 (≈ NIST SP 800-171 Rev 2) practices a **SIEM/XDR realistically touches**. Not exhaustive across either framework.
**Status:** ⏳ **Partial** — the mapping is complete, but several control-relevant capabilities come back **Untested/Gap** in this POC, so a compliance *claim* cannot yet be made without follow-up testing (see §Open items).

> **Two scoping guardrails (per phase brief):**
> 1. This assesses whether **WanAware's *use* of Wazuh, as configured in this POC**, can meet control requirements — **NOT** whether Wazuh Inc. holds SOC2/ISO certification (separate vendor due-diligence, out of scope).
> 2. **Conservative status:** anything not empirically verified *in this POC* is **Untested**, even where Wazuh's docs claim the capability. Statuses: **Met** (verified this POC) · **Partial** (mechanism verified, incomplete/needs config) · **Gap** (not provided / fails requirement) · **Untested** (capability may exist, not validated here).

---

## Posture summary

| # | Control family | ISO 27001:2022 | CMMC 2.0 L2 domain | Headline status |
|---|----------------|----------------|--------------------|-----------------|
| 1 | Logging & monitoring | A.8.15, A.8.16 | AU | 🟡 Partial — alerting verified; **log tamper-evidence a Gap** |
| 2 | Access control & authentication | A.8.2, A.8.3, A.8.5 | AC, IA | 🔴 Gap — **repo-default creds, no MFA, RBAC unconfigured** |
| 3 | Malware defense / endpoint | A.8.7 | SI | 🔴 Gap standalone — **CrowdStrike is the compensating control** |
| 4 | Configuration management | A.8.9 | CM | 🟡 Partial — config-as-code supports it *with discipline* |
| 5 | Vulnerability management | A.8.8 | RA | ⚪ Untested — VD feed present, **efficacy never validated** |
| 6 | Third-party data handling | A.5.19–A.5.23 | SC / CUI boundary | 🟡 Partial — VT + **Slack** are external data flows to document |
| 7 | Incident response | A.5.24–A.5.26 | IR | 🟡 Partial — detection/notification only; tracking/Incident.io blocked |

**Overall:** Wazuh as configured in this POC provides strong **detection & logging mechanics** but is **not yet compliance-demonstrable** on its own for endpoint malware protection (SI), access hardening (AC/IA), vulnerability management (RA), or log integrity (AU) without follow-up work. The single most consequential finding for a real migration: **CrowdStrike remaining in place is itself the compensating control** for the malware-defense (SI-3-equivalent) gap.

---

## 1. Logging & monitoring — ISO A.8.15/A.8.16 · CMMC AU

| Control ID | Requirement (summary) | Wazuh capability (POC evidence) | Status | Notes |
|---|---|---|---|---|
| AU.L2-3.3.1 / A.8.15 | Create & retain audit/system logs | Alerts generated & verified: rule **5401** sudo, **550** FIM, **87105** VT/EICAR, **24010** osquery (Phase 2). ISM retention hot/warm/cold/**delete 90d** (Phase 5, verified transitioning). | 🟡 Partial | Mechanism verified. 90-day retention is short for many CUI regimes (often ≥1 yr) — Phase 5 documented a 365-day option (~4× storage). |
| AU.L2-3.3.2 / A.8.16 | Trace actions to individual users | Alerts carry agent, user, cmdline (e.g. 5401 shows `pobtampal`, MITRE T1548.003). | 🟡 Partial | Per-event attribution works; not validated across all required event types. |
| AU.L2-3.3.5 | Correlate & review audit records | Dashboard (Discover/Threat Hunting) + Slack alerting (Phase 8). Query speed <0.2s (Phase 9). | 🟡 Partial | Correlation rules are mostly Wazuh defaults; custom correlation not built. ⚠️ Phase 9: default views buried under osquery noise (~41k/hr) — review is impaired until filtered to `rule.level>=7`. |
| AU.L2-3.3.4 | Alert on audit-logging failure | Not tested — no verification that a logging-pipeline failure (e.g. indexer down, filebeat stall) itself raises an alert. | ⚪ Untested | Add to evidence gaps. |
| **AU.L2-3.3.8 / A.8.15 / A.5.28** | **Protect audit info from unauthorized modification/deletion (tamper-evidence, evidence integrity)** | Wazuh does **not** natively hash-chain or cryptographically sign alert logs at rest. Indexer data is admin-mutable. **Partial mitigation:** Phase 5 ISM sets warm/cold indices **read-only** after 7 days (aged data resists modification), but it's non-cryptographic and an admin can lift it. | 🔴 **Gap** | **Key finding.** No native tamper-evidence. Compounded by §2 (repo-default indexer admin creds → anyone with default creds can alter/delete indices). Hot 0–7d window has no read-only protection. → open item: define log-integrity approach (WORM/immutable snapshots, external SIEM forwarding, or signing). |

---

## 2. Access control & authentication — ISO A.8.2/A.8.3/A.8.5 · CMMC AC/IA

| Control ID | Requirement (summary) | Wazuh capability (POC evidence) | Status | Notes |
|---|---|---|---|---|
| **IA.L2-3.5.7 / A.8.5** | **Manage/rotate authenticators; no default creds** | Dashboard `admin`/`<LOCAL_DEFAULT_INDEXER_PW>`, API `wazuh-wui`/`<LOCAL_DEFAULT_API_PW>`, indexer `admin`/`<LOCAL_DEFAULT_INDEXER_PW>` — **all still repo defaults** (Phase 9 open item; VT key was also exposed & neutralized, Phase 2/8). | 🔴 **Gap** | **Live finding, not hypothetical.** Default credentials fail IA outright and undermine AU-3.3.8 (§1). Must rotate before any compliance posture. |
| IA.L2-3.5.3 / A.8.5 | Multi-factor authentication | No MFA configured in POC. Dashboard (OpenSearch) can integrate SAML/OIDC (→ IdP MFA), but not native and **not set up here**. | 🔴 Gap | Would require SSO/IdP integration — untested. |
| AC.L2-3.1.5 / A.8.2 | Least privilege / privileged access | Wazuh RBAC (dashboard roles + API RBAC policies) **exists** but POC used only the built-in super-admin accounts — no restricted roles created or tested. | ⚪ Untested | Capability present per docs; **not validated** — mark Untested per conservative rule. |
| AC.L2-3.1.1 / A.8.3 | Limit system access to authorized users | Single admin identity used throughout; no per-analyst accounts. | ⚪ Untested | Same as above — RBAC unconfigured. |
| AC.L2-3.1.12 | Monitor/control remote access | POC bound to `localhost` only; no remote-access exposure tested. | ⚪ Untested | Re-assess at shared-host/production. |

---

## 3. Malware defense / endpoint protection — ISO A.8.7 · CMMC SI

| Control ID | Requirement (summary) | Wazuh capability (POC evidence) | Status | Notes |
|---|---|---|---|---|
| **SI.L2-3.14.2 / A.8.7** | **Malicious code protection at entry/exit & endpoints** | **No native AV/anti-malware engine** (Phase 2). EICAR detected **only via VirusTotal** (rule 87105) = **hash-reputation only, misses zero-days**; ~80s latency. macOS FIM **not real-time** (scheduled, 12h default). | 🔴 **Gap** (standalone) | **Central finding.** Wazuh is **not an AV/EDR replacement** for SI-3-equivalent protection. **CrowdStrike remaining in place IS the compensating control** during any real migration — do not decommission Falcon on the strength of Wazuh alone. |
| SI.L2-3.14.4 | Keep malicious-code mechanisms current | VT cloud lookup is inherently current for *known* hashes; no local signature engine to update. | 🟡 Partial | N/A framing — there's no AV signature set; currency ≠ coverage (still misses zero-days). |
| SI.L2-3.14.5 | Periodic + real-time scans | FIM **scheduled** scans exist (12h); **no real-time** on macOS (Phase 2), **no malware content scanning**. | 🔴 Gap | Periodic FIM ≠ malware scanning. |
| SI.L2-3.14.6/3.14.7 | Monitor for attacks / unauthorized use | Behavioral alerts verified (sudo 5401; osquery process telemetry 24010 with custom rules) (Phase 2). | 🟡 Partial | Detection works; classification into "attack" needs custom rules (Phase 2: 24010 is telemetry, not detections, without rule authoring). |

---

## 4. Configuration management — ISO A.8.9 · CMMC CM

| Control ID | Requirement (summary) | Wazuh capability (POC evidence) | Status | Notes |
|---|---|---|---|---|
| CM.L2-3.4.1 / A.8.9 | Establish & maintain baseline configs | Config-as-code: manager `wazuh_manager.conf`, `docker-compose.yml`, `local_rules.xml`, `agent.conf` are file-based & git-trackable (Phase 6). | 🟡 Partial | Baseline exists in files; not under a formal VCS/change-control process yet. |
| CM.L2-3.4.2 | Enforce security config settings | Central config push to agents via groups + `agent.conf` verified (~40s propagation, Phase 9). | 🟡 Partial | Mechanism works (single agent); fleet-scale enforcement unvalidated (Phase 10). |
| **CM.L2-3.4.3** | **Track/review/approve config changes (audit trail)** | Config-as-code **supports** change evidence *if* changes go through git-tracked files. **But** Phase 6 found a **config-drift bug**: runtime edits made inside the container (Slack/VT integrations) bypassed the declarative config and would silently revert on recreate — caught & fixed. Phase 9: engineer-operated (file edits + CLI), **no built-in change-approval/audit log** like a GUI platform. | 🟡 Partial | **Nuanced finding.** Config-as-code *can* provide strong CM evidence (git history) — but only with process discipline; the tool doesn't enforce it, and ad-hoc runtime edits can create drift between declared and running state. A GUI platform with a native change-audit log is easier to *evidence*; Wazuh needs a wrapper process. |

---

## 5. Vulnerability management — ISO A.8.8 · CMMC RA

| Control ID | Requirement (summary) | Wazuh capability (POC evidence) | Status | Notes |
|---|---|---|---|---|
| **RA.L2-3.11.2 / A.8.8** | **Scan for vulnerabilities** | Vulnerability Detector present — CVE feed downloaded (~8.3 GB RocksDB in `wazuh_queue`, Phase 5). **But detection was never validated end-to-end** — no confirmation it actually flags vulnerable packages on the macOS agent. | ⚪ **Untested** | **Evidence gap.** Feed exists ≠ scanning works. Do not claim RA coverage until validated. → open item: test VD end-to-end. |
| RA.L2-3.11.3 | Remediate vulnerabilities | Out of Wazuh scope (detection tool; no remediation/patching). | 🔴 Gap (tool) | Remediation is a WanAware process, not a Wazuh capability. |

---

## 6. Third-party data handling — ISO A.5.19–A.5.23 · CMMC SC / CUI boundary

| Control ID | Requirement (summary) | Wazuh capability (POC evidence) | Status | Notes |
|---|---|---|---|---|
| A.5.19–5.23 / SC.L2-3.13.1 | Supplier/cloud data-flow control; monitor & control comms at boundaries | **VirusTotal** integration sends file **hashes** to a 3rd party (Phase 2) — hash-only (not file contents) limits exposure, but hashes derived from CUI systems still cross the boundary. **Currently neutralized** (key REMOVED) so no live egress. | 🟡 Partial | For CMMC, any egress from a CUI-scoped system to external SaaS needs a documented data-flow + supplier agreement. Hash-only ≠ zero exposure (can confirm file existence). Re-enabling VT = a boundary decision. |
| A.5.19–5.23 / SC.L2-3.13.1 | (same — second external flow) | **Slack** alerting (Phase 8) sends **alert content** (hostnames, usernames, file paths, command lines) to Slack SaaS — a **larger** third-party data flow than VT, and it's **live** in `#wazuh-alerts` / `#wazuh-demo`. | 🟡 Partial | **Flagged proactively.** Slack egress carries richer CUI-adjacent metadata than VT hashes. Both flows need documenting; consider redaction/scoping or an internal notification channel for CUI environments. |

---

## 7. Incident response — ISO A.5.24–A.5.26 · CMMC IR

| Control ID | Requirement (summary) | Wazuh capability (POC evidence) | Status | Notes |
|---|---|---|---|---|
| IR.L2-3.6.1 / A.5.24-25 | IR capability (prepare/detect/analyze) | Detection + **notification** verified (Slack, Phase 8). Wazuh **Active Response** (automated response) exists but was **not configured/tested**. | 🟡 Partial | Detection/notification met; response handling is WanAware process, not Wazuh-native. Active Response untested. |
| IR.L2-3.6.2 / A.5.26 | Track & report incidents | **Incident.io integration is BLOCKED** (Phase 8 extension). No automated incident tracking/ticketing today. | 🔴 Gap | Manual process only. Automated-IR-workflow claims cannot be made until Incident.io (or equivalent) is wired up. |
| IR.L2-3.6.3 | Test IR capability | Not performed in POC (the FIM demo runbook is a detection demo, not an IR exercise). | ⚪ Untested | — |

---

## Key Technical Decisions

- **"Untested" is used aggressively** — VD scanning, RBAC, MFA, audit-failure alerting, Active Response, and IR testing all have plausible Wazuh support per docs but were **not validated in this POC**, so none is marked Met. A compliance claim requires closing these.
- **CrowdStrike is the SI-3 compensating control** — the single most important compliance conclusion. Wazuh's lack of a native AV/EDR engine (Phase 2) means it cannot alone satisfy malicious-code-protection controls; Falcon must remain during any migration, and the migration plan must state this explicitly.
- **Two external data flows, not one** — VT (hashes, currently off) *and* Slack (live, richer alert metadata) both cross the boundary. The Slack flow is the bigger CUI consideration and is easy to overlook.
- **Log integrity is the quiet gap** — no native tamper-evidence; the ISM read-only-on-aged-indices behavior (Phase 5) is a partial, non-cryptographic mitigation only, and the hot window + default indexer creds leave it exposed.
- **Config-as-code cuts both ways for CM** — it *enables* change evidence (git) but doesn't *enforce* it; the Phase 6 drift bug shows running state can diverge from declared state.

---

## Open items raised by this phase

| Item | Type | Detail |
|---|---|---|
| **Test Vulnerability Detector end-to-end** | 🔴 New | RA.L2-3.11.2 / A.8.8 is **Untested** — validate that VD actually flags vulnerable packages on the agent (feed exists, efficacy unproven). Highest-value compliance evidence gap. |
| **Define log integrity / tamper-evidence approach** | 🔴 New | AU.L2-3.3.8 / A.8.15 / A.5.28 Gap — no native signing/WORM. Evaluate immutable snapshots, external SIEM forwarding, or log signing; and rely less on ISM read-only alone. |
| **Configure & test RBAC + MFA/SSO** | 🟡 New | AC/IA Untested/Gap — create least-privilege roles, integrate IdP for MFA. (Pairs with the existing Phase 9 credential-rotation item — both must land together.) |
| **Document third-party data flows (VT + Slack) vs CUI boundary** | 🟡 New | A.5.19–23 / SC.L2-3.13.1 — data-flow diagrams + supplier assessment; decide redaction/scoping for CUI. |
| **IR workflow (Incident.io) + Active Response test** | 🟡 New (partly blocked) | IR.L2-3.6.2 Gap — Incident.io is blocked (Phase 8); also test Active Response for automated IR. |

> **Framework-version note:** ISO control IDs are the **2022** Annex A revision; CMMC practice IDs follow **CMMC 2.0 Level 2 / NIST SP 800-171 Rev 2**. If WanAware's audit targets 800-171 **Rev 3** or a specific CMMC assessment guide version, the family mappings hold but individual IDs should be re-checked.
