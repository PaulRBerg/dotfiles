#!/usr/bin/env bash

alias docker-compose="docker compose"
alias e="\${EDITOR}"
alias mkdir="mkdir -p"
alias now="date +\"%Y-%m-%dT%H:%M:%S%z\""
alias ports="sudo lsof -iTCP -sTCP:LISTEN -n -P"
alias reload="exec \${SHELL} -l" # reload the shell (i.e. invoke as a login shell)
alias sudo="sudo "               # enable aliases to be sudo'ed
alias v="\${VISUAL}"

# Intuitive map function
# For example, to list all directories that contain a certain file:
# find . -name .gitattributes | map dirname
alias map="xargs -n1"

###############################################################################
# CLI                                                                         #
###############################################################################

alias g="git"
alias j="just"
alias ls='eza $eza_params'
command -v btm &>/dev/null && alias top='btm'
command -v duf &>/dev/null && alias df='duf'

###############################################################################
# NAVIGATION                                                                  #
###############################################################################

alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ~="cd ~" # `cd` is probably faster to type though
alias -- -="cd -"

###############################################################################
# IP                                                                          #
###############################################################################

alias ip="dig +short myip.opendns.com @resolver1.opendns.com"
