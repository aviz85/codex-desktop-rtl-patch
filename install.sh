#!/usr/bin/env bash
#
# Codex Desktop RTL patch — macOS installer.
#
# Patches a local install of Codex Desktop (an Electron app) so Hebrew/Arabic
# text renders right-to-left while code, terminals, and editor surfaces stay LTR.
#
# Unlike the Windows installer (which copies the MSIX app out of WindowsApps),
# this script patches the app in place under /Applications and keeps timestamped
# backups so it is fully reversible. The macOS-specific wrinkle is Electron's
# ASAR integrity fuse: the expected asar header hash is embedded in Info.plist
# (key: ElectronAsarIntegrity) and Electron aborts on launch if it does not
# match. After repacking the asar we recompute that hash and update Info.plist.
#
# Usage:
#   ./install.sh                # patch + relaunch Codex
#   ./install.sh --dry-run      # print actions, change nothing
#   ./install.sh --no-launch    # patch but do not relaunch
#   CODEX_APP=/path/Codex.app ./install.sh   # override app location
#
set -euo pipefail

PATCH_VERSION="0.1.0"
ASAR_PKG="@electron/asar@4.2.0"
DRY_RUN=0
LAUNCH=1

IF_NEEDED=0; NOTIFY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-launch) LAUNCH=0 ;;
    --if-needed) IF_NEEDED=1 ;;   # exit early if already patched (for the auto-patch agent)
    --notify) NOTIFY=1 ;;          # post a macOS notification after a (re)patch
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -25; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_JS_SRC="$SCRIPT_DIR/src/codex-rtl-patch.js"
PATCH_JS_URL="https://raw.githubusercontent.com/mnigli/codex-desktop-rtl-patch/main/src/codex-rtl-patch.js"

step() { printf "\n==> %s\n" "$1"; }
ok()   { printf "OK  %s\n" "$1"; }
warn() { printf "WARN %s\n" "$1" >&2; }
die()  { printf "ERROR %s\n" "$1" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf "DRY RUN %s\n" "$*"
  else
    "$@"
  fi
}

# --- locate Codex.app -------------------------------------------------------
find_codex() {
  if [[ -n "${CODEX_APP:-}" ]]; then echo "$CODEX_APP"; return; fi
  for p in "/Applications/Codex.app" "$HOME/Applications/Codex.app"; do
    [[ -d "$p" ]] && { echo "$p"; return; }
  done
  # last resort: Spotlight
  local hit
  hit="$(mdfind "kMDItemCFBundleIdentifier == 'com.openai.codex'" 2>/dev/null | head -1 || true)"
  [[ -n "$hit" ]] && { echo "$hit"; return; }
  return 1
}

command -v node >/dev/null 2>&1 || die "Node.js (with npm) is required. Install Node 22+ first."
command -v npm  >/dev/null 2>&1 || die "npm is required (ships with Node)."

APP="$(find_codex)" || die "Codex.app not found. Set CODEX_APP=/path/to/Codex.app and retry."
RES="$APP/Contents/Resources"
ASAR="$RES/app.asar"
PLIST="$APP/Contents/Info.plist"
[[ -f "$ASAR" ]]  || die "app.asar not found at: $ASAR"
[[ -f "$PLIST" ]] || die "Info.plist not found at: $PLIST"
ok "Found Codex: $APP"

# Idempotent guard for the auto-patch agent: the injected asset reference
# survives inside the (uncompressed) asar, so a raw grep tells us if we patched.
if [[ "$IF_NEEDED" == 1 ]] && grep -qa "codex-rtl-patch.js" "$ASAR" 2>/dev/null; then
  ok "Already patched — nothing to do."
  exit 0
fi

# Preflight: macOS 14+ "App Management" protection blocks modifying /Applications
# apps unless the running program has Full Disk Access. A background LaunchAgent
# typically does NOT, so fail fast with guidance.
if [[ "$DRY_RUN" == 0 ]] && ! ( : > "$RES/.rtl-write-test" ) 2>/dev/null; then
  [[ "$NOTIFY" == 1 ]] && osascript -e 'display notification "Codex updated, but I lack permission to re-apply RTL. Grant /bin/bash Full Disk Access, or run install.sh in Terminal." with title "Codex RTL"' 2>/dev/null || true
  die "Cannot write to $APP (macOS App Management protection).
     Grant Full Disk Access to the program running this (System Settings >
     Privacy & Security > Full Disk Access > + > Cmd+Shift+G > /bin/bash), then re-run."
fi
rm -f "$RES/.rtl-write-test" 2>/dev/null || true

# --- obtain the patch JS ----------------------------------------------------
PATCH_JS="$PATCH_JS_SRC"
if [[ ! -f "$PATCH_JS" ]]; then
  warn "Patch JS not found locally; downloading from $PATCH_JS_URL"
  PATCH_JS="$(mktemp -t codex-rtl-patch).js"
  run curl -fsSL "$PATCH_JS_URL" -o "$PATCH_JS"
fi

# --- quit Codex if running --------------------------------------------------
if pgrep -f "$APP/Contents/MacOS/Codex" >/dev/null 2>&1; then
  step "Quitting Codex"
  run osascript -e 'quit app "Codex"' || true
  for _ in $(seq 1 20); do
    pgrep -f "$APP/Contents/MacOS/Codex" >/dev/null 2>&1 || break
    sleep 0.5
  done
  if pgrep -f "$APP/Contents/MacOS/Codex" >/dev/null 2>&1; then
    run pkill -f "$APP/Contents/MacOS/Codex" || true
    sleep 1
  fi
  ok "Codex stopped"
fi

# --- backups (once) ---------------------------------------------------------
step "Backing up originals"
if [[ ! -f "$ASAR.orig-backup" ]]; then
  run cp "$ASAR" "$ASAR.orig-backup"; ok "Backed up app.asar -> app.asar.orig-backup"
else ok "app.asar backup already exists (kept)"; fi
if [[ ! -f "$PLIST.orig-backup" ]]; then
  run cp "$PLIST" "$PLIST.orig-backup"; ok "Backed up Info.plist -> Info.plist.orig-backup"
else ok "Info.plist backup already exists (kept)"; fi

# --- workspace with @electron/asar -----------------------------------------
WORK="$(mktemp -d -t codex-rtl)"
cleanup() { [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"; }
trap cleanup EXIT

step "Preparing @electron/asar"
if [[ "$DRY_RUN" == 1 ]]; then
  echo "DRY RUN npm install $ASAR_PKG (in temp dir)"
  ASAR_BIN="asar"
else
  ( cd "$WORK" && npm init -y >/dev/null 2>&1 && npm install "$ASAR_PKG" >/dev/null 2>&1 )
  ASAR_BIN="$WORK/node_modules/.bin/asar"
  [[ -x "$ASAR_BIN" ]] || die "Failed to install $ASAR_PKG"
fi

# --- extract, inject, repack -----------------------------------------------
EXTRACT="$WORK/extracted"
step "Extracting app.asar"
run "$ASAR_BIN" extract "$ASAR" "$EXTRACT"

step "Injecting RTL assets"
if [[ "$DRY_RUN" == 1 ]]; then
  echo "DRY RUN copy patch JS -> webview/assets/codex-rtl-patch.js"
  echo "DRY RUN reference patch JS in webview/index.html"
else
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
fi

step "Packing patched app.asar"
PATCHED="$WORK/app.asar.patched"
run "$ASAR_BIN" pack "$EXTRACT" "$PATCHED"

# --- install patched asar ---------------------------------------------------
step "Installing patched app.asar"
run cp "$PATCHED" "$ASAR"

# --- macOS-specific: update Electron ASAR integrity hash --------------------
step "Updating ElectronAsarIntegrity in Info.plist"
if /usr/libexec/PlistBuddy -c "Print :ElectronAsarIntegrity:Resources/app.asar:hash" "$PLIST" >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY RUN compute sha256 of patched asar header + set Info.plist hash"
  else
    NEW_HASH="$(node -e 'const a=require("@electron/asar"),c=require("crypto");process.stdout.write(c.createHash("sha256").update(a.getRawHeader(process.argv[1]).headerString).digest("hex"))' "$ASAR" --prefix "$WORK" 2>/dev/null || \
      ( cd "$WORK" && node -e 'const a=require("@electron/asar"),c=require("crypto");process.stdout.write(c.createHash("sha256").update(a.getRawHeader(process.argv[1]).headerString).digest("hex"))' "$ASAR" ))
    [[ -n "$NEW_HASH" ]] || die "Failed to compute new asar integrity hash"
    /usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $NEW_HASH" "$PLIST"
    ok "Set ElectronAsarIntegrity hash to $NEW_HASH"
  fi
else
  warn "No ElectronAsarIntegrity in Info.plist (older build) — skipping integrity update"
fi

ok "RTL patch v$PATCH_VERSION installed"

if [[ "$NOTIFY" == 1 && "$DRY_RUN" == 0 ]]; then
  osascript -e 'display notification "RTL re-applied after a Codex update. Restart Codex." with title "Codex RTL"' 2>/dev/null || true
fi

# --- relaunch ---------------------------------------------------------------
if [[ "$LAUNCH" == 1 && "$DRY_RUN" == 0 ]]; then
  step "Launching Codex"
  open -a "$APP"
  ok "Launched. If Codex was already open, fully quit and reopen it."
fi

cat <<EOF

Done. To revert:
  ./uninstall.sh
or manually restore the backups:
  cp "$ASAR.orig-backup"  "$ASAR"
  cp "$PLIST.orig-backup" "$PLIST"

Note: a Codex auto-update overwrites app.asar and reverts the patch — just
re-run this installer afterwards.
EOF
