#!/bin/bash
# Compatibility wrapper for pre-0.3 installations.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/macos/check-runtime.sh" "$@"
