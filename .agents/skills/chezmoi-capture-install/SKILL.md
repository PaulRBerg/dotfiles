---
argument-hint: <install-command>
disable-model-invocation: true
name: chezmoi-capture-install
user-invocable: true
description:
  Capture global dotfile changes made by a CLI installer into the chezmoi source, then commit. Use after an installer
  (curl pipe to sh, npm -g, brew, etc.) edits shell rc files or PATH. Pass the install command as the argument; the
  skill runs it, diffs what changed, ports only the portable edits into the chezmoi source templates, confirms anything
  ambiguous, then commits.
---

# chezmoi-capture-install

Run a CLI installer, figure out what it changed in the global dotfiles, fold the durable parts into the chezmoi source
(portably), and commit. The argument `$ARGUMENTS` is the full install command, e.g.
`curl -fsSL https://pi.dev/install.sh | sh`.

Operate from the chezmoi source directory (`chezmoi cd`). chezmoi manages the target dotfiles, so its own
`status`/`diff` tells you precisely which managed files the installer touched — that is the primary detector.

## Workflow

### 1. Baseline

- From the source dir, run `chezmoi status` and `chezmoi diff`. Note any pre-existing divergence in shell-init files so
  post-install changes are attributable to the installer, not to drift.
- Snapshot the rc/config files installers commonly touch so unmanaged edits are diffable too:
  ```bash
  snap=$(mktemp -d)
  for f in ~/.zshrc ~/.zshenv ~/.zprofile ~/.bashrc ~/.bash_profile ~/.profile ~/.config/fish/config.fish; do
    [ -f "$f" ] && cp "$f" "$snap/$(echo "$f" | tr '/' '_')"
  done
  ```

### 2. Run the installer

Execute `$ARGUMENTS` exactly as given. Capture stdout — installers usually print which file they edited and what they
appended (PATH line, `source` line, etc.). Treat that output as the first clue, not the source of truth.

### 3. Detect what changed

- **Managed files** (the common case — `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.bashrc` are all managed here): run
  `chezmoi status`; for each modified target run `chezmoi diff <target>`. The added lines are the installer's edits.
- **Unmanaged files**: diff the live files against the snapshot, and look for new tool dirs/binaries the installer
  dropped (e.g. `~/.foo/bin/foo`):
  ```bash
  for f in ~/.zshrc ~/.zshenv ~/.zprofile ~/.bashrc ~/.bash_profile ~/.profile ~/.config/fish/config.fish; do
    [ -f "$f" ] && diff "$snap/$(echo "$f" | tr '/' '_')" "$f"
  done
  ```

### 4. Decide what belongs in chezmoi

Port intent, not literal lines. Repo-specific rules:

- **PATH additions** → add a portable entry to [`dot_config/prb/path.sh.tmpl`](dot_config/prb/path.sh.tmpl) using the
  existing `add_path "$HOME/.tool/bin"` idiom (Cross-Machine section, or an OS section if platform-specific). Do **not**
  copy raw `export PATH=...` lines, and never bake in an absolute `/Users/<user>` path or a version-pinned directory
  (e.g. an fnm `node-versions/vX.Y.Z` bin) — those break on another machine or after a version bump.
- **Other rc edits** (shell init, `source` lines, completions) → port into the matching source template. Resolve it with
  `chezmoi source-path <target>` (e.g. `~/.zshrc` → `dot_zshrc.tmpl`). Gate OS-specifics with
  `{{ if eq .chezmoi.os "darwin" }} … {{ end }}`.
- **New config files worth tracking** → `chezmoi add <file>` (ask first — see step 5).
- **Redundant or fragile edits** → drop them. If the tool is already reachable (already on PATH via an existing block,
  or exposed by a version manager like fnm/asdf without an rc edit), the installer's line is noise. Discard it with
  `chezmoi apply --force <target>` so the managed file matches source again. Nothing to commit in that case.
- **Secrets** (tokens, keys the installer wrote into a config) → never commit the value; reference it via
  `onepasswordRead` or env interpolation per the repo's secrets policy.

### 5. Confirm when anything is ambiguous

Stop and ask the user before changing source if any of these hold: the edit conflicts with existing config, it carries a
secret, it is platform-specific and you are unsure which OS guard applies, it pins a version or absolute path, the right
target template is unclear, or you cannot tell whether a new file should be tracked. Otherwise proceed.

### 6. Validate

- `just full-check` (Prettier + ShellCheck + shfmt); `just shell-check` if you only touched shell.
- Render-check the changed source: `chezmoi apply --source-path <path>...` (1–3 files) or `chezmoi apply` (more), and
  `chezmoi apply --force <target>` for any managed file the installer touched, to reconcile it with the new source.

### 7. Commit

Invoke `/commit` to stage and commit the chezmoi source changes. Add `--push` only if the user asks.
