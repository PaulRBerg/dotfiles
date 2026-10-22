# direnv
command -v direnv >/dev/null && eval "$(direnv hook zsh)"

# rbenv
command -v rbenv >/dev/null && eval "$(rbenv init - "${SHELL##*/}")"

# ssh-agent
if [[ -z "$SSH_AUTH_SOCK" ]] && [[ -f ~/.ssh/github/key.pem ]]; then
  eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/github/key.pem
fi
