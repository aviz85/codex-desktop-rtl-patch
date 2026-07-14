#!/bin/bash
# Stable user-facing launcher. Any uncertainty falls back to the official app.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

source_app="$(find_source_app)" || exit 1
mkdir -p "$STATE_DIR" "$LOG_DIR"
key="$(source_key 2>/dev/null || true)"

check_runtime() {
  if [[ "${CODEX_RTL_TEST_CHECK:-}" == "pass" ]]; then return 0; fi
  if [[ "${CODEX_RTL_TEST_CHECK:-}" == "fail" ]]; then return 1; fi
  "$SCRIPT_DIR/check-runtime.sh" --quiet
}

runtime_started() {
  if [[ "${CODEX_RTL_TEST_RUNTIME_STARTED:-}" == "yes" ]]; then return 0; fi
  if [[ "${CODEX_RTL_TEST_RUNTIME_STARTED:-}" == "no" ]]; then return 1; fi
  app_process_running "$RUNTIME_APP"
}

fallback_official() {
  local reason="$1"
  local latch="${2:-0}"
  if [[ "$latch" == 1 && -n "$key" ]]; then printf '%s' "$key" > "$LAUNCH_FAILED_STAMP"; fi
  notify_user "Codex RTL" "$reason RTL was disabled; the official app is opening."
  open_app "$source_app"
  exit 0
}

# A runtime that previously passed validation but failed to stay alive is not
# retried on every click. A source/patch/format change produces a new key and
# automatically clears the effective latch.
if [[ -n "$key" && -f "$LAUNCH_FAILED_STAMP" && "$(cat "$LAUNCH_FAILED_STAMP")" == "$key" ]]; then
  open_app "$source_app"
  exit 0
fi

# A validated pending update is activated only between sessions.
if ! app_process_running "$RUNTIME_APP"; then
  if "$SCRIPT_DIR/check-runtime.sh" --app "$PENDING_APP" --stamp "$PENDING_STAMP" --quiet 2>/dev/null; then
    atomic_activate_pending || fallback_official "The validated update could not be activated."
  fi
fi

if ! check_runtime; then
  # Ask the background manager to try once. Its compatibility latch prevents
  # repeated expensive attempts for the same unsupported version.
  launchctl kickstart -k "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true
  fallback_official "No compatible RTL runtime is available for this version."
fi

if app_process_running "$RUNTIME_APP"; then
  /usr/bin/open "$RUNTIME_APP"
  rm -f "$LAUNCH_FAILED_STAMP"
  exit 0
fi

# The official and RTL runtimes share the user's Codex data. Running both at
# once would make Electron route the request unpredictably, so never kill the
# official app: activate it and explain what happened instead.
if app_process_running "$source_app"; then
  fallback_official "The official app is already running. Fully quit it before opening Codex RTL."
fi

open_app "$RUNTIME_APP" || fallback_official "The RTL runtime could not be opened." 1

for _ in $(seq 1 20); do
  runtime_started && { rm -f "$LAUNCH_FAILED_STAMP"; exit 0; }
  sleep 0.25
done

fallback_official "The RTL runtime did not start successfully." 1
