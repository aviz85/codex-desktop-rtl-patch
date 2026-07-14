#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
builder="$ROOT/macos/build-runtime.sh"
launcher="$ROOT/macos/launch.sh"

# These checks make the safety invariants reviewable in CI even without Codex.
grep -q 'FAILED_STAMP' "$builder"
grep -q 'PENDING_APP' "$builder"
grep -q 'probe-renderer.mjs\|PROBE_JS' "$builder"
grep -q 'ditto.*source_app.*build_app' "$builder"
! grep -q 'cp .*source_app.*Contents/Resources/app.asar' "$builder"
grep -q 'fallback_official' "$launcher"
grep -q 'check-runtime.sh' "$launcher"

echo "macOS safety contract tests passed."
