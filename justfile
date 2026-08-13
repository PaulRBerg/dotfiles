set allow-duplicate-variables
set allow-duplicate-recipes
set shell := ["bash", "-euo", "pipefail", "-c"]
set unstable

export RUST_LOG := "warn"

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
[script("bash")]
apply:
    OP_ACCOUNT="${OP_ACCOUNT:-my.1password.com}"
    signin_output="$(op signin --account "$OP_ACCOUNT")"
    [[ -z "$signin_output" ]] || eval "$signin_output"
    OP_ACCOUNT="$OP_ACCOUNT" chezmoi apply
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
    OP_ACCOUNT="${OP_ACCOUNT:-my.1password.com}"
    signin_output="$(op signin --account "$OP_ACCOUNT")"
    [[ -z "$signin_output" ]] || eval "$signin_output"
    OP_ACCOUNT="$OP_ACCOUNT" gum spin --spinner dot --title "Applying dotfiles..." -- chezmoi apply --force

# ---------------------------------------------------------------------------- #
#                                    CHECKS                                    #
# ---------------------------------------------------------------------------- #

# Run all checks (prettier, plist, shellcheck, shfmt, toml)
[group("checks")]
full-check:
    just prettier-check
    just plist-check
    just shell-check
    just toml-format-check
alias fc := full-check

# Format files with project formatters
[group("checks")]
full-write:
    just prettier-write
    just plist-write
    just shell-write
    just toml-format-write
alias fw := full-write

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
        nlx
        nvim
        prettier
        shellcheck
        shfmt
        taplo
        zsh
    )
    if [[ "$(uname -s)" == "Darwin" ]]; then
        required+=(difft)
        required+=(plutil)
    else
        required+=(plistutil)
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
    chezmoi doctor || status=1

    echo
    echo "== chezmoi dry-run apply =="
    chezmoi apply --dry-run --verbose || status=1

    echo
    echo "== rendered shell templates =="
    check_rendered() {
        local file="$1"
        local shell_bin="$2"
        local rendered

        rendered=$(mktemp)
        if chezmoi execute-template <"$file" >"$rendered"; then
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
    echo "== plist =="
    just plist-check || status=1

    echo
    echo "== shell-check =="
    just shell-check || status=1

    echo
    echo "== toml-format =="
    just toml-format-check || status=1

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

# Check plist syntax and canonical XML formatting
[group("checks")]
@plist-check:
    PLIST_MODE=check just _plist
alias plc := plist-check

# Format plist files as canonical XML
[group("checks")]
@plist-write:
    PLIST_MODE=write just _plist
alias plw := plist-write

# Run plist check/write implementation
[group("checks")]
[private]
[script("bash")]
_plist:
    mode="${PLIST_MODE:-}"
    case "$mode" in
    check | write) ;;
    *)
        echo "unknown plist mode: $mode" >&2
        exit 1
        ;;
    esac

    formatter=""
    if command -v plutil >/dev/null 2>&1; then
        formatter=plutil
    elif command -v plistutil >/dev/null 2>&1; then
        formatter=plistutil
    else
        echo "missing plist formatter: install Xcode Command Line Tools (plutil) or libplist-utils (plistutil)" >&2
        exit 1
    fi

    status=0
    found=0
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    format_plist() {
        local file="$1"
        local output="$2"

        case "$formatter" in
        plutil)
            plutil -convert xml1 -o "$output" "$file"
            ;;
        plistutil)
            plistutil -i "$file" -f xml -o "$output"
            ;;
        esac
    }

    while IFS= read -r -d '' file; do
        found=1
        case "$mode" in
        check)
            if [[ "$formatter" == "plutil" ]] && ! plutil -lint "$file" >/dev/null; then
                status=1
                continue
            fi

            tmp=$(mktemp "$tmpdir/plist.XXXXXX")
            if ! format_plist "$file" "$tmp"; then
                status=1
                continue
            fi
            if ! cmp -s "$file" "$tmp"; then
                printf 'needs format  %s\n' "$file" >&2
                status=1
            fi
            ;;
        write)
            case "$formatter" in
            plutil)
                plutil -convert xml1 "$file" || status=1
                ;;
            plistutil)
                tmp=$(mktemp "$tmpdir/plist.XXXXXX")
                if plistutil -i "$file" -f xml -o "$tmp"; then
                    cp "$tmp" "$file"
                else
                    status=1
                fi
                ;;
            esac
            ;;
        esac
    done < <(fd -HI -0 -e plist .)

    if ((found == 0)); then
        echo "No plist files found"
    fi
    exit "$status"

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

# Check TOML formatting
[group("checks")]
@toml-format-check:
    taplo format --check
alias tfc := toml-format-check

# Format TOML files in place
[group("checks")]
@toml-format-write:
    taplo format
alias tfw := toml-format-write
