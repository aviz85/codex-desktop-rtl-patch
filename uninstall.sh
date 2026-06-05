#!/usr/bin/env bash
#
# Codex Desktop RTL patch — macOS uninstaller.
# Restores the original app.asar and Info.plist from the backups created by
# install.sh, then relaunches Codex.
#
# Usage:
#   ./uninstall.sh                # restore + relaunch
#   ./uninstall.sh --no-launch
#   CODEX_APP=/path/Codex.app ./uninstall.sh
#
set -euo pipefail

LAUNCH=1
for arg in "$@"; do
  case "$arg" in
    --no-launch) LAUNCH=0 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

die() { printf "ERROR %s\n" "$1" >&2; exit 1; }
ok()  { printf "OK  %s\n" "$1"; }

find_codex() {
  if [[ -n "${CODEX_APP:-}" ]]; then echo "$CODEX_APP"; return; fi
  for p in "/Applications/Codex.app" "$HOME/Applications/Codex.app"; do
    [[ -d "$p" ]] && { echo "$p"; return; }
  done
  local hit; hit="$(mdfind "kMDItemCFBundleIdentifier == 'com.openai.codex'" 2>/dev/null | head -1 || true)"
  [[ -n "$hit" ]] && { echo "$hit"; return; }
  return 1
}

APP="$(find_codex)" || die "Codex.app not found. Set CODEX_APP=/path/to/Codex.app and retry."
ASAR="$APP/Contents/Resources/app.asar"
PLIST="$APP/Contents/Info.plist"
BACKUP_DIR="$HOME/Library/Application Support/codex-rtl-patch"
ASAR_BAK="$BACKUP_DIR/app.asar.orig-backup"
PLIST_BAK="$BACKUP_DIR/Info.plist.orig-backup"

[[ -f "$ASAR_BAK" ]]  || die "No backup found: $ASAR_BAK (nothing to restore)"

# quit Codex if running
if pgrep -f "$APP/Contents/MacOS/Codex" >/dev/null 2>&1; then
  osascript -e 'quit app "Codex"' || true
  for _ in $(seq 1 20); do
    pgrep -f "$APP/Contents/MacOS/Codex" >/dev/null 2>&1 || break; sleep 0.5
  done
  pkill -f "$APP/Contents/MacOS/Codex" 2>/dev/null || true
  sleep 1
fi

cp "$ASAR_BAK" "$ASAR"; ok "Restored app.asar"
if [[ -f "$PLIST_BAK" ]]; then
  cp "$PLIST_BAK" "$PLIST"; ok "Restored Info.plist"
fi

# install.sh re-signed the bundle ad-hoc; the ad-hoc signature seals the *patched*
# files, so simply restoring the originals leaves a broken signature ("invalid
# Info.plist") and the app will not launch. Re-sign the restored (unpatched)
# bundle ad-hoc so it runs. For the original notarized OpenAI signature, reinstall
# Codex.
ENT="$(mktemp -t codex-resign).entitlements"
cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
  <key>com.apple.security.automation.apple-events</key><true/>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
  <key>com.apple.security.network.client</key><true/>
</dict>
</plist>
PLIST
if codesign --force --options runtime --entitlements "$ENT" --sign - "$APP" >/dev/null 2>&1; then
  ok "Re-signed restored bundle (ad-hoc)"
else
  echo "WARN re-sign failed; if Codex won't launch, reinstall it" >&2
fi
rm -f "$ENT"

rm -f "$ASAR_BAK" "$PLIST_BAK"
ok "Removed backups"

if [[ "$LAUNCH" == 1 ]]; then
  open -a "$APP"; ok "Relaunched Codex (original, unpatched)"
fi
