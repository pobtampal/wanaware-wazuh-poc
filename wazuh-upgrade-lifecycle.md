# Wazuh Upgrade & Maintenance Lifecycle — POC Phase 6

**Prepared for:** WanAware Wazuh POC (Request for POC dated 2026-06-05) — vs CrowdStrike XDR/SIEM evaluation
**Environment:** single-node Docker (wazuh.manager / wazuh.indexer / wazuh.dashboard) v4.14.5, MacBook Air (Apple Silicon, macOS 26.5.1); agent 001 v4.14.5 on same host
**Date:** 2026-07-30
**Scope:** upgrade-path research, tested backup/restore, a **real** upgrade dry-run (4.14.5 → 4.14.7) + rollback on the live stack, and a maintenance-cadence recommendation
**Result headline:** ✅ Upgrade and rollback both completed clean end-to-end. A config-drift risk was found *before* the upgrade and mitigated, without which the Slack/VT integrations would have been silently wiped on recreate.

---

## 1. Upgrade path research

### Version landscape (as of 2026-07-30)
| Track | Versions available | Notes |
|---|---|---|
| Current | **4.14.5** | POC baseline |
| Stable patches ahead | **4.14.6, 4.14.7** | same minor line — chosen dry-run target: **4.14.7** |
| Next major | 5.0.0 **beta4** only | ❌ no stable 5.x yet — not an upgrade target during POC |

### Supported paths
- Official Wazuh docs give a Docker upgrade procedure but **do not document skip-version support**, and there is **no documented rollback procedure** ([Upgrading Wazuh Docker](https://documentation.wazuh.com/current/deployment-options/docker/upgrading-wazuh-docker.html)). Guidance splits at *"from 4.3 and earlier"* vs *"4.4–4.13"* ([Upgrade guide](https://documentation.wazuh.com/current/upgrade-guide/index.html)).
- **Empirically:** we upgraded **4.14.5 → 4.14.7, skipping 4.14.6**, with no issue. Patch-level skips *within a minor* are safe here. Cross-**minor** or **major** jumps should be treated as sequential and release-note-driven until proven otherwise.
- **Agent vs manager:** agents must be **≤ manager version**; never run an agent newer than its manager. Validated: manager 4.14.7 + agent 4.14.5 ran fine → **manager-first upgrade order is correct**.

### Indexer / OpenSearch compatibility
- The wazuh-indexer is OpenSearch-based; before and after the upgrade it reported **v7.10.2 / Lucene 9.12.3 — unchanged across the 4.14.x patch line.**
- **Implication:** within a patch line, indexer on-disk format doesn't change → **downgrade/rollback of the indexer is data-safe** (confirmed: 915,626 alert docs read cleanly by 4.14.5 after being served by 4.14.7). ⚠️ This assumption **does not hold for minor/major upgrades** — a Lucene/OpenSearch bump can make older versions refuse the migrated indices, making indexer rollback impossible without a volume/snapshot restore.

### Breaking changes that matter for *this* Docker single-node deployment
1. **⚠️ Config-drift / `mount_files` (the big one — see §3).** The manager entrypoint copies the bind-mounted `config/wazuh_cluster/wazuh_manager.conf` over `/var/ossec/etc/ossec.conf` on **every** container init. Any config added only to the *running* container (our Slack + VT integrations) is **reverted on recreate** unless first written back to the mounted file.
2. **Cert tool / `CERT_TOOL_VERSION`** — relevant for major upgrades or cert regeneration; **not needed** for a 4.14.x patch (existing 4.14 certs remained valid — indexer came up clean).
3. **Pre-4.8 dashboard default route** (`uiSettings.overrides.defaultRoute`) — N/A (already 4.14).
4. `git checkout <tag>` (the "quick" method) would **reset all customized files** in `single-node/` — including our mitigated `wazuh_manager.conf`. We used the **manual image-tag edit** method instead (see §3).

---

## 2. Backup / restore — tested for real

Script: `/Users/pobtampal/Desktop/wazuhPOC/backup-wazuh.sh` (no sudo; all Docker + host files). Run before every upgrade.

### What is backed up
| Item | Source | Why |
|---|---|---|
| Manager `/var/ossec/etc` | `docker exec … tar` | ossec.conf (Slack×2, VT), `rules/local_rules.xml` (rule 100533), decoders, `client.keys` |
| Host declarative config | `docker-compose.yml` + `config/` | **creds live in compose**; dashboard yml; TLS certs |
| Indexer metadata | `_plugins/_ism/policies`, `_cat/indices`, `_settings` | ISM policy, index inventory, mappings |
| Indexer data volume | `single-node_wazuh-indexer-data` (flush → tar) | the alert/CVE data (108 MB) |
| Manager etc volume | `single-node_wazuh_etc` | belt-and-suspenders copy of config volume |

### Verification results (backup `20260730-093840`)
| Check | Result |
|---|---|
| All tar archives listable (not corrupt) | ✅ |
| Backed-up `ossec.conf` contains integrations | ✅ 2 Slack + 1 VT block |
| Backed-up `local_rules.xml` has rule 100533 | ✅ |
| ISM policy `wazuh-alerts-retention` captured | ✅ |
| **Restore test** — reindex `wazuh-alerts-…07.05` (44 docs) → scratch index | ✅ **44 = 44 docs** |

⚠️ **Infra flag:** the indexer has **no snapshot repository** configured (`path.repo: []`). The volume-tar + reindex-to-scratch is sufficient for this POC, but **production DR needs a real OpenSearch snapshot repository** (register `path.repo` → `_snapshot` → scheduled snapshots, ideally to object storage / GCS). That requires an indexer config change + restart and, at scale, infra-team involvement. **→ New open item.**

---

## 3. Upgrade dry-run — 4.14.5 → 4.14.7 (performed on the live stack)

### Pre-upgrade mitigation (critical)
Our Slack (×2) and VT integrations existed **only** in the running config volume, **not** in the bind-mounted `wazuh_manager.conf` (verified: 0 matches). Because `mount_files` overwrites `/var/ossec/etc/ossec.conf` from that host file on recreate, a naive `down`/`up` would have **wiped both Slack integrations**. Mitigation applied first:

```bash
cp config/wazuh_cluster/wazuh_manager.conf config/wazuh_cluster/wazuh_manager.conf.pre-drift-fix.bak
docker compose exec -T wazuh.manager cat /var/ossec/etc/ossec.conf > config/wazuh_cluster/wazuh_manager.conf
# host file now carries the 2 Slack blocks + VT (key still REMOVED, untouched)
```
This also **permanently fixes the drift** (config is now declarative). `local_rules.xml` is volume-only (not in the mount) → preserved by the volume, needs no sync.

### Procedure used (manual tag-edit method — preserves customized files)
```bash
cp docker-compose.yml docker-compose.yml.bak.4.14.5
sed -i '' 's/:4\.14\.5/:4.14.7/g' docker-compose.yml   # 3 image tags only
docker compose pull
docker compose down          # keeps named volumes
docker compose up -d
```

### Post-upgrade verification (via API — not `docker compose ps`, which has no HEALTHCHECK)
| # | Check | Result |
|---|---|---|
| 1 | Manager version | ✅ **v4.14.7** (`/manager/info`) |
| 2 | All 3 containers on 4.14.7 images | ✅ |
| 3 | Indexer up + version | ✅ 200; OpenSearch 7.10.2 / Lucene 9.12.3 (unchanged) |
| 4 | Dashboard :443 | ✅ HTTP 302 |
| 5 | **Slack integrations survived recreate** | ✅ 2 blocks in running `ossec.conf`; integratord loaded slack ×2 (mitigation worked) |
| 6 | VT block untouched | ✅ `<api_key>REMOVED</api_key>` unchanged |
| 7 | ISM policy applied | ✅ `wazuh-alerts-retention` present |
| 8 | Agent 001 connects | ✅ active, keepalive current (v4.14.5) |
| 9 | Agent config unchanged | ✅ syscheck 43200s, osquery wodle `disabled: no` |
| 10 | local_rules.xml rule 100533 | ✅ intact |
| 11 | Slack **fires** end-to-end (failed sudo → #wazuh-demo) | ✅ 3× failed sudo (rule 5401) → 3 demo-webhook invocations (`B0BJ03SN0CT`) in integrations.log; confirmed landed in #wazuh-demo (Phase 8 rotated webhook still working post-round-trip) |

**Nothing broke.** The only risk (config drift) was pre-empted by the mitigation.

---

## 4. Rollback — 4.14.7 → 4.14.5 (tested)

### Procedure
```bash
cp docker-compose.yml.bak.4.14.5 docker-compose.yml   # restore exact pre-upgrade compose
docker compose down
docker compose up -d                                   # 4.14.5 images still cached locally
```

### Post-rollback verification (stack returned to known-good)
| # | Check | Result |
|---|---|---|
| 1 | Manager version | ✅ back to **v4.14.5** |
| 2 | All 3 containers on 4.14.5 | ✅ |
| 3 | Indexer data intact after downgrade | ✅ **915,626** alert docs readable |
| 4 | Cluster health | ✅ **yellow = benign** — 9 unassigned *replicas* on system indices (normal single-node); 0 unassigned primaries; alert indices are replicas=0 (green) |
| 5 | ISM policy | ✅ present |
| 6 | Slack ×2 + VT (REMOVED) + rule 100533 | ✅ all preserved |
| 7 | Agent 001 | ✅ active, v4.14.5 |

**Key rollback insight:** because the 4.14.x patch line keeps the same OpenSearch/Lucene, an image-tag revert is a complete, data-safe rollback. **For minor/major upgrades, always assume indexer rollback requires the volume/snapshot restore from §2** — the image revert alone may not be enough.

### Rollback decision tree
1. **Bad manager/dashboard only, indexer format unchanged (patch):** revert image tags → `down`/`up`. (What we did.)
2. **Indexer won't start / index format migrated (minor/major):** revert tags **and** restore `wazuh-indexer-data` volume from backup, then `up`.
3. **Config reverted/lost:** restore `manager/var-ossec-etc.tgz`, or re-sync from `wazuh_manager.conf` (now declarative post-mitigation).
4. **Agent upgrade failed:** reinstall the N-1 `.pkg` (kept staged) — agent ≤ manager still holds.

---

## 5. Maintenance cadence recommendation

Because **CrowdStrike remains authoritative throughout the POC**, Wazuh is not the sole line of defense — so cadence can favour stability over speed.

### Scheduled cadence
| Release type | Recommended cadence | Gate |
|---|---|---|
| **Patch** (4.14.x) | Apply within ~2–4 weeks of release | Backup (§2) → staging soak → maintenance window |
| **Minor** (4.x → 4.(x+1)) | ~1–2 per quarter, deliberate | Read release notes for breaking changes; full backup incl. **snapshot restore drill**; test indexer compat before prod |
| **Major** (5.x) | Only once **GA/stable** (currently beta) + a dedicated migration project | Separate change; expect config/format changes; not a drop-in |

### Out-of-cycle (emergency) update triggers
- A **CVE in Wazuh itself** (manager/agent) or in the **bundled OpenSearch/Lucene** (indexer) or **OpenSearch-Dashboards** (dashboard) — the indexer/dashboard inherit upstream CVEs, so watch OpenSearch advisories too.
- An **actively-exploited** vulnerability, or a fix affecting **detection integrity** (a rule/decoder/engine bug that causes missed alerts).
- Subscribe to Wazuh security advisories + OpenSearch security bulletins; treat indexer CVEs as first-class (it's the largest attack surface and holds all data).

### Agent update strategy at 2,000 agents (Phase 10 / Fleet Manager)
- **Manager-first, always.** Upgrade the manager cluster before any agents (agents must stay ≤ manager). Validated here (mgr 4.14.7 + agent 4.14.5).
- **Staged rollout, never all-at-once:** canary **1–5%** → soak (≥24–48h, watch enrollment + alert flow) → **25%** → **100%**, grouped by OS and business criticality. A simultaneous 2,000-agent push is an unacceptable blast radius.
- **Rollback blast radius:** keep the **N-1 package staged** in Fleet Manager for fast per-group rollback; ensure upgrades are reversible per wave. A bad push caught at canary affects ~20–100 agents, not 2,000.
- **macOS-specific (from Phases 2/8):** the agent `.pkg` upgrade needs **root** (sudo or MDM push), and the **PPPC/TCC profile** that grants osqueryd EndpointSecurity/Full Disk Access **must persist across the upgrade** — validate the profile survives a package update in the canary wave, or process telemetry silently degrades.

---

## Key Technical Decisions

- **Manual tag-edit over `git checkout <tag>`** for upgrade — `git checkout` would reset our customized `docker-compose.yml` + `wazuh_manager.conf`. Edit the 3 image tags in place instead.
- **Fix config drift permanently** — runtime-only config (integrations) is fragile against recreate. All manager config should live in the bind-mounted `wazuh_manager.conf` (now done). Treat the volume as data, the mounted file as config-as-code.
- **Manager-first, agent-≤-manager** upgrade ordering — validated across the 4.14.7/4.14.5 split.
- **Indexer rollback is only trivially safe within a patch line** (same Lucene). Minor/major rollback ⇒ plan for a volume/snapshot restore.
- **Backup before every upgrade**; verify with a reindex-to-scratch (data readability) — but stand up a real **snapshot repository** for production DR.

---

## Open items / flags raised by this phase

| Item | Type | Detail |
|---|---|---|
| **Snapshot repository for the indexer** | 🔴 New — needs infra at scale | `path.repo` unset; no `_snapshot` repo. Production DR needs registered snapshots to durable/object storage (GCS). Config change + restart; infra-team item on a shared host. |
| **Config drift now fixed** | 🟢 Resolved this phase | Slack/VT integrations were volume-only; synced into declarative `wazuh_manager.conf`. Keep future config changes in that file, not the running container. |
| **Agent upgrade not exercised live** | 🟡 Follow-up | This phase upgraded the **manager stack** only (correct, manager-first). A real macOS agent `.pkg` upgrade (+ TCC-profile persistence) should be dry-run before Phase 10 fleet rollout. Requires sudo on the agent host. |
| **Live Slack fire re-test post-upgrade** | 🟢 Resolved | 3× failed sudo → 3 #wazuh-demo webhook invocations confirmed (rule 5401, in Slack + integrations.log). |
