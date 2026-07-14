#!/bin/bash
# Dedicated installer for the ChatGPT-only RTL product ("ChatGPT RTL").
# Targets /Applications/ChatGPT.app exclusively and installs alongside (never
# in place of) the generic Codex RTL product from install.sh. See README.md.
set -e
export CODEX_RTL_BRAND=chatgpt
exec "$(cd "$(dirname "$0")" && pwd)/macos/install.sh" "$@"
