---
argument-hint: "[audit|cleanup-safe]"
disable-model-invocation: false
name: mac-efficiency-cleanup
user-invocable: true
description:
  Audit macOS efficiency, background load, cache sprawl, Homebrew cleanup, login items, LaunchAgents, and safe developer
  cache cleanup. Use for Mac performance, disk cleanup, cache cleanup, background process, launch daemon, or login item
  audits.
---

# Mac Efficiency Cleanup

Audit macOS background load and cache sprawl first, then clean only low-risk regenerated caches with explicit approval.

## Arguments

- `audit`: Run the read-only audit script.
- `cleanup-safe`: Preview guarded cleanup for regenerated developer caches and Homebrew stale downloads.

## Safety Rules

- Treat duplicate screenshot tools, browsers, editors, and terminals as user-approved. Do not recommend removing them.
- Treat Helium as the default browser. Do not clear Helium cache by default because it may slow browsing.
- Do not delete caches or app data that may contain login state, browsing/session context, model downloads, project
  indexes, local databases, simulator devices, wallets, chat history, or unsynced user data.
- Prefer dry-run, preview, Trash, or vendor cleanup commands over raw `rm -rf`.
- Keep secret-safe output: report sizes, paths, process names, service names, and counts; do not print environment
  variables, tokens, rendered secret-backed templates, browser data, wallet data, or raw application databases.

## Cleanup Policy

- Safe by default after preview: Homebrew stale downloads via `brew cleanup --dry-run` first, unreachable `uv` objects,
  `pnpm` orphan store entries, Go build/test cache, and old tool logs when a vendor command owns the cleanup.
- Review-only: Bun/npm caches, CoreSimulator, Docker, browser caches, editor caches, AI/model caches, package stores,
  and app support folders.
- Never automatic: Helium browsing cache, browser profiles, Google Drive data, wallet/crypto app data, editor workspace
  storage, Cursor/VSCode history, 1Password data, chat/app histories, and model stores.
- Use `mac-cleanup-go` only in preview-first mode. Any selected deletion must be confirmed manually.

## Workflow

1. Start with a read-only audit:

   ```bash
   .agents/skills/mac-efficiency-cleanup/scripts/audit.sh
   ```

2. Summarize measured pressure before recommending changes: cache roots, Homebrew cleanup preview, memory pressure, top
   CPU/RSS processes, `brew services`, `sfltool dumpbtm`, and LaunchAgent/LaunchDaemon registrations.
3. Decide on-demand vs always-on only from audit evidence for Docker, Nix, WARP, Zoom, Google Drive, BetterTouchTool
   helper, Karabiner, Atuin, SleepWatcher, and CleanMyMac helpers.
4. Keep Raycast, 1Password, AlDente, Atuin, SleepWatcher, BetterTouchTool, and WARP unless a measured issue justifies
   changing them.
5. Remove only stale helper registrations or tools the audit proves unused. Prefer disabling through the vendor app,
   System Settings, `brew services`, or `launchctl bootout` previews before deleting files.
6. For low-risk regenerated cache cleanup, preview first:

   ```bash
   .agents/skills/mac-efficiency-cleanup/scripts/cleanup-safe.sh --dry-run
   ```

7. Execute guarded cleanup only after explicit user approval:

   ```bash
   .agents/skills/mac-efficiency-cleanup/scripts/cleanup-safe.sh --execute
   ```

## Script Interfaces

- `scripts/audit.sh`: Non-destructive macOS audit for cache sizes, Homebrew cleanup preview, brew services, launch
  agents, login/background items, memory pressure, top CPU processes, and top RSS processes.
- `scripts/cleanup-safe.sh --dry-run`: Print the safe cleanup commands and run dry-run-capable previews only.
- `scripts/cleanup-safe.sh --execute`: Prompt for exact confirmation, then run only low-risk regenerated cache cleanup.
