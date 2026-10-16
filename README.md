# dotfiles

Configuración de mi entorno de desarrollo, con el mismo sistema de temas en
**macOS** y **Windows**.

La fuente de verdad de los colores es `themes/<tema>/`. Cada plataforma solo
cambia *a dónde* se aplican esos colores.

---

## macOS

```bash
git clone <este-repo> ~/dotfiles
cd ~/dotfiles
./install.sh
```

Instala con Homebrew, enlaza las configuraciones a `~/.config` y aplica un tema.
Shell: **zsh** (`.zshrc`). Terminal: **Ghostty**.

```bash
./theme.sh                 # selector interactivo
./theme.sh list
./theme.sh preview nord
./theme.sh apply nord
```

---

## Windows

### Requisitos previos

1. **Modo Desarrollador** — necesario para crear symlinks sin ser
   administrador:
   *Configuración → Privacidad y seguridad → Para desarrolladores → Modo de
   desarrollador*.

   Sin esto el instalador **copia** los archivos sueltos en vez de enlazarlos,
   y entonces editar el repo ya no actualiza tu configuración. El script avisa
   si ocurre.

2. La directiva de ejecución de PowerShell debe permitir scripts locales, o
   invoca el instalador con `-ExecutionPolicy Bypass` como abajo.

### Instalación

```powershell
git clone <este-repo> $HOME\dotfiles
cd $HOME\dotfiles
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Funciona tanto en Windows PowerShell 5.1 (el preinstalado) como en PowerShell 7,
e instala PowerShell 7 por el camino.

Opciones útiles:

| Flag | Qué hace |
| --- | --- |
| `-SkipPackages` | Solo enlaza configuraciones y aplica el tema |
| `-SkipOpencode` | No compila mi fork de opencode (requiere bun, tarda) |
| `-WithDocker` | Instala además Docker Desktop (descarga grande) |
| `-Theme <nombre>` | Tema inicial (por defecto `catppuccin`) |

### Temas

```powershell
.\theme.ps1                # selector interactivo
.\theme.ps1 list
.\theme.ps1 preview nord
.\theme.ps1 apply nord
# o, ya con el perfil cargado:
theme apply nord
```

`theme.ps1 apply` fusiona el esquema de color con el `settings.json` real de
Windows Terminal **preservando** tus perfiles (`profiles.list`), los perfiles
dinámicos y tus otros esquemas. Windows Terminal recarga al guardar, así que el
cambio se ve al instante.

---

## Equivalencias macOS ↔ Windows

| Pieza | macOS | Windows |
| --- | --- | --- |
| Shell | zsh (`.zshrc`) | PowerShell 7 (`powershell/profile.ps1`) |
| Terminal | Ghostty (`ghostty/config`) | Windows Terminal (`windows-terminal/settings.json`) |
| Instalador | `install.sh` (Homebrew) | `install.ps1` (winget + scoop) |
| Temas | `theme.sh` | `theme.ps1` |
| Colores del shell | `~/.config/zsh-colors.sh` | `powershell/colors.ps1` (PSReadLine + `LS_COLORS`) |
| Autosugerencias | zsh-autosuggestions | PSReadLine `PredictionSource` |
| Búsqueda en historial | zsh-history-substring-search | PSReadLine `HistorySearchBackward/Forward` (↑/↓) |
| Completado con menú | fzf-tab | PSReadLine `MenuComplete` (Tab) |
| Atajos de fzf | fzf key-bindings | módulo PSFzf (Ctrl+T, Ctrl+R) |
| Splits y pestañas | Ghostty / tmux | Windows Terminal (mismos atajos: `alt+v`, `alt+d`, `alt+hjkl`) |
| Node | nvm (`nvm.sh`, carga diferida) | nvm-windows (`nvm.exe`) |
| Limpiar pantalla | `cmd+k` | `Ctrl+L` (PSReadLine) |
| Copiar / pegar | `cmd+c` / `cmd+v` | `ctrl+shift+c` / `ctrl+v` |

Los atajos de splits (`alt+v`, `alt+d`, `alt+h/j/k/l`) son idénticos en las dos
plataformas; solo cambia `Cmd` por `Ctrl` en los de ventana y pestañas.

### No disponible en Windows nativo

- **Ghostty** y **tmux** no tienen versión para Windows. Sus funciones (splits,
  pestañas, scrollback, zoom de panel) las cubre Windows Terminal.
  `tmux/tmux.conf` se mantiene en el repo para usarlo desde WSL.
- **direnv** no tiene soporte oficial; se omite a propósito en el perfil.
- **btop** se instala como `btop4win`.

---

## Estructura

```
.zshrc                       shell en macOS
install.sh                   instalador de macOS (Homebrew)
theme.sh                     cambio de tema en macOS

install.ps1                  instalador de Windows (winget + scoop)
theme.ps1                    cambio de tema en Windows
powershell/
  profile.ps1                shell en Windows (equivalente del .zshrc)
  lib/dotfiles.ps1           helpers compartidos por install.ps1 y theme.ps1
windows-terminal/
  settings.json              config base (equivalente de ghostty/config)

themes/<tema>/               FUENTE DE VERDAD de los colores
  ghostty.conf               paleta (la leen las dos plataformas)
  starship.toml              prompt
  nvim.lua                   colorscheme de Neovim
  zsh.sh                     LS_COLORS

ghostty/                     terminal en macOS
nvim/                        Neovim (LazyVim), igual en las dos
opencode/                    OpenCode
claude/                      Claude Code
tmux/ yazi/ wallpapers/
```

### Archivos generados (no versionados)

`theme.sh` / `theme.ps1` los reescriben en cada `apply`; ver `.gitignore`:

```
ghostty/theme.conf              windows-terminal/theme.json
                                powershell/colors.ps1
starship.toml
nvim/lua/plugins/colorscheme.lua
opencode/tui.json  opencode/themes/
claude/settings.json  claude/themes/
```

## Temas incluidos

`catppuccin` · `dracula` · `gruvbox` · `monokai` · `nord` · `onedark` ·
`tokyonight`
