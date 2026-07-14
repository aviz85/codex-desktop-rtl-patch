#!/bin/bash
# Shared paths and helpers for the macOS fail-open RTL runtime.

set -u

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$MACOS_DIR/.." && pwd)"

# BRAND selects which official app this tool targets and how the generated
# launcher/runtime/support files are named. It defaults to "codex", which is
# the original, unchanged behavior: detect ChatGPT.app or Codex.app (in that
# order) and brand everything "Codex RTL". Set CODEX_RTL_BRAND=chatgpt to
# build the dedicated ChatGPT-only "ChatGPT RTL" product instead. The two
# brands use disjoint support directories, bundle identifiers, LaunchAgent
# labels, and launcher app names, so installing one never touches the other.
BRAND="${CODEX_RTL_BRAND:-codex}"

case "$BRAND" in
  chatgpt)
    PRODUCT_NAME="ChatGPT RTL"
    BUNDLE_SLUG="chatgpt-rtl"
    SUPPORT_SLUG="chatgpt-rtl-patch"
    TARGET_APPS=("/Applications/ChatGPT.app")
    ;;
  codex)
    PRODUCT_NAME="Codex RTL"
    BUNDLE_SLUG="codex-rtl"
    SUPPORT_SLUG="codex-rtl-patch"
    TARGET_APPS=("/Applications/ChatGPT.app" "/Applications/Codex.app")
    ;;
  *)
    echo "ERROR unknown CODEX_RTL_BRAND: $BRAND (expected 'codex' or 'chatgpt')" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

SUPPORT_DIR="${CODEX_RTL_SUPPORT_DIR:-$HOME/Library/Application Support/$SUPPORT_SLUG}"
MANAGER_DIR="${CODEX_RTL_MANAGER_DIR:-$SUPPORT_DIR/manager}"
RUNTIME_DIR="${CODEX_RTL_RUNTIME_DIR:-$SUPPORT_DIR/runtime}"
STATE_DIR="${CODEX_RTL_STATE_DIR:-$SUPPORT_DIR/state}"
LOG_DIR="${CODEX_RTL_LOG_DIR:-$HOME/Library/Logs/$SUPPORT_SLUG}"

RUNTIME_APP="${CODEX_RTL_RUNTIME_APP:-$RUNTIME_DIR/$PRODUCT_NAME Runtime.app}"
PENDING_APP="${CODEX_RTL_PENDING_APP:-$RUNTIME_DIR/$PRODUCT_NAME Pending.app}"
PREVIOUS_APP="${CODEX_RTL_PREVIOUS_APP:-$RUNTIME_DIR/$PRODUCT_NAME Previous.app}"
LAUNCHER_APP="${CODEX_RTL_LAUNCHER_APP:-$HOME/Applications/$PRODUCT_NAME.app}"

CURRENT_STAMP="${CODEX_RTL_CURRENT_STAMP:-$STATE_DIR/current.key}"
PENDING_STAMP="${CODEX_RTL_PENDING_STAMP:-$STATE_DIR/pending.key}"
FAILED_STAMP="${CODEX_RTL_FAILED_STAMP:-$STATE_DIR/failed.key}"
FAILED_REASON="${CODEX_RTL_FAILED_REASON:-$STATE_DIR/failed.reason}"
LAUNCH_FAILED_STAMP="${CODEX_RTL_LAUNCH_FAILED_STAMP:-$STATE_DIR/launch-failed.key}"

PATCH_JS="${CODEX_RTL_PATCH_JS:-$PROJECT_DIR/src/codex-rtl-patch.js}"
PROBE_JS="${CODEX_RTL_PROBE_JS:-$MACOS_DIR/probe-renderer.mjs}"
MIRROR_FORMAT="3"
RUNTIME_BUNDLE_ID="io.github.aviz85.$BUNDLE_SLUG-runtime"
LAUNCHER_BUNDLE_ID="io.github.aviz85.$BUNDLE_SLUG-launcher"
AGENT_LABEL="io.github.aviz85.$BUNDLE_SLUG-update"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*" >&2; }

find_source_app() {
  if [[ -n "${CODEX_APP:-}" ]]; then
    [[ -d "$CODEX_APP" ]] && { printf '%s\n' "$CODEX_APP"; return 0; }
    return 1
  fi
  local app
  for app in "${TARGET_APPS[@]}"; do
    [[ -d "$app" ]] && { printf '%s\n' "$app"; return 0; }
  done
  return 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

ensure_node() {
  if command -v node >/dev/null 2>&1; then
    NODE_BIN="$(command -v node)"
  else
    local source_app bundled
    source_app="$(find_source_app)" || return 1
    bundled="$source_app/Contents/Resources/cua_node/bin/node"
    [[ -x "$bundled" ]] || return 1
    NODE_BIN="$bundled"
    export PATH="$(dirname "$bundled"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  fi
  export NODE_BIN
}

source_key() {
  local source_app build patch_hash
  source_app="$(find_source_app)" || return 1
  build="$(plist_value "$source_app" CFBundleVersion)"
  [[ -n "$build" && -f "$PATCH_JS" ]] || return 1
  patch_hash="$(shasum -a 256 "$PATCH_JS" | awk '{print $1}')"
  printf '%s:%s:%s:%s\n' "$(basename "$source_app")" "$build" "$patch_hash" "$MIRROR_FORMAT"
}

app_process_running() {
  local app="$1"
  pgrep -f "^$app/" >/dev/null 2>&1
}

notify_user() {
  local title="$1" message="$2"
  if [[ -n "${CODEX_RTL_TEST_NOTIFY_LOG:-}" ]]; then
    printf '%s|%s\n' "$title" "$message" >> "$CODEX_RTL_TEST_NOTIFY_LOG"
    return 0
  fi
  /usr/bin/osascript - "$title" "$message" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

open_app() {
  local app="$1"
  if [[ -n "${CODEX_RTL_TEST_OPEN_LOG:-}" ]]; then
    printf '%s\n' "$app" >> "$CODEX_RTL_TEST_OPEN_LOG"
    return 0
  fi
  if [[ "$app" == "$RUNTIME_APP" ]]; then
    /usr/bin/open -na "$app"
  else
    /usr/bin/open "$app"
  fi
}

atomic_activate_pending() {
  [[ -d "$PENDING_APP" && -f "$PENDING_STAMP" ]] || return 1
  app_process_running "$RUNTIME_APP" && return 1
  rm -rf "$PREVIOUS_APP"
  [[ -d "$RUNTIME_APP" ]] && mv "$RUNTIME_APP" "$PREVIOUS_APP"
  if mv "$PENDING_APP" "$RUNTIME_APP"; then
    mv "$PENDING_STAMP" "$CURRENT_STAMP"
    rm -rf "$PREVIOUS_APP"
    return 0
  fi
  [[ -d "$PREVIOUS_APP" ]] && mv "$PREVIOUS_APP" "$RUNTIME_APP"
  return 1
}
