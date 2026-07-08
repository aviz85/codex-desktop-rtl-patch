#!/usr/bin/env bash
#
# Codex Desktop RTL — MIRROR builder (macOS).
#
# Instead of patching /Applications/Codex.app in place (which requires Full Disk
# Access on macOS 14+ and gets wiped by every Sparkle auto-update), this builds a
# patched COPY under ~/Applications/"Codex RTL.app":
#
#   1. rsync the pristine /Applications/Codex.app  ->  ~/Applications/Codex RTL.app
#   2. inject the RTL patch JS into the COPY's app.asar (extract/inject/pack)
#   3. recompute + write the COPY's ElectronAsarIntegrity hash
#   4. disable Sparkle auto-update in the COPY (SUEnableAutomaticChecks=false)
#   5. ad-hoc re-sign the COPY (top-level only, no --deep) so it launches
#   6. strip the quarantine xattr from the COPY
#   7. stamp the source CFBundleVersion so we know when to re-mirror
#
# ~/Applications is user-owned -> NO App Management / Full Disk Access / TCC grant.
# The source app is NEVER modified (read-only).
#
# Usage:
#   ./build-mirror.sh              build/refresh the mirror unconditionally
#   ./build-mirror.sh --if-needed  no-op if the mirror already matches the source
#   ./build-mirror.sh --no-launch  do not open the mirror afterwards (default for agent)
#   ./build-mirror.sh --launch     open the mirror when done
#   ./build-mirror.sh --notify     post a macOS notification after a (re)build
#
set -euo pipefail

ASAR_PKG="@electron/asar@4.2.0"
IF_NEEDED=0; LAUNCH=0; NOTIFY=0

for arg in "$@"; do
  case "$arg" in
    --if-needed) IF_NEEDED=1 ;;
    --no-launch) LAUNCH=0 ;;
    --launch)    LAUNCH=1 ;;
    --notify)    NOTIFY=1 ;;
    -h|--help)   grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -30; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_JS="$REPO_DIR/src/codex-rtl-patch.js"

SRC_APP="${CODEX_APP:-/Applications/Codex.app}"
DEST_APP="$HOME/Applications/Codex RTL.app"
SUPPORT="$HOME/Library/Application Support/codex-rtl-patch"
STAMP="$SUPPORT/mirror.stamp"
TOOLS_DIR="$SUPPORT/asar-tools"           # cached @electron/asar (no network at update time)

step() { printf "\n==> %s\n" "$1"; }
ok()   { printf "OK  %s\n" "$1"; }
warn() { printf "WARN %s\n" "$1" >&2; }
die()  { printf "ERROR %s\n" "$1" >&2; exit 1; }

command -v node >/dev/null 2>&1 || die "Node.js is required."
[[ -d "$SRC_APP" ]]  || die "Source app not found: $SRC_APP"
[[ -f "$PATCH_JS" ]] || die "Patch JS not found: $PATCH_JS"

SRC_PLIST="$SRC_APP/Contents/Info.plist"
SRC_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SRC_PLIST" 2>/dev/null || echo unknown)"

# --- idempotency guard ------------------------------------------------------
mirror_is_current() {
  [[ -d "$DEST_APP" ]] || return 1
  [[ -f "$STAMP" ]] || return 1
  [[ "$(cat "$STAMP" 2>/dev/null)" == "$SRC_VER" ]] || return 1
  grep -qa "codex-rtl-patch.js" "$DEST_APP/Contents/Resources/app.asar" 2>/dev/null || return 1
  codesign --verify "$DEST_APP" >/dev/null 2>&1 || return 1
  return 0
}

if [[ "$IF_NEEDED" == 1 ]] && mirror_is_current; then
  ok "Mirror already current for source version $SRC_VER — nothing to do."
  exit 0
fi

step "Source Codex.app version: $SRC_VER"

# --- cached @electron/asar --------------------------------------------------
ASAR_BIN="$TOOLS_DIR/node_modules/.bin/asar"
if [[ ! -x "$ASAR_BIN" ]]; then
  step "Installing $ASAR_PKG (cached at $TOOLS_DIR)"
  mkdir -p "$TOOLS_DIR"
  ( cd "$TOOLS_DIR" && npm init -y >/dev/null 2>&1 && npm install "$ASAR_PKG" >/dev/null 2>&1 )
  [[ -x "$ASAR_BIN" ]] || die "Failed to install $ASAR_PKG"
fi
ok "asar tool: $ASAR_BIN"

# --- quit a running mirror --------------------------------------------------
if pgrep -f "$DEST_APP/Contents/MacOS/" >/dev/null 2>&1; then
  step "Quitting running mirror"
  pkill -f "$DEST_APP/Contents/MacOS/" 2>/dev/null || true
  sleep 1
fi

# --- 1. mirror the pristine bundle -----------------------------------------
step "Mirroring $SRC_APP -> $DEST_APP"
mkdir -p "$HOME/Applications"
# --delete so a shrunk/renamed source never leaves stale files behind.
rsync -a --delete "$SRC_APP/" "$DEST_APP/"
ok "Mirrored."

DEST_RES="$DEST_APP/Contents/Resources"
DEST_ASAR="$DEST_RES/app.asar"
DEST_PLIST="$DEST_APP/Contents/Info.plist"
[[ -f "$DEST_ASAR" ]]  || die "Mirror missing app.asar: $DEST_ASAR"
[[ -f "$DEST_PLIST" ]] || die "Mirror missing Info.plist: $DEST_PLIST"

# --- 2. inject RTL patch into the COPY's asar ------------------------------
WORK="$(mktemp -d -t codex-rtl-mirror)"
cleanup() { [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"; }
trap cleanup EXIT
EXTRACT="$WORK/extracted"

step "Extracting mirror app.asar"
"$ASAR_BIN" extract "$DEST_ASAR" "$EXTRACT"

step "Injecting RTL assets"
cp "$PATCH_JS" "$EXTRACT/webview/assets/codex-rtl-patch.js"
INDEX="$EXTRACT/webview/index.html"
[[ -f "$INDEX" ]] || die "webview/index.html not found inside asar"
python3 - "$INDEX" <<'PY'
import re, sys, io
p = sys.argv[1]
html = io.open(p, encoding="utf-8").read()
if "codex-rtl-patch.js" in html:
    print("OK  index.html already references the patch"); sys.exit(0)
tag = '    <script type="module" crossorigin src="./assets/codex-rtl-patch.js"></script>'
pat = re.compile(r'(    <script type="module" crossorigin src="\./assets/index-[^"]+\.js"></script>)')
if pat.search(html):
    html = pat.sub(tag + "\n" + r"\1", html, count=1)
elif "</head>" in html:
    html = html.replace("</head>", tag + "\n</head>", 1)
else:
    sys.exit("ERROR no safe insertion point in index.html")
io.open(p, "w", encoding="utf-8").write(html)
print("OK  injected patch reference into index.html")
PY

step "Packing patched app.asar"
PATCHED="$WORK/app.asar.patched"
"$ASAR_BIN" pack "$EXTRACT" "$PATCHED"
cp "$PATCHED" "$DEST_ASAR"
ok "Patched asar installed into mirror."

# --- 3. recompute ElectronAsarIntegrity for the COPY -----------------------
step "Updating ElectronAsarIntegrity in mirror Info.plist"
if /usr/libexec/PlistBuddy -c "Print :ElectronAsarIntegrity:Resources/app.asar:hash" "$DEST_PLIST" >/dev/null 2>&1; then
  HASH_JS="$WORK/asar-hash.js"
  cat > "$HASH_JS" <<'JS'
const a = require("@electron/asar"), c = require("crypto");
process.stdout.write(c.createHash("sha256").update(a.getRawHeader(process.argv[2]).headerString).digest("hex"));
JS
  NEW_HASH="$( NODE_PATH="$TOOLS_DIR/node_modules" node "$HASH_JS" "$DEST_ASAR" )"
  [[ -n "$NEW_HASH" ]] || die "Failed to compute new asar integrity hash"
  /usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $NEW_HASH" "$DEST_PLIST"
  ok "Set ElectronAsarIntegrity hash to $NEW_HASH"
else
  warn "No ElectronAsarIntegrity in Info.plist — skipping integrity update"
fi

# --- 4. disable Sparkle auto-update in the COPY ----------------------------
step "Disabling Sparkle auto-update in mirror"
/usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$DEST_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool false" "$DEST_PLIST"
/usr/libexec/PlistBuddy -c "Set :SUAutomaticallyUpdate false" "$DEST_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool false" "$DEST_PLIST"
ok "Sparkle automatic checks disabled."

# --- 5. ad-hoc re-sign the COPY (top-level only, no --deep) -----------------
step "Re-signing mirror (ad-hoc)"
ENT="$WORK/codex-resign.entitlements"
cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
  <key>com.apple.security.automation.apple-events</key><true/>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
  <key>com.apple.security.network.client</key><true/>
</dict>
</plist>
PLIST
codesign --force --options runtime --entitlements "$ENT" --sign - "$DEST_APP" \
  || die "codesign failed — mirror is patched but unsigned and will not launch"
if codesign --verify --verbose=1 "$DEST_APP" >/dev/null 2>&1; then
  ok "Re-signed (ad-hoc) — signature valid"
else
  warn "Re-signed but 'codesign --verify' reports issues; the app may still launch"
fi

# --- 6. strip quarantine ----------------------------------------------------
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

# --- 7. stamp the source version -------------------------------------------
mkdir -p "$SUPPORT"
printf "%s" "$SRC_VER" > "$STAMP"
ok "Stamped source version: $SRC_VER"

echo
ok "Mirror built: $DEST_APP"

if [[ "$NOTIFY" == 1 ]]; then
  osascript -e 'display notification "Codex RTL mirror rebuilt after a Codex update." with title "Codex RTL"' 2>/dev/null || true
fi
if [[ "$LAUNCH" == 1 ]]; then
  step "Launching mirror"
  open "$DEST_APP"
fi
