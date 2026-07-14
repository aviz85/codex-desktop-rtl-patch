#!/bin/bash
# Removes only the ChatGPT RTL product installed by install-chatgpt.sh.
# The generic Codex RTL product (install.sh) is untouched.
set -e
export CODEX_RTL_BRAND=chatgpt
exec "$(cd "$(dirname "$0")" && pwd)/macos/uninstall.sh" "$@"
