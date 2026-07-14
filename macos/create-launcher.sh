#!/bin/bash
# Create the stable Codex RTL launcher app. The large runtime remains hidden.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

source_app="$(find_source_app)" || { echo "ERROR official app not found" >&2; exit 1; }
manager_launch="$MANAGER_DIR/macos/launch.sh"
[[ -x "$manager_launch" ]] || manager_launch="$SCRIPT_DIR/launch.sh"

staging="${LAUNCHER_APP%.app}.building.app"
version="$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo 0.0.0)"
rm -rf "$staging"
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources" "$(dirname "$LAUNCHER_APP")"

python3 - "$staging/Contents/Info.plist" "$LAUNCHER_BUNDLE_ID" "$version" "$PRODUCT_NAME" <<'PY'
import plistlib, sys
path, bundle_id, version, product_name = sys.argv[1:5]
data = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleDisplayName": product_name,
    "CFBundleExecutable": product_name,
    "CFBundleIconFile": "AppIcon",
    "CFBundleIdentifier": bundle_id,
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": product_name,
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": version,
    "LSMinimumSystemVersion": "13.0",
}
with open(path, "wb") as f:
    plistlib.dump(data, f)
PY

python3 - "$staging/Contents/MacOS/$PRODUCT_NAME" "$manager_launch" "$BRAND" <<'PY'
import io, os, shlex, sys
path, launcher, brand = sys.argv[1:4]
# BRAND must be baked in here: a double-clicked .app has no shell env, so
# without this the launcher silently falls back to the "codex" default brand.
body = (
    "#!/bin/bash\n"
    f"export CODEX_RTL_BRAND={shlex.quote(brand)}\n"
    "exec " + shlex.quote(launcher) + "\n"
)
io.open(path, "w", encoding="utf-8").write(body)
os.chmod(path, 0o755)
PY

icon="$(find "$source_app/Contents/Resources" -maxdepth 1 -iname '*.icns' | head -1 || true)"
[[ -n "$icon" ]] && cp "$icon" "$staging/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$staging" >/dev/null
xattr -dr com.apple.quarantine "$staging" 2>/dev/null || true

rm -rf "$LAUNCHER_APP"
mv "$staging" "$LAUNCHER_APP"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$lsregister" ]] && "$lsregister" -f "$LAUNCHER_APP"
echo "OK launcher created: $LAUNCHER_APP"
