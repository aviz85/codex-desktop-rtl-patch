#!/bin/bash
# Compatibility wrapper for pre-0.3 installations.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
args=()
for arg in "$@"; do
  case "$arg" in
    --no-launch|--launch) ;;
    *) args+=("$arg") ;;
  esac
done
exec "$ROOT/macos/build-runtime.sh" "${args[@]}"
