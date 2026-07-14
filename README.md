# Codex Desktop RTL Patch

Unofficial RTL support for Hebrew, Arabic, and mixed-direction text in Codex
Desktop. Code blocks, terminals, Monaco/CodeMirror, and syntax-highlighted
content remain left-to-right.

This repository supports:

- **macOS:** fail-open launcher plus an isolated, locally built RTL runtime.
- **Windows:** local copied runtime installed by `install.ps1`.

The official OpenAI app is never redistributed.

## macOS: safety first

The macOS design has one non-negotiable rule:

> If RTL compatibility cannot be proven, open the official app without RTL.

The installer never modifies `/Applications/ChatGPT.app` or
`/Applications/Codex.app`. It creates:

- `~/Applications/Codex RTL.app` — a small, stable launcher.
- `~/Library/Application Support/codex-rtl-patch/runtime/` — the hidden,
  locally built runtime.
- a per-user LaunchAgent that detects source updates.

### What happens after an app update

1. The official app updates normally.
2. A new RTL runtime is built in a temporary directory.
3. The patch is embedded into the webview's loaded JavaScript bundle.
4. ASAR integrity is recalculated and the isolated copy is ad-hoc signed.
5. A real renderer smoke test verifies:
   - the patch loaded;
   - Hebrew resolves to RTL;
   - code remains LTR.
6. Only a passing build is activated atomically.
7. If anything fails, that app/patch combination is latched as incompatible.
   Further automatic retries stop until either the official app or patch
   changes.
8. The launcher opens the official app.

A running RTL session is never killed for an update. A validated rebuild waits
as a pending runtime and is activated on the next launch.

## Install on macOS

### GitHub Release installer

Download `Codex-RTL-Installer-<version>.zip` from Releases, open
**Install Codex RTL**, and follow the dialog.

For public distribution the release should be signed and notarized. Unsigned
development builds may require right-click → Open.

### From a reviewed clone

```bash
git clone https://github.com/aviz85/codex-desktop-rtl-patch.git
cd codex-desktop-rtl-patch
./install.sh
```

To explicitly retry a latched compatibility failure after troubleshooting:

```bash
./install.sh --repair
```

No `sudo`, Full Disk Access, certificate installation, or modification of the
official app is required.

After installation, fully quit the official app and open **Codex RTL** from
`~/Applications`.

## Diagnose macOS

```bash
./check-macos.sh
```

A healthy runtime reports:

- matching source/runtime versions;
- isolated bundle identity;
- embedded RTL code;
- current app + patch stamp;
- valid code signature;
- matching Electron ASAR integrity.

Logs are stored under:

```text
~/Library/Logs/codex-rtl-patch/
```

If a version is incompatible, the reason is stored locally and the launcher
continues opening the official app.

## Uninstall macOS

```bash
./uninstall.sh
```

This removes only the launcher, hidden runtime, manager, state, and LaunchAgent.
The official app and user data are untouched.

## Build a macOS release

Requirements for the release machine:

- macOS;
- Node.js and npm;
- optional Apple Developer ID credentials for public distribution.

```bash
VERSION=0.3.0 ./macos/build-release.sh
```

Outputs:

```text
dist/Codex-RTL-Installer-0.3.0.zip
dist/Codex-RTL-Installer-0.3.0.zip.sha256
```

Signed and notarized build:

```bash
VERSION=0.3.0 \
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="codex-rtl-notary" \
./macos/build-release.sh
```

The release vendors the pinned `@electron/asar` dependency. End users do not
need npm; the installer can use the Node runtime bundled with current
ChatGPT/Codex builds.

See [macOS architecture](docs/MACOS-ARCHITECTURE.md) and
[release guide](docs/RELEASING-MACOS.md).

## Windows

Windows uses a separate copied runtime under:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl
```

From a reviewed clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Remove it with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

The Windows scripts remain independent of the macOS fail-open manager.

## Tests

```bash
node tests/rtl-direction.test.js
tests/macos-fail-open.test.sh
tests/macos-build-lock.test.sh
tests/macos-safety-contract.test.sh
```

GitHub Actions runs the JavaScript tests on Node 22 and the safety/launcher
tests on macOS.

## Security boundaries

This project does not:

- modify the official OpenAI application;
- redistribute OpenAI binaries;
- install a privileged daemon;
- request Full Disk Access;
- install certificates;
- disable Gatekeeper or System Integrity Protection;
- download and execute an unpinned remote patch during normal updates.

The isolated runtime is built exclusively from the user's locally installed
official app and the reviewed patch shipped with this package.

## Limitations

Codex UI internals are not a public compatibility API. A future release can
disable RTL until this project is updated. That is an expected safe outcome:
the official application must continue to open normally.

## License

MIT. This is an independent community project and is not an OpenAI product.
