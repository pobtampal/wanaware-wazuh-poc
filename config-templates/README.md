# Config templates

Placeholder versions of the stack config we customized during the POC. The **real** files live in the gitignored `wazuh-docker/single-node/` clone and contain secrets; these `.example` files capture the *structure and decisions* so the setup is reproducible without committing anything sensitive.

| Template | Real file (gitignored) | What to do |
|---|---|---|
| `docker-compose.yml.example` | `wazuh-docker/single-node/docker-compose.yml` | Fill `<INDEXER_ADMIN_PW>`, `<API_PW>`, `<KIBANASERVER_PW>`. Local stack publishes on `0.0.0.0`; the DO droplet variant binds 55000/9200/1514/1515/514 to `127.0.0.1` (only 443 public) and sets indexer heap `-Xms2g -Xmx2g`. |
| `manager-integrations.conf.example` | appended to `config/wazuh_cluster/wazuh_manager.conf` | Slack (#wazuh-alerts + #wazuh-demo) + VirusTotal integration blocks. Fill `<SLACK_WEBHOOK_URL>` and `<VIRUSTOTAL_API_KEY>`. |
| `local_rules.xml.example` | `/var/ossec/etc/rules/local_rules.xml` (in the `wazuh_etc` volume) | Phase 8 rule 100533 — downgrades noisy netstat rule 533 below the level-7 Slack threshold. No secret. |

**Rebuild flow:** `git clone https://github.com/wazuh/wazuh-docker && cd wazuh-docker && git checkout v4.14.5`, then apply these templates (with real secrets) and generate certs per the Phase 1 / upgrade-lifecycle docs.
