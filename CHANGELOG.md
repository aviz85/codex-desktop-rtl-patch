# Changelog

## 0.3.0 - Unreleased

- Add a stable macOS launcher with official-app fail-open behavior.
- Move the patched runtime out of `~/Applications` into isolated support data.
- Add app/patch/format compatibility keys and failure latching.
- Add atomic activation and non-disruptive pending updates.
- Add a real Electron renderer compatibility probe before activation.
- Add distinct launcher/runtime bundle identifiers.
- Add per-user installation, removal, LaunchAgent, and release-app packaging.
- Add GitHub Actions and fail-open safety tests.
- Deprecate in-place macOS patching and the CDP daemon path.
