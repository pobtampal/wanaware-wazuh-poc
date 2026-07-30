#!/bin/bash
# Wazuh single-node POC backup — run before any upgrade. No sudo required (all Docker + host files).
# Backs up: manager /var/ossec/etc (config, rules, keys), host declarative config (compose w/ creds,
# dashboard yml, certs), indexer metadata (ISM, mappings), and the indexer + manager data volumes.
set -euo pipefail
cd /Users/pobtampal/Desktop/wazuhPOC/wazuh-docker/single-node
TS=$(date +%Y%m%d-%H%M%S)
BK="/Users/pobtampal/Desktop/wazuhPOC/backups/$TS"
mkdir -p "$BK/manager" "$BK/indexer" "$BK/host-config"
echo "=== backup target: $BK ==="

echo "== 1. Manager /var/ossec/etc (running config incl. Slack/VT integrations, local_rules 100533, client.keys) =="
docker compose exec -T wazuh.manager tar czf - -C /var/ossec etc > "$BK/manager/var-ossec-etc.tgz"

echo "== 2. Host declarative config (docker-compose.yml WITH creds, dashboard yml, certs) =="
tar czf "$BK/host-config/single-node-config.tgz" docker-compose.yml config/

echo "== 3. Indexer metadata (ISM policies, index list, alerts settings+mappings) =="
curl -sk -u admin:${WAZUH_INDEXER_PW:?Set WAZUH_INDEXER_PW to the indexer admin password} "https://localhost:9200/_plugins/_ism/policies" > "$BK/indexer/ism-policies.json"
curl -sk -u admin:${WAZUH_INDEXER_PW:?Set WAZUH_INDEXER_PW to the indexer admin password} "https://localhost:9200/_cat/indices/wazuh-*?v&h=index,docs.count,store.size&s=index" > "$BK/indexer/index-list.txt"
curl -sk -u admin:${WAZUH_INDEXER_PW:?Set WAZUH_INDEXER_PW to the indexer admin password} "https://localhost:9200/wazuh-alerts-*/_settings" > "$BK/indexer/alerts-settings.json"

echo "== 4. Data volumes (flush indexer first, then tar volumes via throwaway container) =="
curl -sk -u admin:${WAZUH_INDEXER_PW:?Set WAZUH_INDEXER_PW to the indexer admin password} -XPOST "https://localhost:9200/_flush" >/dev/null || true
docker run --rm -v single-node_wazuh-indexer-data:/data:ro -v "$BK/indexer":/backup alpine \
  tar czf /backup/wazuh-indexer-data-volume.tgz -C /data . 2>/dev/null
docker run --rm -v single-node_wazuh_etc:/data:ro -v "$BK/manager":/backup alpine \
  tar czf /backup/wazuh_etc-volume.tgz -C /data . 2>/dev/null

echo "== 5. Manifest + checksums =="
{ echo "Wazuh POC backup $TS (stack v4.14.5)"; echo; du -h "$BK"/*/*; } > "$BK/MANIFEST.txt"
( cd "$BK" && find . -type f ! -name CHECKSUMS.sha256 -exec shasum -a 256 {} \; > CHECKSUMS.sha256 )
echo "=== DONE. Backup at: $BK ==="
cat "$BK/MANIFEST.txt"
echo "BACKUP_DIR=$BK"