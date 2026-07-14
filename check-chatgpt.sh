#!/bin/bash
# Diagnoses only the ChatGPT RTL product installed by install-chatgpt.sh.
set -e
export CODEX_RTL_BRAND=chatgpt
exec "$(cd "$(dirname "$0")" && pwd)/macos/check-runtime.sh" "$@"
