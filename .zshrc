# EDITOR
export EDITOR=nvim
export VISUAL=nvim

# PATH portable entre Homebrew en Apple Silicon e Intel, sin entradas repetidas.
path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  /opt/homebrew/bin
  /opt/homebrew/sbin
  /usr/local/bin
  /usr/local/sbin
  "$HOME/.lmstudio/bin"
  $path
)
path=(${path:#/Users/alvaro.lopez/.opencode/bin})
typeset -U path PATH

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Historial compartido, deduplicado y suficientemente grande para búsquedas.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt append_history inc_append_history share_history
setopt hist_expire_dups_first hist_find_no_dups hist_ignore_all_dups
setopt hist_ignore_space hist_reduce_blanks hist_save_no_dups hist_verify

# Completion antes de los plugins que lo amplían.
autoload -Uz compinit
ZSH_COMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-${ZSH_VERSION}"
mkdir -p "${ZSH_COMPDUMP:h}"
compinit -d "$ZSH_COMPDUMP"

source_if_exists() {
  [[ -r "$1" ]] && source "$1"
}

# Plugins opcionales: la configuración sigue funcionando aunque falten en otra máquina.
source_if_exists "$HOME/dotfiles/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh"
for zsh_plugin in \
  /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh; do
  source_if_exists "$zsh_plugin" && break
done
if (( $+commands[fzf] )); then
  if [[ -r /opt/homebrew/opt/fzf/shell/key-bindings.zsh ]]; then
    source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
    source_if_exists /opt/homebrew/opt/fzf/shell/completion.zsh
  elif [[ -r /usr/local/opt/fzf/shell/key-bindings.zsh ]]; then
    source /usr/local/opt/fzf/shell/key-bindings.zsh
    source_if_exists /usr/local/opt/fzf/shell/completion.zsh
  fi
  (( $+commands[fd] )) && export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
fi

zsh_history_substring_loaded=0
for zsh_plugin in \
  /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh \
  /usr/local/share/zsh-history-substring-search/zsh-history-substring-search.zsh; do
  if source_if_exists "$zsh_plugin"; then
    zsh_history_substring_loaded=1
    break
  fi
done
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"
(( $+commands[atuin] )) && eval "$(atuin init zsh)"
(( $+commands[direnv] )) && eval "$(direnv hook zsh)"
(( $+commands[mise] )) && eval "$(mise activate zsh)"

if (( zsh_history_substring_loaded )); then
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey '^[OA' history-substring-search-up
  bindkey '^[OB' history-substring-search-down
fi
unset zsh_history_substring_loaded

# Syntax highlighting debe cargarse al final, después de todos los widgets.
for zsh_plugin in \
  /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  source_if_exists "$zsh_plugin" && break
done
unset zsh_plugin

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
alias gstp='git stash pop'
alias gstpush='git stash push'
alias gstl='git stash list'
alias gstd='git stash drop'
alias theme='~/dotfiles/theme.sh'

# NVM (Node Version Manager), cargado solo al invocarlo para acelerar el inicio.
export NVM_DIR="$HOME/.nvm"
load_nvm() {
  unfunction nvm node npm npx corepack 2>/dev/null
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
}
nvm() { load_nvm; nvm "$@"; }
node() { load_nvm; node "$@"; }
npm() { load_nvm; npm "$@"; }
npx() { load_nvm; npx "$@"; }
corepack() { load_nvm; corepack "$@"; }

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

# Mi fork de opencode (panel de background agents + alertas)
alias opencode="$HOME/bin/opencode"

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

# TEMA ACTIVO (generado por theme.sh)
[ -f "$HOME/.config/zsh-colors.sh" ] && source "$HOME/.config/zsh-colors.sh"

(( $+commands[starship] )) && eval "$(starship init zsh)"
