#!/bin/bash
# Build a double-clickable installer app ZIP for GitHub Releases.
# Optional: CODESIGN_IDENTITY and NOTARY_PROFILE for public distribution.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${VERSION:-$(cat "$PROJECT_DIR/VERSION")}"
DIST="${DIST_DIR:-$PROJECT_DIR/dist}"

# BRAND selects which product this release ZIP installs: "codex" (default,
# detects ChatGPT.app or Codex.app, unchanged since 0.3.0) or "chatgpt" (the
# dedicated ChatGPT-only product). See macos/common.sh.
BRAND="${CODEX_RTL_BRAND:-codex}"
case "$BRAND" in
  chatgpt) PRODUCT_NAME="ChatGPT RTL"; BUNDLE_SLUG="chatgpt-rtl"; SUPPORT_SLUG="chatgpt-rtl-patch" ;;
  codex) PRODUCT_NAME="Codex RTL"; BUNDLE_SLUG="codex-rtl"; SUPPORT_SLUG="codex-rtl-patch" ;;
  *) echo "ERROR unknown CODEX_RTL_BRAND: $BRAND" >&2; exit 2 ;;
esac
INSTALLER_NAME="Install $PRODUCT_NAME"

APP="$DIST/$INSTALLER_NAME.app"
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

python3 - "$APP/Contents/Info.plist" "$VERSION" "$INSTALLER_NAME" "io.github.aviz85.$BUNDLE_SLUG-installer" <<'PY'
import plistlib, sys
path, version, installer_name, bundle_id = sys.argv[1:5]
with open(path, "wb") as f:
    plistlib.dump({
        "CFBundleDisplayName": installer_name,
        "CFBundleExecutable": installer_name,
        "CFBundleIdentifier": bundle_id,
        "CFBundleName": installer_name,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "LSMinimumSystemVersion": "13.0",
    }, f)
PY

python3 - "$APP/Contents/MacOS/$INSTALLER_NAME" "$PRODUCT_NAME" "$SUPPORT_SLUG" "$BRAND" <<'PY'
import io, os, sys
path, product_name, support_slug, brand = sys.argv[1:5]
body = f'''#!/bin/bash
set -u
ROOT="$(cd "$(dirname "$0")/../Resources/payload" && pwd)"
LOG="$HOME/Library/Logs/{support_slug}/installer.log"
mkdir -p "$(dirname "$LOG")"
export CODEX_RTL_BRAND="{brand}"
if "$ROOT/macos/install.sh" >"$LOG" 2>&1; then
  /usr/bin/osascript -e 'display dialog "{product_name} was installed. Quit the official app, then open {product_name} from Applications." buttons {{"OK"}} default button "OK" with title "{product_name}"' || true
else
  /usr/bin/osascript -e 'display dialog "Installation could not complete. The official app was not changed. See ~/Library/Logs/{support_slug}/installer.log" buttons {{"OK"}} default button "OK" with icon caution with title "{product_name}"' || true
fi
'''
io.open(path, "w", encoding="utf-8").write(body)
os.chmod(path, 0o755)
PY

chmod +x "$PAYLOAD/macos"/*.sh
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP" >/dev/null
fi

zip_path="$DIST/$(printf '%s' "$PRODUCT_NAME" | tr ' ' '-')-Installer-$VERSION.zip"
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
