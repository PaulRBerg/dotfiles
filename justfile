set allow-duplicate-variables
set allow-duplicate-recipes
set shell := ["bash", "-euo", "pipefail", "-c"]
set unstable

# ---------------------------------------------------------------------------- #
#                                 DEPENDENCIES                                 #
# ---------------------------------------------------------------------------- #

# Gum: https://github.com/charmbracelet/gum
gum := require("gum")

# Ni: https://github.com/antfu-collective/ni
nlx := require("nlx")

# ShellCheck: https://github.com/koalaman/shellcheck
shellcheck := require("shellcheck")

# shfmt: https://github.com/mvdan/sh
shfmt := require("shfmt")

# ---------------------------------------------------------------------------- #
#                                  CONSTANTS                                   #
# ---------------------------------------------------------------------------- #

# Backticks use /bin/sh (not `set shell`), so bash's globstar isn't available.
# Use fd to find .sh and .sh.tmpl files, then append non-extension matches.
GLOBS_SHELL := `fd -e sh -e sh.tmpl . | tr '\n' ' ' && echo dot_bashrc dot_zshrc.tmpl`

# ---------------------------------------------------------------------------- #
#                                    SCRIPTS                                   #
# ---------------------------------------------------------------------------- #

# Show available commands
@default:
    just --list

# Apply changes to the root directory using chezmoi
@apply:
    chezmoi apply
alias a := apply

# Sync dotfiles and apply changes
[script("bash")]
sync msg="":
    git add -A
    # Only commit if there are staged changes
    if ! git diff --cached --quiet; then
        if [[ -z "{{ msg }}" ]]; then
            USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/prb"
            source "${USER_DIR}/agents.sh"
            ccc
        else
            git commit -m "{{ msg }}"
        fi
        git push origin main
    else
        echo "No changes to commit"
    fi
    gum spin --spinner dot --title "Applying dotfiles..." -- chezmoi apply --force

# ---------------------------------------------------------------------------- #
#                                    CHECKS                                    #
# ---------------------------------------------------------------------------- #

# Run all checks (chezmoi, prettier, shellcheck, shfmt)
[group("checks")]
full-check:
    just prettier-check
    just shell-check
alias fc := full-check

# Check Prettier formatting
[group("checks")]
@prettier-check:
    nlx prettier --check "**/*.{md,yaml,yml}"
alias pc := prettier-check

# Format using Prettier
[group("checks")]
@prettier-write:
    nlx prettier --write "**/*.{md,yaml,yml}"
alias pw := prettier-write

# Check shell scripts with ShellCheck and shfmt
[group("checks")]
@shell-check:
    shellcheck -x {{ GLOBS_SHELL }}
    shfmt -d {{ GLOBS_SHELL }}
alias sc := shell-check

# Format shell scripts with shfmt
[group("checks")]
@shell-write:
    shfmt -w {{ GLOBS_SHELL }}
alias sw := shell-write
