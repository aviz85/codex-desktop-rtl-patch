#!/bin/bash
# Remove only the local RTL manager/runtime/launcher. Official app is untouched.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

plist="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
rm -f "$plist"
for legacy_label in \
  com.aviz85.codex-rtl-mirror \
  com.aviz85.codex-rtl-cdp \
  com.aviz85.codex-rtl-autopatch; do
  launchctl bootout "gui/$(id -u)/$legacy_label" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$legacy_label.plist"
done
pkill -f "^$RUNTIME_DIR/" 2>/dev/null || true
rm -rf "$LAUNCHER_APP" "$RUNTIME_DIR" "$STATE_DIR" "$MANAGER_DIR"
rm -rf "$SUPPORT_DIR/asar-tools"
echo "OK $PRODUCT_NAME removed. The official app was not changed."
