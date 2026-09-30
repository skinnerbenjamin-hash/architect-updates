#!/usr/bin/env bash
# Architect Print Center (Tester Pi) — from-scratch installer for /home/scorpionscan/architect/
# Runs the full stack on port 8600 with mDNS alias + daily 4am auto-updater.
# Safe to re-run.
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/skinnerbenjamin-hash/architect-updates/main"
ARCH_DIR="/home/scorpionscan/architect"
USER_NAME="scorpionscan"
PORT="8600"

echo "==> Architect Print Center installer"
echo "    Target dir : $ARCH_DIR"
echo "    User       : $USER_NAME"
echo "    Web port   : $PORT"

if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  echo "ERROR: user '$USER_NAME' not found on this Pi." >&2
  exit 1
fi

echo "==> Installing prerequisites (avahi + jq)"
sudo apt-get update -qq
sudo apt-get install -y -qq avahi-utils jq curl

echo "==> Creating $ARCH_DIR"
sudo mkdir -p "$ARCH_DIR/backups"
sudo chown -R "$USER_NAME:$USER_NAME" "$ARCH_DIR"

echo "==> Fetching manifest"
MAN=$(curl -sSL --fail "$REPO_RAW/manifest.json")
VER=$(echo "$MAN" | jq -r .version)
CUT_URL=$(echo "$MAN" | jq -r .url)
CUT_SHA=$(echo "$MAN" | jq -r .sha256)
echo "    Latest version: $VER"

echo "==> Downloading cut.html v$VER"
sudo -u "$USER_NAME" curl -sSL --fail "$CUT_URL" -o "$ARCH_DIR/cut.html"
GOT=$(sha256sum "$ARCH_DIR/cut.html" | awk '{print $1}')
if [ "$GOT" != "$CUT_SHA" ]; then
  echo "ERROR: cut.html SHA mismatch" >&2
  exit 1
fi
echo "$VER" | sudo -u "$USER_NAME" tee "$ARCH_DIR/VERSION" >/dev/null
echo "    SHA verified."

echo "==> Installing architect-web.service (port $PORT)"
sudo tee /etc/systemd/system/architect-web.service >/dev/null <<UNIT
[Unit]
Description=Architect Print Center web (cut.html on port $PORT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$ARCH_DIR
ExecStart=/usr/bin/python3 -m http.server $PORT
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

echo "==> Installing architect-mdns.service (alias: architect.local)"
sudo tee /etc/systemd/system/architect-mdns.service >/dev/null <<UNIT
[Unit]
Description=Publish architect.local via avahi
After=avahi-daemon.service
Wants=avahi-daemon.service

[Service]
Type=simple
ExecStart=/usr/bin/avahi-publish -a -R architect.local \$(hostname -I | awk '{print \$1}')
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

echo "==> Installing daily auto-updater"
sudo curl -sSL --fail "$REPO_RAW/scripts/architect-update.sh"      -o /usr/local/bin/architect-update.sh
sudo chmod +x /usr/local/bin/architect-update.sh
sudo curl -sSL --fail "$REPO_RAW/scripts/architect-update.service" -o /etc/systemd/system/architect-update.service
sudo curl -sSL --fail "$REPO_RAW/scripts/architect-update.timer"   -o /etc/systemd/system/architect-update.timer

echo "==> Enabling services"
sudo systemctl daemon-reload
sudo systemctl enable --now architect-web.service
sudo systemctl enable --now architect-mdns.service
sudo systemctl enable --now architect-update.timer

echo
echo "==================================================="
echo "  Architect Print Center installed."
echo "  Version : $VER"
echo "  Access  : http://architect.local:$PORT/cut.html"
echo "  Or      : http://$(hostname -I | awk '{print $1}'):$PORT/cut.html"
echo "  Updates : daily at 4am (±15 min)"
echo "  Logs    : sudo journalctl -u architect-update -n 50"
echo "==================================================="
