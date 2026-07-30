# Wazuh POC — Phase Status Summary

**Prepared for:** WanAware Security Team — Wazuh XDR/SIEM evaluation vs CrowdStrike (RFP dated 2026-06-05)
**Environment:** single-node Docker (v4.14.5, known-good), MacBook Air (macOS 26.5.1); agent 001 v4.14.5
**Date:** 2026-07-30
**Purpose:** one-page snapshot of where every phase stands — finished / partial / blocked — plus the open items and the two threads that will decide the go/no-go. Canonical live state lives in `Wazuh-POC-Context.md`; this is the at-a-glance rollup.
**Maintenance:** this is a **rolling snapshot** — update the date and contents **whenever a phase status changes**, in step with `Wazuh-POC-Context.md`.

---

## Phase tracker (all 11)

| Phase | Description | Status | Deliverable |
|---|---|---|---|
| 1 | Stack deployment | ✅ Complete | (in context doc) |
| 2 | EDR testing (osquery/VT) | ✅ Complete¹ | `wazuh-edr-evaluation.md` |
| 3 | Scalability, architecture & cost | ✅ Complete² | `wazuh-architecture-scalability-cost.md` |
| 4 | Compliance mapping (ISO 27001 / CMMC) | ⏳ Partial³ | `wazuh-compliance-mapping.md` |
| 5 | Retention & storage | ✅ Complete | `wazuh-storage-retention.md` |
| 6 | Upgrade / maintenance lifecycle | ✅ Complete | `wazuh-upgrade-lifecycle.md` + `backup-wazuh.sh` |
| 7 | SIEM log ingestion (GCP + NinjaOne) | ⛔ Blocked | — |
| 8 | Slack alerting + Incident.io | ✅ Slack / ⛔ Incident.io | `wazuh-slack-integration.md` |
| 9 | Manageability assessment | ⏳ Partial⁴ | `wazuh-manageability-assessment.md` |
| 10 | Fleet Manager integration | ⛔ Blocked | — |
| 11 | Report compilation + go/no-go | ⬜ Not started | — (after testing) |

¹ CrowdStrike comparison column is drafted-from-public-docs — needs Falcon-console verification.
² Draft for mgmt review; endpoint-only baseline (excludes GCP/NinjaOne volume); competitor/SaaS figures are planning estimates pending procurement.
³ Mapping complete, but several controls are Untested/Gap — a compliance *claim* is not yet supportable.
⁴ Single-node *mechanisms* assessed; fleet-scale ergonomics unvalidated (depends on Phase 10).

---

## ✅ Genuinely finished

- **Phase 1 — Deployment:** stack up, all three containers healthy on v4.14.5.
- **Phase 2 — EDR testing:** detection behavior characterized (rules 5401 sudo, 550 FIM, 87105 VT/EICAR, 24010 osquery); macOS limitations documented. *Caveat:* CrowdStrike column needs Falcon-console verification.
- **Phase 3 — Architecture/scale/cost:** 7-node production topology for 2,000 agents; GCP infra ~$19k–$31k/yr; all-in TCO ~$40k–$143k/yr vs CrowdStrike ~$285k–$435k/yr (~3–7× gross advantage). *Caveat:* endpoint-only; estimates pending procurement/vendor quotes.
- **Phase 5 — Retention & storage:** ISM policy (hot/warm/cold/delete 90d) live + verified; ~20 MB/day/agent, ~3.75 TB/90-day at 2,000 agents.
- **Phase 6 — Upgrade lifecycle:** 4.14.5→4.14.7 upgrade + rollback tested for real; backup script verified; config-drift trap found & fixed.
- **Phase 8 (Slack) — Alerting:** two channels (#wazuh-alerts level≥7, #wazuh-demo level≥5), webhooks rotated, verified end-to-end.

## ⏳ Honestly partial (work done; conclusions caveated)

- **Phase 4 — Compliance:** full ISO/CMMC mapping done, but a compliance *claim* isn't supportable — key controls are **Untested/Gap**: Vulnerability Detector efficacy untested, no native log tamper-evidence, RBAC/MFA unconfigured. **CrowdStrike is the SI (malware) compensating control** — the central finding.
- **Phase 9 — Manageability:** single-node mechanisms validated (centralized config push works ~40s; strong manager-side agent health visibility; `wazuh-logtest` for rules). **Fleet-scale ergonomics cannot be assessed on one agent** — deferred to Phase 10.

## ⛔ Purely waiting on external people

| Phase / item | Waiting on |
|---|---|
| 7 — GCP log ingestion | **Jeff** (GCP change request) |
| 7 — NinjaOne log ingestion | WanAware infra team (API creds) |
| 8 — Incident.io alerting | WanAware Incident.io owner (webhook) |
| 10 — Fleet Manager | WanAware infra team (internal access) — also gates Phase 9 fleet-scale validation |
| CrowdStrike contracted pricing | WanAware procurement (for Phase 11) |
| Wazuh Cloud quote | Wazuh vendor sales (for Phase 11, if SaaS in contention) |
| 11 — Final report / go-no-go | Waits on the above |

---

## Open items — unblocked, can do now (hygiene / validation before production)

Highest-value first:
1. **Rotate repo-default credentials** — ✅ **done on the DO droplet** (2026-07-30); the **local Mac stack still runs defaults** but is localhost-only (rotate if ever exposed). Was a live compliance AC/IA gap.
2. **Test Vulnerability Detector end-to-end** — closes the biggest compliance evidence gap (RA / ISO A.8.8).
3. **FIM demo dry-run** — run pre-stage → trigger → Slack → revert once before any live demo.
4. **Define log integrity / tamper-evidence approach** — compliance AU gap.
5. **Configure & test RBAC + MFA/SSO** — pairs with credential rotation.
6. **macOS agent-upgrade + TCC-profile persistence dry-run** — before Phase 10 fleet rollout.
7. Consolidated operator runbook · signal-vs-noise default dashboard views · document VT+Slack data flows vs CUI boundary · fill CrowdStrike column in EDR doc · load-test agents/worker split · measure mixed-fleet per-agent volume · move stack to shared host.

---

## The two threads that decide go/no-go

1. **CrowdStrike must stay as the SI (malware-protection) compensating control.** Wazuh has no native AV/EDR engine — this is the hard constraint on any "replacement" framing; at best Wazuh is a *supplement* unless compensating controls are accepted.
2. **The cost advantage is real but conditional.** ~3–7× gross vs Falcon, but dominated by operational labor, and must be read against the macOS EDR capability gaps (Phase 2) and the untested compliance controls (Phase 4) — never presented as the license-line number alone.

---

## Critical path when work resumes

- **Everything unblocked and desk-researchable is done.** The critical path now runs through **Jeff / the GCP change request** — GCP + NinjaOne log volume is the single largest unmeasured variable and is a dependency for Phase 7 *and* for finalizing the Phase 3/5 storage & cost numbers.
- **Current stack:** local Mac stack v4.14.5 (known-good, config untouched, repo-default creds, localhost-only) **+ a parallel DigitalOcean droplet** (`143.244.180.78`, sfo3, s-4vcpu-8gb, hardened, creds rotated, backups on) added 2026-07-30 as an off-laptop host — **parallel to, not a replacement for, the pending GCP shared-host plan**. Both managers post to the same Slack webhooks. macOS-agent→droplet enrollment is untested (Phase 10). Reminder: **revoke the DO API token** pasted in chat.

---

*Snapshot as of 2026-07-30. Live/authoritative state: `Wazuh-POC-Context.md`.*
