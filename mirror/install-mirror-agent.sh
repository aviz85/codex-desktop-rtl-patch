#!/usr/bin/env bash
#
# Codex Desktop RTL — MIRROR auto-rebuild LaunchAgent (macOS).
#
# Installs a per-user LaunchAgent that keeps ~/Applications/"Codex RTL.app" in
# sync with /Applications/Codex.app. It watches the source app's Info.plist and
# re-runs build-mirror.sh --if-needed whenever Codex is updated (Sparkle rewrites
# the bundle -> Info.plist changes -> WatchPaths fires). Also runs at load and
# hourly as a safety net.
#
# Because the mirror lives in ~/Applications (user-owned), this agent needs NO
# Full Disk Access / App Management grant — unlike an in-place patcher.
#
# Usage:  ./install-mirror-agent.sh          install + load
#         ./install-mirror-agent.sh --remove  unload + delete
#
set -euo pipefail

LABEL="com.aviz85.codex-rtl-mirror"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/codex-rtl-patch"
LOG="$LOG_DIR/mirror-agent.log"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SH="$SCRIPT_DIR/build-mirror.sh"

if [[ "${1:-}" == "--remove" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "OK  Removed $LABEL"
  exit 0
fi

[[ -f "$BUILD_SH" ]] || { echo "ERROR build-mirror.sh not found at $BUILD_SH" >&2; exit 1; }

SRC_PLIST="${CODEX_APP:-/Applications/Codex.app}/Contents/Info.plist"
[[ -f "$SRC_PLIST" ]] || { echo "ERROR source Info.plist not found: $SRC_PLIST" >&2; exit 1; }

NODE_DIR="$(dirname "$(command -v node)")"
PATH_VALUE="$NODE_DIR:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$LOG_DIR" "$(dirname "$PLIST")"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$BUILD_SH</string>
    <string>--if-needed</string>
    <string>--no-launch</string>
    <string>--notify</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$PATH_VALUE</string></dict>
  <key>WatchPaths</key>
  <array><string>$SRC_PLIST</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>3600</integer>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST"

echo "OK  Mirror agent installed: $LABEL"
echo "    Watches:  $SRC_PLIST"
echo "    Rebuilds: $HOME/Applications/Codex RTL.app  (on Codex update + hourly)"
echo "    Log:      $LOG"
echo "    Remove:   ./install-mirror-agent.sh --remove"
