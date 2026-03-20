#!/usr/bin/env bash
# shellcheck disable=SC2034

MACOS_TAPS=(
  bramstein/webfonttools
)

MACOS_FORMULAE=(
  # Core utilities
  bash
  bash-completion2
  coreutils
  findutils
  grep

  # Modern CLI tools
  atuin
  bat
  bats-core
  bottom
  duf
  eza
  gum
  just
  killport
  lazygit
  procs
  ripgrep
  starship
  zoxide

  # File and archive utilities
  moreutils
  p7zip
  pigz
  pv
  rename
  tree

  # Development tools
  gh
  git
  git-lfs
  jq
  ls-lint
  lua
  rlwrap
  shellcheck
  shfmt
  uv
  vim

  # Image and media
  ffmpeg
  gs
  lynx
  pngquant
  sfnt2woff
  sfnt2woff-zopfli
  woff2
  zopfli

  # Other utilities
  ack
  cloc
  duti
  gmp
  gnu-sed
  gnupg
  openssh
  pinentry-mac
  screen
  sleepwatcher
  ssh-copy-id
  tmux
  wget
  yq
  zellij
)

UBUNTU_APT_PACKAGES=(
  # Core utilities
  bash
  bash-completion
  coreutils
  findutils
  grep
  xsel

  # Modern CLI tools
  ripgrep
  fd-find
  bat
  bats
  fzf
  git-delta
  zoxide

  # File and archive utilities
  p7zip-full
  pigz
  pv
  rename
  moreutils
  rsync
  tree

  # Development tools
  direnv
  gh
  git
  git-lfs
  jq
  just
  shellcheck
  shfmt
  vim

  # Image and media
  lynx

  # Other utilities
  cloc
  curl
  gnupg
  python3
  python3-pip
  screen
  sqlite3
  tmux
  wget
)

UBUNTU_SNAP_PACKAGES=(
  bottom
  duf
  procs
  yq
)

UBUNTU_CLASSIC_SNAP_PACKAGES=(
  gum
)
