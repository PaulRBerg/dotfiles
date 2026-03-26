# Development Instructions

AI agents working on this dotfiles repository should follow these guidelines.

## Most Important Thing

**Maintain cross-platform compatibility between macOS and Linux.** All changes must work correctly after `chezmoi init`
and subsequent `chezmoi apply` on both platforms. Test changes on both operating systems when possible.

## Repository Purpose

PRB's reusable dotfiles managed with [chezmoi](https://chezmoi.io/). These dotfiles provide a consistent shell
environment, aliases, functions, and tooling across macOS and Linux systems.

**Note**: When in doubt about chezmoi syntax or API, use the context7 MCP to fetch the latest chezmoi documentation.

## Cross-Platform Patterns

### Chezmoi Templates

Use chezmoi template syntax for platform-specific code:

```sh
{{- if eq .chezmoi.os "darwin" }}
# macOS-specific code
pbcopy
{{- else if eq .chezmoi.os "linux" }}
# Linux-specific code
xclip -selection clipboard
{{- end }}
```

### Ubuntu Bootstrap

The Ubuntu bootstrap script is `bootstrap_ubuntu.sh` (kept in the repo root and ignored by chezmoi). Run it once on a
fresh Ubuntu installation from the chezmoi source dir; it installs snapd + chezmoi, then initializes and applies the
dotfiles.

### Tool Installation Scripts

- [`dot_setup/executable_tools_macos.sh`](dot_setup/executable_tools_macos.sh): Homebrew packages for macOS
- [`dot_setup/executable_tools_ubuntu.sh`](dot_setup/executable_tools_ubuntu.sh): APT/Snap packages for Ubuntu
- [`dot_setup/packages.sh`](dot_setup/packages.sh): shared package manifest/source of truth

**Keep `dot_setup/packages.sh` as the source of truth.** The installer scripts should stay thin and platform-specific,
while package additions and removals happen in the shared manifest first.

When adding tools:

1. Add to the appropriate category (alphabetically)
2. If cross-platform, ensure equivalent packages in both files
3. Note package name differences (e.g., `bat` on macOS vs `bat` installed as `batcat` on Ubuntu)

## 1Password Integration

Use `onepasswordRead` in templates to fetch secrets:

```sh
{{ onepasswordRead "op://Vault/Item/field" }}
```

See `dot_config/prb/load_env_macos.sh.tmpl` for examples.

The chezmoi config at `~/.config/chezmoi/chezmoi.toml` controls the 1Password mode:

- `mode = "account"` — uses the interactive 1Password CLI (`op signin`). Use this for local development.
- `mode = "service"` — requires `OP_SERVICE_ACCOUNT_TOKEN` in the environment. Use this for CI/automation.

If `chezmoi apply` fails with `onepassword.mode is service, but OP_SERVICE_ACCOUNT_TOKEN is not set`, either set the
token or switch the mode to `"account"`.

## Shell Startup Order

See [`dot_zshrc.tmpl`](dot_zshrc.tmpl) for the complete startup order.

## Just Recipes

```bash
just apply            # Apply chezmoi (alias: a)
just sync [msg]       # Git commit + chezmoi apply (uses ccc if no msg)
just full-check       # Run all checks (alias: fc)
just prettier-check   # Check Prettier formatting (alias: pc)
just prettier-write   # Format with Prettier (alias: pw)
just shell-check      # Validate shell scripts (alias: sc)
just shell-write      # Auto-format shell scripts (alias: sw)
```

## Validation

Run validation before committing:

```bash
just shell-check  # Validate shell scripts with ShellCheck and shfmt
just shell-write  # Auto-format shell scripts
```

## Key Files

- `dot_*.tmpl`: Template files using chezmoi syntax
- `dot_setup/executable_*.sh`: Installation and configuration scripts
- `justfile`: Task runner with validation recipes
- `.chezmoiignore.tmpl`: Files to ignore during chezmoi apply

## Common Operations

```bash
chezmoi apply        # Apply dotfiles
chezmoi diff         # Preview changes
chezmoi edit <file>  # Edit source file
chezmoi cd           # Navigate to source directory
```
