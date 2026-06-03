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

[[ -f "$ASAR.orig-backup" ]]  || die "No backup found: $ASAR.orig-backup (nothing to restore)"

# quit Codex if running
if pgrep -f "$APP/Contents/MacOS/Codex" >/dev/null 2>&1; then
  osascript -e 'quit app "Codex"' || true
  for _ in $(seq 1 20); do
    pgrep -f "$APP/Contents/MacOS/Codex" >/dev/null 2>&1 || break; sleep 0.5
  done
  pkill -f "$APP/Contents/MacOS/Codex" 2>/dev/null || true
  sleep 1
fi

cp "$ASAR.orig-backup" "$ASAR"; ok "Restored app.asar"
if [[ -f "$PLIST.orig-backup" ]]; then
  cp "$PLIST.orig-backup" "$PLIST"; ok "Restored Info.plist"
fi

rm -f "$ASAR.orig-backup" "$PLIST.orig-backup"
ok "Removed backups"

if [[ "$LAUNCH" == 1 ]]; then
  open -a "$APP"; ok "Relaunched Codex (original, unpatched)"
fi
