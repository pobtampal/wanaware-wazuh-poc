# Wazuh Manageability Assessment — POC Phase 9

**Prepared for:** WanAware Wazuh POC (Request for POC dated 2026-06-05) — vs CrowdStrike XDR/SIEM evaluation
**Environment:** single-node Docker (v4.14.5), MacBook Air (Apple Silicon, macOS 26.5.1); agent 001 v4.14.5 on same host
**Date:** 2026-07-30
**Scope:** day-to-day *operability* from the perspective of whoever runs this at WanAware post-POC — NOT detection efficacy (Phase 2), cost (Phase 3), or compliance (Phase 4). Synthesizes Phase 2/5/6/8 findings and adds net-new hands-on manageability tests.
**Status:** ⏳ **Partial by design** — single-node *mechanisms* assessed and documented; **fleet-scale (2,000-agent) manageability cannot be validated on a one-agent test bed** and is deferred to Phase 10 (Fleet Manager). See §7.

> **CrowdStrike columns are DRAFTED FROM PUBLIC DOCS — VERIFY against the actual Falcon console.** No Falcon-specific detection names, timings, or UI claims are asserted as fact; they describe publicly-documented behavior and are flagged for verification, consistent with the Phase 2 CrowdStrike column.

---

## Summary — friction scoring

Friction = how much effort/skill an operator needs for the task. **Low** = GUI/API, minutes, junior-runnable. **Medium** = file edit + CLI + reload, needs runbook/some skill. **High** = engineering effort or non-obvious traps.

| # | Manageability area | Wazuh (observed) | CrowdStrike (drafted — verify) |
|---|--------------------|------------------|--------------------------------|
| 1 | Console/dashboard usability | 🟡 **Medium** — fast queries, but noise buries signal & advanced filters need DQL | 🟢 Low (analyst-oriented console) |
| 2 | Rule/detection management | 🟡 **Medium** — file-based XML + reload; `wazuh-logtest` helps | 🟢 Low (GUI IOA builder, no restart) |
| 3 | Agent fleet ops (mechanism) | 🟢 **Low** visibility / 🟡 **Medium** config-push — *works today*; fleet-scale unvalidated | 🟢 Low (cloud console, staged rings) |
| 4 | Alerting/notification management | 🟡 **Medium** — 1 file + 1 restart per change; noise tuning needs know-how | 🟢 Low (GUI suppression/tuning) |
| 5 | Upgrade/patch operational burden | 🟡 **Medium–High** — scripted but a non-obvious config-drift trap | 🟢 Low (cloud-managed sensor updates) |
| 6 | Documentation & runbook quality | 🟡 **Medium** — strong per-phase docs, no consolidated operator runbook | n/a (vendor-provided) |

**Bottom line:** Wazuh is an **engineer-operated** platform (file edits, CLI, manager reloads, config-as-code discipline) where CrowdStrike is an **analyst-operated SaaS** (GUI, cloud-managed, no restarts). Nothing about Wazuh's day-to-day is *hard*, but almost everything routine touches a file + a reload and assumes CLI/XML comfort and awareness of specific gotchas. For WanAware this implies an **owner with sysadmin/SIEM-engineering skills**, not a pure GUI analyst — a real staffing/manageability cost line vs Falcon.

---

## 1. Console / dashboard usability — 🟡 Medium

**Time-to-answer (net-new test, via the API layer the dashboard queries):**
| Operator question | Answered in | How |
|---|---|---|
| "Is agent 001 connected?" | **0.05 s** | `GET /agents?...select=status,lastKeepAlive` → `active`, live keepalive |
| "What alerts fired in the last hour?" | **0.14 s** | indexer aggregation by `rule.id` |
| "All failed sudo this week?" | **0.05 s** | indexer query `rule.id:5401` + date histogram → 3 events |

**Query speed is excellent** — sub-200ms for all three. The dashboard (OpenSearch-Dashboards / Wazuh app) runs the same queries behind Discover/Threat-Hunting views.

**Navigation depth (assessed from Wazuh 4.14 dashboard product knowledge — not live-clicked in this session):** home → Threat Hunting/Security-Events module → filter by agent/rule → Events tab → expand a document → raw log (`full_log`) + all fields ≈ **3–5 clicks**. Reasonable.

**⚠️ Signal-vs-noise (net-new finding):** the "last hour" query surfaced **41,385 osquery rule-24010 telemetry events** vs only 3 meaningful sudo alerts. Default/broad dashboard views are **dominated by osquery noise** — an operator must know to filter `rule.level >= 7` or `NOT rule.id:24010` to see actionable signal. This is a real usability tax that ties directly to the Phase 2 noise finding.

**Search/filter for a non-DSL analyst:** the visual filter builder (field/operator/value pills) is usable **without** query-language knowledge. Free-text works. But anything beyond simple equality (ranges, boolean, wildcards) pushes the analyst into **DQL/Lucene** — a learning curve. Verdict: basic triage GUI-doable; power use needs query-language skill.

**CrowdStrike (drafted — verify):** Falcon's console is purpose-built for analyst workflows (guided investigation, process trees, prebuilt dashboards) with less raw-query burden and no equivalent "telemetry noise burying alerts" in default detection views. *Verify the actual analyst click-paths and default noise levels in-console.*

---

## 2. Rule / detection management — 🟡 Medium

**Authoring loop (referencing rule 100533 from Phase 8, plus net-new `wazuh-logtest` test):**
1. **Edit** `/var/ossec/etc/rules/local_rules.xml` (XML; e.g. Phase 8's rule 100533 downgrading noisy netstat rule 533).
2. **Test before deploy** — ✅ net-new: `wazuh-logtest` fed a sample sudo-failure log ran the 3-phase pipeline (pre-decode → decode → rules) and correctly matched **rule 5401** (level 5, MITRE T1548.003) with **no restart/deploy**. Strong risk-reducer.
3. **Deploy** — `wazuh-control restart` (manager), **~30–60 s** (per Phase 6/8). Restarts analysis, not the whole stack.
4. **Verify** — `wazuh-logtest` again, or a live event.
5. **Rollback** — revert the file + restart.

**Friction:** Medium. It's **file-based XML** (no GUI rule-builder for custom rules in the base dashboard — there's a rules *viewer*, not an authoring UI), a **manager reload** per deploy, and **manual MITRE mapping**. `wazuh-logtest` meaningfully de-risks iteration. Requires XML + CLI comfort — not a pure-GUI task.

**CrowdStrike (drafted — verify):** custom IOAs authored in a **console GUI** (rule groups, point-and-click conditions/regex), deployed to sensors **without a restart**, near-instant. Lower friction, more GUI-driven. *Verify the custom-IOA authoring flow and deploy latency in-console.*

---

## 3. Agent fleet operations — 🟢 Low (visibility) / 🟡 Medium (config push) — *mechanism only; fleet-scale unvalidated*

**Health visibility (net-new test) — strong, no SSH required:**
- Per-agent (`GET /agents`): `status`, `version`, `lastKeepAlive`, **`group_config_status: synced`** (is the agent running the config the manager expects), OS/arch.
- **Fleet triage** (`GET /agents/summary/status`): connection `{active / disconnected / never_connected / pending}` **and** configuration `{synced / not_synced}` — the exact at-a-glance view for triaging a fleet.
- `GET /agents/outdated` (version < manager) and `/agents/no_group` — ready-made fleet health queries.
- Per-agent `stats/logcollector` etc. to spot a degraded (stalled) agent.
→ You can tell disconnected / misconfigured / version-drifted / degraded **from the manager alone**. 🟢 Low friction.

**Config push (net-new live test — pushed + reverted):**
- Mechanism **exists and works today** (does *not* wait for Fleet Manager): **agent groups + shared `agent.conf`**. Edited the `default` group's `agent.conf` via `PUT /groups/default/configuration`, and the change **propagated to the agent in ~40 s** (`group_config_status: synced → not_synced → synced`, new `mergedSum`). Then reverted (label removed; group config functionally empty again).
- **Manual today:** assigning agents to groups, editing `agent.conf` XML (the dashboard *does* have a group-config editor, reducing this). A syscheck-frequency change at scale would be done by putting it in the group `agent.conf` (overrides/merges with the agent's local config), not by touching 2,000 hosts.
- **What Fleet Manager (Phase 10) adds:** orchestration/UI, bulk group management, **staged rollout**, and rollback ergonomics on top of this mechanism — not the mechanism itself.

**⚠️ Single-agent caveat (honest):** everything here was tested with **one agent**. It validates that the *mechanisms* work and are fast, but **not** the *ergonomics or performance at 2,000 agents* — bulk group assignment, push behavior under load, sync-latency distribution across thousands, disconnection-storm triage. Those are genuinely **Phase 10 (Fleet Manager) dependencies** — see §7. Do not read "config push works in ~40s on 1 agent" as "fleet rollout is a solved problem."

**CrowdStrike (drafted — verify):** cloud console with host groups, sensor **update/prevention policy rings**, and staged rollout built in; fleet health is a first-class console view. *Verify group/policy management and staged-rollout controls in-console.*

---

## 4. Alerting / notification management — 🟡 Medium

**Adding a channel / changing a threshold (referencing Phase 8):** adding `#wazuh-demo` (2nd Slack integration) took **1 config file + 1 manager restart** — edit the `<integration>` block in the manager config (now the declarative `wazuh_manager.conf`, per the Phase 6 config-as-code fix), then `wazuh-control restart` (~30–60 s). A new webhook also needs the Slack-side webhook created. So each change = **~1 file edit + ~1 restart**; no GUI for integrations, brief analysis downtime on reload.

**Noise-tuning workflow (the Phase 2 ~8,900 alerts/5min finding) — the *practical* playbook, all exercised in prior phases:**
1. **Identify** the noisy rule via an aggregation query (as in §1: rule 24010 = 41k/hr). 
2. **Choose the lever:**
   - **Filter at source** — e.g. the osquery allowlist that cut volume 91% (Phase 5).
   - **Downgrade the rule level** via a `local_rules.xml` override so it drops below alert/integration thresholds (rule 533 → 100533 @ level 3, Phase 8).
   - **Scope the integration** — restrict a Slack channel to specific groups/levels (Phase 8: `#wazuh-demo` = level 5 + `sudo,syscheck` only).
3. **Deploy** (restart) and **verify** (aggregation query / `wazuh-logtest`).

This is a **real, repeatable workflow** — but it requires knowing *which* lever fits (source vs rule vs integration scope), all file-based, each needing a reload.

**CrowdStrike (drafted — verify):** detection tuning and notification routing via **console GUI** (suppression rules, ML sensitivity, no restart). Lower friction. *Verify suppression/tuning UX in-console.*

---

## 5. Upgrade / patch operational burden — 🟡 Medium–High

**Referencing Phase 6 (tested end-to-end, not re-run here). Operational burden for a patch (4.14.5→4.14.7):**
| Step | Effort |
|---|---|
| Backup (`backup-wazuh.sh`, scripted + verified) | ~5 min |
| **Config-drift mitigation** (sync running `ossec.conf` → `wazuh_manager.conf`) | ~2 min — **the trap** |
| Edit image tags + `pull` + `down`/`up` | ~10–15 min |
| Verify via API (11 checks) | ~5 min |
| **Total (patch, happy path)** | **~25–30 min** |
| Rollback if needed (tag revert + `up`; volume restore for minor/major) | ~10 min (patch) |

**Junior vs senior:** the **config-drift risk is a non-obvious trap** — a naive `down`/`up` silently wipes the Slack/VT integrations (the manager entrypoint's `mount_files` reverts the running config from the mounted file). A junior following a *naive* runbook would hit it. **With the Phase 6 runbook** (which documents the mitigation + backup + rollback), a junior *can* run a patch upgrade — but must follow it exactly, and **senior review is warranted for the first run and for any minor/major upgrade** (where indexer rollback may require a volume/snapshot restore). Verdict: **runbook-gated junior for patches; senior for minor/major.** Not a "click update."

**CrowdStrike (drafted — verify):** sensor updates are **cloud-managed** via update policies / staged rings; the platform backend is vendor-operated — near-zero operator upgrade burden. Materially lower. *Verify sensor update-policy controls in-console.*

---

## 6. Documentation & runbook quality — 🟡 Medium

**Do the existing docs let an on-call operator act without asking the POC owner?** The per-phase docs are genuinely strong:
| Doc | Covers |
|---|---|
| wazuh-edr-evaluation.md | detection behavior, macOS limits, CrowdStrike (draft) |
| wazuh-storage-retention.md | ISM policy, capacity, osquery tuning |
| wazuh-slack-integration.md | Slack setup, demo + FIM runbooks |
| wazuh-upgrade-lifecycle.md | backup/restore, upgrade, rollback runbooks |
| Wazuh-POC-Context.md | stack, creds, quick-ref, demo triggers |

**Gaps a real on-call operator would hit (→ open items):**
- **No single consolidated "operator runbook"** — knowledge is spread across 5 docs; an on-call person must know which doc holds what.
- **No alert-triage guide** — "what does rule X mean, is it actionable, what's just noise" (the osquery-24010 noise isn't explained for a triager).
- **No GUI recipe** for the common questions in §1 (Test A shows they're trivial via API, but a dashboard operator needs the click-paths).
- **No agent onboarding/offboarding procedure** (add/remove/re-key an agent).
- **No container recovery runbook** (what to do if a container is down — partially in the upgrade doc).
- **No credential-rotation procedure** — dashboard/API creds are still the **repo defaults** (`admin`/`<LOCAL_DEFAULT_INDEXER_PW>`, `wazuh-wui`/`<LOCAL_DEFAULT_API_PW>`); flagged in context but no rotation steps.

---

## 7. What a single-agent POC can and cannot tell us (honesty section)

**CAN (validated this phase):** the *mechanisms* of day-2 operation — dashboard/API query speed, agent health visibility, that centralized config push works (~40 s) and how, the rule/alert iteration loops and their friction, and the upgrade burden.

**CANNOT (deferred to Phase 10 / Fleet Manager — do not overstate):**
- Fleet health triage at 2,000 agents (does the summary view stay usable; how do you find the 5 broken agents among 2,000).
- Bulk group assignment and **staged config rollout** (canary → waves) — the mechanism exists on 1 agent; the *orchestration* is Fleet Manager's job.
- Config-push behavior **under load** (push storm, sync-latency distribution) — 40 s on one idle agent ≠ 40 s across a fleet.
- Agent upgrade at scale (the macOS `.pkg` + TCC-profile-persistence dry-run is itself still an open Phase 6 item).
- Alert volume/triage ergonomics at fleet scale (the noise problem compounds with agent count).

**Any fleet-scale manageability claim in this document is a single-agent extrapolation and must be re-validated in Phase 10.**

---

## Key Technical Decisions

- **`wazuh-logtest` is the rule-authoring safety net** — always validate a rule/log against it before deploying; it's the one low-friction part of the detection loop.
- **Config push = agent groups + `agent.conf`, and it works *today*** (~40 s propagation). Fleet Manager improves ergonomics/scale, but WanAware is **not** blocked on it for basic centralized config management.
- **Everything routine = file edit + manager reload.** Rules, integrations, tuning all follow edit → `wazuh-control restart` (~30–60 s) → verify. Budget brief analysis downtime and require config-as-code discipline (edit `wazuh_manager.conf`, not the running container — Phase 6).
- **Signal is buried by telemetry noise** — default views need `rule.level >= 7` / `NOT rule.id:24010`. Operators must be taught the filter, or dashboards pre-built with it.
- **Operator skill profile:** this needs a **sysadmin/SIEM engineer**, not a pure-GUI analyst — the central manageability finding vs CrowdStrike's analyst-operated SaaS model.

---

## Open items raised by this phase

| Item | Type | Detail |
|---|---|---|
| **Consolidated operator runbook** | 🟡 New | Create a single day-2 on-call runbook (triage, common queries/click-paths, agent on/offboarding, container recovery, "what's noise") — the 5 phase docs don't collectively serve an on-call operator without tribal knowledge. |
| **Credential rotation procedure** | 🟡 New | Dashboard/API/indexer creds are still repo defaults. Document + perform rotation before shared-host/production (compounds the Phase 8 webhook-rotation lesson). |
| **Fleet-scale manageability validation** | 🔴 Deferred → Phase 10 | Everything in §3/§7 marked single-agent-only must be re-tested with Fleet Manager at representative scale. Blocked on Fleet Manager access. |
| **Signal-vs-noise default views** | 🟡 New | Pre-build dashboard views/saved searches filtered to `rule.level >= 7` so operators aren't drowned by osquery telemetry. |
