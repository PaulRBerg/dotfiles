---
argument-hint: <tool-name>
name: chezmoi-add-tool
description: Add a new dependency to the macOS tool installation manifest
---

Add the tool "$1" to the macOS package manifest. This repository supports macOS only; the historical Ubuntu setup is
preserved on `archive/ubuntu-2026-10-05`.

**Instructions:**

1. **Read the manifest and installer** to understand their structure and categorization: `dot_setup/packages.sh` and
   `dot_setup/executable_tools_macos.sh` (paths relative to the repository root).

2. **Determine the appropriate category** for the tool:
   - Core utilities
   - Modern CLI tools
   - File and archive utilities
   - Development tools
   - Image and media
   - Other utilities

3. **Add the tool alphabetically** within its category in `MACOS_FORMULAE` or `MACOS_CASKS` in `dot_setup/packages.sh`.
   Keep the installer thin; do not duplicate package lists there.

4. **Handle special cases**:
   - If the tool requires a Homebrew tap, add it to `MACOS_TAPS` in the manifest.
   - If the tool needs symlinks or custom setup, add them in the appropriate installer section.

5. **Validate the changes**:

   ```bash
   just shell-check
   ```

6. **Check macOS installation**:
   - Verify the Homebrew package name and availability.
   - Confirm the installer supports a fresh macOS setup.

**Example Usage:**

- `/chezmoi-add-tool ripgrep`
- `/chezmoi-add-tool duti`

## Completion

Report the added package, changed files, and validation results. State whether installation was run or only configured.
