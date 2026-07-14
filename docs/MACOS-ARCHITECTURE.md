# macOS fail-open architecture

## Invariant

The official application is the recovery path and is never patched. Every
launcher decision must end in one of two states:

1. a runtime matching the installed official version has passed all checks and
   is opened; or
2. the official application is opened without RTL.

There is no state in which an unvalidated runtime is opened.

## Components

| Component | Location | Purpose |
| --- | --- | --- |
| Stable launcher | `~/Applications/Codex RTL.app` | Chooses validated RTL or official fallback |
| Manager | `~/Library/Application Support/codex-rtl-patch/manager` | Versioned scripts and patch source |
| Active runtime | `…/runtime/Codex RTL Runtime.app` | Validated isolated copy |
| Pending runtime | `…/runtime/Codex RTL Pending.app` | Validated update waiting for the next launch |
| State | `…/state` | Current, pending, and failure keys |
| LaunchAgent | `~/Library/LaunchAgents/io.github.aviz85.codex-rtl-update.plist` | Update detection and rebuild |

## Compatibility key and latch

The compatibility key contains:

- official app filename;
- official `CFBundleVersion`;
- SHA-256 of `src/codex-rtl-patch.js`;
- mirror/injection format version.

If a build fails, the key and reason are recorded. Automatic runs for the same
key become inexpensive no-ops. A new official version, patch, or injection
format creates a new key and permits exactly one new automatic attempt.

Manual installation or repair uses `--force` and may retry explicitly.

## Build transaction

1. Copy the official bundle to a staging path.
2. Extract the staging `app.asar`.
3. Prepend the RTL script to the webview JavaScript entry bundle.
4. Repack ASAR and update `ElectronAsarIntegrity`.
5. Give the isolated runtime a distinct bundle identifier.
6. Disable the runtime's own updater.
7. Ad-hoc sign the isolated copy.
8. Run structural checks.
9. Launch with an isolated temporary profile and CDP port.
10. Probe a real renderer for RTL text and LTR code.
11. Atomically activate, or store as pending if the current runtime is open.

An error before step 11 removes staging, records the latch, and leaves both the
official app and the previously active runtime untouched.

## Launcher behavior

- Invalid or stale runtime: start one background rebuild and open official.
- Compatible runtime: open RTL and verify that its process remains alive.
- RTL launch failure: record the failure and open official.
- Official app already running: do not kill it; activate official and explain
  that it must be fully quit before starting RTL.

## Trust model

The release installer may be Developer ID signed and notarized. The generated
runtime is created locally, has quarantine removed locally, and is ad-hoc
signed because modifying `app.asar` necessarily invalidates OpenAI's top-level
signature. Nested OpenAI frameworks are not modified.

The updater never downloads patch JavaScript. A package update is required to
change patch code, keeping the reviewed release payload as the trust boundary.
