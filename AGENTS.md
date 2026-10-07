# Development Instructions

These guidelines apply to AI agents and developers who work on this macOS-only dotfiles repository.

Ubuntu support is frozen on `archive/ubuntu-2026-10-05`. Maintain only macOS on `main`. Do not add Linux alternatives or
require cross-platform validation. Both chezmoi init and apply reject non-macOS hosts.

## Stack

- **chezmoi** — dotfile manager. Source state uses Go templates (`.tmpl`). Fetch current chezmoi docs via the context7
  MCP when unsure about syntax or API.
- **Zsh** — Oh My Zsh + Starship prompt. `bash` runs scripts and `just` recipes.
- **just** — task runner (`justfile`). Requires `gum`, `nlx`, `shellcheck`, and `shfmt` on `PATH` (declared via
  `require()`).
- **Prettier** — formats Markdown/YAML. **ShellCheck** + **shfmt** lint and format shell.
- **Gitleaks** — scans the current tree and Git history for committed secrets.
- **1Password CLI** (`op`) — secret injection in templates via `onepasswordRead`.
- **Homebrew** — provisions packages.

## Commands

Run `just` recipes from the chezmoi source directory (`chezmoi cd`).

| Recipe                | Alias | Action                                                |
| --------------------- | ----- | ----------------------------------------------------- |
| `just`                | —     | List recipes                                          |
| `just apply`          | `a`   | `op signin`, then `chezmoi apply`                     |
| `just sync [msg]`     | —     | Commit, push, then signin + apply                     |
| `just full-check`     | `fc`  | Run all formatting, static, and regression checks     |
| `just prettier-check` | `pc`  | Prettier `--check` over `**/*.{md,yaml,yml}`          |
| `just prettier-write` | `pw`  | Prettier `--write` over `**/*.{md,yaml,yml}`          |
| `just shell-check`    | `sc`  | ShellCheck (`-x`) + `shfmt -d` over all shell scripts |
| `just shell-write`    | `sw`  | `shfmt -w` over all shell scripts                     |

### chezmoi

- `chezmoi apply` — apply the source state to `$HOME`
- `chezmoi diff` — preview pending changes
- `chezmoi edit <file>` — edit the source of a target file
- `chezmoi cd` — open a shell in the source directory
- `chezmoi update` — pull the repo and apply

**Apply proactively, scoped to what changed.** After editing source-state files, apply without waiting for a request. Do
not default to a blanket `chezmoi apply`. Scope the apply to the files you just changed:

- For 1-3 apply-eligible files (not ignored by `.chezmoiignore.tmpl`), run `chezmoi apply --source-path <path>...` from
  the source directory.
- For more than 3 apply-eligible files, run plain `chezmoi apply`.
- If no changed file is apply-eligible, skip the apply.

Use the correct path type. `--source-path` takes source-relative paths (e.g. `dot_config/prb/agents.sh`). `chezmoi diff`
and bare `chezmoi apply` take target paths (e.g. `~/.config/prb/agents.sh`). Do not chain `chezmoi diff <source-path>`
after an `apply --source-path`. It fails with `not managed`.

### Provisioning

- macOS: `~/.setup/tools_macos.sh` (Homebrew)

### Validation (before committing)

- `just full-check` — Prettier, plist validation, ShellCheck, shfmt, TOML formatting, and regression tests
- `gitleaks git --redact --no-banner --no-color` — scan current files and Git history for secrets
- `op signin --account "${OP_ACCOUNT:-my.1password.com}"`, then `chezmoi apply --dry-run --verbose` (or `chezmoi diff`)
  — confirm a clean apply

## Project Structure

chezmoi source-state naming (source name → target):

- `dot_<x>` → `~/.x`
- `<x>.tmpl` → templated with Go template syntax
- `executable_<x>` → target gets the executable bit
- `symlink_<x>` → target is a symlink
- `run_onchange_<x>.sh` → re-run on `chezmoi apply` when the script's contents change

Layout:

| Path                                    | Purpose                                                            |
| --------------------------------------- | ------------------------------------------------------------------ |
| `dot_zshrc.tmpl`                        | Main Zsh bootstrap (→ `~/.zshrc`)                                  |
| `dot_zshenv`                            | Early XDG defaults. Prepends `~/.local/bin` to `PATH`              |
| `dot_config/prb/`                       | Custom shell modules (→ `~/.config/prb/`)                          |
| `dot_config/prb/bin/`                   | Shell utilities, added to `PATH`                                   |
| `dot_config/prb/aliases/`, `functions/` | Sourced alias and function modules                                 |
| `dot_config/iterm2/`                    | Selected iTerm2 settings overlay (macOS, merged into global prefs) |
| `dot_setup/`                            | Provisioning scripts (→ `~/.setup/`, added to `PATH`)              |
| `dot_setup/packages.sh`                 | Shared package manifest — source of truth                          |
| `dot_setup/lib/common.sh`               | Shared setup helpers                                               |
| `dot_setup/run_onchange_*`              | chezmoi hooks (biome, dutix, uv tools, completions, …)             |
| `.chezmoiignore.tmpl`                   | Development-file exclusions and macOS guard                        |
| `justfile`                              | Task runner                                                        |

### Shell Startup Order

1. `~/.zshenv` — set XDG base dirs. Prepend `~/.local/bin`.
2. `~/.config/prb/env_core.sh` — path-critical env (sourced first in `.zshrc`).
3. `~/.config/prb/path.sh` — build `PATH` (adds `~/.config/prb/bin`, `~/.setup`, and macOS paths).
4. Tracked modules, in order: `agents.sh`, `aliases.sh`, `web3.sh`, `functions.sh`, `gh.sh`, `env_session.sh`,
   `shims.sh`.
5. Oh My Zsh, then tool init: zoxide, fnm, atuin, fzf, Starship (last).

`~/.config/prb/load_env.sh` remains a compatibility wrapper for manual sourcing. The boot path uses `env_core.sh` before
`path.sh`.

## macOS Patterns

### Tool installation

- [`dot_setup/packages.sh`](dot_setup/packages.sh) — package manifest, **source of truth**.
- [`dot_setup/executable_tools_macos.sh`](dot_setup/executable_tools_macos.sh) — Homebrew installer.

Keep the installer thin. Source `packages.sh` rather than duplicating lists. Add tools alphabetically to the appropriate
category in `MACOS_FORMULAE`, `MACOS_CASKS`, or `MACOS_TAPS`.

### Clipboard

Shell functions and Git aliases use the native macOS `pbcopy` and `pbpaste` commands.

### LaunchAgents, sleep and wake hooks, and local HTTPS

The items below live in `~/projects/circadian` (GitHub `PaulRBerg/circadian`), not in this repository:

- Every `local.*` LaunchAgent.
- The sleepwatcher hooks.
- The Caddyfile for the named `*.localhost` apps.
- The launchd dashboard at `https://circadian.localhost`.

That repository installs its own plists with `just deploy`. Follow its `AGENTS.md`. This repository only provisions the
tools those agents need (`caddy`, `sleepwatcher`, `smartmontools`, Bun) and the shell modules some of them source
(`env_core.sh`, `path.sh`, `functions/dev.sh`). Do not add LaunchAgents or `run_onchange` launchctl hooks here.

### iTerm2 settings (macOS only)

iTerm2 uses its normal global preferences domain (`com.googlecode.iterm2`). Do not point iTerm2 at the chezmoi
source-state folder as a custom settings folder. iTerm rewrites that plist during normal GUI use.

Track only selected settings in `dot_config/iterm2/managed.plist`. The macOS apply hook
`dot_setup/run_onchange_setup_iterm2_macos.sh.tmpl` exports the current iTerm2 defaults, merges the managed overlay into
them, imports the result, and disables custom-folder loading. The live prefs file
`dot_config/iterm2/com.googlecode.iterm2.plist` is intentionally ignored. You should not add it again.

## Managed App Settings (partial overlays)

Some apps own their settings files and rewrite them whenever you change preferences through their GUI. If chezmoi
tracked the full file, `chezmoi apply` would overwrite legitimate GUI changes, and the app would overwrite ours. For
these apps, we do not manage the whole file.

We commit a small overlay of only the settings we always want enforced. An apply hook merges that overlay onto the app's
live settings. The overlay wins. This restores our preferences after GUI drift, a reinstall, or changes to app defaults,
while leaving every other setting the app manages unchanged. The live settings file stays untracked.

App managed this way:

- **iTerm2** (macOS) — overlay `dot_config/iterm2/managed.plist`, merged into the `com.googlecode.iterm2` defaults
  domain by `dot_setup/run_onchange_setup_iterm2_macos.sh.tmpl` (via the `dot_setup/executable_merge_iterm2_prefs.py`
  helper). See the iTerm2 subsection above. The live prefs `dot_config/iterm2/com.googlecode.iterm2.plist` are ignored
  in `.chezmoiignore.tmpl`.

When adding another such app, use the same structure: a committed overlay of just the settings to enforce, plus a
`run_*` apply hook that merges it onto the app's live file.

## 1Password Integration

Fetch secrets in templates with `onepasswordRead`:

```sh
{{ onepasswordRead "op://Vault/Item/field" }}
```

See `dot_config/prb/load_env_macos.sh.tmpl` for examples. The chezmoi config at `~/.config/chezmoi/chezmoi.toml` uses
account auth:

- `mode = "account"` — interactive 1Password CLI (`op signin`). Use for local development.
- `prompt = false` — skips chezmoi's own `op signin` prompt and relies on the 1Password desktop-app CLI integration
  (Touch ID). Enable it in 1Password -> Settings -> Developer.

`just apply` and `just sync` handle 1Password auth before running `chezmoi apply`. For direct `chezmoi` or `op`
commands, unlock the 1Password desktop app, then authenticate the shell explicitly:

```sh
export OP_ACCOUNT="${OP_ACCOUNT:-my.1password.com}"
eval "$(op signin --account "$OP_ACCOUNT")"
op whoami --account "$OP_ACCOUNT"
```

Use the same preflight before any shell command that loads 1Password data (`op read`, `op item get`,
`chezmoi execute-template`, `chezmoi diff`, `chezmoi apply`). `op signin` is idempotent with the desktop-app
integration. It only prompts when the shell is not already authenticated. If multiple accounts are available, prefer
`--account` or `OP_ACCOUNT` over relying on the most recently signed-in terminal.

`op signin` cannot persist across new shells in the normal env-var sense. When the CLI emits shell code,
`eval "$(op signin ...)"` sets an `OP_SESSION` token only in the current shell. That token expires after inactivity. Do
not put `OP_SESSION` tokens or `eval "$(op signin ...)"` in shell startup files.

If this remains annoying, future work should use either option below:

- Fix true 1Password desktop-app integration so `op` authenticates through the app without session-token exports.
- Switch back to service-account mode with `OP_SERVICE_ACCOUNT_TOKEN` for noninteractive `chezmoi apply`.

If `chezmoi apply` prompts for the account password, check the 1Password desktop-app CLI integration before changing the
repo back to service-account mode.

Review secret-backed and machine-specific templates before applying on a new machine:
`dot_config/prb/load_env_macos.sh.tmpl`, `aliases/locations.sh`, `path_macos.sh`, `agents.sh`, and `web3.sh`.

## Secrets

- Never commit raw secrets, tokens, passwords, private keys, recovery phrases, session tokens, or rendered secret-backed
  templates. This includes `OP_SESSION`, `OP_SERVICE_ACCOUNT_TOKEN`, SSH/GPG private keys, npm tokens, GitHub tokens,
  API keys, wallet keys, and mnemonics.
- Store secret values in 1Password and reference them with `onepasswordRead`, runtime keychain reads, or documented
  environment interpolation. Only commit references, variable names, and documented setup commands.
- Keep secret scans and debugging output redacted. Do not paste rendered template output, command traces, diffs, logs,
  or scanner findings that include the secret value itself.
- If a secret may have been exposed, take these steps:
  - Treat it as compromised.
  - First, revoke or rotate it.
  - Then remove it from the current tree and history as needed, and rerun
    `gitleaks git --redact --no-banner --no-color`.

## Code Style

- **Shell**: `shfmt` + ShellCheck (`.shellcheckrc`). Run `just shell-write` then `just shell-check`. Recipes execute
  under `bash -euo pipefail`.
- **Markdown/YAML**: Prettier (`.prettierrc.yml`: `printWidth: 120`, `proseWrap: always`). Wrap prose at 120 columns.
- **Templates**: use chezmoi Go template syntax for machine data and secrets. macOS code needs no per-OS branch.
- Standalone shell scripts use `.sh` (or `.sh.tmpl` for chezmoi templates). Preserve required extensionless entry points
  with chezmoi `symlink_*` files. Shell startup files and Zsh completion definitions retain their conventional names.
  Non-shell scripts retain their language extensions.
- Name shell functions in snake_case with underscores, never hyphens (e.g. `clean_dev_caches`). ZLE widgets keep zsh's
  hyphenated `*-widget` convention.
- Order package lists alphabetically.

## Conventions

- `dot_setup/packages.sh` is the single source of truth for packages. Edit it before the installer scripts.
- **Gum spin gotcha**: `gum spin -- <cmd>` spawns a subprocess via Go's `exec.Command`, which only finds executables on
  `$PATH`. It cannot find shell functions. Call the executable directly.

  ```sh
  # Bad — _my_helper is a shell function, gum can't find it
  gum spin --spinner dot --title "Working..." -- _my_helper "$@"

  # Good — call the executable directly
  gum spin --spinner dot --title "Working..." -- claude --print "$@"
  ```

## Contribution Workflow

- Default branch: `main`. `just sync` commits and pushes directly to `main` (personal repo, no PR flow), then runs
  `chezmoi apply`.
- Run `just full-check` before committing and fix any reported findings.
- Once a coherent unit of work passes `just full-check`, run `just sync` proactively. Do not ask first. Do not stop at
  "here's the command to run". Unless you want the recipe's `ccc` helper to generate a message, pass an explicit one
  (`just sync "<msg>"`).
- **Guard first**: `just sync` runs `git add -A`, so it sweeps the entire working tree. Before running it, check
  `git status --porcelain` and confirm every dirty path is one you edited this session. If anything unrelated is dirty,
  do **not** run `just sync`. It is likely another agent's work in progress. Instead, commit and push only your own
  files:

  ```sh
  git add <files you edited>
  git commit -m "<msg>"
  git push origin main
  ```

  Then apply manually per the bullet below. Say plainly that you skipped `just sync` because of unrelated dirty paths.

- After committing and pushing without `just sync`, apply per the scoped-apply rule in the chezmoi section under
  Commands above.
- There is no CI. Validation is local only.
- Claude Code reads `AGENTS.md` directly. Do not add a `CLAUDE.md`.
