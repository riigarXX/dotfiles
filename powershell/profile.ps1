# =============================================================================
#  profile.ps1 — equivalente de .zshrc en Windows (PowerShell 7+).
#
#  install.ps1 lo enlaza a Documents\PowerShell\Microsoft.PowerShell_profile.ps1
#  Recarga con:  reload
# =============================================================================

# EDITOR
$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'

# Raíz del repo de dotfiles, para que `theme` y los colores del tema se
# encuentren. Se busca en tres sitios, en este orden:
#   1. DOTFILES_DIR, que fija install.ps1 como variable de usuario (es lo que
#      funciona también cuando el perfil es una copia y no un symlink).
#   2. El destino real del symlink de este archivo.
#   3. ~\dotfiles, por si nada de lo anterior está disponible.
function Test-DotfilesRoot {
  param([string]$Path)
  return ($Path -and (Test-Path (Join-Path $Path 'theme.ps1')))
}

$dotfilesRoot = $null
if (Test-DotfilesRoot $env:DOTFILES_DIR) {
  $dotfilesRoot = $env:DOTFILES_DIR
}
if (-not $dotfilesRoot -and $PSCommandPath) {
  $self = Get-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
  if ($self -and $self.LinkType) {
    $target = $self.Target
    if ($target -is [array]) { $target = $target[0] }
    if ($target) {
      $candidate = Split-Path -Parent (Split-Path -Parent $target)
      if (Test-DotfilesRoot $candidate) { $dotfilesRoot = $candidate }
    }
  }
}
if (-not $dotfilesRoot) {
  $candidate = Join-Path $HOME 'dotfiles'
  if (Test-DotfilesRoot $candidate) { $dotfilesRoot = $candidate }
}
$env:DOTFILES_DIR = $dotfilesRoot
Remove-Item Function:Test-DotfilesRoot -ErrorAction SilentlyContinue

# PATH sin entradas repetidas, con las rutas propias por delante.
$dotPath = @(
  (Join-Path $HOME '.local\bin')
  (Join-Path $HOME 'bin')
  (Join-Path $HOME 'scoop\shims')
  (Join-Path $HOME '.bun\bin')
  (Join-Path $HOME '.cargo\bin')
  (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
  (Join-Path $env:LOCALAPPDATA 'Programs\Neovim\bin')
)
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$merged = [System.Collections.Generic.List[string]]::new()
foreach ($p in ($dotPath + ($env:PATH -split ';'))) {
  if ([string]::IsNullOrWhiteSpace($p)) { continue }
  $p = $p.TrimEnd('\')
  if ($seen.Add($p)) { [void]$merged.Add($p) }
}
$env:PATH = $merged -join ';'

# UTF-8 en entrada y salida (equivalente de LANG/LC_ALL=en_US.UTF-8).
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)

# ----------------------------------------------------------------- PSReadLine -
# Cubre lo que en zsh hacían compinit, zsh-autosuggestions,
# zsh-history-substring-search y fzf-tab.
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Module PSReadLine) {
  $psrlVersion = (Get-Module PSReadLine).Version

  Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
  Set-PSReadLineOption -MaximumHistoryCount 100000
  Set-PSReadLineOption -HistoryNoDuplicates
  Set-PSReadLineOption -HistorySearchCursorMovesToEnd
  Set-PSReadLineOption -BellStyle None
  Set-PSReadLineOption -EditMode Windows

  # Menú de completado al tabular (lo más cercano a fzf-tab).
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

  # Sugerencia en línea según el historial (zsh-autosuggestions).
  if ($psrlVersion -ge [version]'2.2.0') {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Ctrl+f -Function ForwardWord
  }

  # Flechas = búsqueda por subcadena en el historial
  # (zsh-history-substring-search).
  Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
  Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

  # Navegación por palabras con Alt+flechas (de ahí el unbind en el terminal).
  Set-PSReadLineKeyHandler -Key Alt+LeftArrow -Function BackwardWord
  Set-PSReadLineKeyHandler -Key Alt+RightArrow -Function ForwardWord
}

# ------------------------------------------------------------------ fzf -------
if (Get-Command fzf -ErrorAction SilentlyContinue) {
  if (Get-Command fd -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
  }
  # PSFzf aporta los atajos Ctrl+T (archivos) y Ctrl+R (historial).
  Import-Module PSFzf -ErrorAction SilentlyContinue
  if (Get-Module PSFzf) {
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
  }
}

# -------------------------------------------------------- shell integrations --
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  Invoke-Expression (& zoxide init powershell | Out-String)
}
if (Get-Command atuin -ErrorAction SilentlyContinue) {
  Invoke-Expression (& atuin init powershell | Out-String)
}
if (Get-Command mise -ErrorAction SilentlyContinue) {
  Invoke-Expression (& mise activate pwsh | Out-String)
}
# direnv no tiene soporte oficial en Windows nativo; se omite a propósito.

# ---------------------------------------------- aliases nativos que estorban --
# En PowerShell un alias gana a una función, así que los integrados que
# queremos redefinir hay que quitarlos primero.
foreach ($builtin in @('ls', 'cat', 'gc', 'gcm', 'gl', 'gp', 'gm', 'gcb', 'gi', 'gu')) {
  if (Test-Path "Alias:$builtin") {
    Remove-Item "Alias:$builtin" -Force -ErrorAction SilentlyContinue
  }
}

# ------------------------------------------- ALIASES BÁSICOS PARA DESARROLLO --
function ls { lsd @args }
function ll { lsd @args }
function lsa { lsd -la @args }
function lst { eza -T @args }

function .. { Set-Location .. }
function ... { Set-Location ../.. }
function .... { Set-Location ../../.. }
function ..... { Set-Location ../../../.. }

function grep { rg @args }
function find { fd @args }
function cat { bat @args }

function reload { . $PROFILE }
function psrc { nvim $PROFILE }

# ----------------------------------------------------- ALIASES PARA NEOVIM ----
function vim { nvim @args }
function v { nvim @args }
function vi { nvim @args }
function nvimrc { nvim (Join-Path $env:LOCALAPPDATA 'nvim\init.lua') }

# -------------------------------------------------------- ALIASES PARA GIT ----
function g { git @args }
function ga { git add @args }
function gaa { git add --all @args }
function gc { git commit @args }
function gcm { git commit -m @args }
function gca { git commit --amend @args }
function gcan { git commit --amend --no-edit @args }
function gs { git status @args }
function gst { git status @args }
function gd { git diff @args }
function gdc { git diff --cached @args }
function gl { git log --oneline --decorate --graph @args }
function gla { git log --oneline --decorate --graph --all @args }
function gp { git push @args }
function gpf { git push --force-with-lease @args }
function gf { git fetch @args }
function gfa { git fetch --all @args }
function gpl { git pull @args }
function gplr { git pull --rebase @args }
function gb { git branch @args }
function gba { git branch -a @args }
function gco { git checkout @args }
function gsw { git switch @args }
function gswc { git switch -c @args }
function gm { git merge @args }
function gr { git reset @args }
function grh { git reset HEAD @args }
function grhh { git reset HEAD --hard @args }
function gcp { git cherry-pick @args }
function gstp { git stash pop @args }
function gstpush { git stash push @args }
function gstl { git stash list @args }
function gstd { git stash drop @args }

function theme {
  if (-not $env:DOTFILES_DIR) {
    Write-Host 'No encuentro el repo de dotfiles (DOTFILES_DIR vacío).' -ForegroundColor Red
    return
  }
  & (Join-Path $env:DOTFILES_DIR 'theme.ps1') @args
}

# ------------------------------------------------------------------- NODE -----
# En Windows se usa nvm-windows (CoreyButler.NVMforWindows), que es un .exe en
# el PATH: no hace falta la carga diferida que el .zshrc necesita para nvm.sh.

# ----------------------------------------------------- ALIASES PARA DOCKER ----
function d { docker @args }
function dc { docker compose @args }
function dcu { docker compose up @args }
function dcub { docker compose up --build @args }
function dcd { docker compose down @args }
function dcl { docker compose logs @args }
function dclf { docker compose logs -f @args }
function dcr { docker compose restart @args }
function dps { docker ps @args }
function dpsa { docker ps -a @args }
function di { docker images @args }
function drm { docker rm @args }
function drmi { docker rmi @args }
function dex { docker exec -it @args }
function dlogs { docker logs @args }
function dlogsf { docker logs -f @args }

# Mi fork de opencode (panel de background agents + alertas)
function opencode {
  $bin = Join-Path $HOME 'bin\opencode.cmd'
  if (Test-Path $bin) { & $bin @args } else { & 'opencode' @args }
}

# ------------------------------------------ FUNCIONES ÚTILES PARA DESARROLLO --
# Crear directorio y entrar
function mkcd {
  param([Parameter(Mandatory)][string]$Path)
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
  Set-Location $Path
}

# Buscar y reemplazar en archivos
function find_replace {
  param([string]$Directory, [string]$Search, [string]$Replace)
  if (-not $Directory -or -not $Search -or $null -eq $Replace) {
    Write-Host 'Uso: find_replace <directorio> <buscar> <reemplazar>'
    return
  }
  sd $Search $Replace $Directory
}

# Mostrar tamaño de directorios, de mayor a menor
function duh {
  param([string]$Path = '.')
  Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
      $bytes = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
      if ($null -eq $bytes) { $bytes = 0 }
      [pscustomobject]@{ Size = [int64]$bytes; Name = $_.Name }
    } |
    Sort-Object Size -Descending |
    ForEach-Object {
      $s = $_.Size
      $unit = 'B'
      foreach ($u in @('K', 'M', 'G', 'T')) {
        if ($s -lt 1024) { break }
        $s = $s / 1024
        $unit = $u
      }
      '{0,7} {1}' -f ('{0:N1}{1}' -f $s, $unit), $_.Name
    }
}

# Extraer archivos
function extract {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "'$Path' no es un archivo válido"
    return
  }
  switch -Regex ($Path) {
    '\.tar\.bz2$|\.tbz2$' { tar xjf $Path }
    '\.tar\.gz$|\.tgz$' { tar xzf $Path }
    '\.tar\.xz$' { tar xJf $Path }
    '\.tar$' { tar xf $Path }
    '\.bz2$' { 7z x $Path }
    '\.gz$' { 7z x $Path }
    '\.rar$' { 7z x $Path }
    '\.7z$' { 7z x $Path }
    '\.zip$' { Expand-Archive -LiteralPath $Path -DestinationPath (Get-Location) -Force }
    '\.Z$' { 7z x $Path }
    default { Write-Host "'$Path' no puede ser extraído" }
  }
}

# Git: Crear rama y cambiar a ella
function gcb {
  param([Parameter(Mandatory)][string]$Branch)
  git checkout -b $Branch
}

# Git: Push y set upstream
function gpu {
  git push -u origin (git branch --show-current)
}

# Mostrar IP local y pública
function myip {
  $local = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
    Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
    Select-Object -First 1 -ExpandProperty IPv4Address |
    Select-Object -First 1 -ExpandProperty IPAddress
  if (-not $local) {
    $local = ([System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
      Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
      Select-Object -First 1).IPAddressToString
  }
  Write-Host "IP Local: $local"
  try {
    Write-Host "IP Pública: $(Invoke-RestMethod -Uri 'https://ifconfig.me' -TimeoutSec 5)"
  } catch {
    Write-Host 'IP Pública: (sin conexión)'
  }
}

# --------------------------------------- TEMA ACTIVO (generado por theme.ps1) --
# Ojo: este archivo está enlazado, así que $PSScriptRoot apunta a
# Documents\PowerShell y no al repo; se usa DOTFILES_DIR como ruta principal.
if ($env:DOTFILES_DIR) {
  $dotColors = Join-Path $env:DOTFILES_DIR 'powershell\colors.ps1'
  if (Test-Path $dotColors) { . $dotColors }
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
  Invoke-Expression (& starship init powershell | Out-String)
}
