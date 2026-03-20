---
name: zsh-completions
description: Add custom zsh completions for a tool.
argument-hint: <tool-name>
---

Add or update completions for the tool "$1".

Basics:

- Zsh loads completions from directories in `fpath` via `compinit`.
- Oh My Zsh adds `$ZSH_CUSTOM/completions` and enabled plugin directories to `fpath` before `compinit`.

Steps:

1. Find or generate the completion script.

   If the tool supports it, generate a zsh completion file, for example:

   ```bash
   $1 completion zsh > _${1}
   ```

2. Choose a placement strategy.

   Option A: custom completions directory (no plugin needed):

   ```bash
   mkdir -p "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions"
   mv _${1} "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions/_${1}"
   ```

   Option B: custom plugin (useful if you want `plugins=(...)` control):

   ```bash
   mkdir -p "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/${1}"
   mv _${1} "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/${1}/_${1}"
   ```

   Add `${1}` to the `plugins=(...)` list in your `.zshrc` if you use Option B.

3. Reload completions.

   ```bash
   rm -f "$ZSH_COMPDUMP"
   exec zsh
   ```

Notes:

- Completion files must be named `_${tool}` to be discovered.
- If the tool has no generator, write `_tool` manually using zsh completion functions.
