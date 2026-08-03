#!/usr/bin/env bash
# Migrate Ben's existing Pi off dead paste.rs updater onto the GitHub-hosted one.
# Safe to re-run — only reinstalls the updater bits.
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/skinnerbenjamin-hash/architect-updates/main"

echo "==> Installing prereq (jq)"
sudo apt-get install -y -qq jq curl

echo "==> Replacing updater script + units"
sudo curl -sSL --fail "$REPO_RAW/scripts/architect-update.sh"      -o /usr/local/bin/architect-update.sh
sudo chmod +x /usr/local/bin/architect-update.sh
sudo curl -sSL --fail "$REPO_RAW/scripts/architect-update.service" -o /etc/systemd/system/architect-update.service
sudo curl -sSL --fail "$REPO_RAW/scripts/architect-update.timer"   -o /etc/systemd/system/architect-update.timer

sudo systemctl daemon-reload
sudo systemctl enable --now architect-update.timer

echo "==> Running updater once now to pick up v1.7.3"
sudo /usr/local/bin/architect-update.sh || true

echo
echo "Done. Your Pi is now on the durable GitHub updater host."
echo "Next auto-check: $(systemctl list-timers architect-update.timer --no-pager | awk 'NR==2 {print $1, $2}')"
