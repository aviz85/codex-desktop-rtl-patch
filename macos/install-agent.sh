#!/bin/bash
# Install the update detector. It rebuilds only after a source/patch change.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

plist="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
mkdir -p "$(dirname "$plist")" "$LOG_DIR"
build_script="$MANAGER_DIR/macos/build-runtime.sh"
[[ -x "$build_script" ]] || build_script="$SCRIPT_DIR/build-runtime.sh"

watch_paths=()
for app in "${TARGET_APPS[@]}"; do
  watch_paths+=("$app/Contents/Info.plist")
done

python3 - "$plist" "$AGENT_LABEL" "$build_script" "$LOG_DIR/update-agent.log" "${watch_paths[@]}" <<'PY'
import plistlib, sys
path, label, build_script, log = sys.argv[1:5]
watch_paths = sys.argv[5:]
data = {
    "Label": label,
    "ProgramArguments": ["/bin/bash", build_script, "--if-needed", "--notify"],
    "WatchPaths": watch_paths,
    "RunAtLoad": True,
    "StartInterval": 3600,
    "StandardOutPath": log,
    "StandardErrorPath": log,
    "ProcessType": "Background",
}
with open(path, "wb") as f:
    plistlib.dump(data, f)
PY

launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "OK update agent installed: $AGENT_LABEL"
