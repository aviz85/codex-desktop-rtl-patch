#!/usr/bin/env bash
# Is the patched Codex in a healthy, launch-safe state on macOS?
# Checks code signature, asar-integrity parity (the #1 cause of a startup crash),
# and whether the RTL patch is present.
set -uo pipefail
APP="${CODEX_APP:-/Applications/Codex.app}"
RES="$APP/Contents/Resources"; PLIST="$APP/Contents/Info.plist"
hdr_hash() { node -e 'const fs=require("fs"),c=require("crypto");const fd=fs.openSync(process.argv[1],"r");const b=Buffer.alloc(16);fs.readSync(fd,b,0,16,0);const jl=b.readUInt32LE(12);const h=Buffer.alloc(jl);fs.readSync(fd,h,0,jl,16);process.stdout.write(c.createHash("sha256").update(h).digest("hex"))' "$1"; }
has_patch() { node -e 'const fs=require("fs");const fd=fs.openSync(process.argv[1],"r");const b=Buffer.alloc(16);fs.readSync(fd,b,0,16,0);const jl=b.readUInt32LE(12);const h=Buffer.alloc(jl);fs.readSync(fd,h,0,jl,16);process.stdout.write(h.toString())' "$1" | grep -q codex-rtl-patch.js; }

echo "▸ signature:"
if codesign --verify "$APP" >/dev/null 2>&1; then echo "   ✓ valid (will launch)"; else echo "   ✗ INVALID — will not launch"; fi
echo "▸ asar integrity:"
PH=$(/usr/libexec/PlistBuddy -c "Print :ElectronAsarIntegrity:Resources/app.asar:hash" "$PLIST" 2>/dev/null || echo "")
AH=$(hdr_hash "$RES/app.asar" 2>/dev/null || echo "")
if [ -z "$PH" ]; then echo "   – no ElectronAsarIntegrity (older build)"; \
elif [ "$PH" = "$AH" ]; then echo "   ✓ plist hash == asar header (no startup abort)"; \
else echo "   ✗ MISMATCH — Codex will SIGTRAP at startup  (plist=$PH asar=$AH)"; fi
echo "▸ RTL patch:"
if has_patch "$RES/app.asar" 2>/dev/null; then echo "   ✓ present"; else echo "   – not present (clean app / reverted by an update)"; fi
