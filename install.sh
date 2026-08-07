#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf "\033[1;32m[install]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[install]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[install]\033[0m %s\n" "$*"; exit 1; }

# ------------------------------------------------------------ Symlinks -------
link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    log "Ya enlazado: $dst"
  elif [ -e "$dst" ]; then
    warn "Existe $dst, moviendo a $dst.bak"
    mv "$dst" "$dst.bak"
    ln -s "$src" "$dst"
  else
    ln -s "$src" "$dst"
    log "Enlazado: $dst -> $src"
  fi
}

mkdir -p "$HOME/.config"

link "$DOTFILES_DIR/.zshrc"               "$HOME/.zshrc"
link "$DOTFILES_DIR/starship.toml"        "$HOME/.config/starship.toml"
link "$DOTFILES_DIR/ghostty"              "$HOME/.config/ghostty"
link "$DOTFILES_DIR/wallpapers"           "$HOME/.config/ghostty/wallpapers"
link "$DOTFILES_DIR/nvim"                 "$HOME/.config/nvim"

# ---------------------------------------------------------------- OpenCode --
mkdir -p "$HOME/.config/opencode"
link "$DOTFILES_DIR/opencode/opencode.jsonc" "$HOME/.config/opencode/opencode.jsonc"
link "$DOTFILES_DIR/opencode/tui.json"       "$HOME/.config/opencode/tui.json"
link "$DOTFILES_DIR/opencode/themes"         "$HOME/.config/opencode/themes"

# ---------------------------------------------------------------- Homebrew --
if ! command -v brew >/dev/null 2>&1; then
  log "Instalando Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  log "Homebrew ya instalado"
fi

# ------------------------------------------------------------------ Apps ----
log "Instalando apps con Homebrew..."
brew install \
  git \
  neovim \
  starship \
  lsd \
  eza \
  ripgrep \
  fd \
  bat \
  sd \
  fzf \
  zoxide \
  ghostty \
  docker \
  opencode \
  jq \
  || warn "Alguna app falló; revisa el error de arriba"

log "Instalando cask de la fuente Cascadia Code Nerd Font..."
brew install --cask font-caskaydia-cove-nerd-font || warn "Fallo al instalar la fuente"

# ------------------------------------------------------------------ NVM ----
if [ ! -d "$HOME/.nvm" ]; then
  log "Instalando nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash || warn "Fallo al instalar nvm"
else
  log "nvm ya instalado"
fi

# ------------------------------------------------- Neovim plugins (LazyVim) --
log "Instalando plugins de Neovim (primera ejecución)..."
nvim --headless "+Lazy! sync" +qa 2>/dev/null || warn "Ejecuta 'nvim' manualmente para terminar de instalar los plugins"

log "¡Listo! Recarga tu shell con: source ~/.zshrc"
