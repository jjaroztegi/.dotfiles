# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input must stay above this block.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_THEME="robbyrussell"

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

alias tmux-sessionizer="bash $HOME/scripts/tmux-sessionizer.sh"

if [[ -d "$HOME/.config/zsh/rc.d" ]]; then
  for rc_file in "$HOME"/.config/zsh/rc.d/*.zsh(N); do
    source "$rc_file"
  done
fi
