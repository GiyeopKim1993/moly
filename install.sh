#!/bin/bash
set -euo pipefail

MOLY_RAW="https://raw.githubusercontent.com/GiyeopKim1993/moly/main"
DROPBOX_DOWNLOAD_URL="https://www.dropbox.com/desktop"
DROPBOX_RELEASE_URL="https://github.com/GiyeopKim1993/moly/releases/latest/download/DropboxInstaller.dmg"
MOLY_HOME="${HOME}/.local/share/moly"
MOLY_LOGS="${MOLY_HOME}/logs"
mkdir -p "$MOLY_HOME" "$MOLY_LOGS"

MOLY_DROPBOX_APP=""
for MOLY_APP in "/Applications/Dropbox.app" "$HOME/Applications/Dropbox.app"; do
  if [[ -d "$MOLY_APP" ]]; then
    MOLY_DROPBOX_APP="$MOLY_APP"
    break
  fi
done

if [[ -z "$MOLY_DROPBOX_APP" ]]; then
  echo "Dropbox 데스크톱 앱이 없습니다. GitHub에 게시된 최신 공식 Dropbox DMG를 받습니다."
  MOLY_DMG="$(mktemp "${TMPDIR:-/tmp}/DropboxInstaller.XXXXXX.dmg")"
  MOLY_MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/moly-dropbox.XXXXXX")"
  MOLY_MOUNTED=0
  cleanup_dropbox_install() {
    if [[ "$MOLY_MOUNTED" -eq 1 ]]; then
      hdiutil detach "$MOLY_MOUNT" -quiet >/dev/null 2>&1 || true
    fi
    rm -f "$MOLY_DMG"
    rmdir "$MOLY_MOUNT" >/dev/null 2>&1 || true
  }
  trap cleanup_dropbox_install EXIT
  if ! curl --fail --silent --show-error --location "$DROPBOX_RELEASE_URL" -o "$MOLY_DMG"; then
    echo "GitHub에 최신 DMG가 아직 없거나 다운로드할 수 없어 Dropbox 공식 링크에서 받습니다."
    if ! curl --fail --silent --show-error --location "https://www.dropbox.com/download?plat=mac&full=1" -o "$MOLY_DMG"; then
      echo "Dropbox DMG를 다운로드하지 못했습니다. 공식 페이지에서 직접 설치해 주세요: $DROPBOX_DOWNLOAD_URL" >&2
      exit 1
    fi
  fi
  if ! hdiutil attach "$MOLY_DMG" -quiet -nobrowse -readonly -mountpoint "$MOLY_MOUNT"; then
    echo "Dropbox DMG를 열지 못했습니다. 공식 페이지에서 직접 설치해 주세요: $DROPBOX_DOWNLOAD_URL" >&2
    exit 1
  fi
  MOLY_MOUNTED=1
  MOLY_APP_SOURCE="$(find "$MOLY_MOUNT" -maxdepth 3 -type d -name Dropbox.app -print -quit)"
  if [[ -z "$MOLY_APP_SOURCE" ]]; then
    echo "DMG 안에서 Dropbox.app을 찾지 못했습니다. 공식 페이지에서 직접 설치해 주세요: $DROPBOX_DOWNLOAD_URL" >&2
    exit 1
  fi
  mkdir -p "$HOME/Applications"
  ditto "$MOLY_APP_SOURCE" "$HOME/Applications/Dropbox.app"
  cleanup_dropbox_install
  trap - EXIT
  MOLY_DROPBOX_APP="$HOME/Applications/Dropbox.app"
  echo "Dropbox를 ~/Applications에 설치했습니다. 본인 계정으로 로그인하고 동기화 폴더가 준비되면 이 명령을 다시 실행하세요."
  open -a "$MOLY_DROPBOX_APP" >/dev/null 2>&1 || true
  exit 0
fi

if [[ -n "${MOLY_CLOUD_ROOT:-}" ]]; then
  MOLY_CLOUD_ROOT="${MOLY_CLOUD_ROOT/#\~/$HOME}"
elif [[ -d "$HOME/Library/CloudStorage/Dropbox/Mac-Profile-Sync" ]]; then
  MOLY_CLOUD_ROOT="$HOME/Library/CloudStorage/Dropbox/Mac-Profile-Sync"
elif [[ -d "$HOME/Dropbox/Mac-Profile-Sync" ]]; then
  MOLY_CLOUD_ROOT="$HOME/Dropbox/Mac-Profile-Sync"
else
  echo "Dropbox 동기화 폴더에서 Mac-Profile-Sync를 찾지 못했습니다."
  echo "Dropbox 앱을 열어 본인 계정으로 로그인하고 동기화가 끝날 때까지 기다리세요."
  echo "Dropbox 웹에 폴더가 이미 있다면, 이 Mac에서도 해당 폴더가 동기화되도록 설정하세요."
  echo "완료 후 이 명령을 다시 실행하세요."
  if command -v open >/dev/null 2>&1; then
    open -a "$MOLY_DROPBOX_APP" >/dev/null 2>&1 || true
  fi
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
