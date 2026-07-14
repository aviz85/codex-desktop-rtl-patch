#!/bin/bash
# Per-user macOS installer. No sudo and no modification of /Applications.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPAIR=0
for arg in "$@"; do
  case "$arg" in
    --repair) REPAIR=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
find_source_app >/dev/null || { echo "ERROR Install ChatGPT/Codex first." >&2; exit 1; }

# Stop an older manager before replacing its files or starting the initial
# build. The updated agent is loaded again only after installation completes.
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
for legacy_label in \
  com.aviz85.codex-rtl-mirror \
  com.aviz85.codex-rtl-cdp \
  com.aviz85.codex-rtl-autopatch; do
  launchctl bootout "gui/$(id -u)/$legacy_label" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$legacy_label.plist"
done

staged_manager="$SUPPORT_DIR/manager.building"
rm -rf "$staged_manager"
mkdir -p "$staged_manager/macos" "$staged_manager/src"

/usr/bin/ditto "$PROJECT_DIR/macos" "$staged_manager/macos"
cp "$PROJECT_DIR/src/codex-rtl-patch.js" "$staged_manager/src/codex-rtl-patch.js"
cp "$PROJECT_DIR/VERSION" "$staged_manager/VERSION"
if [[ -d "$PROJECT_DIR/vendor" ]]; then /usr/bin/ditto "$PROJECT_DIR/vendor" "$staged_manager/vendor"; fi
chmod +x "$staged_manager/macos"/*.sh

rm -rf "$MANAGER_DIR"
mv "$staged_manager" "$MANAGER_DIR"

manager_macos="$MANAGER_DIR/macos"

# Build before loading the LaunchAgent so RunAtLoad cannot race the initial
# explicit build. The launcher is created regardless: it safely opens the
# official app when no compatible runtime exists.
build_ok=0
build_args=(--if-needed --notify)
[[ "$REPAIR" == 1 ]] && build_args=(--force --notify)
if "$manager_macos/build-runtime.sh" "${build_args[@]}"; then build_ok=1; fi
"$manager_macos/create-launcher.sh"
"$manager_macos/install-agent.sh"

if [[ "$build_ok" == 1 ]]; then
  echo
  echo "Installed. Fully quit the official app, then open Codex RTL from ~/Applications."
  exit 0
fi

echo
echo "RTL is not compatible with this app version. The launcher remains safe and opens the official app." >&2
exit 0
