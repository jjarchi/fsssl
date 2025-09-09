#!/bin/bash
set -euo pipefail

# === Configuration ===
SOURCE_CERT="/home/admfitsecure/ssl/star_fitserver_nl.crt"
SOURCE_KEY="/home/admfitsecure/ssl/star_fitserver_nl.key"
DEST_CERT="/home/uosserver/.local/share/containers/storage/volumes/uosserver_data/_data/unifi-core/config/unifi-core.crt"
DEST_KEY="/home/uosserver/.local/share/containers/storage/volumes/uosserver_data/_data/unifi-core/config/unifi-core.key"
CHECKSUM_FILE="/home/admfitsecure/ssl/cert_bundle.md5"
LOGFILE="/var/log/unifi-os-server-ssl-import.log"
UOSSERVICE="uosserver.service"

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }

log "—— UniFi OS SSL Import ———"
log "Cert: $SOURCE_CERT"
log "Key: $SOURCE_KEY"
log "Force update: $FORCE"

# Validate files
for f in "$SOURCE_CERT" "$SOURCE_KEY"; do
  if [[ ! -f "$f" ]]; then log "❌ Missing file: $f"; exit 1; fi
done
log "✅ Source files found."

# Checksum
CURRENT_SUM=$(cat "$SOURCE_KEY" "$SOURCE_CERT" | md5sum | awk '{print $1}')
LAST_SUM=$(cat "$CHECKSUM_FILE" 2>/dev/null || echo "")
log "Checksum → current: $CURRENT_SUM ; last: ${LAST_SUM:-<none>}"

if [[ "$CURRENT_SUM" == "$LAST_SUM" && "$FORCE" != true ]]; then
  log "No change — exiting."
  exit 0
fi

log "Proceeding with update."

run_cmd() { log "+ $*"; "$@"; }

# Stop service
log "Stopping UniFi OS service..."
sudo systemctl stop "$UOSSERVICE"

# Copy cert & key
run_cmd sudo cp "$SOURCE_KEY" "$DEST_KEY"
run_cmd sudo cp "$SOURCE_CERT" "$DEST_CERT"

# Set permissions
run_cmd sudo chown uosserver:uosserver "$DEST_KEY" "$DEST_CERT"
run_cmd sudo chmod 600 "$DEST_KEY"
run_cmd sudo chmod 644 "$DEST_CERT"

echo "$CURRENT_SUM" | sudo tee "$CHECKSUM_FILE" >/dev/null
log "Checksum updated."

# Show cert info
log "Cert info:"
sudo -u uosserver openssl x509 -in "$DEST_CERT" -noout -subject -issuer -serial -enddate || log "Unable to read cert."

# Restart service
log "Restarting UniFi OS service..."
sudo systemctl start "$UOSSERVICE"

# Restart container as uosserver
log "Restarting UniFi container:"
safe_dir="/var/lib/uosserver"  # accessible by uosserver
sudo -u uosserver bash -c "cd $safe_dir && podman restart uosserver && echo 'Container restarted.'"

log "✅ SSL import and reload complete."
