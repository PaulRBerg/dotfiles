# Development Instructions

Guidelines for AI agents and developers working on this dotfiles repository.

## Most Important Thing

**Maintain cross-platform compatibility between macOS and Linux.** Every change must work after `chezmoi init` and a
subsequent `chezmoi apply` on both platforms. Test on both when possible.

## Stack

- **chezmoi** — dotfile manager; source state uses Go templates (`.tmpl`). Fetch current chezmoi docs via the context7
  MCP when unsure about syntax or API.
- **Zsh** — Oh My Zsh + Starship prompt. `bash` runs scripts and `just` recipes.
- **just** — task runner (`justfile`). Requires `gum`, `nlx`, `shellcheck`, and `shfmt` on `PATH` (declared via
  `require()`).
- **Prettier** — formats Markdown/YAML. **ShellCheck** + **shfmt** lint and format shell.
- **1Password CLI** (`op`) — secret injection in templates via `onepasswordRead`.
- **Homebrew** (macOS) / **APT + Snap** (Ubuntu) — package provisioning.

## Commands

Run `just` recipes from the chezmoi source directory (`chezmoi cd`).

| Recipe                | Alias | Action                                                                  |
| --------------------- | ----- | ----------------------------------------------------------------------- |
| `just`                | —     | List recipes                                                            |
| `just apply`          | `a`   | `chezmoi apply`                                                         |
| `just sync [msg]`     | —     | `git add -A`, commit (uses `ccc` if no msg), push to `main`, then apply |
| `just full-check`     | `fc`  | Run `prettier-check` then `shell-check`                                 |
| `just prettier-check` | `pc`  | Prettier `--check` over `**/*.{md,yaml,yml}`                            |
| `just prettier-write` | `pw`  | Prettier `--write` over `**/*.{md,yaml,yml}`                            |
| `just shell-check`    | `sc`  | ShellCheck (`-x`) + `shfmt -d` over all shell scripts                   |
| `just shell-write`    | `sw`  | `shfmt -w` over all shell scripts                                       |

### chezmoi

- `chezmoi apply` — apply the source state to `$HOME`
- `chezmoi diff` — preview pending changes
- `chezmoi edit <file>` — edit the source of a target file
- `chezmoi cd` — open a shell in the source directory
- `chezmoi update` — pull the repo and apply

### Provisioning

- macOS: `~/.setup/tools_macos.sh` (Homebrew)
- Ubuntu: `~/.setup/tools_ubuntu.sh` (APT/Snap); also installs `shellcheck` and `shfmt` for local validation
- Fresh Ubuntu: run `./bootstrap_ubuntu.sh` once from the source dir — installs snapd + chezmoi, then runs init + apply

### Validation (before committing)

- `just full-check` — Prettier + ShellCheck + shfmt
- `chezmoi apply --dry-run --verbose` (or `chezmoi diff`) — confirm a clean apply

## Project Structure

chezmoi source-state naming (source name → target):

- `dot_<x>` → `~/.x`
- `<x>.tmpl` → templated with Go template syntax
- `executable_<x>` → target gets the executable bit
- `symlink_<x>` → target is a symlink
- `run_onchange_<x>.sh` → re-run on `chezmoi apply` when the script's contents change

Layout:

| Path                                    | Purpose                                                |
| --------------------------------------- | ------------------------------------------------------ |
| `dot_zshrc.tmpl`                        | Main Zsh bootstrap (→ `~/.zshrc`)                      |
| `dot_zshenv`                            | Early XDG defaults; prepends `~/.local/bin` to `PATH`  |
| `dot_config/prb/`                       | Custom shell modules (→ `~/.config/prb/`)              |
| `dot_config/prb/bin/`                   | Portable shims (`pbcopy`/`pbpaste`), added to `PATH`   |
| `dot_config/prb/aliases/`, `functions/` | Sourced alias and function modules                     |
| `dot_setup/`                            | Provisioning scripts (→ `~/.setup/`, added to `PATH`)  |
| `dot_setup/packages.sh`                 | Shared package manifest — source of truth              |
| `dot_setup/lib/common.sh`               | Shared setup helpers                                   |
| `dot_setup/run_onchange_*`              | chezmoi hooks (biome, dutix, uv tools, completions, …) |
| `.chezmoiignore.tmpl`                   | Per-OS exclusions during apply                         |
| `bootstrap_ubuntu.sh`                   | Fresh-Ubuntu bootstrap (repo root; ignored by chezmoi) |
| `justfile`                              | Task runner                                            |

### Shell Startup Order

1. `~/.zshenv` — set XDG base dirs; prepend `~/.local/bin`.
2. `~/.config/prb/env_core.sh` — path-critical env (sourced first in `.zshrc`).
3. `~/.config/prb/path.sh` — build `PATH` (adds `~/.config/prb/bin`, `~/.setup`, and per-OS paths).
4. Tracked modules, in order: `agents.sh`, `aliases.sh`, `web3.sh`, `functions.sh`, `gh.sh`, `env_session.sh`,
   `shims.sh`.
5. Oh My Zsh, then tool init: zoxide, fnm, atuin (macOS), fzf, Starship (last).

`~/.config/prb/load_env.sh` remains a compatibility wrapper for manual sourcing; the boot path uses `env_core.sh` before
`path.sh`.

## Cross-Platform Patterns

### chezmoi templates

Gate platform-specific code with template conditionals:

```sh
{{- if eq .chezmoi.os "darwin" }}
# macOS-specific code
pbcopy
{{- else if eq .chezmoi.os "linux" }}
# Linux-specific code
xclip -selection clipboard
{{- end }}
```

### Tool installation

- [`dot_setup/packages.sh`](dot_setup/packages.sh) — shared manifest, **source of truth**.
- [`dot_setup/executable_tools_macos.sh`](dot_setup/executable_tools_macos.sh) — Homebrew packages.
- [`dot_setup/executable_tools_ubuntu.sh`](dot_setup/executable_tools_ubuntu.sh) — APT/Snap packages.

Keep installers thin and platform-specific; source `packages.sh` rather than duplicating lists. When adding tools:

1. Add to the right category (alphabetically) in `packages.sh` first.
2. Ensure equivalent packages in both installers if cross-platform.
3. Note package-name differences (e.g. `bat` on macOS vs `batcat` on Ubuntu).

### Clipboard

Portable `pbcopy`/`pbpaste` shims live in `dot_config/prb/bin/` (on `PATH`). Shell functions and git aliases call them
directly, so clipboard workflows work on macOS and Linux without per-OS aliases.

## 1Password Integration

Fetch secrets in templates with `onepasswordRead`:

```sh
{{ onepasswordRead "op://Vault/Item/field" }}
```

See `dot_config/prb/load_env_macos.sh.tmpl` for examples. The default chezmoi config at `~/.config/chezmoi/chezmoi.toml`
uses service-account auth:

- `mode = "service"` — requires `OP_SERVICE_ACCOUNT_TOKEN` in the environment.
- `chezmoi-service` — loads `OP_SERVICE_ACCOUNT_TOKEN` from macOS Keychain, then execs `chezmoi`.

Use `just apply` or `chezmoi-service apply` for local runs. If raw `chezmoi apply` fails with
`onepassword.mode is service, but OP_SERVICE_ACCOUNT_TOKEN is not set`, export the token explicitly or use the wrapper.
On macOS, set it from Keychain for one command:

```sh
OP_SERVICE_ACCOUNT_TOKEN="$(security find-generic-password -a "$USER" -s chezmoi-op-service-account-token -w)" chezmoi apply
```

If the Keychain item is missing, seed it once after unlocking 1Password:

```sh
token="$(op read --no-newline 'op://Keys/1Password Service Account - Chezmoi/credential')"
security add-generic-password -a "$USER" -s chezmoi-op-service-account-token -w "$token" -U
unset token
```

Review secret-backed and machine-specific templates before applying on a new machine:
`dot_config/prb/load_env_macos.sh.tmpl`, `load_env_linux.sh.tmpl`, `aliases/locations.sh`, `path_macos.sh`, `agents.sh`,
and `web3.sh`.

## Code Style

- **Shell**: `shfmt` + ShellCheck (`.shellcheckrc`). Run `just shell-write` then `just shell-check`. Recipes execute
  under `bash -euo pipefail`.
- **Markdown/YAML**: Prettier (`.prettierrc.yml`: `printWidth: 120`, `proseWrap: always`). Wrap prose at 120 columns.
- **Templates**: chezmoi Go template syntax; gate OS-specific blocks with `{{ if eq .chezmoi.os ... }}`.
- Order package lists alphabetically.

## Conventions

- `dot_setup/packages.sh` is the single source of truth for packages — edit it before the installer scripts.
- **Gum spin gotcha**: `gum spin -- <cmd>` spawns a subprocess via Go's `exec.Command`, which only finds executables on
  `$PATH`. Shell functions are invisible to it — call the executable directly.

  ```sh
  # Bad — _my_helper is a shell function, gum can't find it
  gum spin --spinner dot --title "Working..." -- _my_helper "$@"

  # Good — call the executable directly
  gum spin --spinner dot --title "Working..." -- claude --print "$@"
  ```

## Contribution Workflow

- Default branch: `main`. `just sync` commits and pushes directly to `main` (personal repo; no PR flow).
- Run `just full-check` before committing and fix any Prettier / ShellCheck / shfmt findings.
- No CI — validation is local only.
- `CLAUDE.md` is a symlink to `AGENTS.md`; both paths resolve to this file. Edit `AGENTS.md` directly.
