# Codex RTL — macOS auto-patch agent

Codex auto-updates overwrite `app.asar` and revert the RTL patch. This
LaunchAgent watches the app and re-applies the patch — the macOS analog of the
Windows scheduled-task watcher.

```bash
cd autopatch
chmod +x install-autopatch.sh uninstall-autopatch.sh
./install-autopatch.sh      # install + load the agent
./uninstall-autopatch.sh    # remove it
```

A per-user LaunchAgent (`com.aviz85.codex-rtl-autopatch`) runs
`../install.sh --if-needed --no-launch --notify` on **WatchPaths** (the instant
an update replaces `app.asar`) and at login (**RunAtLoad**). `--if-needed` makes
it a no-op when already patched. Logs: `~/Library/Logs/codex-rtl-patch/autopatch.log`.

## The honest status: two modes

macOS 14+ ("App Management" protection) blocks a background LaunchAgent from
modifying apps in `/Applications`. **Out of the box this agent only DETECTS
updates and notifies you** (verified). It cannot re-write the app yet.

- **Mode A — semi-automatic (default):** after a Codex update you get a
  notification; run `../install.sh` once from Terminal to re-apply.
- **Mode B — fully automatic (one-time grant):** give `/bin/bash` Full Disk
  Access (System Settings → Privacy & Security → Full Disk Access → + →
  Cmd+Shift+G → `/bin/bash`). Then the agent re-applies on its own. This mode is
  designed but **not yet end-to-end verified** — confirm after a real update.

Granting FDA to `/bin/bash` is broad (covers any shell script); if you'd rather
not, stay on Mode A.
