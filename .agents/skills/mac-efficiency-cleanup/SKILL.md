---
argument-hint: "[audit|cleanup-safe]"
coordination: exempt
disable-model-invocation: false
name: mac-efficiency-cleanup
user-invocable: true
description:
  Audit macOS efficiency, background load, cache sprawl, Homebrew cleanup, login items, LaunchAgents, and safe developer
  cache cleanup. Use for Mac performance, disk cleanup, cache cleanup, background process, launch daemon, or login item
  audits.
---

# Mac Efficiency Cleanup

First, audit macOS background load and cache sprawl. Then, with explicit approval, clean only low-risk regenerated
caches.

This skill is coordination-exempt: skip the ai-coord gate for its declared work.

## Arguments

- `audit`: Run the read-only audit script.
- `cleanup-safe`: Preview guarded cleanup for regenerated developer caches and Homebrew stale downloads.

## Safety Rules

- Treat duplicate screenshot tools, browsers, editors, and terminals as user-approved. Do not recommend removing them.
- Treat Helium as the default browser. Do not clear Helium cache by default because it may slow browsing.
- Do not delete caches or app data that may contain login state, browsing/session context, model downloads, project
  indexes, local databases, simulator devices, wallets, chat history, or unsynced user data.
- Shell history (atuin) records only CLI invocations. GUI apps never appear in it. Thus, absence from history gives no
  evidence that an app is uninstalled. Verify install state (see "Verifying an app is actually uninstalled") before
  recommending removal of any app's `~/Library` data.
- Even when the owning app is gone, treat credential-, key-, or content-bearing data as review-only. This includes
  Keybase keys, GitHub Desktop/CLI tokens, browser profiles with saved passwords, notes apps, and wallet stores. Rotate
  any secret embedded in a config (e.g. a deploy key in `~/.<tool>.json`) before deleting it.
- Prefer dry-run, preview, Trash, or vendor cleanup commands over raw `rm -rf`.
- Keep output safe for secrets. Report sizes, paths, process names, service names, and counts. Do not print environment
  variables, tokens, rendered secret-backed templates, browser data, wallet data, or raw application databases.

## Verifying an app is actually uninstalled

Before marking any `~/Library` data for removal, prove the owning app is gone. This includes Application Support,
Containers, Group Containers, Caches, and Saved Application State. A single signal is not enough. False "not installed"
verdicts lead to deletion of live app data.

- Check every app location, not just `/Applications`. Also check `~/Applications` (user-scoped apps), vendor subfolders
  such as `/Applications/Adobe/Adobe Acrobat DC`, Safari extension bundles under `/Applications/Safari/*.app` (e.g.
  AdBlock, PayPal Honey), `/System/Applications`, and `/Applications/Setapp`.
- For an authoritative lookup by name, use `mdfind -name "<AppName>" | grep -i '\.app/\?$'`. Then cross-check the data
  directory's bundle id (`com.vendor.App`) against the result.
- `mdfind` predicate warning: comparison modifiers must be lowercase, as in `kMDItemDisplayName == '*X*'cd`. An
  uppercase `C` silently voids the filter and returns every indexed app, so an identical "match" for every name you test
  is the failure signature. Sanity-check that different names return different results.
- Absence from `brew list --cask` alone is insufficient. Apps are frequently installed outside Homebrew (direct
  download, Mac App Store).
- Calibrate "unused" against the history window. First, read `min`/`max(timestamp)` from atuin. "0 hits" means "not in
  the recorded window," not "never used."

Cautionary example: in one audit, a naive `/Applications`-plus-history check gave a false "not installed" result for
these apps. Every one was present:

- Warp and WarpPreview.
- MyCrypto.
- Topaz Photo AI.
- Adobe Acrobat/Creative Cloud.
- AdBlock and PayPal Honey (Safari extensions).
- Tor Browser.
- Trader Workstation (in `~/Applications`).

Verify before recommending removal.

## Cleanup Policy

- Safe by default after preview: Homebrew stale downloads via `brew cleanup --dry-run` first, unreachable `uv` objects,
  `pnpm` orphan store entries, Go build/test cache, and old tool logs when a vendor command owns the cleanup.
- Review-only: Bun/npm caches, CoreSimulator, Docker, browser caches, editor caches, AI/model caches, package stores,
  and app support folders.
- Never automatic: Helium browsing cache, browser profiles, Google Drive data, wallet/crypto app data, editor workspace
  storage, Cursor/VSCode history, 1Password data, chat/app histories, and model stores.
- Use `mac-cleanup-go` only in preview-first mode. Any selected deletion requires manual confirmation.

## Workflow

1. Start with a read-only audit:

   ```bash
   .agents/skills/mac-efficiency-cleanup/scripts/audit.sh
   ```

2. Before recommending changes, summarize measured pressure: cache roots, Homebrew cleanup preview, memory pressure, top
   CPU/RSS processes, `brew services`, `sfltool dumpbtm`, and LaunchAgent/LaunchDaemon registrations.
3. For Docker, Nix, WARP, Zoom, Google Drive, BetterTouchTool helper, Karabiner, Atuin, SleepWatcher, and CleanMyMac
   helpers, decide on-demand vs always-on only from audit evidence.
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
- `scripts/cleanup-safe.sh --execute`: Prompt for exact confirmation. Then attempt every requested low-risk regenerated
  cache cleanup and exit nonzero if any action fails.
