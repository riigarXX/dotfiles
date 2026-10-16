#Requires -Version 5.1
<#
.SYNOPSIS
  Instalador de estos dotfiles en Windows (equivalente de install.sh).

.DESCRIPTION
  Enlaza las configuraciones a las rutas que espera Windows, instala las
  herramientas con winget (y scoop como respaldo) y aplica un tema por defecto.

  Para que los symlinks se puedan crear sin ser administrador, activa el Modo
  Desarrollador: Configuración → Privacidad y seguridad → Para desarrolladores.
  Si no está activo, el script usa junctions para carpetas y copia los archivos
  sueltos, avisando de ello.

.PARAMETER SkipPackages
  No instala nada: solo enlaza configuraciones y aplica el tema.

.PARAMETER WithDocker
  Instala además Docker Desktop (descarga grande y suele pedir reinicio).

.PARAMETER SkipOpencode
  No compila mi fork de opencode (requiere bun y tarda varios minutos).

.PARAMETER Theme
  Tema a aplicar si todavía no hay ninguno. Por defecto: catppuccin.

.EXAMPLE
  pwsh -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
  pwsh -File .\install.ps1 -SkipPackages
#>

[CmdletBinding()]
param(
  [switch]$SkipPackages,
  [switch]$WithDocker,
  [switch]$SkipOpencode,
  [string]$Theme = 'catppuccin'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powershell\lib\dotfiles.ps1')

$Root = Get-DotfilesRoot

function Test-DotAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($id)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Tras instalar cosas, los nuevos comandos no están en el PATH de esta sesión.
function Update-DotPath {
  $machine = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('PATH', 'User')
  $extra = @(
    (Join-Path $HOME 'scoop\shims'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
    (Join-Path $HOME '.bun\bin'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Neovim\bin')
  )
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $merged = New-Object System.Collections.ArrayList
  foreach ($p in ($extra + ($machine -split ';') + ($user -split ';'))) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $p = $p.TrimEnd('\')
    if ($seen.Add($p)) { [void]$merged.Add($p) }
  }
  $env:PATH = $merged -join ';'
}

Write-DotInfo install "Repo: $Root"
$canSymlink = Test-DotSymlinkCapable
if ($canSymlink) {
  Write-DotInfo install 'Symlinks disponibles'
} else {
  Write-DotWarn install 'Sin permiso para symlinks (activa el Modo Desarrollador o ejecuta como admin).'
  Write-DotWarn install 'Se usarán junctions para carpetas y copias para archivos sueltos.'
}

# ================================================= artefactos generados =======
# theme.ps1 genera estos archivos, pero los enlaces tienen que existir antes de
# que se aplique el tema. En un clon limpio no están (ver .gitignore), así que
# se crean como marcadores vacíos y el tema los sobrescribe después.
function Initialize-DotGenerated {
  $files = @{
    (Join-Path $Root 'starship.toml')                      = "# Lo genera theme.ps1 / theme.sh`n"
    (Join-Path $Root 'claude\settings.json')               = "{}`n"
    (Join-Path $Root 'opencode\tui.json')                  = "{}`n"
    (Join-Path $Root 'nvim\lua\plugins\colorscheme.lua')   = "-- Lo genera theme.ps1 / theme.sh`nreturn {}`n"
  }
  foreach ($f in $files.Keys) {
    if (-not (Test-Path -LiteralPath $f)) {
      Write-DotInfo install "Creando marcador: $f"
      Write-DotText -Path $f -Content $files[$f]
    }
  }
  foreach ($d in @((Join-Path $Root 'claude\themes'), (Join-Path $Root 'opencode\themes'))) {
    if (-not (Test-Path -LiteralPath $d)) {
      New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
  }
}

# claude/settings.json y opencode/tui.json los genera el tema, pero solo tocan
# la clave "theme": el resto del archivo se conserva. Si ya hay una config real
# en su sitio (model, statusLine, permissions...), se usa como semilla para no
# perderla al enlazar.
function Import-DotExistingConfig {
  $pairs = @(
    @{ Live = (Join-Path $HOME '.claude\settings.json'); Repo = (Join-Path $Root 'claude\settings.json') },
    @{ Live = (Join-Path $HOME '.config\opencode\tui.json'); Repo = (Join-Path $Root 'opencode\tui.json') }
  )
  foreach ($p in $pairs) {
    if (-not (Test-Path -LiteralPath $p.Live -PathType Leaf)) { continue }
    # Si ya es un enlace al repo, la semilla sería circular.
    if (Get-DotLinkTarget -Path $p.Live) { continue }

    $live = Read-DotJson $p.Live
    if ($null -eq $live -or $live.Keys.Count -eq 0) { continue }

    $repo = Read-DotJson $p.Repo
    $repoKeys = 0
    if ($null -ne $repo) { $repoKeys = $repo.Keys.Count }
    # Solo se siembra sobre el marcador vacío, nunca sobre una config ya hecha.
    if ($repoKeys -gt 1) { continue }

    $merged = Merge-DotHashtable $live $repo
    Write-DotWarn install "Conservando tu config de $(Split-Path -Leaf $p.Live) en el repo ($($live.Keys.Count) claves)"
    Write-DotJson -Path $p.Repo -Value $merged
  }
}

Initialize-DotGenerated
Import-DotExistingConfig

# ============================================================== paquetes ======
function Install-DotScoop {
  if (Test-DotCommand scoop) {
    Write-DotInfo install 'scoop ya instalado'
    return $true
  }
  Write-DotInfo install 'Instalando scoop...'
  try {
    $installer = Invoke-RestMethod -Uri 'https://get.scoop.sh' -UseBasicParsing
    $sb = [scriptblock]::Create($installer)
    if (Test-DotAdmin) { & $sb -RunAsAdmin } else { & $sb }
    Update-DotPath
    return (Test-DotCommand scoop)
  } catch {
    Write-DotWarn install "No se pudo instalar scoop: $($_.Exception.Message)"
    return $false
  }
}

function Install-DotPackage {
  param(
    [Parameter(Mandatory)][string]$Label,
    [string]$Probe,
    [string]$WingetId,
    [string]$ScoopId,
    [string]$MinVersion
  )

  # Con MinVersion, una versión instalada más antigua cuenta como "no lista" y
  # se actualiza en vez de omitirse.
  $isReady = {
    if (-not $Probe) { return $true }
    if (-not (Test-DotCommand $Probe)) { return $false }
    if (-not $MinVersion) { return $true }
    $v = Get-DotCommandVersion $Probe
    return ($null -ne $v -and $v -ge [version]$MinVersion)
  }

  $upgrade = $false
  if ($Probe -and (Test-DotCommand $Probe)) {
    if (& $isReady) {
      Write-DotInfo install "$Label ya instalado"
      return
    }
    $upgrade = $true
    $current = Get-DotCommandVersion $Probe
    Write-DotWarn install "$Label $current es anterior a $MinVersion; actualizando..."
  }

  if ($WingetId -and (Test-DotCommand winget)) {
    $verb = 'install'
    if ($upgrade) { $verb = 'upgrade' }
    Write-DotInfo install "Instalando $Label (winget $verb)..."
    & winget $verb --id $WingetId --exact --source winget `
      --accept-package-agreements --accept-source-agreements `
      --disable-interactivity | Out-Null
    Update-DotPath
    if (& $isReady) { return }
    Write-DotWarn install "winget no pudo con $Label; probando scoop"
  }

  if ($ScoopId -and (Test-DotCommand scoop)) {
    Write-DotInfo install "Instalando $Label (scoop)..."
    & scoop install $ScoopId | Out-Null
    if ($upgrade) { & scoop update $ScoopId | Out-Null }
    Update-DotPath
    if (& $isReady) { return }
  }

  if ($upgrade) {
    Write-DotWarn install "No se pudo actualizar $Label a >= $MinVersion; actualízalo a mano"
  } else {
    Write-DotWarn install "No se pudo instalar $Label; instálalo a mano"
  }
}

if ($SkipPackages) {
  Write-DotInfo install 'Omitiendo instalación de paquetes (-SkipPackages)'
} else {
  if (-not (Test-DotCommand winget)) {
    Write-DotWarn install 'winget no está disponible; se usará solo scoop'
  }
  Install-DotScoop | Out-Null
  if (Test-DotCommand scoop) {
    foreach ($bucket in @('extras', 'nerd-fonts')) {
      & scoop bucket add $bucket | Out-Null
    }
  }

  # Equivalente del `brew install` de install.sh. tmux y ghostty no existen en
  # Windows nativo: sus funciones las cubren Windows Terminal (splits, tabs,
  # scrollback) y PSReadLine.
  $packages = @(
    @{ Label = 'PowerShell 7'; Probe = 'pwsh'; Winget = 'Microsoft.PowerShell'; Scoop = 'pwsh' },
    @{ Label = 'Windows Terminal'; Probe = 'wt'; Winget = 'Microsoft.WindowsTerminal'; Scoop = 'windows-terminal' },
    @{ Label = 'git'; Probe = 'git'; Winget = 'Git.Git'; Scoop = 'git' },
    @{ Label = 'neovim'; Probe = 'nvim'; Winget = 'Neovim.Neovim'; Scoop = 'neovim'; MinVersion = (Get-DotNvimMinVersion).ToString() },
    @{ Label = 'starship'; Probe = 'starship'; Winget = 'Starship.Starship'; Scoop = 'starship' },
    @{ Label = 'lsd'; Probe = 'lsd'; Winget = 'lsd-rs.lsd'; Scoop = 'lsd' },
    @{ Label = 'eza'; Probe = 'eza'; Winget = 'eza-community.eza'; Scoop = 'eza' },
    @{ Label = 'ripgrep'; Probe = 'rg'; Winget = 'BurntSushi.ripgrep.MSVC'; Scoop = 'ripgrep' },
    @{ Label = 'fd'; Probe = 'fd'; Winget = 'sharkdp.fd'; Scoop = 'fd' },
    @{ Label = 'bat'; Probe = 'bat'; Winget = 'sharkdp.bat'; Scoop = 'bat' },
    @{ Label = 'sd'; Probe = 'sd'; Winget = 'chmln.sd'; Scoop = 'sd' },
    @{ Label = 'fzf'; Probe = 'fzf'; Winget = 'junegunn.fzf'; Scoop = 'fzf' },
    @{ Label = 'zoxide'; Probe = 'zoxide'; Winget = 'ajeetdsouza.zoxide'; Scoop = 'zoxide' },
    @{ Label = 'yazi'; Probe = 'yazi'; Winget = 'sxyazi.yazi'; Scoop = 'yazi' },
    @{ Label = 'atuin'; Probe = 'atuin'; Winget = 'atuinsh.atuin'; Scoop = 'atuin' },
    @{ Label = 'mise'; Probe = 'mise'; Winget = 'jdx.mise'; Scoop = 'mise' },
    @{ Label = 'btop'; Probe = 'btop4win'; Winget = 'aristocratos.btop4win'; Scoop = 'btop-lhm' },
    @{ Label = 'fastfetch'; Probe = 'fastfetch'; Winget = 'Fastfetch-cli.Fastfetch'; Scoop = 'fastfetch' },
    @{ Label = 'git-delta'; Probe = 'delta'; Winget = 'dandavison.delta'; Scoop = 'delta' },
    @{ Label = 'lazygit'; Probe = 'lazygit'; Winget = 'JesseDuffield.lazygit'; Scoop = 'lazygit' },
    @{ Label = 'jq'; Probe = 'jq'; Winget = 'jqlang.jq'; Scoop = 'jq' },
    @{ Label = '7-Zip'; Probe = '7z'; Winget = '7zip.7zip'; Scoop = '7zip' },
    @{ Label = 'nvm-windows'; Probe = 'nvm'; Winget = 'CoreyButler.NVMforWindows'; Scoop = 'nvm' }
  )
  if ($WithDocker) {
    $packages += @{ Label = 'Docker Desktop'; Probe = 'docker'; Winget = 'Docker.DockerDesktop'; Scoop = '' }
  }

  foreach ($p in $packages) {
    Install-DotPackage -Label $p.Label -Probe $p.Probe -WingetId $p.Winget -ScoopId $p.Scoop -MinVersion $p.MinVersion
  }
  if (-not $WithDocker) {
    Write-DotInfo install 'Docker Desktop omitido (usa -WithDocker para instalarlo)'
  }

  # ------------------------------------------------- módulos de PowerShell ----
  # Sustituyen a los plugins de zsh: PSReadLine hace de autosuggestions +
  # history-substring-search, y PSFzf de fzf key-bindings / fzf-tab.
  foreach ($mod in @('PSReadLine', 'PSFzf', 'Terminal-Icons')) {
    if (Get-Module -ListAvailable -Name $mod) {
      Write-DotInfo install "Módulo $mod ya instalado"
      continue
    }
    Write-DotInfo install "Instalando módulo $mod..."
    try {
      Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber -AcceptLicense -ErrorAction Stop
    } catch {
      Write-DotWarn install "No se pudo instalar el módulo ${mod}: $($_.Exception.Message)"
    }
  }

  # ------------------------------------------------------------- la fuente ----
  Write-DotInfo install 'Instalando la fuente Cascadia Code Nerd Font...'
  if (Test-DotCommand scoop) {
    & scoop install nerd-fonts/CascadiaCode-NF-Mono | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-DotWarn install 'Fallo al instalar la fuente; pruébalo con: scoop install nerd-fonts/CascadiaCode-NF-Mono'
    }
  } else {
    Write-DotWarn install 'Sin scoop no puedo instalar la Nerd Font; descárgala de https://nerdfonts.com'
  }
}

Update-DotPath

# =============================================================== symlinks =====
$docs = Get-DotDocumentsPath
Write-DotInfo install "Documentos: $docs"

# El perfil necesita saber dónde vive el repo (para `theme` y los colores del
# tema). Como variable de usuario funciona incluso si el perfil acabó siendo
# una copia en vez de un symlink.
if ([Environment]::GetEnvironmentVariable('DOTFILES_DIR', 'User') -ne $Root) {
  [Environment]::SetEnvironmentVariable('DOTFILES_DIR', $Root, 'User')
  Write-DotInfo install "DOTFILES_DIR = $Root (variable de usuario)"
}
$env:DOTFILES_DIR = $Root

New-DotLink (Join-Path $Root 'powershell\profile.ps1') (Get-DotProfilePath)
New-DotLink (Join-Path $Root 'starship.toml') (Join-Path $HOME '.config\starship.toml')
New-DotLink (Join-Path $Root 'nvim') (Join-Path $env:LOCALAPPDATA 'nvim')
New-DotLink (Join-Path $Root 'yazi\yazi.toml') (Join-Path $env:APPDATA 'yazi\config\yazi.toml')

# ---------------------------------------------------------------- OpenCode ----
New-DotLink (Join-Path $Root 'opencode\opencode.jsonc') (Join-Path $HOME '.config\opencode\opencode.jsonc')
New-DotLink (Join-Path $Root 'opencode\tui.json') (Join-Path $HOME '.config\opencode\tui.json')
New-DotLink (Join-Path $Root 'opencode\themes') (Join-Path $HOME '.config\opencode\themes')

# ------------------------------------------------------------------ Claude ----
New-DotLink (Join-Path $Root 'claude\settings.json') (Join-Path $HOME '.claude\settings.json')
New-DotLink (Join-Path $Root 'claude\settings.local.json') (Join-Path $HOME '.claude\settings.local.json')
New-DotLink (Join-Path $Root 'claude\CLAUDE.md') (Join-Path $HOME '.claude\CLAUDE.md')
New-DotLink (Join-Path $Root 'claude\agents') (Join-Path $HOME '.claude\agents')
New-DotLink (Join-Path $Root 'claude\skills') (Join-Path $HOME '.claude\skills')
New-DotLink (Join-Path $Root 'claude\plugins\known_marketplaces.json') (Join-Path $HOME '.claude\plugins\known_marketplaces.json')
New-DotLink (Join-Path $Root 'claude\themes') (Join-Path $HOME '.claude\themes')

# tmux no existe en Windows nativo: sus atajos de splits/panes los cubre
# Windows Terminal (ver windows-terminal/settings.json). tmux/tmux.conf se deja
# para cuando se usa este repo desde WSL.

# ================================================= OpenCode (mi fork) ========
# Usa mi fork de opencode (panel de background agents + alertas) en lugar del
# oficial: compila mi repo y deja un shim `opencode` en ~\bin, que va antes que
# scoop/winget en el PATH del profile.
if ($SkipOpencode) {
  Write-DotInfo install 'Omitiendo el fork de opencode (-SkipOpencode)'
} else {
  $opencodeRepo = 'https://github.com/riigarXX/opencode-agent-monitor-view.git'
  $opencodeBranch = 'feat/background-agents-monitor'
  $opencodeDir = Join-Path $HOME 'opencode-agent-monitor-view'

  if (-not (Test-DotCommand bun)) {
    Write-DotInfo install 'Instalando bun...'
    try {
      Invoke-RestMethod -Uri 'https://bun.sh/install.ps1' -UseBasicParsing | Invoke-Expression
      Update-DotPath
    } catch {
      Write-DotWarn install "Fallo al instalar bun: $($_.Exception.Message)"
    }
  }

  if (-not (Test-DotCommand bun)) {
    Write-DotWarn install 'Sin bun no puedo compilar opencode; omitido'
  } elseif (-not (Test-DotCommand git)) {
    Write-DotWarn install 'Sin git no puedo clonar opencode; omitido'
  } else {
    if (Test-Path -LiteralPath (Join-Path $opencodeDir '.git')) {
      Write-DotInfo install 'Actualizando fork de opencode...'
      & git -C $opencodeDir fetch --depth 1 origin $opencodeBranch
      if ($LASTEXITCODE -eq 0) { & git -C $opencodeDir reset --hard FETCH_HEAD }
      if ($LASTEXITCODE -ne 0) { Write-DotWarn install 'No se pudo actualizar el fork' }
    } else {
      Write-DotInfo install 'Clonando fork de opencode...'
      & git clone --depth 1 -b $opencodeBranch $opencodeRepo $opencodeDir
    }

    if (Test-Path -LiteralPath (Join-Path $opencodeDir 'package.json')) {
      Write-DotInfo install 'Compilando opencode (fork)... (puede tardar unos minutos)'
      Push-Location $opencodeDir
      try {
        & bun install
        if ($LASTEXITCODE -eq 0) {
          Push-Location (Join-Path $opencodeDir 'packages\opencode')
          try {
            & bun run build --single --skip-embed-web-ui --skip-install
          } finally {
            Pop-Location
          }
        }
      } finally {
        Pop-Location
      }

      $dist = Join-Path $opencodeDir 'packages\opencode\dist'
      $bin = $null
      if (Test-Path -LiteralPath $dist) {
        $bin = Get-ChildItem -LiteralPath $dist -Recurse -File -Filter 'opencode.exe' -ErrorAction SilentlyContinue |
          Select-Object -First 1
      }
      if ($bin) {
        $binDir = Join-Path $HOME 'bin'
        if (-not (Test-Path -LiteralPath $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
        # Shim .cmd en vez de symlink: funciona sin permisos especiales y
        # sobrevive a que el binario se recompile en el mismo sitio.
        Write-DotText -Path (Join-Path $binDir 'opencode.cmd') -Content "@echo off`r`n`"$($bin.FullName)`" %*`r`n"
        Write-DotInfo install "Comando 'opencode' -> mi fork ($($bin.FullName))"
      } else {
        Write-DotWarn install 'No se encontró el binario compilado de opencode; usa el oficial o revisa el log de build'
      }
    }
  }
}

# ========================================================= tema por defecto ===
# Los archivos del tema activo no se versionan (ver .gitignore); si no hay
# ninguno aplicado se aplica uno para dejar el setup listo.
if (-not (Test-Path -LiteralPath (Join-Path $Root 'windows-terminal\theme.json'))) {
  Write-DotInfo install "Sin tema aplicado; aplicando $Theme por defecto..."
  $global:LASTEXITCODE = 0
  & (Join-Path $Root 'theme.ps1') apply $Theme
  if ($LASTEXITCODE -ne 0) {
    Write-DotWarn install 'Fallo al aplicar el tema; ejecuta: .\theme.ps1 apply <tema>'
  }
} else {
  Write-DotInfo install 'Tema ya aplicado'
}

# ============================================ Neovim plugins (LazyVim) ========
if (Test-DotCommand nvim) {
  Write-DotInfo install 'Instalando plugins de Neovim (primera ejecución)...'
  if (-not (Invoke-DotNvimSync -Tag install)) {
    Write-DotWarn install "Ejecuta 'nvim' manualmente para terminar de instalar los plugins"
  }
} else {
  Write-DotWarn install "nvim no está en el PATH; ejecútalo a mano para instalar los plugins"
}

Write-DotInfo install '¡Listo! Abre una terminal nueva (o ejecuta: reload)'
Write-DotInfo install 'Cambia de tema con:  theme    (o .\theme.ps1 list)'

if (-not $canSymlink) {
  Write-Host ''
  Write-DotWarn install 'IMPORTANTE: los archivos sueltos se copiaron en vez de enlazarse,'
  Write-DotWarn install 'así que editar el repo NO actualizará tu configuración (ni al revés).'
  Write-DotWarn install 'Activa Configuración → Privacidad y seguridad → Para desarrolladores →'
  Write-DotWarn install 'Modo de desarrollador, y vuelve a ejecutar:  .\install.ps1 -SkipPackages'
}
