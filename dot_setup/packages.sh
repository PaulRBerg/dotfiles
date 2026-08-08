#!/usr/bin/env bash
# shellcheck disable=SC2034

MACOS_TAPS=(
  bramstein/webfonttools
  jackchuka/tap
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
  difftastic
  dua-cli
  duf
  eza
  fd
  fnm
  fzf
  git-delta
  glow
  gum
  hurl
  hyperfine
  jless
  just
  killport
  lazygit
  mprocs
  procs
  ripgrep
  starship
  tealdeer
  television
  tokei
  ugrep
  vivid
  watchexec
  xh
  yazi
  zoxide

  # File and archive utilities
  moreutils
  p7zip
  pigz
  pv
  qpdf
  rename
  tree

  # Development tools
  direnv
  gh
  git
  git-absorb
  git-lfs
  gitleaks
  golangci-lint
  jq
  ls-lint
  lua
  mergiraf
  neovim
  pnpm
  rlwrap
  ruby # gem runtime for run_onchange_setup_ruby_gems.sh
  shellcheck
  shfmt
  sqlite-utils
  uv
  vim

  # Image and media
  ffmpeg
  gs
  img2pdf
  lynx
  ocrmypdf
  pngquant
  poppler # provides pdftotext
  sfnt2woff
  sfnt2woff-zopfli
  tesseract-lang
  woff2
  zopfli

  # Other utilities
  ack
  cloc
  dutix
  gmp
  gnu-sed
  gnupg
  mac-cleanup-go
  openssh
  pinentry-mac
  screen
  sleepwatcher
  smartmontools
  ssh-copy-id
  tmux
  wget
  yq
  zellij
)

MACOS_CASKS=(
  # Browsers
  ungoogled-chromium

  # Quick Look extensions
  qlmarkdown
  syntax-highlight
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
  bat
  bats
  fd-find
  fzf
  git-delta
  hyperfine
  ripgrep
  tealdeer
  zoxide

  # File and archive utilities
  libplist-utils
  moreutils
  p7zip-full
  pigz
  pv
  qpdf
  rename
  rsync
  tree

  # Development tools
  direnv
  gh
  git
  git-absorb
  git-lfs
  jq
  just
  neovim
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
