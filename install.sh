#!/bin/bash
set -euo pipefail

MOLY_RAW="https://raw.githubusercontent.com/GiyeopKim1993/moly/main"
MOLY_HOME="${HOME}/.local/share/moly"
MOLY_LOGS="${MOLY_HOME}/logs"
mkdir -p "$MOLY_HOME" "$MOLY_LOGS"

if [[ -n "${MOLY_CLOUD_ROOT:-}" ]]; then
  MOLY_CLOUD_ROOT="${MOLY_CLOUD_ROOT/#\~/$HOME}"
elif [[ -d "$HOME/Library/CloudStorage/Dropbox/Mac-Profile-Sync" ]]; then
  MOLY_CLOUD_ROOT="$HOME/Library/CloudStorage/Dropbox/Mac-Profile-Sync"
elif [[ -d "$HOME/Dropbox/Mac-Profile-Sync" ]]; then
  MOLY_CLOUD_ROOT="$HOME/Dropbox/Mac-Profile-Sync"
else
  echo "Dropbox's local Mac-Profile-Sync folder was not found." >&2
  echo "Sign in to the Dropbox Mac app, or set MOLY_CLOUD_ROOT and rerun." >&2
  exit 1
fi

curl --fail --silent --show-error --location "$MOLY_RAW/sync.py" -o "$MOLY_HOME/sync.py"
mkdir -p "$MOLY_CLOUD_ROOT/apps" "$MOLY_CLOUD_ROOT/settings" "$MOLY_CLOUD_ROOT/files"
if [[ ! -f "$MOLY_CLOUD_ROOT/manifest.json" ]]; then
  curl --fail --silent --show-error --location "$MOLY_RAW/manifest.example.json" -o "$MOLY_CLOUD_ROOT/manifest.json"
  echo "Created an empty manifest at $MOLY_CLOUD_ROOT/manifest.json. Add your allow-listed items, then rerun this command."
  exit 0
fi

MOLY_PYTHON="$(command -v python3 || true)"
if [[ -z "$MOLY_PYTHON" ]]; then
  echo "python3 is required; install it or ask IT to provide it." >&2
  exit 1
fi

# Restore before enabling backups so an empty local profile cannot overwrite cloud data.
"$MOLY_PYTHON" "$MOLY_HOME/sync.py" restore --cloud-root "$MOLY_CLOUD_ROOT"

MOLY_PLIST="$HOME/Library/LaunchAgents/com.moly.sync.plist"
mkdir -p "$(dirname "$MOLY_PLIST")"
"$MOLY_PYTHON" - "$MOLY_PLIST" "$MOLY_PYTHON" "$MOLY_HOME/sync.py" "$MOLY_CLOUD_ROOT" "$MOLY_LOGS" <<'PY'
import plistlib
import sys

plist_path, python, script, cloud_root, logs = sys.argv[1:]
payload = {
    "Label": "com.moly.sync",
    "ProgramArguments": [python, script, "backup", "--cloud-root", cloud_root],
    "RunAtLoad": True,
    "StartInterval": 300,
    "StandardOutPath": logs + "/agent.out.log",
    "StandardErrorPath": logs + "/agent.err.log",
}
with open(plist_path, "wb") as stream:
    plistlib.dump(payload, stream)
PY

MOLY_DOMAIN="gui/$(id -u)"
launchctl bootout "$MOLY_DOMAIN" "$MOLY_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "$MOLY_DOMAIN" "$MOLY_PLIST"
launchctl kickstart -k "$MOLY_DOMAIN/com.moly.sync"
echo "Moly restored your allow-listed profile and enabled a 5-minute backup while you are logged in."
echo "Logout itself cannot be used as a guaranteed backup trigger; use the periodic backup and confirm Dropbox is synced before leaving."
