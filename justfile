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
    chezmoi-service apply
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
    gum spin --spinner dot --title "Applying dotfiles..." -- chezmoi-service apply --force

# ---------------------------------------------------------------------------- #
#                                    CHECKS                                    #
# ---------------------------------------------------------------------------- #

# Run all checks (chezmoi, prettier, shellcheck, shfmt)
[group("checks")]
full-check:
    just prettier-check
    just shell-check
alias fc := full-check

# Run local health checks for this chezmoi source tree
[group("checks")]
[script("bash")]
doctor:
    status=0

    echo "== required commands =="
    missing=0
    required=(
        chezmoi
        delta
        direnv
        fd
        fnm
        fzf
        git
        git-absorb
        gum
        just
        chezmoi-service
        nlx
        nvim
        prettier
        shellcheck
        shfmt
        zsh
    )
    if [[ "$(uname -s)" == "Darwin" ]]; then
        required+=(difft)
    fi
    for cmd in "${required[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf 'ok  %s\n' "$cmd"
        else
            printf 'missing  %s\n' "$cmd" >&2
            missing=1
        fi
    done
    if [[ "$(uname -s)" != "Darwin" ]]; then
        if command -v difft >/dev/null 2>&1; then
            printf 'ok  %s\n' difft
        else
            printf 'optional  %s (not in standard Ubuntu apt)\n' difft
        fi
    fi
    if ((missing != 0)); then
        exit 1
    fi

    echo
    echo "== PATH duplicates =="
    duplicates=$(zsh -i -c 'print -rl -- $path' | awk 'NF { seen[$0]++ } END { for (path in seen) if (seen[path] > 1) print path }' | sort)
    if [[ -n "$duplicates" ]]; then
        echo "$duplicates" >&2
        status=1
    else
        echo "ok"
    fi

    echo
    echo "== chezmoi doctor =="
    chezmoi-service doctor || status=1

    echo
    echo "== chezmoi dry-run apply =="
    chezmoi-service apply --dry-run --verbose || status=1

    echo
    echo "== rendered shell templates =="
    check_rendered() {
        local file="$1"
        local shell_bin="$2"
        local rendered

        rendered=$(mktemp)
        if chezmoi-service execute-template <"$file" >"$rendered"; then
            if "$shell_bin" -n "$rendered"; then
                printf 'ok  %s\n' "$file"
            else
                status=1
            fi
        else
            printf 'skip  %s (template render failed)\n' "$file" >&2
        fi
        rm -f "$rendered"
    }

    while IFS= read -r -d '' file; do
        check_rendered "$file" bash
    done < <(fd -0 -e sh.tmpl .)
    check_rendered dot_zshrc.tmpl zsh
    check_rendered dot_zshenv zsh
    check_rendered dot_zprofile zsh
    check_rendered dot_bashrc bash

    echo
    echo "== prettier =="
    just prettier-check || status=1

    echo
    echo "== shell-check =="
    just shell-check || status=1

    exit "$status"
alias d := doctor

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
