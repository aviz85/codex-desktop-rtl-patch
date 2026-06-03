# Codex Desktop RTL Patch

Unofficial local RTL patch for Codex Desktop on **Windows and macOS**.

This patch improves Hebrew, Arabic, and mixed right-to-left text rendering in
Codex Desktop while keeping code blocks, inline code, terminals, and editor-like
surfaces left-to-right.

> **macOS support** was added in this fork. The RTL patch logic
> (`src/codex-rtl-patch.js`) is shared across platforms; only the installer
> differs. See [macOS](#macos) below. Windows instructions are unchanged.

## What It Does

- Detects Hebrew/Arabic text and applies `dir="rtl"` where appropriate.
- Uses `unicode-bidi: plaintext` for mixed Hebrew/English paragraphs.
- Keeps `pre`, `code`, terminal, Monaco/CodeMirror-like, and syntax-highlighted
  content left-to-right.
- Switches the Codex composer direction while typing.
- Installs into a local copy of Codex instead of modifying the official app.

## What It Does Not Do

This project intentionally does **not**:

- edit files under `C:\Program Files\WindowsApps`
- replace hashes inside executables
- install certificates
- change Windows Trusted Root stores
- redistribute Codex or any OpenAI app files

The installer copies the locally installed Codex app to:

```powershell
%LOCALAPPDATA%\OpenAI\CodexRtl\app
```

Then it patches only the copied `resources\app.asar` and creates a desktop
shortcut named `Codex RTL`.

## Requirements

- Windows.
- Codex Desktop installed.
- Node.js 22+ with `npx` available.

Check:

```powershell
node --version
npx.cmd --version
```

## Install From GitHub

Close the regular Codex app first.

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/mnigli/codex-desktop-rtl-patch/main/install.ps1 | iex
```

Then open Codex from the new desktop shortcut:

```text
Codex RTL
```

If the regular Codex app is still running, Windows/Electron may reuse the
existing instance. Close all Codex windows and launch `Codex RTL` again.

## Install From a Clone

```powershell
git clone https://github.com/mnigli/codex-desktop-rtl-patch.git
cd codex-desktop-rtl-patch
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

## Dry Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

## Update After Codex Updates

When Codex updates, rerun the installer:

```powershell
irm https://raw.githubusercontent.com/mnigli/codex-desktop-rtl-patch/main/install.ps1 | iex
```

The installer mirrors the current official Codex app into the local RTL copy
and reapplies the patch.

## Uninstall

From a clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Or manually remove:

```powershell
Remove-Item "$env:LOCALAPPDATA\OpenAI\CodexRtl" -Recurse -Force
Remove-Item "$([Environment]::GetFolderPath('Desktop'))\Codex RTL.lnk" -Force
```

Uninstall removes only the local RTL copy and shortcut. It does not remove or
modify the official Codex installation.

## macOS

The macOS installer patches the app **in place** under `/Applications/Codex.app`
and keeps timestamped backups, so it is fully reversible. It does not copy,
re-sign, or redistribute Codex.

### Requirements

- macOS.
- Codex Desktop installed (`/Applications/Codex.app`).
- Node.js 22+ with `npm` (ships with Node).

### Install

```bash
git clone https://github.com/aviz85/codex-desktop-rtl-patch.git
cd codex-desktop-rtl-patch
chmod +x install.sh uninstall.sh
./install.sh
```

Options: `./install.sh --dry-run` (change nothing), `./install.sh --no-launch`,
or `CODEX_APP=/path/to/Codex.app ./install.sh` to override the app location.

### How it works on macOS

1. Quits Codex if running.
2. Backs up `Contents/Resources/app.asar` and `Contents/Info.plist` (once).
3. Extracts the asar, drops `codex-rtl-patch.js` into `webview/assets/`, and
   references it from `webview/index.html`, then repacks the asar.
4. **Recomputes the Electron ASAR integrity hash.** macOS Electron builds embed
   the expected asar header hash in `Info.plist`
   (`ElectronAsarIntegrity → Resources/app.asar → hash`) and abort on launch with
   `FATAL: Integrity check failed` if the asar changed. The installer computes the
   new `sha256` of the patched asar header and writes it back to `Info.plist`.
   This is the key step the Windows installer does not need.
5. Relaunches Codex.

A harmless `Keychain lookup failed (errSecAuthFailed)` line may appear in the
logs — it is a side effect of modifying a signed bundle and does not affect
Codex sign-in (Codex auth lives in `~/.codex`, not the Chromium keychain).

### Update after Codex updates

A Codex auto-update overwrites `app.asar` and reverts the patch. Either re-run
`./install.sh`, or install the **auto-patch agent** so it re-applies automatically:

```bash
cd autopatch
chmod +x install-autopatch.sh uninstall-autopatch.sh
./install-autopatch.sh
```

This installs a LaunchAgent that watches `app.asar` and re-applies the patch the
moment Codex updates (the macOS analog of the Windows scheduled-task watcher). It
needs a one-time **Full Disk Access** grant for `/bin/bash` — macOS 14+ blocks
background agents from modifying `/Applications`. The installer opens the pane and
explains it.

### Uninstall (macOS)

```bash
./uninstall.sh
```

This restores the original `app.asar` and `Info.plist` from the backups and
relaunches the unpatched app.

## Safety Notice

This is an unofficial patch. Codex UI internals may change, so the patch can
break after app updates. Reinstalling the patch after a Codex update is expected.

Use at your own risk.
