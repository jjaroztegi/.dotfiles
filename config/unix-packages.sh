#!/usr/bin/env bash

DOTFILES_BREW_TAPS=(
)

DOTFILES_BREW_FORMULAE_COMMON=(
  git
  zsh
  tmux
  fzf
  btop
  jq
  ripgrep
  fd
  fnm
  pyenv
)

DOTFILES_BREW_FORMULAE_MACOS=(
  openssl@3
  qt@5
)

DOTFILES_BREW_CASKS_MACOS=(
  visual-studio-code
)

DOTFILES_APT_PACKAGES_COMMON=(
  build-essential
  ca-certificates
  curl
  file
  git
  zsh
  tmux
  fzf
  btop
  jq
  ripgrep
  fd-find
  xclip
  wl-clipboard
)

DOTFILES_APT_PACKAGES_LINUX=(
  python3-pip
)
