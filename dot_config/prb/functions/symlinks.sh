#!/usr/bin/env bash

###############################################################################
# SYMLINKS                                                                    #
###############################################################################

# Replace a symlink with a copy of its target, then symlink the target back
function deref() {
  local link="${1-}"
  local link_dir link_abs raw_target target_path target_abs
  local backup_dir backup_link

  if [[ -z "$link" ]]; then
    echo "❌ Symlink path not provided" >&2
    return 1
  fi
  if [[ ! -L "$link" || ! -e "$link" ]]; then
    echo "❌ Expected a non-dangling symlink: $link" >&2
    return 1
  fi

  link_dir="$(cd "$(dirname "$link")" && pwd -P)" || return 1
  link_abs="$link_dir/$(basename "$link")"
  raw_target="$(readlink "$link_abs")" || return 1
  if [[ "$raw_target" = /* ]]; then
    target_path="$raw_target"
  else
    target_path="$link_dir/$raw_target"
  fi
  target_abs="$(grealpath -e "$target_path")" || return 1
  if [[ ! -e "$target_abs" ]]; then
    echo "❌ Symlink target does not exist: $target_abs" >&2
    return 1
  fi
  if [[ -d "$target_abs" && "$link_abs/" == "$target_abs/"* ]]; then
    echo "❌ Cannot dereference a link contained by its target: $link_abs" >&2
    return 1
  fi

  backup_dir="$(mktemp -d "$link_dir/.deref.XXXXXX")" || return 1
  backup_link="$backup_dir/original-link"

  if ! command mv "$link_abs" "$backup_link"; then
    command rmdir "$backup_dir" 2>/dev/null || true
    echo "❌ Failed to preserve the original symlink" >&2
    return 1
  fi
  if ! command mv "$target_abs" "$link_abs"; then
    command mv "$backup_link" "$link_abs" 2>/dev/null || true
    command rmdir "$backup_dir" 2>/dev/null || true
    echo "❌ Failed to move the symlink target; original link restored" >&2
    return 1
  fi

  if ! command ln -s "$link_abs" "$target_abs"; then
    if [[ ! -e "$target_abs" && ! -L "$target_abs" ]] &&
      command mv "$link_abs" "$target_abs" &&
      command mv "$backup_link" "$link_abs"; then
      command rmdir "$backup_dir" 2>/dev/null || true
      echo "❌ Failed to create the reverse symlink; original state restored" >&2
    else
      echo "❌ Failed to create the reverse symlink and fully roll back; original link is at $backup_link" >&2
    fi
    return 1
  fi

  command rm "$backup_link"
  command rmdir "$backup_dir"
  printf '📋 Dereferenced: \033[36m%s\033[0m ← %s\n' "$link_abs" "$target_abs"
}

function is_symlink() {
  local show_path=false
  local target_path=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --path | -p)
      show_path=true
      shift
      ;;
    *)
      target_path="$1"
      shift
      ;;
    esac
  done

  if [[ -z "$target_path" ]]; then
    echo "Please provide a path"
    return 1
  fi

  if [[ -L "$target_path" ]]; then
    echo "✅ Yes"
    if [[ "$show_path" == true ]]; then
      readlink "$target_path"
    fi
  else
    echo "❌ No"
  fi
}

# Symlink utility with two modes:
#   1. Info mode:     symlink <path>          - Check if a path is a symlink and show its target
#   2. Creation mode: symlink <link> <target> - Create <link> as a new relative symlink to <target>
#
# Uses relative paths for portability (symlinks work even if parent dirs move).
# Uses grealpath from Homebrew coreutils.
function symlink() {
  local link_path="${1-}"   # In info mode: path to check. In creation mode: where the symlink will be created
  local link_target="${2-}" # Only in creation mode: the file/dir the symlink will point to

  # Expand tilde to $HOME (handles cases where tilde isn't shell-expanded)
  link_path="${link_path/#\~/$HOME}"
  [[ -n "$link_target" ]] && link_target="${link_target/#\~/$HOME}"

  # Validate the link path is provided
  if [[ -z "$link_path" ]]; then
    echo "❌ Path not provided, aborting"
    return 1
  fi

  # Helper to convert a path to absolute (even if it doesn't exist yet).
  abs_path() {
    local p="$1"

    grealpath -m "$p"
  }

  # Helper to convert absolute path to relative path from a base directory.
  # This ensures symlinks use relative paths for better portability.
  abs_to_rel() {
    local absolute="$1"
    local base_dir="${2:-$(pwd)}"

    # macOS: use grealpath from GNU coreutils (brew install coreutils)
    grealpath -m --relative-to="$base_dir" "$absolute"
  }

  # INFO MODE: When only one argument is given, inspect the path
  if [[ -z "$link_target" ]]; then
    if [[ -L "$link_path" ]]; then
      # The path is a symlink - show where it points
      echo "🔗 Path $link_path is a symlink"
      local current_target="$(readlink "$link_path")"
      # Convert absolute link targets to relative for cleaner display
      if [[ "$current_target" = /* ]]; then
        current_target="$(abs_to_rel "$current_target")"
      fi
      echo "👉 $current_target"
    else
      # The path exists but is not a symlink (regular file/directory)
      echo "📄 Path $link_path isn't a symlink"
    fi
    return
  fi

  # CREATION MODE: When two arguments are given, create a new symlink

  # Safety check: refuse to overwrite existing files or symlinks
  if [[ -e "$link_path" || -L "$link_path" ]]; then
    echo "❌ Target already exists: $link_path"
    echo "💡 Delete it first to create a new symlink"
    return 1
  fi

  # Resolve the target to an absolute path, then convert to relative from the link's dir.
  # This handles cases where the target is given as relative or contains symlinks.
  local link_dir_abs="$(abs_path "$(dirname "$link_path")")"
  local target_abs="$(abs_path "$link_target")"
  local relative_target="$(abs_to_rel "$target_abs" "$link_dir_abs")"

  if [[ -z "$relative_target" ]]; then
    echo "❌ Failed to resolve symlink target: $link_target"
    return 1
  fi

  ln -s "$relative_target" "$link_path"

  echo "✅ Symlink created: $link_path -> $relative_target"
}

# Create CLAUDE.md symlinks pointing to AGENTS.md files in every directory
# that contains an AGENTS.md. Useful for tools that look for CLAUDE.md.
function symlink_agents_md() {
  echo "Finding AGENTS.md files..."
  while IFS= read -r agents_file; do
    local dir=$(dirname "$agents_file")
    local claude_file="$dir/CLAUDE.md"
    if [[ -L "$claude_file" ]] && [[ "$(readlink "$claude_file")" == "AGENTS.md" ]]; then
      echo "✓ Skip: $claude_file (already linked)"
      continue
    fi
    if [[ -e "$claude_file" ]]; then
      echo "⚠ Replace: $claude_file (removing regular file)"
      rm "$claude_file"
    fi
    ln -s AGENTS.md "$claude_file"
    echo "✓ Created: $claude_file → AGENTS.md"
  done < <(fd -t f "^AGENTS\.md$" .)
  echo "Done!"
}
