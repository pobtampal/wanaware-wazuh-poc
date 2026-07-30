# Wazuh Storage & Retention — POC Findings and 2,000-Node Projection

**Prepared for:** WanAware Wazuh POC (Request for POC dated 2026-06-05)
**Environment:** single-node Docker, Wazuh v4.14.5, MacBook Air (Apple Silicon, macOS 26.5.1), localhost
**Agent under test:** `Pobtams-MacBook-Air.local` (agent 001, macOS, **osquery process-telemetry enabled**)
**Date of measurement:** 2026-07-13
**Scope:** index retention (ISM) config, storage baseline, measured per-agent volume, projection to 2,000 agents

> **Primary-figure decision (confirmed with stakeholder):** projections use the **osquery-enabled** volume — a *security-instrumented* macOS endpoint with process telemetry — as the realistic production figure, because Phase 2 established that macOS process/behavioral visibility *requires* osquery + EndpointSecurity. The clean-agent floor (~0.4 MB/day) is retained only as a reference footnote.

---

## 1. ISM retention policy configured (Part A)

No ISM policy previously existed on the indexer (`_plugins/_ism/policies` returned 0). Created policy **`wazuh-alerts-retention`**, attached to all existing `wazuh-alerts-*` indices and auto-applied to new ones via `ism_template`.

**Tiers:** hot `0–7d` → warm `7–30d` (read-only) → cold `30–90d` (read-only, replicas→0) → **delete at 90d**.

**Verification (live):** ISM has already transitioned indices correctly by age —
- `<7d` (07.09–07.13) → **hot**
- `7–30d` (06.20, 06.28, 06.29, 07.05) → **warm** (read-only applied)
- (no index is >30d or >90d yet, so cold/delete transitions are pending but scheduled)

### Exact policy JSON (reproducible for production)

```json
{
  "policy": {
    "description": "Tiered retention for Wazuh alert indices: hot 0-7d, warm 7-30d (read-only), cold 30-90d (read-only), delete at 90d.",
    "default_state": "hot",
    "states": [
      { "name": "hot",  "actions": [], "transitions": [ { "state_name": "warm", "conditions": { "min_index_age": "7d" } } ] },
      { "name": "warm", "actions": [ { "read_only": {} } ], "transitions": [ { "state_name": "cold", "conditions": { "min_index_age": "30d" } } ] },
      { "name": "cold", "actions": [ { "read_only": {} }, { "replica_count": { "number_of_replicas": 0 } } ], "transitions": [ { "state_name": "delete", "conditions": { "min_index_age": "90d" } } ] },
      { "name": "delete", "actions": [ { "delete": {} } ], "transitions": [] }
    ],
    "ism_template": [ { "index_patterns": ["wazuh-alerts-*"], "priority": 100 } ]
  }
}
```

Apply commands:
```bash
# create
curl -k -u admin:*** -X PUT "https://<indexer>:9200/_plugins/_ism/policies/wazuh-alerts-retention" \
  -H 'Content-Type: application/json' -d @ism-policy.json
# attach to existing indices
curl -k -u admin:*** -X POST "https://<indexer>:9200/_plugins/_ism/add/wazuh-alerts-*" \
  -H 'Content-Type: application/json' -d '{"policy_id":"wazuh-alerts-retention"}'
```

**Longer retention (e.g. 1-year compliance):** change the `cold → delete` transition `min_index_age` from `"90d"` to `"365d"`. Storage impact is ~4× the 90-day steady-state (see §5). In production also set `number_of_replicas: 0` only in cold (keep ≥1 replica hot/warm for HA), and consider a true cold tier on cheaper storage (searchable snapshots / GCS) rather than keeping 365 days on hot SSD.

---

## 2. Storage baseline (Part B)

Captured 2026-07-13 ~18:44 UTC:

| Metric | Value |
|---|---|
| `wazuh-alerts-*` total | **111.65 MB**, **522,689 docs**, 9 daily indices |
| Data date range | 2026-06-20 → 2026-07-13 (~23 days) |
| `wazuh-indexer-data` volume | 202.9 MB |
| `wazuh_logs` volume | 190.3 MB |
| **`wazuh_queue` volume** | **8.95 GB** ⚠️ (see finding below) |
| Container images (3× 4.14.5) | ~7 GB combined |

### ✅ Finding (CORRECTED in Phase 6): `wazuh_queue` 8.95 GB = Vulnerability Detector CVE feed, **NOT** osquery
**Phase 5 wrongly attributed this to unfiltered osquery. That was incorrect.** Phase 6 diagnosis (`du -sh /var/ossec/queue/*/`) shows:

| Queue subdir | Size | What it is |
|---|---|---|
| `vd/feed` | **8.3 GB** | **Vulnerability Detector CVE feed database** (RocksDB, 541 `.sst` files) |
| `indexer/db` | 1.4 GB | stateful-inventory RocksDB (`wazuh-states-inventory-*`) — normal working state |
| `diff/` (osquery/FIM) | **12K** | negligible |

**Proof it isn't osquery:** the queue was 8.95 GB in Phase 5 and is **8.957 GB now** — flat across days of osquery flooding. An osquery-driven queue would have grown. VD is enabled (`<vulnerability-detection><enabled>yes</enabled>`, 60 m feed refresh).

**Correct characterization:**
- It is the **global CVE feed** — a **fixed ~8–8.5 GB cost *per manager*, independent of agent count** (it does *not* ×2,000). At fleet scale it's negligible against log storage.
- It is a **live RocksDB, not stale/rotated files** — nothing safe to "clear"; deleting it breaks vulnerability detection and forces a multi-GB re-download.
- The manager is **not falling behind** (no "queue full"/"dropping" log entries).

**Decision (confirmed):** keep VD enabled; treat this as expected overhead. **Manager-sizing finding → provision ~15–20 GB for the manager working set (VD feed + inventory RocksDB) per manager node, independent of agent count.** Minor caveat: 8.3 GB is larger than Wazuh's typically-documented VD footprint (~1–3 GB) — possibly an uncompacted RocksDB or the full multi-OS feed; stable, non-scaling, worth monitoring only.

---

## 3. Measurement methodology (honest: real vs synthetic)

**All figures are from *natural* live telemetry — no synthetic load was generated** (Part C option b). Two complementary real measurements:

1. **Complete-day index sizes** (most representative of a real endpoint's daily total, including idle/sleep periods):

   | Day | Docs | Size | Character |
   |---|---|---|---|
   | 2026-07-11 | 68,117 | 15.1 MB | quiet day |
   | 2026-07-12 | 67,669 | 14.5 MB | quiet day |
   | 2026-07-13 | 122,841 | 25.9 MB | active day (interactive testing captured) |
   | 2026-07-10 | 203,745 | 41.4 MB | **excluded** — inflated by Phase 2 ES validation bursts |

2. **30-minute live steady-state window** (2026-07-13 13:41–14:11 local, active use): **8,558 docs / 30 min = 285 docs/min (~17,100/hr)**, ~64 KB/min ≈ **3.85 MB/hr**. Consistent ~**225 bytes/doc**.

**Honesty caveats (material):**
- **Single macOS *laptop*, not a server.** It sleeps and idles, so daily totals swing widely (15 MB quiet ↔ 26 MB active). A 24/7 server has no sleep windows.
- The 30-min window was during **active interactive use** — my own shell/docker/curl commands were themselves captured by osquery `process_events`. Extrapolating that window 24/7 (~88 MB/day) **over-states** a real endpoint; the complete-day totals are more trustworthy.
- **Unfiltered osquery.** The `process_events` query captures *every* exec system-wide. Production query tuning (filter to security-relevant binaries/paths) would cut this substantially.
- 99.92% of all agent-001 volume is osquery rule 24010; everything else (FIM, sudo, rootcheck) is ~100 alerts/day.

**Representative figure chosen: ~20 MB/day/agent** (midpoint of the 15–27 MB complete-day range for a security-instrumented macOS endpoint). Used as the primary projection rate below; the range is carried through so the sensitivity is visible.

---

## 4. Storage projection — 2,000-node target (Part D)

**Primary per-agent rate: 20 MB/day** (osquery-enabled, raw primary-shard, compressed as stored). Range shown where it matters.

### Raw generated volume (primary shard, no replica)

| Timeframe | 1 agent | 100 agents | 2,000 agents |
|-----------|---------|------------|--------------|
| 1 day     | 20 MB   | 2.0 GB     | **40 GB**    |
| 1 week    | 140 MB  | 14 GB      | **280 GB**   |
| 1 month (30d) | 600 MB | 60 GB   | **1.2 TB**   |
| 3 months (90d) | 1.8 GB | 180 GB | **3.6 TB**   |
| 1 year (365d) | 7.3 GB | 730 GB  | **14.6 TB**  |

> Range at 2,000 agents / 90 days: **2.7 TB** (@15 MB/day) → **3.6 TB** (@20) → **4.9 TB** (@27) raw.

### What is actually *retained on disk* (with the 90-day ISM policy)
Storage reaches **steady state at the retention window**, not the 1-year cumulative — data older than 90 days is deleted. So for 2,000 agents the disk footprint plateaus at the **90-day figure (~3.6 TB raw)**, *not* 14.6 TB.

### Provisioned storage (production, with HA replica + headroom)
Add **×2 for 1 replica** (HA) and **~30% headroom** (merge/overhead/free space) → **raw × ~2.6**:

| Retention | Raw (2,000 agents) | Provisioned (×2.6) |
|---|---|---|
| 30 days | 1.2 TB | ~3.1 TB |
| **90 days** | **3.6 TB** | **~9.4 TB** |
| 365 days | 14.6 TB | ~38 TB |

### 🔽 Post-tuning update (Phase 6) — osquery allowlist applied
After applying the allowlist filter + 30 s interval (see §7), the measured event rate dropped **~91%** (apples-to-apples active window): **285 → 25.5 docs/min**. All system-path noise (`/usr/libexec`, `/System`) is gone; residual is shells/interpreters/user-paths (and ~95% of that residual is `/bin/bash` from *this POC session itself*, so a genuinely quiet endpoint is lower).

**Tuned per-agent rate: ~8 MB/day conservative** (post-tuning active rate extrapolated 24/7; likely quiet floor **~2 MB/day**), vs **20 MB/day untuned**.

| At 2,000 agents / 90-day retention | Untuned (20 MB/day) | **Tuned (~8 MB/day, conservative)** | Tuned floor (~2 MB/day) |
|---|---|---|---|
| Daily ingest | 40 GB/day | **16 GB/day** | 4 GB/day |
| 90-day raw | 3.6 TB | **1.44 TB** | 360 GB |
| 90-day provisioned (×2.6) | ~9.4 TB | **~3.75 TB** | ~940 GB |

**Manageability finding:** tuning cut storage **~60% (conservative) to ~90% (quiet floor)**. **Untuned osquery is not production-ready** — it drives ~2.5× the storage and (per §7) the query must be filtered before scale. A full tuned *day* was not yet measured; refine once a clean 24 h tuned baseline is available.

### Assumptions (stated explicitly)
- **Agent OS mix:** macOS-only, **osquery process-telemetry enabled** on every agent (per stakeholder decision). A Linux/Windows fleet would differ; Linux with `auditd` and Windows with Sysmon have their own (often higher) event rates.
- **Event types included:** osquery `process_events` (dominant) + FIM + sudo/auth + rootcheck. **Excludes** any cloud/GCP log sources.
- **Rate basis:** real measurement on one laptop over ~3 complete days + a 30-min live window; extrapolated linearly to N agents (assumes independent, comparable endpoints — real fleets have variance).
- **Bytes/doc:** ~225 B measured (compressed, primary shard).
- **Retention:** the 90-day ISM policy from §1.
- **⚠️ GCP log ingestion is NOT configured.** When it is, per-asset volume is expected to be **significantly higher** than macOS agent telemetry alone (cloud audit/flow/data-access logs are voluminous). **These projections cover endpoint-agent telemetry only and must be revised once GCP ingestion is live.**

### Cross-reference: is 90-day retention practical self-hosted vs Wazuh Cloud? (Part D4)
- **Ingest:** ~**40 GB/day** at 2,000 agents (unfiltered). That is a real indexing load requiring a **multi-node indexer cluster**, not a single node — but it is well within self-hosted GCP capability.
- **Disk:** ~**9.4 TB provisioned** for 90-day HA retention. Very feasible self-hosted on GCP (e.g. a small indexer cluster with balanced persistent disks). **Not** an extreme figure.
- **Conclusion:** 90-day retention at 2,000 nodes is **practical self-hosted on GCP.** The bigger levers are (a) **osquery query tuning** — could cut volume/cost by an order of magnitude, and (b) the **unmeasured GCP log volume**, which may dominate everything here. Wazuh Cloud pricing at this scale/volume should be compared once GCP volume is known, since managed pricing typically tracks ingest/retention GB.

---

## 5. Retention recommendations: POC vs production

| | POC (now) | Production (2,000 nodes) |
|---|---|---|
| Retention window | 90 days (as configured) | 90 days hot/warm on indexer + **cold/archive tier** (searchable snapshots → GCS) for any compliance window beyond 90d |
| Replicas | 0 (single node) | **≥1** on hot/warm (HA); 0 acceptable on cold |
| osquery query | **tuned (Phase 6): allowlist + 30 s** | **Tuned/filtered mandatory** — unfiltered `process_events` drove ~40 GB/day ingest; allowlist cut it ~91% |
| Indexer topology | single node | **multi-node cluster** (see ingest load) |
| Manager working set | ~9 GB (VD feed + inventory) | **provision ~15–20 GB per manager** (VD CVE feed ~8–8.5 GB + inventory RocksDB) — agent-count-independent |
| 1-year compliance | change `delete` to `365d` (~38 TB provisioned) | keep 90d hot + **archive older data to cheaper GCS cold storage**, not hot SSD |

---

## 6. Key flags for the next phase

1. **⚠️ These projections cover macOS agent telemetry only. They WILL need revision once GCP log ingestion is configured — GCP log volume per asset is expected to be significantly higher than macOS agent telemetry alone.** Re-baseline after the GCP change request is approved and ingestion is live.
2. **osquery query-tuning is done (Phase 6) and is mandatory before scale.** The allowlist filter cut the event rate ~91% (285 → 25.5 docs/min) and projected storage ~60–90%. Unfiltered `process_events` was ~40 GB/day at 2,000 agents; tuned is ~16 GB/day (conservative).
3. **`wazuh_queue` 8.95 GB is the Vulnerability Detector CVE feed, NOT osquery** (Phase 5 mis-attribution corrected in §2). It is a fixed ~8–8.5 GB *per-manager* cost, agent-count-independent, and must **not** be cleared. Size manager disk for ~15–20 GB working set.
4. **macOS operational overhead (from Phase 2)** compounds here: every macOS agent needs osquery + EndpointSecurity + an MDM-pushed PPPC/TCC profile. Even *tuned*, the process-telemetry volume (~8 MB/day) is ~20× the clean-agent floor (~0.4 MB/day) — a combined cost/manageability line a Linux-only fleet would not carry to the same degree.

---

## 7. osquery tuning (Phase 6)

**Diagnosis (Part A):** 100% of osquery volume came from a **single** scheduled query (`process_events` → `es_process_events`), **171,245 events/24h, all `action=added`**. No inventory queries existed, so **nothing duplicated syscollector**. Key technical point: `es_process_events` is an **evented table** — lengthening the interval only changes flush cadence, **not event count**. The real volume lever is a **`WHERE` filter**.

**Change applied:** allowlist filter (high-risk dirs + shells/interpreters) + interval 5 s → 30 s. Config at `/var/osquery/osquery.conf` (backup: `/var/osquery/osquery.conf.bak.*`):

```sql
SELECT pid,path,cmdline,parent,uid,time FROM es_process_events
WHERE path LIKE '/tmp/%' OR path LIKE '/private/tmp/%' OR path LIKE '/Users/%'
   OR path LIKE '/private/var/folders/%' OR path LIKE '/var/folders/%'
   OR path LIKE '%/bash' OR path LIKE '%/zsh' OR path LIKE '%/sh' OR path LIKE '%/dash'
   OR path LIKE '%/ksh' OR path LIKE '%/tcsh' OR path LIKE '%/csh'
   OR path LIKE '%/python' OR path LIKE '%/python3' OR path LIKE '%/perl'
   OR path LIKE '%/ruby' OR path LIKE '%/node' OR path LIKE '%/php' OR path LIKE '%/env'
   OR path = '/usr/bin/osascript';
```

**Before / after (same active-window method):**

| | Rate | Extrapolated/day | Notes |
|---|---|---|---|
| Untuned | 285 docs/min | ~20 MB/day (complete-day basis) | every exec, system-wide |
| **Tuned** | **25.5 docs/min** | **~8 MB/day conservative** | shells/interpreters + user/temp paths only |
| Reduction | **~91%** | ~60–90% storage | — |

**⚠️ Trade-off (accepted, per stakeholder decision):** the allowlist means Wazuh is now **blind to executions in system paths** — `/usr/libexec`, `/System`, `/usr/sbin`, `/usr/bin` (non-interpreter binaries), `/Applications/*/Contents/MacOS`, etc. Malware that runs *only* from those locations (e.g. a compromised signed system binary, or a payload dropped into a writable `/Library` subpath) would **not** generate a `process_events` alert. This was chosen deliberately to prioritize volume reduction; the residual coverage (temp/user dirs + interpreters) catches the most common initial-execution and living-off-the-land patterns. **Revisit the allowlist against the specific threat model before production**, and pair it with detection rules (Phase 2 finding: rule 24010 is telemetry, not classified detections).

## 8. Ready-for-Phase-7 (GCP ingestion) checklist

- ✅ **ISM retention policy active** — `wazuh-alerts-retention` (hot 7d / warm 30d / cold 90d / delete 90d), verified transitioning by age.
- ✅ **osquery tuned** to production-appropriate scope — allowlist filter, 30 s interval, ~91% volume reduction.
- ✅ **Queue "bloat" resolved** — diagnosed as expected VD CVE feed (not a fault); manager-sizing guidance recorded (~15–20 GB/manager). Stable at 8.957 GB, not growing.
- ✅ **Baseline alert rate stable and measured** — tuned rate 25.5 docs/min (active); queue flat; osqueryd running under the wodle.
- ⏳ **GCP change request pending approval** — endpoint-telemetry baseline is set; GCP log volume (expected to dominate) must be measured and these projections re-run once ingestion is live.

**Stability statement:** with retention capped (ISM), osquery volume cut ~91%, and the queue confirmed stable/VD-driven (not a leak), the stack can receive additional log sources without risk of the endpoint-telemetry path overflowing the queue. The **unknown** remaining risk is GCP log volume magnitude — size the indexer cluster and manager ingest for it before enabling, rather than assuming the current single-node footprint scales.

---

### Footnote — clean-agent floor (reference only)
A macOS agent **without** osquery process telemetry generates only **~90–100 alerts/day ≈ 0.3–0.6 MB/day** (measured on pre-2026-07-09 days: 44/45/84/186 docs). At 2,000 agents / 90 days that is only **~72 GB raw** — roughly **50× less** than the osquery-enabled figure. This is the floor if process telemetry were disabled fleet-wide; it is **not** the recommended production posture because it sacrifices the macOS process/behavioral visibility Phase 2 identified as required.
