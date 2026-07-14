#!/bin/bash
# Validate that a runtime is safe, current, and contains the expected patch.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

APP="$RUNTIME_APP"
STAMP="$CURRENT_STAMP"
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --stamp) STAMP="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { [[ "$QUIET" == 1 ]] || printf '%s\n' "$*"; }
fail=0
source_app="$(find_source_app)" || { say "FAIL none of ${TARGET_APPS[*]} found"; exit 1; }
expected_key="$(source_key)" || { say "FAIL could not calculate source key"; exit 1; }

source_version="$(plist_value "$source_app" CFBundleShortVersionString)"
runtime_version="$(plist_value "$APP" CFBundleShortVersionString)"
runtime_id="$(plist_value "$APP" CFBundleIdentifier)"
asar="$APP/Contents/Resources/app.asar"
plist="$APP/Contents/Info.plist"

[[ -d "$APP" ]] || { say "FAIL runtime is missing"; exit 1; }

if [[ -n "$runtime_version" && "$runtime_version" == "$source_version" ]]; then
  say "PASS runtime version matches $source_version"
else
  say "FAIL runtime version '$runtime_version' does not match '$source_version'"
  fail=1
fi

if [[ "$runtime_id" == "$RUNTIME_BUNDLE_ID" ]]; then
  say "PASS runtime has an isolated bundle identity"
else
  say "FAIL runtime bundle identity is '$runtime_id'"
  fail=1
fi

if [[ -f "$asar" ]] && grep -qa "__codexRtlPatchVersion" "$asar"; then
  say "PASS RTL code is embedded in the loaded bundle"
else
  say "FAIL embedded RTL code is missing"
  fail=1
fi

if [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$expected_key" ]]; then
  say "PASS runtime stamp is current"
else
  say "FAIL runtime stamp is stale"
  fail=1
fi

if codesign --verify "$APP" >/dev/null 2>&1; then
  say "PASS code signature is launch-safe"
else
  say "FAIL code signature is invalid"
  fail=1
fi

expected_hash="$(/usr/libexec/PlistBuddy -c 'Print :ElectronAsarIntegrity:Resources/app.asar:hash' "$plist" 2>/dev/null || true)"
actual_hash="$(python3 - "$asar" 2>/dev/null <<'PY'
import hashlib, struct, sys
with open(sys.argv[1], "rb") as f:
    prefix = f.read(16)
    size = struct.unpack_from("<I", prefix, 12)[0]
    header = f.read(size)
print(hashlib.sha256(header).hexdigest())
PY
)"
if [[ -z "$expected_hash" || "$expected_hash" == "$actual_hash" ]]; then
  say "PASS ASAR integrity is valid"
else
  say "FAIL ASAR integrity mismatch"
  fail=1
fi

exit "$fail"
