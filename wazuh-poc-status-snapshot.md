# Wazuh POC — Status Snapshot (pre-meeting)

**Captured:** 2026-09-05 · **Host:** Pobtams-MacBook-Air.local (macOS 26.6.2, arm64) · single-node Docker v4.14.5
**Framing:** the POC's *capability* is demonstrated and healthy. What remains is **gated on approvals/credentials, not on Wazuh's ability.** No secrets in this file (webhook URLs / passwords / tokens redacted).

---

## Live stack — real numbers (read-only pull)

| Metric | Value |
|---|---|
| Containers | manager / indexer / dashboard **Up**; manager v4.14.5 (11/17 daemons — the 6 off are optional/deprecated, normal for single-node) |
| Indexer cluster | `yellow` (single-node → unassigned = replicas, expected), 1 node, 203 primary shards |
| **Agents** | **1 active** (agent 001), synced, 0 disconnected/never-connected |
| **Alerts (last 24h)** | **37,456** total — by level: **L3 = 37,448**, L4 = 1, **L5 = 3**, **L7 = 4** |
| Signal vs noise | 99.98% is level-3 osquery telemetry; actionable (L≥5) is a handful. Operators must filter `rule.level>=7` (Phase 9 finding). |
| Retention (ISM `wazuh-alerts-retention`) | Attached to **49 indices** · states: **7 hot / 16 warm / 26 cold** (aging correctly; nothing past 90d yet → none deleted) |
| Integrations configured (names only) | Slack ×2 (`#wazuh-alerts` ≥L7 all groups; `#wazuh-demo` ≥L5 sudo+syscheck), VirusTotal (**neutralized — no valid key**), osquery wodle (enabled, allowlist filter) |
| Storage footprint (volumes) | indexer-data **366.7 MB** · wazuh_etc 2.9 MB · **wazuh_queue 12.95 GB = Vulnerability Detector CVE feed** (fixed ~per-manager cost, not per-agent; do NOT delete) |

## Telemetry data points — all populated on agent 001 (demo-ready)

| View | Count | 
|---|---|
| FIM (syscheck) | **1,270** entries |
| SCA | CIS macOS 26.x — **41 pass / 25 fail (62%)** |
| Vulnerabilities | **80** findings |
| Inventory | packages **356**, ports **11**, processes **431** |
| MITRE-tagged alerts (24h) | **12** |

---

## Complete vs access-blocked

### ✅ Complete / demonstrated on this machine
- Full pipeline healthy; agent active; every telemetry view populated with real data.
- **Instant event-flow demo** (failed sudo → rule 5401/L5 → #wazuh-demo) — rehearsed, ~2–5 s to Slack.
- **FIM live demo** (file change → rule 550/L7 → #wazuh-alerts + #wazuh-demo) — rehearsed, ~49 s (bounded by the scan interval).
- Retention/ISM, storage baseline, upgrade/rollback, Slack alerting, compliance & manageability mapping — all documented (Phases 2–9).
- DigitalOcean off-laptop deployment stood up (parallel host, hardened, creds rotated).

### ⛔ Blocked on approvals / credentials (NOT on capability)
| Item | Blocked on |
|---|---|
| GCP log ingestion (Phase 7) | GCP change request — **Jeff** (draft config staged in `ingestion-drafts/`) |
| NinjaOne log ingestion | NinjaOne API credentials — infra (draft staged) |
| Incident.io alerting | Incident.io webhook — owner |
| Fleet Manager / 2,000-agent scale (Phase 10) | Internal access — infra |
| CrowdStrike contracted pricing / Wazuh Cloud quote | Procurement / vendor (Phase 11 cost close-out) |

**Takeaway for management:** the platform works and the demo is bulletproof; the remaining POC items are waiting on people/approvals, not on Wazuh.
