typeset -U path PATH

for candidate in "$HOME/.local/bin" "$HOME/bin"; do
  if [[ -d "$candidate" ]]; then
    path=("$candidate" $path)
  fi
done

if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
if [[ -d "$PYENV_ROOT/bin" ]]; then
  path=("$PYENV_ROOT/bin" $path)
fi

if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init - zsh)"
fi

if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

export VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
if [[ -f "$VCPKG_ROOT/scripts/vcpkg_completion.zsh" ]]; then
  autoload -Uz bashcompinit
  bashcompinit
  source "$VCPKG_ROOT/scripts/vcpkg_completion.zsh"
fi
