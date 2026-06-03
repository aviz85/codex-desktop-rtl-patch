#!/usr/bin/env bash
# Remove the Codex RTL auto-patch LaunchAgent.
set -euo pipefail
LABEL="com.aviz85.codex-rtl-autopatch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "OK  Auto-patch agent removed ($LABEL). The patch itself stays until you run ../uninstall.sh."
