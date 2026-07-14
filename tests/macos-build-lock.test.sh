#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t codex-rtl-lock-test)"
trap 'rm -rf "$TMP"' EXIT

SOURCE="$TMP/ChatGPT.app"
mkdir -p "$SOURCE/Contents" "$TMP/state/build.lock"
python3 - "$SOURCE/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as f:
    plistlib.dump({"CFBundleVersion":"1", "CFBundleShortVersionString":"1"}, f)
PY
printf '%s' "$$" > "$TMP/state/build.lock/pid"

output="$(
  CODEX_APP="$SOURCE" \
  CODEX_RTL_SUPPORT_DIR="$TMP/support" \
  CODEX_RTL_RUNTIME_DIR="$TMP/runtime" \
  CODEX_RTL_STATE_DIR="$TMP/state" \
  CODEX_RTL_PATCH_JS="$ROOT/src/codex-rtl-patch.js" \
  CODEX_RTL_PROBE_JS="$ROOT/macos/probe-renderer.mjs" \
  "$ROOT/macos/build-runtime.sh" --if-needed
)"

grep -q "another RTL build is already running" <<<"$output"
echo "macOS build lock test passed."
