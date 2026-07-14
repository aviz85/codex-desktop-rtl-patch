# Changelog

## 0.4.0 - 2026-07-14

- Add a dedicated **ChatGPT RTL** product (`install-chatgpt.sh`,
  `uninstall-chatgpt.sh`, `check-chatgpt.sh`) that targets `ChatGPT.app`
  exclusively, now that OpenAI has folded Codex into the ChatGPT desktop app.
- Parameterize the macOS fail-open engine (`macos/common.sh` and friends) by
  a `CODEX_RTL_BRAND` variable so both products share one codebase with
  disjoint bundle identifiers, LaunchAgents, and support directories.
- `install.sh` (Codex RTL) keeps its existing default behavior unchanged:
  detect `ChatGPT.app`, fall back to `Codex.app`.
- Parameterize `macos/build-release.sh` so release ZIPs can be built for
  either product via `CODEX_RTL_BRAND`.

## 0.3.0 - 2026-07-12

- Add a stable macOS launcher with official-app fail-open behavior.
- Move the patched runtime out of `~/Applications` into isolated support data.
- Add app/patch/format compatibility keys and failure latching.
- Add atomic activation and non-disruptive pending updates.
- Add a real Electron renderer compatibility probe before activation.
- Add distinct launcher/runtime bundle identifiers.
- Add per-user installation, removal, LaunchAgent, and release-app packaging.
- Add GitHub Actions and fail-open safety tests.
- Deprecate in-place macOS patching and the CDP daemon path.
