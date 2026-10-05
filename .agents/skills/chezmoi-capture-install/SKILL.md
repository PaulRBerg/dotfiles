---
argument-hint: <install-command>
disable-model-invocation: true
name: chezmoi-capture-install
user-invocable: true
description:
  Capture global dotfile changes made by a CLI installer into the chezmoi source, then commit. Use after an installer
  (curl pipe to sh, npm -g, brew, etc.) edits shell rc files or PATH. Pass the install command as the argument. The
  skill runs it and diffs what changed. It ports only the durable edits into the chezmoi source templates, confirms
  anything ambiguous, then commits.
---

# chezmoi-capture-install

Run a CLI installer. Identify its changes to the global dotfiles. Integrate the durable changes into the chezmoi source
for macOS, and commit. The argument `$ARGUMENTS` is the full install command, e.g.
`curl -fsSL https://pi.dev/install.sh | sh`.

Operate from the chezmoi source directory (`chezmoi cd`). chezmoi manages the target dotfiles, so its own
`status`/`diff` tells you precisely which managed files the installer changed. This is the primary detector.

## Workflow

### 1. Baseline

- From the source directory, run `chezmoi status` and `chezmoi diff`. Note any pre-existing differences in shell-init
  files to distinguish installer changes from drift after installation.
- Snapshot the rc/config files that installers commonly change so you can also diff unmanaged edits:
  ```bash
  snap=$(mktemp -d)
  for f in ~/.zshrc ~/.zshenv ~/.zprofile ~/.bashrc ~/.bash_profile ~/.profile ~/.config/fish/config.fish; do
    [ -f "$f" ] && cp "$f" "$snap/$(echo "$f" | tr '/' '_')"
  done
  ```

### 2. Run the installer

Execute `$ARGUMENTS` exactly as given. Capture stdout. Installers usually print which file they edited and what they
appended (PATH line, `source` line, etc.). Treat that output as the first clue, not the source of truth.

### 3. Detect what changed

- **Managed files**: run `chezmoi status`. For each modified target, run `chezmoi diff <target>`. This is the common
  case. chezmoi manages `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, and `~/.bashrc` here. The added lines are the
  installer's edits.
- **Unmanaged files**: diff the live files against the snapshot and look for new tool directories or binaries the
  installer created (e.g. `~/.foo/bin/foo`):
  ```bash
  for f in ~/.zshrc ~/.zshenv ~/.zprofile ~/.bashrc ~/.bash_profile ~/.profile ~/.config/fish/config.fish; do
    [ -f "$f" ] && diff "$snap/$(echo "$f" | tr '/' '_')" "$f"
  done
  ```

### 4. Decide what belongs in chezmoi

Copy the intended behavior, not literal lines. Repository-specific rules:

- **PATH additions** → add a home-relative entry to [`dot_config/prb/path.sh.tmpl`](dot_config/prb/path.sh.tmpl) using
  the existing `add_path "$HOME/.tool/bin"` idiom (Cross-Machine section, or `path_macos.sh` for Homebrew and macOS
  tools). Do **not** copy raw `export PATH=...` lines. Never include an absolute `/Users/<user>` path or a
  version-pinned directory (e.g. an fnm `node-versions/vX.Y.Z` bin). Those paths break on another machine or after a
  version bump.
- **Other rc edits** (shell init, `source` lines, completions) → copy the intended behavior into the matching source
  template. Resolve it with `chezmoi source-path <target>` (e.g. `~/.zshrc` → `dot_zshrc.tmpl`). The repository supports
  macOS only. No OS guard is needed.
- **New config files worth tracking** → `chezmoi add <file>` (ask first — see step 5).
- **Redundant or fragile edits** → omit them. If the tool is already reachable, the installer's line is unnecessary.
  This includes tools already on PATH via an existing block or exposed by a version manager like fnm/asdf without an rc
  edit. Discard the line with `chezmoi apply --force <target>` so the managed file matches source again. In that case,
  there is nothing to commit.
- **Secrets** (tokens, keys the installer wrote into a config) → never commit the value. Reference it via
  `onepasswordRead` or env interpolation per the repo's secrets policy.

### 5. Confirm when anything is ambiguous

If any condition below applies, stop and ask the user before changing source:

- The edit conflicts with existing config.
- The edit contains a secret.
- The edit pins a version or absolute path.
- The right target template is unclear.
- You cannot tell whether to track a new file.

Otherwise, proceed.

### 6. Validate

- Run `just full-check` (Prettier + ShellCheck + shfmt). If you only changed shell, run `just shell-check`.
- Render-check the changed source: `chezmoi apply --source-path <path>...` (1–3 files) or `chezmoi apply` (more), and
  `chezmoi apply --force <target>` for any managed file the installer touched, to reconcile it with the new source.

### 7. Commit

Invoke `/commit` to stage and commit the chezmoi source changes. Add `--push` only if the user asks.

## Completion

Report the captured changes, validation and apply results, and commit outcome. Identify any unresolved installer
changes.
