# Architect Print Center — Update Host

Public update manifest + release files for the Architect Print Center software
that runs on customer Raspberry Pis.

## How it works

Each Pi runs `architect-update.service` on a daily timer. Every night it fetches
`manifest.json` from this repo, compares versions, and if newer:

1. Downloads the new `cut.html` from `releases/`
2. Verifies SHA-256 against the manifest
3. Backs up current version, atomically swaps in the new one
4. Restarts `architect-web.service`
5. Auto-rolls back if the service fails to come back up

## Publishing a new version

1. Add the new file to `releases/cut-X.Y.Z.html`
2. Update `manifest.json` — bump `version`, update `url` + `sha256`
3. Commit + push
4. Every Pi picks it up on its next 4am check

## Layout

- `manifest.json` — current-latest pointer
- `releases/` — every shipped `cut.html`
- `scripts/` — updater script + systemd units
- `installer/` — one-shot Pi installers
