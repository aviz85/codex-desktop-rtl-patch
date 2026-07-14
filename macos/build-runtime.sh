#!/bin/bash
# Build and validate an isolated RTL runtime. Never modifies the official app.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

IF_NEEDED=0
FORCE=0
NOTIFY=0
for arg in "$@"; do
  case "$arg" in
    --if-needed) IF_NEEDED=1 ;;
    --force) FORCE=1 ;;
    --notify) NOTIFY=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

source_app="$(find_source_app)" || { echo "ERROR none of ${TARGET_APPS[*]} found" >&2; exit 1; }
[[ -f "$PATCH_JS" ]] || { echo "ERROR patch source not found: $PATCH_JS" >&2; exit 1; }
[[ -f "$PROBE_JS" ]] || { echo "ERROR renderer probe not found: $PROBE_JS" >&2; exit 1; }
ensure_node || { echo "ERROR Node.js 22+ or the bundled runtime is required" >&2; exit 1; }

key="$(source_key)"
mkdir -p "$SUPPORT_DIR" "$RUNTIME_DIR" "$STATE_DIR" "$LOG_DIR"

# launchd, an interactive repair, and an installer may be triggered together.
# Only one process may touch staging/pending state at a time.
lock_dir="$STATE_DIR/build.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  lock_pid="$(cat "$lock_dir/pid" 2>/dev/null || echo 0)"
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
    log "OK another RTL build is already running."
    exit 0
  fi
  rm -rf "$lock_dir"
  mkdir "$lock_dir"
fi
printf '%s' "$$" > "$lock_dir/pid"
trap 'rm -rf "$lock_dir"' EXIT

if [[ "$IF_NEEDED" == 1 && "$FORCE" == 0 ]]; then
  if "$SCRIPT_DIR/check-runtime.sh" --quiet; then
    log "OK RTL runtime is already current."
    exit 0
  fi
  if "$SCRIPT_DIR/check-runtime.sh" --app "$PENDING_APP" --stamp "$PENDING_STAMP" --quiet; then
    log "OK a validated RTL update is pending the next launch."
    exit 0
  fi
  if [[ -f "$FAILED_STAMP" && "$(cat "$FAILED_STAMP")" == "$key" ]]; then
    log "OK RTL is disabled for this incompatible app/patch version; official app remains available."
    exit 0
  fi
fi

vendored_tools="$PROJECT_DIR/vendor/asar"
tools_dir="$SUPPORT_DIR/asar-tools"
if [[ -x "$vendored_tools/node_modules/.bin/asar" ]]; then
  tools_dir="$vendored_tools"
fi
asar_bin="$tools_dir/node_modules/.bin/asar"
if [[ ! -x "$asar_bin" ]]; then
  log "Installing the cached ASAR tool..."
  command -v npm >/dev/null 2>&1 || { echo "ERROR npm is required by a source checkout; GitHub release installers include this dependency." >&2; exit 1; }
  mkdir -p "$tools_dir"
  (cd "$tools_dir" && npm init -y >/dev/null 2>&1 && npm install @electron/asar@4.2.0 >/dev/null 2>&1)
fi
[[ -x "$asar_bin" ]] || { echo "ERROR could not prepare @electron/asar" >&2; exit 1; }

build_app="$RUNTIME_DIR/$PRODUCT_NAME Runtime.building.app"
build_stamp="$STATE_DIR/building.key"
work=""
smoke_profile=""
success=0
failure_reason="runtime build failed"

cleanup() {
  rc=$?
  pkill -f "^$build_app/" 2>/dev/null || true
  if [[ -n "$smoke_profile" ]]; then rm -rf "$smoke_profile" || true; fi
  if [[ -n "$work" && -d "$work" ]]; then rm -rf "$work" || true; fi
  if [[ "$success" != 1 ]]; then
    if [[ "${CODEX_RTL_KEEP_FAILED_BUILD:-0}" != 1 ]]; then rm -rf "$build_app" || true; fi
    rm -f "$build_stamp" || true
    printf '%s' "$key" > "$FAILED_STAMP"
    printf '%s\n' "$failure_reason" > "$FAILED_REASON"
    warn "$failure_reason; RTL disabled for this version."
    [[ "$NOTIFY" == 1 ]] && notify_user "$PRODUCT_NAME" "RTL disabled for this version; opening the official app remains safe."
  fi
  rm -rf "$lock_dir" || true
  return "$rc"
}
trap cleanup EXIT

failure_reason="could not copy the official app"
rm -rf "$build_app"
/usr/bin/ditto --rsrc --extattr "$source_app" "$build_app"

build_res="$build_app/Contents/Resources"
build_asar="$build_res/app.asar"
build_plist="$build_app/Contents/Info.plist"
[[ -f "$build_asar" && -f "$build_plist" ]] || { failure_reason="copied app is missing app.asar or Info.plist"; exit 1; }

work="$(mktemp -d -t codex-rtl-build)"
extract="$work/extracted"
failure_reason="could not extract app.asar"
"$asar_bin" extract "$build_asar" "$extract"

index="$extract/webview/index.html"
[[ -f "$index" ]] || { failure_reason="unsupported app layout: webview/index.html is missing"; exit 1; }
mkdir -p "$extract/webview/assets"
cp "$PATCH_JS" "$extract/webview/assets/codex-rtl-patch.js"

failure_reason="unsupported app layout: main webview bundle was not found"
python3 - "$index" "$PATCH_JS" <<'PY'
import io, os, re, sys
index_path, patch_path = sys.argv[1:3]
html = io.open(index_path, encoding="utf-8").read()
match = re.search(r'<script type="module" crossorigin src="(\./assets/index-[^"]+\.js)"></script>', html)
if not match:
    raise SystemExit(1)
bundle_path = os.path.normpath(os.path.join(os.path.dirname(index_path), match.group(1)))
if not os.path.isfile(bundle_path):
    raise SystemExit(1)
patch = io.open(patch_path, encoding="utf-8").read()
bundle = io.open(bundle_path, encoding="utf-8").read()
io.open(bundle_path, "w", encoding="utf-8").write(patch + "\n" + bundle)
PY

failure_reason="could not repack the patched app.asar"
patched_asar="$work/app.asar.patched"
"$asar_bin" pack "$extract" "$patched_asar"
cp "$patched_asar" "$build_asar"

failure_reason="could not update the Electron ASAR integrity hash"
if /usr/libexec/PlistBuddy -c "Print :ElectronAsarIntegrity:Resources/app.asar:hash" "$build_plist" >/dev/null 2>&1; then
  hash_js="$work/asar-hash.js"
  python3 - "$hash_js" <<'PY'
import io, sys
io.open(sys.argv[1], "w", encoding="utf-8").write(
    'const a=require("@electron/asar"),c=require("crypto");'
    'process.stdout.write(c.createHash("sha256").update(a.getRawHeader(process.argv[2]).headerString).digest("hex"));'
)
PY
  new_hash="$(cd "$tools_dir" && NODE_PATH="$tools_dir/node_modules" "$NODE_BIN" "$hash_js" "$build_asar")"
  [[ -n "$new_hash" ]] || exit 1
  /usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $new_hash" "$build_plist"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $RUNTIME_BUNDLE_ID" "$build_plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $PRODUCT_NAME" "$build_plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string '$PRODUCT_NAME'" "$build_plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $PRODUCT_NAME" "$build_plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$PRODUCT_NAME'" "$build_plist"
/usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$build_plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool false" "$build_plist"
/usr/libexec/PlistBuddy -c "Set :SUAutomaticallyUpdate false" "$build_plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool false" "$build_plist"

failure_reason="could not re-sign the isolated runtime"
entitlements="$work/runtime.entitlements"
python3 - "$entitlements" <<'PY'
import io, sys
io.open(sys.argv[1], "w", encoding="utf-8").write('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.cs.allow-jit</key><true/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
<key>com.apple.security.cs.disable-library-validation</key><true/>
<key>com.apple.security.automation.apple-events</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.network.client</key><true/>
</dict></plist>''')
PY
codesign --force --options runtime --entitlements "$entitlements" --sign - "$build_app" >/dev/null
xattr -dr com.apple.quarantine "$build_app" 2>/dev/null || true
printf '%s' "$key" > "$build_stamp"

failure_reason="structural validation failed"
"$SCRIPT_DIR/check-runtime.sh" --app "$build_app" --stamp "$build_stamp" --quiet

failure_reason="renderer compatibility probe failed"
smoke_profile="$(mktemp -d -t codex-rtl-profile)"
port="$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PY
)"
smoke_log="$LOG_DIR/renderer-smoke.log"
: > "$smoke_log"
/usr/bin/open -j -na "$build_app" -o "$smoke_log" --stderr "$smoke_log" --args \
  --user-data-dir="$smoke_profile" --remote-debugging-port="$port" --no-first-run
page_ready=0
for _ in $(seq 1 90); do
  count="$(curl -fsS "http://127.0.0.1:$port/json" 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
  if [[ "$count" -gt 0 ]]; then page_ready=1; break; fi
  sleep 0.5
done
[[ "$page_ready" == 1 ]] || exit 1
"$NODE_BIN" "$PROBE_JS" "$port" >/dev/null
pkill -f "^$build_app/" 2>/dev/null || true
rm -rf "$smoke_profile"; smoke_profile=""

failure_reason="could not activate the validated runtime"
if app_process_running "$RUNTIME_APP"; then
  rm -rf "$PENDING_APP"
  mv "$build_app" "$PENDING_APP"
  mv "$build_stamp" "$PENDING_STAMP"
  log "OK validated RTL update is pending the next launch; current session was not interrupted."
else
  rm -rf "$PREVIOUS_APP"
  [[ -d "$RUNTIME_APP" ]] && mv "$RUNTIME_APP" "$PREVIOUS_APP"
  if mv "$build_app" "$RUNTIME_APP"; then
    mv "$build_stamp" "$CURRENT_STAMP"
    rm -rf "$PREVIOUS_APP"
  else
    [[ -d "$PREVIOUS_APP" ]] && mv "$PREVIOUS_APP" "$RUNTIME_APP"
    exit 1
  fi
  log "OK validated RTL runtime activated."
fi

rm -f "$FAILED_STAMP" "$FAILED_REASON" "$LAUNCH_FAILED_STAMP"
success=1
[[ "$NOTIFY" == 1 ]] && notify_user "$PRODUCT_NAME" "A validated RTL runtime is ready."
exit 0
