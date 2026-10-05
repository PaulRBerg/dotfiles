# Dotfiles

[![Managed with chezmoi](https://img.shields.io/badge/managed%20with-chezmoi-18a303)](https://chezmoi.io)
![Platform](https://img.shields.io/badge/platform-macOS-555)

macOS dotfiles managed with [chezmoi](https://chezmoi.io): Zsh, aliases, functions, helper utilities, secret-backed env
templates, and tooling.

The last dual macOS/Ubuntu setup is preserved on
[`archive/ubuntu-2026-10-05`](https://github.com/PaulRBerg/dotfiles/tree/archive/ubuntu-2026-10-05). Ubuntu provisioning
and its setup instructions live on that frozen branch; `main` supports macOS only.

## Links

- [chezmoi](https://chezmoi.io) — the dotfile manager this repo is built on

## Setting Up a New Machine

The order below matters. Several pieces depend on each other (the brew manifest does not install `chezmoi` or the
1Password CLI, the first `chezmoi apply` renders 1Password-backed templates and runs hooks that need brew-installed
tools, and the applied `.zshrc` assumes Oh My Zsh is already present), so following the steps out of order leads to
chicken-and-egg failures.

### macOS

**Prerequisites** — install these by hand before touching the repo:

1. **Xcode Command Line Tools** (provides `git`): `xcode-select --install`
2. **Homebrew**: install from [brew.sh](https://brew.sh), then `eval "$(/opt/homebrew/bin/brew shellenv)"` in the
   current shell.
3. **1Password app + CLI** (neither is in the brew manifest): `brew install --cask 1password 1password-cli`. Open the
   app, sign in, and enable **Settings → Developer → Integrate with 1Password CLI** (Touch ID). Required because
   `chezmoi apply` renders templates with `onepasswordRead`.
4. **GitHub SSH key**: only the public key is tracked (`dot_ssh/github/key.pub`). Restore the passphrase-protected
   private key from your secure backup to `~/.ssh/github/key.pem` and `chmod 600` it. Until then, GitHub access over SSH
   does not work — use HTTPS URLs as a fallback. Store its passphrase in the macOS login keychain once, so the
   `local.ssh-load-keychain` LaunchAgent (from `PaulRBerg/circadian`, step 6) can load the key at every login without
   prompting. Git uses this local key for both GitHub authentication and SSH commit signing; neither operation invokes
   1Password.

   ```sh
   /usr/bin/ssh-add --apple-use-keychain ~/.ssh/github/key.pem
   ```

   Apple's `ssh-add` is required here: Homebrew OpenSSH has no `--apple-*` flags and ignores `UseKeychain` in
   `~/.ssh/config`. Skip this and every reboot leaves the agent empty, which blocks non-interactive `git` over SSH.

**Setup** — now bootstrap the dotfiles:

1. Install chezmoi and pull the source tree (it lands in `~/.local/share/chezmoi`):

   ```sh
   brew install chezmoi
   chezmoi init git@github.com:PaulRBerg/dotfiles.git
   ```

2. Install the CLI toolset **before** the first apply — the apply hooks hard-require some of these tools (e.g. `dutix`).
   Run the installer straight from the source tree:

   ```sh
   bash ~/.local/share/chezmoi/dot_setup/executable_tools_macos.sh
   ```

3. Install Oh My Zsh **into the XDG location** the tracked `.zshrc` expects (`~/.local/share/oh-my-zsh`, not the
   installer's default), plus the three custom plugins:

   ```sh
   export ZSH="$HOME/.local/share/oh-my-zsh"
   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
   git clone https://github.com/Aloxaf/fzf-tab "$ZSH/custom/plugins/fzf-tab"
   git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH/custom/plugins/zsh-autosuggestions"
   git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH/custom/plugins/zsh-syntax-highlighting"
   ```

4. Review the secret-backed and machine-specific templates (see [`AGENTS.md`](AGENTS.md)), then sign in to 1Password and
   apply. Do **not** start with `just apply` — the justfile requires tools that are not all installed yet:

   ```sh
   export OP_ACCOUNT="my.1password.com"
   eval "$(op signin --account "$OP_ACCOUNT")"
   chezmoi apply
   ```

5. Open a **new terminal** so the applied Zsh setup loads, then provision Node.js, bun, and the global JS CLIs (`nlx`
   from this step is required by the `justfile`):

   ```sh
   fnm_bump_node
   ```

6. Optional, recommended:
   - macOS defaults (Dock, Finder, input, etc.): `~/.setup/configure_macos_defaults.sh`
   - iTerm2 (not in the brew manifest): `brew install --cask iterm2` — the apply hook merges the selected settings from
     `dot_config/iterm2/managed.plist` into iTerm2's normal macOS preferences domain.
   - Agent configs: `git clone git@github.com:PaulRBerg/dot-claude.git ~/.claude` and
     `git clone git@github.com:PaulRBerg/dot-agents.git ~/.agents`
   - Shell history sync: `atuin login`
   - LaunchAgents, sleep and wake hooks, and local HTTPS:
     `git clone git@github.com:PaulRBerg/circadian.git ~/projects/circadian`, then `just install && just deploy` there.
     Run `caddy trust` once (sudo prompt) so browsers accept Caddy's local CA.

7. Verify everything: `chezmoi cd && just doctor` — checks required commands, PATH health, a dry-run apply, rendered
   templates, and lint.

## Contributing

This is a personal dotfiles repository, but fixes and suggestions are welcome. See [`AGENTS.md`](AGENTS.md) for the
development workflow, commands, and conventions.

## License

Licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
