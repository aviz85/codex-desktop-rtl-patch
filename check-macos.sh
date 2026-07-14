#!/bin/bash
set -e
exec "$(cd "$(dirname "$0")" && pwd)/macos/check-runtime.sh" "$@"
