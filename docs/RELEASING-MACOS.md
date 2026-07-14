# Releasing the macOS installer

## Prerequisites

- clean reviewed checkout;
- Node.js/npm on the release machine;
- Apple Developer ID Application certificate for a frictionless public build;
- `notarytool` keychain profile for notarization.

## Validate

```bash
node tests/rtl-direction.test.js
tests/macos-fail-open.test.sh
tests/macos-build-lock.test.sh
tests/macos-safety-contract.test.sh
for file in macos/*.sh; do bash -n "$file"; done
```

Perform one end-to-end install on a disposable macOS user account and confirm:

- the official app hash/signature is unchanged;
- RTL launcher opens the isolated runtime;
- deleting `current.key` makes the launcher open the official app;
- an intentionally invalid webview selector produces a failure latch;
- restoring the patch and changing its hash permits a rebuild.

## Build

```bash
VERSION=0.3.0 \
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="codex-rtl-notary" \
./macos/build-release.sh
```

The command creates a ZIP and SHA-256 checksum under `dist/`. The installer
payload includes pinned `@electron/asar@4.2.0`, so users do not need npm.

## Publish

Attach both files to the GitHub Release. Document the supported official app
version used for the renderer smoke test. Never attach a generated RTL runtime
or any OpenAI application binaries.

## Emergency response

If a release is incompatible, remove the release asset and publish a new patch
version. Existing installations fail open automatically; do not instruct users
to bypass the latch or patch the official app in place.
