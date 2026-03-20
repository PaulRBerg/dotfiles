---
name: chezmoi-add-tool
description: Add a new dependency to tool installation scripts
argument-hint: <tool-name> [--macos|--ubuntu]
---

Add the tool "$1" to the appropriate installation script(s).

**OS Targeting:**

- If `$2` is `--macos`: Add only to [dot_setup/executable_tools_macos.sh](dot_setup/executable_tools_macos.sh)
- If `$2` is `--ubuntu`: Add only to [dot_setup/executable_tools_ubuntu.sh](dot_setup/executable_tools_ubuntu.sh)
- If `$2` is empty: Add to **both** scripts (cross-platform tool)

**Instructions:**

1. **Read both tool scripts** to understand their structure and categorization

2. **Determine the appropriate category** for the tool:
   - Core utilities
   - Modern CLI tools
   - File and archive utilities
   - Development tools
   - Image and media
   - Other utilities

3. **Add the tool alphabetically** within its category:
   - macOS: Add to the `formulae=()` array
   - Ubuntu: Add to the `packages=()` array in `install_apt_packages()`
   - Note: Package names may differ between platforms (e.g., `fd-find` on Ubuntu vs `fd` on macOS)

4. **Handle special cases**:
   - If the tool requires a tap/PPA, add repository setup before the package installation
   - If the tool needs symlinks, add them in the appropriate section
   - Document any platform-specific differences

5. **Validate the changes**:

   ```bash
   just shell-check
   ```

6. **Cross-platform compatibility check**:
   - Ensure the tool is available on the target platform(s)
   - Verify package names are correct for each platform
   - Confirm the scripts will execute successfully on fresh installs

**Example Usage:**

- `/add-tool ripgrep` (adds to both platforms)
- `/add-tool duti --macos` (macOS-only utility)
- `/add-tool xclip --ubuntu` (Linux-only utility)
