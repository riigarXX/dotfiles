eval "$(starship init zsh)"

# opencode
export PATH=/Users/alvaro.lopez/.opencode/bin:$PATH

# EDITOR
export EDITOR=nvim
export VISUAL=nvim

# ALIASES BÁSICOS PARA DESARROLLO
alias ls='lsd'
alias ll='lsd'
alias lsa='lsd -la'
alias lst='eza -T'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias grep='rg'
alias find='fd'
alias cat='bat'

alias reload='source ~/.zshrc'
alias zshrc='nvim ~/.zshrc'

# ALIASES PARA NEOVIM
alias vim='nvim'
alias v='nvim'
alias vi='nvim'
alias nvimrc='nvim ~/.config/nvim/init.lua'

# ALIASES PARA GIT
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gcan='git commit --amend --no-edit'
alias gs='git status'
alias gst='git status'
alias gd='git diff'
alias gdc='git diff --cached'
alias gl='git log --oneline --decorate --graph'
alias gla='git log --oneline --decorate --graph --all'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gf='git fetch'
alias gfa='git fetch --all'
alias gpl='git pull'
alias gplr='git pull --rebase'
alias gb='git branch'
alias gba='git branch -a'
alias gco='git checkout'
alias gsw='git switch'
alias gswc='git switch -c'
alias gm='git merge'
alias gr='git reset'
alias grh='git reset HEAD'
alias grhh='git reset HEAD --hard'
alias gcp='git cherry-pick'
alias gstp='git stash push'
alias gstp='git stash pop'
alias gstl='git stash list'
alias gstd='git stash drop'

# NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# PYENV (Python Version Manager) - Instalar con: curl https://pyenv.run | bash
# export PYENV_ROOT="$HOME/.pyenv"
# export PATH="$PYENV_ROOT/bin:$PATH"
# eval "$(pyenv init --path)"
# eval "$(pyenv init -)"
# eval "$(pyenv virtualenv-init -)"

# ALIASES PARA DOCKER
alias d='docker'
alias dc='docker compose'
alias dcu='docker compose up'
alias dcub='docker compose up --build'
alias dcd='docker compose down'
alias dcl='docker compose logs'
alias dclf='docker compose logs -f'
alias dcr='docker compose restart'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias drm='docker rm'
alias drmi='docker rmi'
alias dex='docker exec -it'
alias dlogs='docker logs'
alias dlogsf='docker logs -f'

# PATHS ADICIONALES PARA HERRAMIENTAS
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"

# CONFIGURACIONES ADICIONALES
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# HISTORY CONFIG
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt share_history

# FUNCIONES ÚTILES PARA DESARROLLO
# Crear directorio y entrar
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Buscar y reemplazar en archivos
find_replace() {
  if [ $# -ne 3 ]; then
    echo "Uso: find_replace <directorio> <buscar> <reemplazar>"
    return 1
  fi
  sd "$2" "$3" "$1"
}

# Mostrar tamaño de directorios
duh() {
  du -h "$@" | sort -hr
}

# Extraer archivos
extract() {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar.bz2) tar xjf "$1" ;;
      *.tar.gz) tar xzf "$1" ;;
      *.bz2) bunzip2 "$1" ;;
      *.rar) unrar x "$1" ;;
      *.gz) gunzip "$1" ;;
      *.tar) tar xf "$1" ;;
      *.tbz2) tar xjf "$1" ;;
      *.tgz) tar xzf "$1" ;;
      *.zip) unzip "$1" ;;
      *.Z) uncompress "$1" ;;
      *.7z) 7z x "$1" ;;
      *) echo "'$1' no puede ser extraído" ;;
    esac
  else
    echo "'$1' no es un archivo válido"
  fi
}

# Git: Crear rama y cambiar a ella
gcb() {
  git checkout -b "$1"
}

# Git: Push y set upstream
gpu() {
  git push -u origin "$(git branch --show-current)"
}

# Mostrar IP local
myip() {
  echo "IP Local: $(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I | awk '{print $1}')"
  echo "IP Pública: $(curl -s ifconfig.me)"
}
