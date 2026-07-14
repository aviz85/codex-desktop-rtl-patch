#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t codex-rtl-tests)"
trap 'rm -rf "$TMP"' EXIT

SOURCE="$TMP/ChatGPT.app"
mkdir -p "$SOURCE/Contents"
python3 - "$SOURCE/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as f:
    plistlib.dump({
        "CFBundleVersion": "9999",
        "CFBundleShortVersionString": "99.0",
        "CFBundleIdentifier": "com.openai.codex",
    }, f)
PY

export CODEX_APP="$SOURCE"
export CODEX_RTL_SUPPORT_DIR="$TMP/support"
export CODEX_RTL_RUNTIME_DIR="$TMP/support/runtime"
export CODEX_RTL_STATE_DIR="$TMP/support/state"
export CODEX_RTL_LOG_DIR="$TMP/logs"
export CODEX_RTL_RUNTIME_APP="$TMP/support/runtime/Codex RTL Runtime.app"
export CODEX_RTL_PENDING_APP="$TMP/support/runtime/Codex RTL Pending.app"
export CODEX_RTL_LAUNCHER_APP="$TMP/Codex RTL.app"
export CODEX_RTL_PATCH_JS="$ROOT/src/codex-rtl-patch.js"
export CODEX_RTL_TEST_OPEN_LOG="$TMP/open.log"
export CODEX_RTL_TEST_NOTIFY_LOG="$TMP/notify.log"
mkdir -p "$CODEX_RTL_STATE_DIR"

assert_line() {
  local expected="$1" actual
  actual="$(tail -n 1 "$CODEX_RTL_TEST_OPEN_LOG")"
  [[ "$actual" == "$expected" ]] || { echo "expected '$expected', got '$actual'" >&2; exit 1; }
}

# Incompatible/missing RTL must open the official app and return success.
: > "$CODEX_RTL_TEST_OPEN_LOG"
CODEX_RTL_TEST_CHECK=fail "$ROOT/macos/launch.sh"
assert_line "$SOURCE"

# A compatible runtime that starts must not open the official app.
: > "$CODEX_RTL_TEST_OPEN_LOG"
CODEX_RTL_TEST_CHECK=pass CODEX_RTL_TEST_RUNTIME_STARTED=yes "$ROOT/macos/launch.sh"
[[ "$(wc -l < "$CODEX_RTL_TEST_OPEN_LOG" | tr -d ' ')" == 1 ]]
assert_line "$CODEX_RTL_RUNTIME_APP"

# A runtime that passes checks but fails at launch must immediately fail open.
: > "$CODEX_RTL_TEST_OPEN_LOG"
CODEX_RTL_TEST_CHECK=pass CODEX_RTL_TEST_RUNTIME_STARTED=no "$ROOT/macos/launch.sh"
[[ "$(wc -l < "$CODEX_RTL_TEST_OPEN_LOG" | tr -d ' ')" == 2 ]]
assert_line "$SOURCE"

# The recorded launch failure suppresses another runtime attempt for this key.
: > "$CODEX_RTL_TEST_OPEN_LOG"
CODEX_RTL_TEST_CHECK=pass CODEX_RTL_TEST_RUNTIME_STARTED=yes "$ROOT/macos/launch.sh"
[[ "$(wc -l < "$CODEX_RTL_TEST_OPEN_LOG" | tr -d ' ')" == 1 ]]
assert_line "$SOURCE"

echo "macOS fail-open tests passed (4 scenarios)."
