#!/usr/bin/env bash
# Architect Print Center — daily auto-updater
# Byte-compatible reconstruction of the June-11 build for /home/scorpionscan/architect/
set -euo pipefail

ARCH_DIR="/home/scorpionscan/architect"
CUT_FILE="$ARCH_DIR/cut.html"
VERSION_FILE="$ARCH_DIR/VERSION"
BACKUP_DIR="$ARCH_DIR/backups"
LOG="/var/log/architect-update.log"
MANIFEST_URL="https://raw.githubusercontent.com/skinnerbenjamin-hash/architect-updates/main/manifest.json"
SERVICE_NAME="architect-web.service"
MAX_BACKUPS=5

mkdir -p "$BACKUP_DIR"
touch "$LOG"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG" ; }

log "=== Update check start ==="

# 1) Fetch manifest
TMP_MAN="$(mktemp)"
if ! curl -sSL --fail --max-time 30 "$MANIFEST_URL" -o "$TMP_MAN"; then
  log "ERROR: could not fetch manifest from $MANIFEST_URL — skipping"
  rm -f "$TMP_MAN"; exit 0
fi

# 2) Parse (jq if available, else python3)
if command -v jq >/dev/null 2>&1; then
  NEW_VER="$(jq -r '.version' "$TMP_MAN")"
  NEW_URL="$(jq -r '.url'     "$TMP_MAN")"
  NEW_SHA="$(jq -r '.sha256'  "$TMP_MAN")"
else
  NEW_VER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$TMP_MAN")"
  NEW_URL="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["url"])' "$TMP_MAN")"
  NEW_SHA="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"])' "$TMP_MAN")"
fi
rm -f "$TMP_MAN"

CUR_VER="$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0")"
log "Installed=$CUR_VER  Latest=$NEW_VER"

if [ "$NEW_VER" = "$CUR_VER" ]; then
  log "Up to date."
  exit 0
fi

# 3) Download new file
TMP_NEW="$(mktemp)"
if ! curl -sSL --fail --max-time 120 "$NEW_URL" -o "$TMP_NEW"; then
  log "ERROR: download failed from $NEW_URL"
  rm -f "$TMP_NEW"; exit 1
fi

# 4) Verify SHA
GOT_SHA="$(sha256sum "$TMP_NEW" | awk '{print $1}')"
if [ "$GOT_SHA" != "$NEW_SHA" ]; then
  log "ERROR: SHA mismatch. Expected $NEW_SHA, got $GOT_SHA — aborting"
  rm -f "$TMP_NEW"; exit 1
fi
log "SHA verified."

# 5) Backup + atomic swap
if [ -f "$CUT_FILE" ]; then
  BK="$BACKUP_DIR/cut.html.$CUR_VER.$(date +%Y%m%d-%H%M%S)"
  cp "$CUT_FILE" "$BK"
  log "Backed up current file to $BK"
fi
mv "$TMP_NEW" "$CUT_FILE.new"
mv -f "$CUT_FILE.new" "$CUT_FILE"
chown scorpionscan:scorpionscan "$CUT_FILE" 2>/dev/null || true
chmod 644 "$CUT_FILE"
echo "$NEW_VER" > "$VERSION_FILE"

# 6) Prune backups
ls -1t "$BACKUP_DIR"/cut.html.* 2>/dev/null | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm -f

# 7) Restart service (if it exists) with auto-rollback
if systemctl list-unit-files | grep -q "^$SERVICE_NAME"; then
  log "Restarting $SERVICE_NAME"
  if ! systemctl restart "$SERVICE_NAME"; then
    log "ERROR: service restart failed — ROLLING BACK"
    LATEST_BK="$(ls -1t "$BACKUP_DIR"/cut.html.* 2>/dev/null | head -1 || true)"
    if [ -n "$LATEST_BK" ]; then
      cp "$LATEST_BK" "$CUT_FILE"
      echo "$CUR_VER" > "$VERSION_FILE"
      systemctl restart "$SERVICE_NAME" || true
      log "Rolled back to $CUR_VER"
    fi
    exit 1
  fi
  sleep 3
  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    log "ERROR: $SERVICE_NAME not active after restart — ROLLING BACK"
    LATEST_BK="$(ls -1t "$BACKUP_DIR"/cut.html.* 2>/dev/null | head -1 || true)"
    if [ -n "$LATEST_BK" ]; then
      cp "$LATEST_BK" "$CUT_FILE"
      echo "$CUR_VER" > "$VERSION_FILE"
      systemctl restart "$SERVICE_NAME" || true
      log "Rolled back to $CUR_VER"
    fi
    exit 1
  fi
fi

log "SUCCESS: $CUR_VER -> $NEW_VER"
