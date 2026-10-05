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
  caddy # local HTTPS reverse proxy for *.localhost (local.caddy LaunchAgent)
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
  taplo
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
