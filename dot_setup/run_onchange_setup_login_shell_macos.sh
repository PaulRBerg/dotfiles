#!/usr/bin/env bash
# Enforce the login shell. macOS sets this in Directory Services (not a dotfile),
# so chezmoi can only converge it via this run_onchange_ script.
#
# macOS only: the _macos.sh suffix matches the `*macos.sh` rule in
# .chezmoiignore.tmpl, so chezmoi skips this entirely on Linux.
# shellcheck disable=SC2034  # SCRIPT_NAME is consumed by common.sh's LOG_PREFIX

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# run_onchange_ scripts execute from a temp dir, so source from the installed path
source "$HOME/.setup/lib/common.sh"

# Apple's /bin/zsh: always present, always in /etc/shells, survives OS updates.
# Interactive sessions still resolve Homebrew zsh via PATH regardless of this.
readonly DESIRED_SHELL="/bin/zsh"

current_shell="$(dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}')"

if [[ "$current_shell" == "$DESIRED_SHELL" ]]; then
  exit 0
fi

if [[ ! -x "$DESIRED_SHELL" ]]; then
  log_error "$DESIRED_SHELL not found or not executable; leaving shell as $current_shell"
  exit 0
fi

if ! grep -qxF "$DESIRED_SHELL" /etc/shells; then
  log_error "$DESIRED_SHELL is not listed in /etc/shells; add it before changing shell"
  exit 0
fi

log_info "Changing login shell: $current_shell → $DESIRED_SHELL"
if chsh -s "$DESIRED_SHELL"; then
  log_success "Login shell set to $DESIRED_SHELL (open a new terminal to take effect)"
else
  log_error "chsh failed; login shell unchanged"
fi

exit 0
