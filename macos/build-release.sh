#!/bin/bash
# Build a double-clickable installer app ZIP for GitHub Releases.
# Optional: CODESIGN_IDENTITY and NOTARY_PROFILE for public distribution.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${VERSION:-$(cat "$PROJECT_DIR/VERSION")}"
DIST="${DIST_DIR:-$PROJECT_DIR/dist}"
APP="$DIST/Install Codex RTL.app"
PAYLOAD="$APP/Contents/Resources/payload"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$PAYLOAD/macos" "$PAYLOAD/src" "$DIST"
/usr/bin/ditto "$PROJECT_DIR/macos" "$PAYLOAD/macos"
cp "$PROJECT_DIR/src/codex-rtl-patch.js" "$PAYLOAD/src/codex-rtl-patch.js"
cp "$PROJECT_DIR/VERSION" "$PAYLOAD/VERSION"

# Vendoring @electron/asar removes the need for users to install npm. The
# runtime uses the Node binary bundled with current ChatGPT/Codex releases.
vendor="$PAYLOAD/vendor/asar"
mkdir -p "$vendor"
(cd "$vendor" && npm init -y >/dev/null 2>&1 && npm install --omit=dev @electron/asar@4.2.0 >/dev/null 2>&1)

python3 - "$APP/Contents/Info.plist" "$VERSION" <<'PY'
import plistlib, sys
path, version = sys.argv[1:3]
with open(path, "wb") as f:
    plistlib.dump({
        "CFBundleDisplayName": "Install Codex RTL",
        "CFBundleExecutable": "Install Codex RTL",
        "CFBundleIdentifier": "io.github.aviz85.codex-rtl-installer",
        "CFBundleName": "Install Codex RTL",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "LSMinimumSystemVersion": "13.0",
    }, f)
PY

python3 - "$APP/Contents/MacOS/Install Codex RTL" <<'PY'
import io, os, sys
body = '''#!/bin/bash
set -u
ROOT="$(cd "$(dirname "$0")/../Resources/payload" && pwd)"
LOG="$HOME/Library/Logs/codex-rtl-patch/installer.log"
mkdir -p "$(dirname "$LOG")"
if "$ROOT/macos/install.sh" >"$LOG" 2>&1; then
  /usr/bin/osascript -e 'display dialog "Codex RTL was installed. Quit the official app, then open Codex RTL from Applications." buttons {"OK"} default button "OK" with title "Codex RTL"' || true
else
  /usr/bin/osascript -e 'display dialog "Installation could not complete. The official app was not changed. See ~/Library/Logs/codex-rtl-patch/installer.log" buttons {"OK"} default button "OK" with icon caution with title "Codex RTL"' || true
fi
'''
io.open(sys.argv[1], "w", encoding="utf-8").write(body)
os.chmod(sys.argv[1], 0o755)
PY

chmod +x "$PAYLOAD/macos"/*.sh
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP" >/dev/null
fi

zip_path="$DIST/Codex-RTL-Installer-$VERSION.zip"
rm -f "$zip_path" "$zip_path.sha256"
/usr/bin/ditto -c -k --keepParent "$APP" "$zip_path"
shasum -a 256 "$zip_path" > "$zip_path.sha256"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$zip_path" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  /usr/bin/ditto -c -k --keepParent "$APP" "$zip_path"
  shasum -a 256 "$zip_path" > "$zip_path.sha256"
fi

echo "Built $zip_path"
