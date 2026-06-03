#!/usr/bin/env bash
#
# Codex Desktop RTL — macOS auto-patch agent (survives Codex updates).
#
# Codex auto-updates overwrite app.asar and revert the RTL patch. This installs
# a per-user LaunchAgent that watches the app bundle and silently re-applies the
# patch whenever Codex is updated — the macOS analog of the Windows
# scheduled-task watcher.
#
# Usage:  ./install-autopatch.sh        (run from the repo's autopatch dir)
#         ./uninstall-autopatch.sh      to remove it
#
set -euo pipefail

LABEL="com.aviz85.codex-rtl-autopatch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/codex-rtl-patch"
LOG="$LOG_DIR/autopatch.log"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$(cd "$SCRIPT_DIR/.." && pwd)/install.sh"
[[ -f "$INSTALL_SH" ]] || { echo "ERROR install.sh not found at $INSTALL_SH" >&2; exit 1; }

APP="${CODEX_APP:-/Applications/Codex.app}"
[[ -d "$APP" ]] || APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.openai.codex'" 2>/dev/null | head -1)"
[[ -d "$APP" ]] || { echo "ERROR Codex.app not found" >&2; exit 1; }
ASAR="$APP/Contents/Resources/app.asar"

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
    <string>$INSTALL_SH</string>
    <string>--if-needed</string>
    <string>--no-launch</string>
    <string>--notify</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$PATH_VALUE</string></dict>
  <key>WatchPaths</key>
  <array><string>$ASAR</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "OK  Auto-patch agent installed: $LABEL"
echo "    Watches: $ASAR"
echo "    Re-applies the RTL patch after every Codex update (+ 6h fallback)."
echo "    Log: $LOG"
echo "    Remove with: ./uninstall-autopatch.sh"
cat <<'NOTE'

⚠️  ONE-TIME SETUP — Full Disk Access
macOS 14+ blocks background agents from modifying apps in /Applications.
For the agent to re-apply the patch automatically, grant Full Disk Access to
the agent's interpreter, /bin/bash:

  System Settings > Privacy & Security > Full Disk Access > "+"
  → press Cmd+Shift+G, type:  /bin/bash  → Open → enable the toggle

Until you do this, the agent detects updates and notifies you, but you'll
re-run ../install.sh manually after a Codex update. Opening the pane now…
NOTE
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true
