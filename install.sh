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

# ------------------------------------------------------------------ Claude --
mkdir -p "$HOME/.claude" "$HOME/.claude/plugins"
link "$DOTFILES_DIR/claude/settings.json"        "$HOME/.claude/settings.json"
link "$DOTFILES_DIR/claude/settings.local.json"  "$HOME/.claude/settings.local.json"
link "$DOTFILES_DIR/claude/CLAUDE.md"            "$HOME/.claude/CLAUDE.md"
link "$DOTFILES_DIR/claude/agents"               "$HOME/.claude/agents"
link "$DOTFILES_DIR/claude/skills"               "$HOME/.claude/skills"
link "$DOTFILES_DIR/claude/plugins/known_marketplaces.json" "$HOME/.claude/plugins/known_marketplaces.json"
link "$DOTFILES_DIR/claude/themes"               "$HOME/.claude/themes"

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
  jq \
  || warn "Alguna app falló; revisa el error de arriba"

log "Instalando cask de la fuente Cascadia Code Nerd Font..."
brew install --cask font-caskaydia-cove-nerd-font || warn "Fallo al instalar la fuente"

# ---------------------------------------------------------- OpenCode (fork) --
# Usa mi fork de opencode (panel de background agents + alertas) en lugar del
# oficial: elimina instalaciones previas, compila mi repo y enlaza el comando
# `opencode` a mi binario (~/bin va antes que Homebrew en el PATH).
OPENCODE_REPO="https://github.com/riigarXX/opencode-agent-monitor-view.git"
OPENCODE_BRANCH="feat/background-agents-monitor"
OPENCODE_DIR="$HOME/opencode-agent-monitor-view"

log "Eliminando instalaciones previas de opencode..."
if command -v brew >/dev/null 2>&1 && brew list opencode >/dev/null 2>&1; then
  brew uninstall --force opencode || warn "No se pudo desinstalar opencode de Homebrew"
fi
if command -v npm >/dev/null 2>&1 && npm ls -g opencode-ai >/dev/null 2>&1; then
  npm uninstall -g opencode-ai || warn "No se pudo desinstalar opencode-ai de npm"
fi
rm -f "$HOME/bin/opencode"

if ! command -v bun >/dev/null 2>&1; then
  log "Instalando bun..."
  curl -fsSL https://bun.sh/install | bash || warn "Fallo al instalar bun"
fi
export PATH="$HOME/.bun/bin:$PATH"

if [ -d "$OPENCODE_DIR/.git" ]; then
  log "Actualizando fork de opencode..."
  git -C "$OPENCODE_DIR" fetch --depth 1 origin "$OPENCODE_BRANCH" \
    && git -C "$OPENCODE_DIR" reset --hard FETCH_HEAD \
    || warn "No se pudo actualizar el fork"
else
  log "Clonando fork de opencode..."
  git clone --depth 1 -b "$OPENCODE_BRANCH" "$OPENCODE_REPO" "$OPENCODE_DIR" \
    || fail "No se pudo clonar el fork de opencode"
fi

log "Compilando opencode (fork)... (puede tardar unos minutos)"
(
  cd "$OPENCODE_DIR" \
    && bun install \
    && cd packages/opencode \
    && bun run build --single --skip-embed-web-ui --skip-install
) || fail "Fallo al compilar opencode"

mkdir -p "$HOME/bin"
OPENCODE_BIN="$(find "$OPENCODE_DIR/packages/opencode/dist" -type f -path '*/bin/opencode' | head -1)"
[ -n "$OPENCODE_BIN" ] || fail "No se encontró el binario compilado de opencode"
ln -sf "$OPENCODE_BIN" "$HOME/bin/opencode"
log "Comando 'opencode' -> mi fork ($OPENCODE_BIN)"

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
