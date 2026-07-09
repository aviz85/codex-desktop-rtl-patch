#!/bin/bash
PORT=9333
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
# If nothing is on the debug port and Codex isn't running, launch it WITH the port (login case).
if ! /usr/bin/curl -s -m2 "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
  if ! /usr/bin/pgrep -f "Codex.app/Contents/MacOS/Codex" >/dev/null 2>&1; then
    /usr/bin/open -na "/Applications/Codex.app" --args --remote-debugging-port=$PORT
    sleep 6
  fi
fi
exec "/opt/homebrew/bin/node" /Users/aviz/codex-desktop-rtl-patch/src/cdp-inject.mjs
