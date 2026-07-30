# Wazuh POC — Context Document
**Purpose:** Paste this at the start of any new Claude chat to restore full context.
**Last updated:** 2026-07-30
**POC Owner:** pobtampal@gmail.com (WanAware Security Team)
**Platform under evaluation:** Wazuh v4.14.5 (XDR/SIEM) — potential replacement/supplement for CrowdStrike

---

## POC Background

WanAware is evaluating Wazuh as a consolidated XDR and SIEM platform. The full scope is defined in "Request for Proof of Concept: Wazuh XDR/SIEM Platform Evaluation" (June 5, 2026). Key objectives: EDR migration feasibility vs CrowdStrike, SIEM log ingestion from GCP and NinjaOne, scalability to 2,000 agents via Fleet Manager, compliance mapping (ISO 27001 / CMMC), Slack and Incident.io alerting, and data retention.

CrowdStrike remains active throughout the POC — this is evaluation only, not a migration.

---

## Current Stack

### Manager (Docker, single-node)
- **Location:** `/Users/pobtampal/Desktop/wazuhPOC/wazuh-docker/single-node`
- **Version:** v4.14.5
- **Host:** MacBook Air (Apple Silicon / arm64, macOS 26.5.1, SIP enabled)
- **Status:** Running. Accessible at:
  - Dashboard: `https://localhost:443` — `admin` / `<LOCAL_DEFAULT_INDEXER_PW>`
  - Manager API: `https://localhost:55000` — `wazuh-wui` / `<LOCAL_DEFAULT_API_PW>`
  - Indexer: `https://localhost:9200` — `admin` / `<LOCAL_DEFAULT_INDEXER_PW>`
- **Containers:** wazuh.manager, wazuh.indexer, wazuh.dashboard — all healthy
- **Note:** No `.env` file in v4.14.5 — credentials are in `docker-compose.yml` directly. No Docker HEALTHCHECK in these images — health verified via API endpoints, not `docker compose ps` status.
- **Config-as-code note (Phase 6):** the manager entrypoint copies the bind-mounted `config/wazuh_cluster/wazuh_manager.conf` over `/var/ossec/etc/ossec.conf` on every container init. Keep all manager config changes in that mounted file — changes made only inside the running container are reverted on recreate/upgrade.

### Manager (DigitalOcean droplet — PARALLEL deployment, added 2026-07-30)
A second, self-contained manager stack on a DO droplet so the POC isn't tied to the laptop. **This is parallel to — NOT a replacement for — the still-pending GCP shared-host plan** (GCP change request still with Jeff). The **local Mac stack remains untouched as the fallback** and still runs.
- **Droplet:** `wazuh-poc` · **IP 143.244.180.78** · region **sfo3** · size **s-4vcpu-8gb** (8 GB / 4 vCPU) · Ubuntu 24.04 LTS · **weekly backups + DO monitoring enabled**
- **Access:** SSH key-only as user `wazuh` (root SSH disabled); key `~/.ssh/id_ed25519` on the Mac. Non-root sudo, `vm.max_map_count=262144`, 2 GB swap.
- **Firewall:** ufw allows **only 22 + 443**. Manager API (55000), indexer (9200), agent ports (1514/1515/514) are bound to **127.0.0.1** on the droplet — reachable only via SSH tunnel, **verified not publicly reachable**. Only the dashboard (443) is public.
- **Dashboard:** `https://143.244.180.78:443` (self-signed cert warning expected).
- **Credentials — ROTATED (repo defaults NOT used here):**
  - Dashboard login / indexer `admin`: `<DROPLET_ADMIN_PW — in password manager>`
  - Manager API `wazuh-wui`: `<DROPLET_API_PW — in password manager>`
  - `kibanaserver` (internal dashboard→indexer): `<DROPLET_KIBANASERVER_PW — in password manager>`
  - (bcrypt hashes in `internal_users.yml` + env in `docker-compose.yml` + API pw in `wazuh.yml`; old `admin:<LOCAL_DEFAULT_INDEXER_PW>` verified → 401)
- **Slack:** both Phase-8 integrations transferred and **load**; **end-to-end firing CONFIRMED** — a droplet-local *throwaway* test agent generated failed-sudo → rule 5401 → `#wazuh-demo` webhook invoked 3×. Test agent + `sudotest` user **removed afterward** (only manager `000` remains). ⚠️ Both managers share the same live webhooks, so the droplet posts to the same `#wazuh-alerts`/`#wazuh-demo` — the test agent's one-time CIS/SCA scan sent ~162 level-7 messages to `#wazuh-alerts` before removal. Re-applied rule 100533 (netstat downgrade) on the droplet for parity.
- **macOS-agent → droplet enrollment path is UNTESTED** (deliberately — chose the droplet-local test agent to avoid touching the working macOS agent). That remote-enrollment path belongs to **Phase 10 (Fleet Manager)**, not this deployment task.
- ⚠️ **DO API token** was pasted in chat — **revoke/regenerate it in the DO console.**

### Agent
- **Host:** Pobtams-MacBook-Air.local (same MacBook as manager)
- **Version:** 4.14.5 (arm64 .pkg, notarized)
- **Agent ID:** 001
- **Status:** Active, connected to manager at 127.0.0.1:1514
- **Install path:** `/Library/Ossec/`
- **Control command:** `sudo /Library/Ossec/bin/wazuh-control [start|stop|restart|status]`
- **Config:** `/Library/Ossec/etc/ossec.conf`
- **Backups:** `/Library/Ossec/etc/ossec.conf.bak.*` (multiple, timestamped)

---

## Completed Phases

### Phase 1 — Stack Deployment ✅
Single-node Docker stack deployed and verified. TLS certs generated. All three containers healthy.

### Phase 2 — EDR Testing (expanded) ✅
Full EDR comparison test bed run. Key findings documented in `/Users/pobtampal/Desktop/wazuhPOC/wazuh-edr-evaluation.md`.

**Test results:**
| Test | Result | Rule | Time-to-alert | Notes |
|---|---|---|---|---|
| EICAR malware | ✅ (with VT) | 87105 lvl 12 | ~80s | Requires VirusTotal integration. No native AV engine. |
| FIM file modification | ✅ | 550 lvl 7 | ~117s | Scheduled scan only. No realtime FIM on macOS (realtime="yes" silently dropped). Default interval 12h. |
| Failed sudo | ✅ | 5401 lvl 5 | ~3s | Near-realtime. MITRE T1548.003 mapped. |
| MITRE discovery (T1033/T1087/T1518/T1217) | ✅ telemetry / ❌ detections | 24010 | ~2s | Requires osquery + ES. Custom rules needed for actual detections. ~8,900 alerts/5min noise. |

**macOS-specific limitations (not applicable on Linux):**
- No realtime FIM — falls back to scheduled scans
- OpenBSM/BSM audit subsystem dead on macOS 26 (auditd LaunchDaemon removed by Apple)
- Process telemetry requires osquery + EndpointSecurity + MDM-pushed PPPC/TCC profile per endpoint
- Wazuh agent is pure userland (no System Extension) vs CrowdStrike which uses ESF

**CrowdStrike comparison column:** DRAFTED FROM PUBLIC DOCS — needs verification against actual Falcon console. Check detection history for Pobtams-MacBook-Air.local on 2026-06-28 (Tests 1-3) and 2026-07-09 (Test 4 re-run).

**VirusTotal integration:** Configured on manager. API key currently set to `REMOVED` (key was exposed in chat — needs a fresh key from a new/rotated VT account before re-enabling).

### Phase 3 — Scalability, Architecture & Cost ✅
Documented in `/Users/pobtampal/Desktop/wazuhPOC/wazuh-architecture-scalability-cost.md`. Desk research; **endpoint-only baseline** (excludes GCP/NinjaOne SIEM volume — Phase 7, the dominant unmeasured variable).

- **Recommended production topology (2,000 agents):** 7-node distributed cluster — 1 server master + 2 server workers (~1,000 agents each, behind a load balancer) + 3 indexer nodes (quorum + 1 replica) + 1 dashboard. Single-node tops out ~100 agents.
- **Sizing (starting points — must load-test):** workers/indexers n2-standard-8 (8 vCPU/32 GB); ~1.3 TB SSD per indexer (from ~3.75 TB 90-day working set); JVM heap ≤32 GB/node. Capacity is EPS-driven — no fixed agents/node ceiling.
- **Cost (endpoint-only, us-central1):** GCP infra ~$2,180/mo single-copy (~$2,560 with replica) → **~$19k/yr (1-yr CUD)** to **~$31k/yr (on-demand + replica)**. Wazuh license **$0**.
- **All-in TCO (infra + labor + license):** Wazuh models **~$40k–$143k/yr** (operational labor is the dominant line, not infra); **CrowdStrike Enterprise ~$285k–$435k/yr** (public list, unverified). Gross advantage **~3–7×** — but must be read against Phase 2 macOS EDR gaps + self-run operational burden.
- **"Fleet Manager" disambiguation:** Wazuh server-cluster *worker nodes* (compute — this phase) ≠ WanAware *Fleet Manager* (agent lifecycle — Phase 10).
- **Recommendation:** self-managed GCP (1-yr CUD) as primary, Wazuh Cloud SaaS as fallback if headcount is the binding constraint. Competitor/SaaS figures are planning estimates — confirm CrowdStrike contracted rate + Wazuh Cloud quote with procurement before Phase 11.

### Phase 4 — Compliance Mapping (ISO 27001 / CMMC) ⏳ Partial
Documented in `/Users/pobtampal/Desktop/wazuhPOC/wazuh-compliance-mapping.md`. Gap analysis mapping POC-demonstrated capabilities against ISO 27001:2022 Annex A + CMMC 2.0 L2 (NIST 800-171 R2), for the 7 control families a SIEM/XDR touches. Mapping is complete; **compliance *claim* is not yet supportable** — multiple controls are Untested/Gap. Conservative statuses (Untested unless empirically verified this POC). Scope: WanAware's *use* of Wazuh, NOT Wazuh Inc. certification.

**Family statuses:** Logging/monitoring (AU) 🟡 Partial · Access/auth (AC/IA) 🔴 Gap · Malware/endpoint (SI) 🔴 Gap standalone · Config mgmt (CM) 🟡 Partial · Vuln mgmt (RA) ⚪ Untested · Third-party data (SC) 🟡 Partial · Incident response (IR) 🟡 Partial.

**Headline findings:**
- **CrowdStrike is the SI-3 compensating control** — Wazuh has no native AV/EDR engine (Phase 2), so it can't alone meet malicious-code-protection controls. Falcon must stay through any migration; the migration plan must say so.
- **Log tamper-evidence is a Gap** (AU-3.3.8) — no native signing/WORM; ISM read-only-on-aged-indices (Phase 5) is a partial non-cryptographic mitigation only; hot window + default indexer creds leave it exposed.
- **Repo-default creds + no MFA + RBAC unconfigured** = AC/IA Gap (live, from Phase 9 credential-rotation item).
- **Vulnerability Detector Untested** — feed exists (~8.3GB, Phase 5) but detection efficacy never validated end-to-end.
- **Two external data flows** — VirusTotal (hashes, currently off) *and* Slack (live, richer alert metadata: hostnames/users/paths/cmdlines). Slack is the bigger CUI-boundary consideration.
- **IR is detection/notification only** — Incident.io (automated tracking) blocked; Active Response untested.

### Phase 5 — Retention & Storage ✅
Documented in `/Users/pobtampal/Desktop/wazuhPOC/wazuh-storage-retention.md`.

**ISM retention policy:** `wazuh-alerts-retention` — hot 0-7d → warm 7-30d → cold 30-90d → delete at 90d. Applied to all wazuh-alerts-* indices. Verified working (indices transitioning correctly by age).

**Storage baseline:** 111.65 MB / 522,689 docs / 9 daily indices (2026-06-20 to 2026-07-13).

**Queue finding (corrected):** The 8.95 GB `wazuh_queue` volume is the Vulnerability Detector CVE feed (`vd/feed` = 8.3 GB RocksDB) — NOT osquery. This is fixed ~8-8.5 GB per manager, agent-count-independent. Normal and expected. Do NOT delete — breaks vulnerability detection and forces multi-GB re-download.

**Storage projections (tuned osquery, security-instrumented macOS agent):**
- ~20 MB/day/agent (primary figure — conservative/high, includes POC session activity)
- At 2,000 agents: ~40 GB/day ingest
- 90-day provisioned: ~3.75 TB (HA + headroom)
- GCP log volume still unmeasured — dominant unknown, will revise projections upward once GCP connected

**osquery tuning:** Allowlist WHERE filter applied — only captures execs in /tmp, /Users/*, /private/var/folders, shells/interpreters. 91% volume reduction (285 → 25.5 docs/min). Trade-off: blind to execs in /usr/libexec, /System, /usr/bin non-interpreters. Documented as accepted decision.

### Phase 6 — Upgrade & Maintenance Lifecycle ✅
Documented in `/Users/pobtampal/Desktop/wazuhPOC/wazuh-upgrade-lifecycle.md`.

**Upgrade tested for real:** 4.14.5 → 4.14.7 (latest stable patch; 4.14.6 skipped successfully), then rolled back to 4.14.5. Both directions verified clean via API. 5.0.0 is beta-only — not an upgrade target during POC. Stack is currently back on **v4.14.5 (known-good)**.

**Backup/restore:** `/Users/pobtampal/Desktop/wazuhPOC/backup-wazuh.sh` written, run, and verified (backup `backups/20260730-093840/`, no sudo needed). Captures manager `/var/ossec/etc`, host `docker-compose.yml` + `config/`, indexer metadata + data volume. Restore verified via reindex-to-scratch (44 = 44 docs). ⚠️ No snapshot repository configured (`path.repo` unset) — production DR needs a real OpenSearch snapshot repository.

**Config-drift finding + fix (important):** Slack (×2) + VT integrations lived ONLY in the running config volume, not in the bind-mounted `wazuh_manager.conf`. The entrypoint's `mount_files` overwrites the running ossec.conf from that host file on every recreate — a naive upgrade would have silently wiped both Slack integrations. Mitigation applied: synced running ossec.conf → host `wazuh_manager.conf` before upgrade (drift now fixed permanently; config-as-code). `local_rules.xml` (rule 100533, netstat downgrade) is volume-only — preserved automatically.

**Indexer / rollback:** wazuh-indexer stays OpenSearch 7.10.2 / Lucene 9.12.3 across the 4.14.x patch line → indexer rollback is data-safe within a patch (915,626 docs read cleanly by 4.14.5 after being served by 4.14.7). ⚠️ Minor/major rollback may require a volume/snapshot restore (a Lucene bump can block downgrade). Single-node cluster health is normally **yellow** (unassigned replicas on system indices) — benign, not data loss.

**Upgrade method decision:** manual image-tag edit in `docker-compose.yml` (NOT `git checkout <tag>`, which resets customized files). Manager-first ordering; agents must be ≤ manager version (validated: mgr 4.14.7 + agent 4.14.5).

**Cadence recommendation:** patches within ~2-4 weeks of release (CrowdStrike authoritative → stability over speed); minors 1-2/quarter with backup + staging soak; majors only at GA + dedicated migration project. Out-of-cycle updates for CVEs in Wazuh / bundled OpenSearch / OpenSearch-Dashboards. At 2,000 agents (Phase 10): manager-first, staged canary (1-5%) → 25% → 100%, keep N-1 package staged for per-group rollback, and verify the macOS TCC/PPPC profile survives agent `.pkg` upgrades.

### Phase 8 — Slack Alerting ✅
Documented in `/Users/pobtampal/Desktop/wazuhPOC/wazuh-slack-integration.md`.

**Two Slack integrations configured on manager:**
| Channel | Threshold | Scope | Purpose |
|---|---|---|---|
| #wazuh-alerts | level ≥ 7 | all groups (rule 533 downgraded to lvl 3) | Production-clean meaningful detections |
| #wazuh-demo | level ≥ 5 | sudo, syscheck groups only | Instant controllable live-demo triggers |

**Key finding:** On macOS, Wazuh tags failed sudo under `sudo`/`syslog` groups — NOT `authentication_failed`. Scoping to `authentication_failed` would silently miss sudo failures.

**Verified end-to-end:**
- Failed sudo (rule 5401, lvl 5) → #wazuh-demo in ~3s ✅
- Level 5 events correctly NOT reaching #wazuh-alerts ✅
- Both webhook URLs rotated after exposure. Old URLs confirmed dead (404).

**FIM demo runbook:** Documented in §5b of wazuh-slack-integration.md. **NEVER RUN LIVE YET** — must do one dry run before any actual demo. Pre-staging: lower syscheck to 120s + recreate /Users/Shared/wazuh_fim_test + restart agent. Trigger: `echo "# demo $(date)" >> /Users/Shared/wazuh_fim_test/watched.txt`. Expected: rule 550 lvl 7 in #wazuh-demo within ~2 min. MUST REVERT frequency to 43200s after.

### Phase 9 — Manageability Assessment ⏳ Partial (single-node)
Documented in `/Users/pobtampal/Desktop/wazuhPOC/wazuh-manageability-assessment.md`. Day-to-day operability vs CrowdStrike. Single-node *mechanisms* assessed; **fleet-scale (2,000-agent) manageability deferred to Phase 10** (can't be validated on 1 agent — honest limit).

**Friction scores:** Console 🟡 Med · Rule mgmt 🟡 Med · Agent health 🟢 Low / config-push 🟡 Med · Alerting 🟡 Med · Upgrade 🟡 Med-High · Docs 🟡 Med.

**Net-new test results:**
- Operator time-to-answer via API: all <0.2s (agent status, alerts-last-hour, failed-sudo-this-week). ⚠️ Default views buried under osquery rule-24010 noise (~41k/hr) — operators must filter `rule.level>=7`.
- Agent health visibility manager-side (no SSH): status, keepalive, `group_config_status`, version, `/agents/summary/status` fleet view, `/agents/outdated`. Strong.
- **Centralized config push WORKS TODAY** (agent groups + `agent.conf`): live push propagated to agent in **~40s**, then reverted. NOT blocked on Fleet Manager — FM adds orchestration/staged-rollout/UI on top of an already-working mechanism.
- `wazuh-logtest` validates rules pre-deploy (no restart); deploy loop = edit `local_rules.xml` → `wazuh-control restart` (~30-60s) → verify.

**Central finding:** Wazuh is **engineer-operated** (file edits + CLI + manager reloads + config-as-code discipline) vs CrowdStrike's **analyst-operated SaaS**. Needs a sysadmin/SIEM-engineer owner, not a pure-GUI analyst — a staffing/manageability cost line. CrowdStrike comparison columns drafted from public docs — need Falcon console verification.

---

## Current Agent Config State

| Setting | Current value | Default | Notes |
|---|---|---|---|
| syscheck frequency | 43200s (12h) | 43200s | Correctly reverted after Phase 2 testing |
| osquery wodle | enabled | disabled | Left on intentionally — security-instrumented baseline |
| osquery config | /var/osquery/osquery.conf | n/a | Allowlist filter, 30s flush interval |
| FIM dirs added | /etc/hosts (monitored) | not added | Added during Phase 2, still in config |
| wazuh_fim_test dir | DELETED from disk | n/a | Config still references it — must recreate for FIM demo |
| VirusTotal integration | REMOVED (key neutralized) | off | Needs fresh API key before re-enabling |

---

## POC Documents on Mac

| File | Path | Status |
|---|---|---|
| EDR evaluation | /Users/pobtampal/Desktop/wazuhPOC/wazuh-edr-evaluation.md | Complete — CrowdStrike column needs Falcon console verification |
| Architecture, scalability & cost | /Users/pobtampal/Desktop/wazuhPOC/wazuh-architecture-scalability-cost.md | Complete (draft for mgmt review) — endpoint-only baseline; competitor/SaaS figures are planning estimates pending procurement |
| Storage retention | /Users/pobtampal/Desktop/wazuhPOC/wazuh-storage-retention.md | Complete |
| Slack integration | /Users/pobtampal/Desktop/wazuhPOC/wazuh-slack-integration.md | Complete |
| Upgrade & maintenance lifecycle | /Users/pobtampal/Desktop/wazuhPOC/wazuh-upgrade-lifecycle.md | Complete |
| Backup script | /Users/pobtampal/Desktop/wazuhPOC/backup-wazuh.sh | Tested (backup `backups/20260730-093840/`) |
| Manageability assessment | /Users/pobtampal/Desktop/wazuhPOC/wazuh-manageability-assessment.md | Partial — single-node assessed; fleet-scale pending Phase 10 |
| Compliance mapping (ISO 27001 / CMMC) | /Users/pobtampal/Desktop/wazuhPOC/wazuh-compliance-mapping.md | Partial — mapping complete; controls Untested/Gap pending follow-up |
| **POC phase status summary (rolling)** | /Users/pobtampal/Desktop/wazuhPOC/wazuh-poc-status-summary.md | Rolling snapshot — **update date + contents whenever a phase status changes**, in step with this context doc |

---

## Open Items / Blockers

### Blocked on access (cannot proceed without these)

| Item | Blocks | Status | Who to chase |
|---|---|---|---|
| GCP change request (Jeff approval) | Phase 7 (GCP log ingestion), shared host VM | Change request drafted and sent to Jeff | Jeff |
| NinjaOne API credentials | Phase 7 (NinjaOne log ingestion) | Pending | WanAware infra team |
| Incident.io webhook | Phase 8 extension (Incident.io alerting) | Pending | Whoever manages WanAware Incident.io |
| Fleet Manager internal access | Phase 10 (Fleet Manager agent orchestration); Phase 9 fleet-scale manageability validation | Pending | WanAware infra team |
| CrowdStrike contracted pricing | Phase 11 final cost comparison / go-no-go (Phase 3 §5 uses public list ranges only) | Not yet requested | WanAware procurement |
| Wazuh Cloud (SaaS) quote | Phase 11 cost comparison if SaaS model is in contention (Phase 3 §5 uses a derived band, not a quote) | Not yet requested | Wazuh vendor sales |

### Unblocked — can do now

| Item | Notes |
|---|---|
| FIM demo dry run | Run pre-stage → trigger → Slack → revert sequence before any live demo |
| Fill in CrowdStrike column in wazuh-edr-evaluation.md | Check Falcon console for host Pobtams-MacBook-Air.local, date range 2026-06-28 and 2026-07-09 |
| Move stack to shared host | **DO droplet deployed 2026-07-30 (143.244.180.78) as a parallel off-laptop host** — see Current Stack. GCP VM is still the preferred production home (pending Jeff's CR); the droplet does **not** replace that plan. On-prem Linux box also remains an option. |
| VirusTotal API key rotation | Old key exposed in chat. Get fresh key from new/rotated VT account, update manager config |
| Test Vulnerability Detector end-to-end | Phase 4 flag (highest-value compliance evidence gap). VD feed exists (~8.3GB) but never validated — confirm it actually flags vulnerable packages on the agent. Maps to RA.L2-3.11.2 / ISO A.8.8 (currently Untested). |
| Define log integrity / tamper-evidence approach | Phase 4 flag. AU.L2-3.3.8 / A.8.15 / A.5.28 Gap — no native signing/WORM. Evaluate immutable snapshots, external SIEM forwarding, or log signing. |
| Configure & test Wazuh RBAC + MFA/SSO | Phase 4 flag (pairs with credential rotation). AC/IA Untested/Gap — least-privilege roles + IdP MFA. |
| Document third-party data flows (VT + Slack) vs CUI boundary | Phase 4 flag. A.5.19–23 / SC.L2-3.13.1 — data-flow diagrams + supplier assessment; decide redaction/scoping for CUI. Slack egress (alert metadata) is the bigger consideration. |
| Load-test the ~1,000-agents/worker split | Phase 3 flag (see arch/cost doc §5). Validate the 2-worker topology assumption under real EPS (~500 & ~1,000/worker) before trusting it for production — capacity is EPS-driven, no fixed ceiling. Needs a load-test/staging environment. |
| Measure mixed-fleet per-agent volume | Phase 3 flag (see arch/cost doc §5). The ~20 MB/day/agent figure is security-instrumented **macOS** only; validate against real **Linux/Windows** agents before final provisioning. Needs non-macOS agents to measure. |
| Indexer snapshot repository (production DR) | Phase 6 flag. `path.repo` unset, no `_snapshot` repo. Register snapshots to durable/object storage (GCS preferred) for real disaster recovery. Requires indexer config change + restart; infra-team involvement at shared-host/2,000-agent scale. POC backup currently relies on volume-tar + reindex-to-scratch. |
| macOS agent-upgrade + TCC-profile persistence dry-run | Phase 6 flag. Before Phase 10 fleet rollout: dry-run a macOS agent `.pkg` upgrade and confirm the osquery/EndpointSecurity Full-Disk-Access (PPPC/TCC) profile survives it — otherwise process telemetry silently degrades post-upgrade. Needs sudo on the agent host. |
| Consolidated operator runbook | Phase 9 flag. Create one day-2 on-call runbook (alert triage, common dashboard queries/click-paths, agent on/offboarding, container recovery, "what's noise vs signal"). The 5 phase docs don't collectively serve an on-call operator without tribal knowledge. |
| Credential rotation | ✅ **RESOLVED on the DO droplet** (2026-07-30) — all three (admin/kibanaserver/wazuh-wui) rotated to strong values; old defaults dead (401). ⚠️ The **local Mac stack still runs repo defaults** but is **localhost-only** (not internet-reachable), so lower risk; rotate it too if it's ever exposed. |
| Signal-vs-noise default dashboard views | Phase 9 flag. Pre-build saved searches/dashboard views filtered to `rule.level>=7` so operators aren't drowned by osquery rule-24010 telemetry in default views. |

---

## Phase Tracking

| Phase | Description | Status |
|---|---|---|
| 1 | Stack deployment | ✅ Complete |
| 2 | EDR testing (expanded with osquery/VT) | ✅ Complete |
| 3 | Scalability, architecture & cost research | ✅ Complete |
| 4 | Compliance mapping ISO 27001/CMMC | ⏳ Partial — mapping complete; key controls Untested/Gap (see doc) |
| 5 | Retention & storage testing | ✅ Complete |
| 6 | Upgrade/maintenance lifecycle | ✅ Complete |
| 7 | SIEM log ingestion (GCP + NinjaOne) | ⏳ Blocked — GCP CR pending Jeff, NinjaOne pending |
| 8 | Slack alerting + Incident.io | ✅ Slack complete — Incident.io blocked |
| 9 | Manageability assessment | ⏳ Partial — single-node assessed ✅; fleet-scale pending Phase 10 |
| 10 | Fleet Manager integration | ⏳ Blocked — internal access pending |
| 11 | Report compilation + go/no-go | ⬜ After all testing complete |

---

## Key Technical Decisions Made

- **osquery approach:** EndpointSecurity (not OpenBSM — dead on macOS 26). Requires FDA grant to osqueryd binary in System Settings → Privacy & Security → Full Disk Access.
- **FIM alerting:** restart-triggered re-baseline does NOT fire alerts — only scheduled scans do. This is the reason forced restart ≠ FIM test.
- **Slack group scoping:** Use `sudo,syscheck` not `authentication_failed` for macOS sudo detection.
- **Queue bloat:** 8.95 GB is VD CVE feed, not osquery. Do not delete.
- **osquery filter:** Allowlist (not denylist) — high-risk paths only. Accepted trade-off: blind to system path execs.
- **VirusTotal:** Hash-reputation only. Misses zero-days. 12h FIM scan latency. Free tier rate limits. Hashes sent to third party.
- **macOS FIM:** realtime="yes" silently dropped — confirmed empirically (API shows realtime: None). 12h default scan interval.
- **Upgrades (Phase 6):** manual image-tag edit, NOT `git checkout <tag>` (resets customized files). Manager-first; agents ≤ manager. Keep manager config in the bind-mounted `wazuh_manager.conf` (config-as-code). Indexer rollback data-safe only within a patch line.

---

## macOS-Specific Notes (Important for Mixed-Fleet Comparisons)

- No realtime FIM (Linux gets sub-second via inotify)
- No process telemetry without osquery + ES + MDM PPPC profile
- No OpenBSM on macOS 26 (auditd daemon removed by Apple)
- Userland agent only (no kernel extension / System Extension)
- SIP does NOT block FIM reading of system paths — only blocks modification
- TCC/Full Disk Access required for osqueryd to use EndpointSecurity
- At fleet scale: MDM-pushed PPPC/TCC profile needed per endpoint (operational cost line)

---

## Demo Trigger Commands (Quick Reference)

**Instant Slack demo (~3s to #wazuh-demo):**
```bash
for n in 1 2 3; do echo "wrong_pw" | sudo -S -k -p "" id 2>&1 | head -1; done
```

**FIM demo (pre-staged, ~2 min to #wazuh-demo):**
See §5b in wazuh-slack-integration.md — requires pre-staging. Do dry run first.

---

*This document was generated from the WanAware Wazuh POC conversation — last updated 2026-07-30 (Phase 6 complete).*
