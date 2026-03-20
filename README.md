# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://chezmoi.io/). The tracked repo includes the full default shell
setup, including personal aliases, machine-specific paths, secret-backed env templates, and helper functions.

## Installation

### macOS

```bash
brew install chezmoi
chezmoi init --apply YOUR_USERNAME/dotfiles
~/.setup/tools_macos.sh
```

### Ubuntu

```bash
# Run from the chezmoi source directory after cloning/init
./bootstrap_ubuntu.sh
```

## Before You Apply

Review these tracked files first if you are using this repo on a different machine or account:

- `dot_config/prb/load_env_macos.sh.tmpl`
- `dot_config/prb/load_env_linux.sh.tmpl`
- `dot_config/prb/aliases_locations.sh`
- `dot_config/prb/path_macos.sh`
- `dot_config/prb/agents.sh`
- `dot_config/prb/web3.sh`

## Shell Layout

Core Zsh startup order:

1. `~/.zshenv` sets early XDG defaults.
2. `~/.config/prb/env_core.sh` exports path-critical env.
3. `~/.config/prb/path.sh` builds `PATH`, including `~/.config/prb/bin`.
4. Tracked modules load: `agents.sh`, `aliases.sh`, `web3.sh`, `functions.sh`, `gh.sh`, `env_session.sh`, `shims.sh`.
5. Oh My Zsh and tool initialization run.

`~/.config/prb/load_env.sh` remains as a compatibility wrapper for manual sourcing; the boot path uses `env_core.sh`
before `path.sh`, then loads the tracked session modules.

## Key Files

| File                                   | Purpose                            |
| -------------------------------------- | ---------------------------------- |
| `dot_zshrc.tmpl`                       | Main Zsh bootstrap                 |
| `dot_config/prb/env_core.sh.tmpl`      | Core environment shared by startup |
| `dot_config/prb/env_session.sh.tmpl`   | Interactive/session environment    |
| `dot_config/prb/path.sh.tmpl`          | PATH assembly                      |
| `dot_config/prb/aliases.sh.tmpl`       | Alias loader for tracked aliases   |
| `dot_config/prb/functions.sh`          | Shared shell function entrypoint   |
| `dot_setup/lib/common.sh`              | Shared setup helpers               |
| `dot_setup/packages.sh`                | Package manifest source of truth   |
| `dot_setup/executable_tools_macos.sh`  | Homebrew provisioning              |
| `dot_setup/executable_tools_ubuntu.sh` | Ubuntu APT/Snap provisioning       |

## Package Management

Package definitions live in `dot_setup/packages.sh`. Installer scripts should source that file instead of owning their
own lists. Keep cross-platform tools aligned there first, then handle package-manager-specific repos/taps in the thin
installer wrappers.

Ubuntu provisioning now installs the tools needed for repo validation, including `shellcheck` and `shfmt`.

## Clipboard

Portable `pbcopy` and `pbpaste` shims now live under `~/.config/prb/bin`. Shell functions and git aliases use those
commands directly, so clipboard workflows work on macOS and Linux without shell aliases.

## Common Operations

```bash
chezmoi apply
chezmoi diff
chezmoi update

just apply
just sync [msg]
just full-check
just shell-check
just shell-write
```

## Validation

Run these before committing:

```bash
just full-check
chezmoi apply --dry-run --verbose
```

On Ubuntu, run `~/.setup/tools_ubuntu.sh` first so the local validation toolchain exists.

## Cross-Platform Notes

- macOS-only assets are excluded via `.chezmoiignore.tmpl`.
- `localip` is now a shell function instead of a platform-specific alias.
- Clipboard operations now go through portable `pbcopy` / `pbpaste` shims in `~/.config/prb/bin`.
- Review tracked secret templates before applying on a different machine.
