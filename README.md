# WanAware — Wazuh XDR/SIEM POC

Documentation, templates, and helper scripts for WanAware's proof-of-concept evaluating **Wazuh v4.14.5** as an XDR/SIEM platform vs **CrowdStrike** (RFP dated 2026-06-05).

> **This repo is documentation + config templates + scripts — NOT the running stack.** The live Wazuh deployment (the upstream `wazuh-docker` clone, TLS keys, real webhooks, credentials, backups) is **deliberately excluded** (see [`.gitignore`](.gitignore)). No secrets are committed.

## Start here
- **[`Wazuh-POC-Context.md`](Wazuh-POC-Context.md)** — the full, authoritative state doc (stack details, phase history, open items, decisions). Paste it into a new assistant session to restore context.
- **[`wazuh-poc-status-summary.md`](wazuh-poc-status-summary.md)** — one-page rolling status of all phases (finished / partial / blocked).

## Phase deliverables
| Phase | Doc |
|---|---|
| 2 — EDR testing | [`wazuh-edr-evaluation.md`](wazuh-edr-evaluation.md) |
| 3 — Architecture, scalability & cost | [`wazuh-architecture-scalability-cost.md`](wazuh-architecture-scalability-cost.md) |
| 4 — Compliance mapping (ISO 27001 / CMMC) | [`wazuh-compliance-mapping.md`](wazuh-compliance-mapping.md) |
| 5 — Retention & storage | [`wazuh-storage-retention.md`](wazuh-storage-retention.md) |
| 6 — Upgrade & maintenance lifecycle | [`wazuh-upgrade-lifecycle.md`](wazuh-upgrade-lifecycle.md) |
| 8 — Slack alerting | [`wazuh-slack-integration.md`](wazuh-slack-integration.md) |
| 9 — Manageability assessment | [`wazuh-manageability-assessment.md`](wazuh-manageability-assessment.md) |

## Config templates
Because the running stack is gitignored, our customizations are captured as **placeholder templates** in [`config-templates/`](config-templates/) — see its README. To rebuild the stack: re-clone `wazuh-docker` at tag **v4.14.5**, apply the templates, and supply your own secrets.

## Scripts
- **`backup-wazuh.sh`** — backs up the single-node stack. Requires `WAZUH_INDEXER_PW` env var (indexer admin password); no credential is hardcoded.
- **`osq-*.sh`** — osquery tuning/validation helpers from Phases 5/6/9.

## Secrets policy
All credentials, TLS private keys, real Slack webhook URLs, the VirusTotal key, agent `client.keys`, and the `backups/` data live **only** in the running configs and a password manager — never in this repo. Credential values in the docs are shown as placeholders (e.g. `<DROPLET_ADMIN_PW>`). If you find a real secret in git history, rotate it immediately.
