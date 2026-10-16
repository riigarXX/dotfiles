# =============================================================================
#  Helpers compartidos por install.ps1 y theme.ps1.
#
#  Compatible con Windows PowerShell 5.1 *y* PowerShell 7+: install.ps1 puede
#  ejecutarse antes de que pwsh exista en la máquina, así que aquí no se usa
#  sintaxis de PS7 (??, ?:, ?., -AsHashtable, Join-String).
# =============================================================================

$script:DotfilesRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$ESC = [char]27
$RST = "$ESC[0m"
$DIM = "$ESC[2m"
$BOLD = "$ESC[1m"

function Get-DotfilesRoot { return $script:DotfilesRoot }

# ------------------------------------------------------------------- logging --
function Write-DotInfo {
  param([string]$Tag = 'dotfiles', [Parameter(ValueFromRemainingArguments)][string[]]$Message)
  Write-Host "[$Tag] " -ForegroundColor Green -NoNewline
  Write-Host ($Message -join ' ')
}

function Write-DotWarn {
  param([string]$Tag = 'dotfiles', [Parameter(ValueFromRemainingArguments)][string[]]$Message)
  Write-Host "[$Tag] " -ForegroundColor Yellow -NoNewline
  Write-Host ($Message -join ' ')
}

function Write-DotFail {
  param([string]$Tag = 'dotfiles', [Parameter(ValueFromRemainingArguments)][string[]]$Message)
  Write-Host "[$Tag] " -ForegroundColor Red -NoNewline
  Write-Host ($Message -join ' ')
  exit 1
}

# Equivalentes de term_cols/term_rows: [Console]::WindowWidth lanza
# IOException cuando no hay consola adjunta (salida redirigida, tareas, CI).
function Get-DotTermWidth {
  try {
    $w = [Console]::WindowWidth
    if ($w -gt 0) { return $w }
  } catch { }
  try {
    $w = $Host.UI.RawUI.WindowSize.Width
    if ($w -gt 0) { return $w }
  } catch { }
  return 80
}

function Get-DotTermHeight {
  try {
    $h = [Console]::WindowHeight
    if ($h -gt 0) { return $h }
  } catch { }
  try {
    $h = $Host.UI.RawUI.WindowSize.Height
    if ($h -gt 0) { return $h }
  } catch { }
  return 24
}

# ¿Se está dibujando sobre una consola de verdad? (equivalente de [ -t 1 ])
function Test-DotInteractive {
  try {
    if ([Console]::IsOutputRedirected) { return $false }
  } catch {
    return $false
  }
  try {
    $null = [Console]::WindowWidth
    return $true
  } catch {
    return $false
  }
}

function Test-DotCommand {
  param([Parameter(Mandatory)][string]$Name)
  $cmd = Get-Command $Name -CommandType Application, Cmdlet, Function -ErrorAction SilentlyContinue
  return $null -ne $cmd
}

# ------------------------------------------------------------- versiones -----
# LazyVim aborta con "Press any key to exit" en versiones anteriores, y en
# --headless esa espera no termina nunca.
$script:DotNvimMinVersion = [version]'0.11.2'
$script:DotNvimSyncTimeoutSec = 300

# Extrae X.Y.Z de una línea tipo "NVIM v0.11.2" o "ripgrep 14.1.0 (rev ...)".
function ConvertTo-DotVersion {
  param([string]$Line)
  if ($Line -match '(\d+)\.(\d+)\.(\d+)') {
    return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
  }
  return $null
}

# Primera línea de `<cmd> --version` convertida a [version] ($null si no se
# puede). El ErrorActionPreference relajado evita NativeCommandError en PS 5.1.
function Get-DotCommandVersion {
  param([Parameter(Mandatory)][string]$Name)
  if (-not (Test-DotCommand $Name)) { return $null }
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $first = & $Name --version 2>$null | Select-Object -First 1
    return ConvertTo-DotVersion ([string]$first)
  } catch {
    return $null
  } finally {
    $ErrorActionPreference = $prev
  }
}

function Get-DotNvimMinVersion { return $script:DotNvimMinVersion }

function Test-DotNvimVersionOk {
  param($Version)
  if ($null -eq $Version) { return $false }
  return ([version]$Version -ge $script:DotNvimMinVersion)
}

# Sincroniza los plugins de Neovim en silencio. Nunca debe colgar el script:
# se omite si nvim es demasiado antiguo para LazyVim, stdin llega vacío (sin
# teclado al que esperar) y hay un tiempo máximo tras el que se mata el proceso.
function Invoke-DotNvimSync {
  param(
    [string]$Tag = 'dotfiles',
    [int]$TimeoutSec = $script:DotNvimSyncTimeoutSec
  )
  if (-not (Test-DotCommand nvim)) { return $false }

  $version = Get-DotCommandVersion nvim
  if (-not (Test-DotNvimVersionOk $version)) {
    $shown = 'desconocida'
    if ($version) { $shown = "v$version" }
    Write-DotWarn $Tag "Neovim $shown es demasiado antiguo (LazyVim necesita >= $script:DotNvimMinVersion); actualízalo con: winget upgrade --id Neovim.Neovim -e  (o: scoop update neovim)"
    return $false
  }

  $exe = (Get-Command nvim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if (-not $exe) { $exe = 'nvim' }
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-nvim-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null
  $stdin = Join-Path $tmp 'stdin'
  [IO.File]::WriteAllText($stdin, '')
  try {
    # En 5.1 -ArgumentList se concatena sin comillas: se pasa como una sola
    # cadena ya entrecomillada.
    $proc = Start-Process -FilePath $exe -ArgumentList '--headless "+Lazy! sync" +qa' `
      -NoNewWindow -PassThru `
      -RedirectStandardInput $stdin `
      -RedirectStandardOutput (Join-Path $tmp 'stdout') `
      -RedirectStandardError (Join-Path $tmp 'stderr') `
      -ErrorAction Stop
    # Sin cachear el handle, ExitCode queda vacío en Start-Process -PassThru.
    $null = $proc.Handle
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
      Write-DotWarn $Tag "La sincronización de plugins de Neovim superó ${TimeoutSec}s; se ha cancelado"
      # /T arrastra también los git que lanza lazy.nvim.
      $prev = $ErrorActionPreference
      $ErrorActionPreference = 'Continue'
      try { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
      if (-not $proc.HasExited) {
        try { $proc.Kill() } catch { }
      }
      return $false
    }
    $proc.WaitForExit()
    return ($proc.ExitCode -eq 0)
  } catch {
    Write-DotWarn $Tag "No se pudo ejecutar la sincronización de Neovim: $($_.Exception.Message)"
    return $false
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# ----------------------------------------------------------------- symlinks ---
# Windows solo permite crear symlinks con Modo Desarrollador activado o como
# administrador. Si falla, se degrada a junction (directorios) o a copia
# (archivos) para que el setup siga siendo usable.
function Test-DotSymlinkCapable {
  $probeDir = Join-Path $env:TEMP 'dotfiles-symlink-probe'
  $probe = Join-Path $probeDir 'link'
  try {
    if (-not (Test-Path $probeDir)) { New-Item -ItemType Directory -Path $probeDir -Force | Out-Null }
    if (Test-Path $probe) { Remove-Item $probe -Force -Recurse -ErrorAction SilentlyContinue }
    New-Item -ItemType SymbolicLink -Path $probe -Target $probeDir -ErrorAction Stop | Out-Null
    Remove-Item $probe -Force -Recurse -ErrorAction SilentlyContinue
    return $true
  } catch {
    return $false
  } finally {
    Remove-Item $probeDir -Force -Recurse -ErrorAction SilentlyContinue
  }
}

function Get-DotLinkTarget {
  param([Parameter(Mandatory)][string]$Path)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { return $null }
  if ([string]::IsNullOrEmpty($item.LinkType)) { return $null }
  $target = $item.Target
  if ($target -is [array]) { $target = $target[0] }
  if ([string]::IsNullOrEmpty($target)) { return $null }
  return $target.TrimEnd('\')
}

# Equivalente de link() en install.sh: enlaza $Source (real, en el repo) a
# $Target (ruta donde Windows espera encontrarlo), respaldando lo que hubiera.
function New-DotLink {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Target
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    Write-DotWarn install "No existe $Source; omitido"
    return
  }

  $Source = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
  $parent = Split-Path -Parent $Target
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  $existingLink = Get-DotLinkTarget -Path $Target
  if ($existingLink -and $existingLink -ieq $Source) {
    Write-DotInfo install "Ya enlazado: $Target"
    return
  }

  # Si no hubo permiso para symlink en una pasada anterior, el destino es una
  # copia idéntica: no hay que volver a copiarla ni dejar otro .bak en cada
  # ejecución del instalador.
  if (-not $existingLink -and (Test-Path -LiteralPath $Target -PathType Leaf) -and
    (Test-Path -LiteralPath $Source -PathType Leaf)) {
    $hSrc = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $hDst = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash
    if ($hSrc -eq $hDst) {
      Write-DotWarn install "Ya en su sitio como COPIA (no se sincroniza): $Target"
      return
    }
  }

  if (Test-Path -LiteralPath $Target) {
    $backup = "$Target.bak"
    if (Test-Path -LiteralPath $backup) {
      $backup = "$Target.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    }
    Write-DotWarn install "Existe $Target, moviendo a $backup"
    # Un symlink/junction previo se borra en vez de moverse: mover arrastraría
    # el contenido real del destino antiguo.
    if ($existingLink) {
      Remove-Item -LiteralPath $Target -Force -Recurse
    } else {
      Move-Item -LiteralPath $Target -Destination $backup -Force
    }
  }

  $isDir = (Get-Item -LiteralPath $Source -Force).PSIsContainer
  try {
    New-Item -ItemType SymbolicLink -Path $Target -Target $Source -ErrorAction Stop | Out-Null
    Write-DotInfo install "Enlazado: $Target -> $Source"
    return
  } catch {
    if ($isDir) {
      try {
        New-Item -ItemType Junction -Path $Target -Target $Source -ErrorAction Stop | Out-Null
        Write-DotWarn install "Sin permiso para symlink; junction creada: $Target -> $Source"
        return
      } catch { }
    }
    Copy-Item -LiteralPath $Source -Destination $Target -Recurse -Force
    Write-DotWarn install "Sin permiso para symlink; COPIADO (no se sincroniza): $Target"
  }
}

# ------------------------------------------------------------------ hex/rgb ---
function Convert-DotHexToRgb {
  param([Parameter(Mandatory)][string]$Hex)
  $h = $Hex.TrimStart('#')
  return @(
    [Convert]::ToInt32($h.Substring(0, 2), 16),
    [Convert]::ToInt32($h.Substring(2, 2), 16),
    [Convert]::ToInt32($h.Substring(4, 2), 16)
  )
}

function Get-DotFg {
  param([Parameter(Mandatory)][string]$Hex)
  $rgb = Convert-DotHexToRgb $Hex
  return "$ESC[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
}

function Get-DotBg {
  param([Parameter(Mandatory)][string]$Hex)
  $rgb = Convert-DotHexToRgb $Hex
  return "$ESC[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
}

# Oscurece un hex al 45% (bordes del marco del mockup).
function Get-DotDimHex {
  param([Parameter(Mandatory)][string]$Hex)
  $rgb = Convert-DotHexToRgb $Hex
  return ('#{0:X2}{1:X2}{2:X2}' -f [int]($rgb[0] * 0.45), [int]($rgb[1] * 0.45), [int]($rgb[2] * 0.45))
}

# Oscurece manteniendo tono y saturación (luminosidad x 0.55): los segmentos
# del prompt quedan profundos pero vivos, no apagados.
function Get-DotHslDarken {
  param([Parameter(Mandatory)][string]$Hex)
  $rgb = Convert-DotHexToRgb $Hex
  $r = $rgb[0] / 255.0; $g = $rgb[1] / 255.0; $b = $rgb[2] / 255.0
  $mx = [Math]::Max($r, [Math]::Max($g, $b))
  $mn = [Math]::Min($r, [Math]::Min($g, $b))
  $l = ($mx + $mn) / 2.0
  $d = $mx - $mn
  if ($d -eq 0) {
    $hue = 0.0; $s = 0.0
  } else {
    if ($l -le 0.5) { $s = $d / ($mx + $mn) } else { $s = $d / (2.0 - $mx - $mn) }
    if ($mx -eq $r) { $hue = (60 * (($g - $b) / $d) + 360) % 360 }
    elseif ($mx -eq $g) { $hue = 60 * (($b - $r) / $d) + 120 }
    else { $hue = 60 * (($r - $g) / $d) + 240 }
  }
  $l = $l * 0.55

  $c = (1 - [Math]::Abs(2 * $l - 1)) * $s
  $hh = $hue / 60.0
  $x = $c * (1 - [Math]::Abs(($hh % 2) - 1))
  switch ([int][Math]::Floor($hh)) {
    0 { $rr = $c; $gg = $x; $bb = 0 }
    1 { $rr = $x; $gg = $c; $bb = 0 }
    2 { $rr = 0; $gg = $c; $bb = $x }
    3 { $rr = 0; $gg = $x; $bb = $c }
    4 { $rr = $x; $gg = 0; $bb = $c }
    default { $rr = $c; $gg = 0; $bb = $x }
  }
  $m = $l - $c / 2
  return ('#{0:X2}{1:X2}{2:X2}' -f `
      [int][Math]::Round(($rr + $m) * 255), `
      [int][Math]::Round(($gg + $m) * 255), `
      [int][Math]::Round(($bb + $m) * 255))
}

# Color de letra para un fondo dado: oscuro si el fondo es claro y al revés,
# usando la propia paleta del tema (Bg = oscuro, Fg = claro).
function Get-DotSegmentText {
  param(
    [Parameter(Mandatory)][string]$Hex,
    [Parameter(Mandatory)][hashtable]$Theme
  )
  $a = Convert-DotHexToRgb $Hex
  $b = Convert-DotHexToRgb $Theme.Bg
  $la = $a[0] * 212 + $a[1] * 715 + $a[2] * 72
  $lb = $b[0] * 212 + $b[1] * 715 + $b[2] * 72
  if ($la -gt $lb) { return $Theme.Bg }
  return $Theme.Fg
}

# ------------------------------------------------------------------- temas ----
function Get-DotThemeNames {
  $dir = Join-Path (Get-DotfilesRoot) 'themes'
  if (-not (Test-Path -LiteralPath $dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $dir -Directory | Sort-Object Name | ForEach-Object { $_.Name })
}

function Test-DotTheme {
  param([Parameter(Mandatory)][string]$Name)
  return Test-Path -LiteralPath (Join-Path (Get-DotfilesRoot) "themes\$Name")
}

# Equivalente de load_theme() en theme.sh: lee la paleta de ghostty.conf (la
# fuente de verdad de colores, compartida con macOS) y los colores con nombre
# de starship.toml.
function Get-DotTheme {
  param([Parameter(Mandatory)][string]$Name)

  $dir = Join-Path (Get-DotfilesRoot) "themes\$Name"
  $conf = Join-Path $dir 'ghostty.conf'
  $starship = Join-Path $dir 'starship.toml'
  if (-not (Test-Path -LiteralPath $conf)) {
    Write-DotFail theme "El tema '$Name' no tiene ghostty.conf con colores"
  }

  $theme = @{
    Name      = $Name
    Bg        = $null
    Fg        = $null
    Cursor    = $null
    Selection = $null
    Palette   = New-Object 'string[]' 16
    Starship  = @{}
  }

  foreach ($line in (Get-Content -LiteralPath $conf)) {
    $line = $line.Trim()
    if ($line -match '^background\s*=\s*(#[0-9A-Fa-f]{6})') { $theme.Bg = $Matches[1]; continue }
    if ($line -match '^foreground\s*=\s*(#[0-9A-Fa-f]{6})') { $theme.Fg = $Matches[1]; continue }
    if ($line -match '^cursor-color\s*=\s*(#[0-9A-Fa-f]{6})') { $theme.Cursor = $Matches[1]; continue }
    if ($line -match '^selection-background\s*=\s*(#[0-9A-Fa-f]{6})') { $theme.Selection = $Matches[1]; continue }
    if ($line -match '^palette\s*=\s*(\d+)\s*=\s*(#[0-9A-Fa-f]{6})') {
      $idx = [int]$Matches[1]
      if ($idx -ge 0 -and $idx -lt 16) { $theme.Palette[$idx] = $Matches[2] }
    }
  }

  if ([string]::IsNullOrEmpty($theme.Bg)) {
    Write-DotFail theme "El tema '$Name' no tiene ghostty.conf con colores"
  }

  if (Test-Path -LiteralPath $starship) {
    foreach ($line in (Get-Content -LiteralPath $starship)) {
      if ($line -match "^\s*color_([a-z0-9]+)\s*=\s*'?(#[0-9A-Fa-f]{6})'?") {
        $theme.Starship[$Matches[1]] = $Matches[2]
      }
    }
  }

  # Rellena huecos para que quien consuma el tema nunca reciba $null.
  for ($i = 0; $i -lt 16; $i++) {
    if ([string]::IsNullOrEmpty($theme.Palette[$i])) { $theme.Palette[$i] = $theme.Fg }
  }
  if ([string]::IsNullOrEmpty($theme.Cursor)) { $theme.Cursor = $theme.Fg }
  if ([string]::IsNullOrEmpty($theme.Selection)) { $theme.Selection = $theme.Palette[0] }

  return $theme
}

# Accesos con nombre a la paleta, igual que hacen opencode_apply/claude_apply.
function Get-DotThemeColors {
  param([Parameter(Mandatory)][hashtable]$Theme)
  $s = $Theme.Starship
  $muted = $Theme.Palette[8]
  $orange = $Theme.Palette[3]
  if ($s.ContainsKey('orange')) { $orange = $s['orange'] }
  $border = $muted
  if ($s.ContainsKey('bg3')) { $border = $s['bg3'] }
  return @{
    Muted  = $muted
    Red    = $Theme.Palette[1]
    Green  = $Theme.Palette[2]
    Yellow = $Theme.Palette[3]
    Blue   = $Theme.Palette[4]
    Purple = $Theme.Palette[5]
    Cyan   = $Theme.Palette[6]
    Pink   = $Theme.Palette[13]
    Orange = $orange
    Border = $border
  }
}

# -------------------------------------------------------------------- JSON ----
# ConvertFrom-Json devuelve PSCustomObject (y 5.1 no tiene -AsHashtable), así
# que se normaliza a hashtables ordenadas para poder mezclar y reescribir.
function ConvertTo-DotHashtable {
  param($InputObject)
  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
    $out = [ordered]@{}
    foreach ($p in $InputObject.PSObject.Properties) {
      $out[$p.Name] = ConvertTo-DotHashtable $p.Value
    }
    return $out
  }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $out = [ordered]@{}
    foreach ($k in $InputObject.Keys) { $out[$k] = ConvertTo-DotHashtable $InputObject[$k] }
    return $out
  }
  if ($InputObject -is [string]) { return $InputObject }
  if ($InputObject -is [System.Collections.IEnumerable]) {
    $out = New-Object System.Collections.ArrayList
    foreach ($i in $InputObject) { [void]$out.Add((ConvertTo-DotHashtable $i)) }
    return , $out.ToArray()
  }
  return $InputObject
}

function Read-DotJson {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $raw = [System.IO.File]::ReadAllText($Path)
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  # Windows Terminal guarda su settings.json con comentarios // y /* */.
  # ConvertFrom-Json no los acepta en ninguna versión, así que se eliminan
  # (ignorando los que vayan dentro de una cadena).
  $raw = [regex]::Replace($raw, '("(?:\\.|[^"\\])*")|/\*[\s\S]*?\*/|//[^\r\n]*', {
      param($m)
      if ($m.Groups[1].Success) { return $m.Groups[1].Value }
      return ''
    })
  $raw = [regex]::Replace($raw, ',(\s*[}\]])', '$1')
  try {
    return ConvertTo-DotHashtable (ConvertFrom-Json $raw)
  } catch {
    Write-DotWarn theme "No se pudo parsear $Path ($($_.Exception.Message))"
    return $null
  }
}

function Write-DotJson {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Value
  )
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  $json = ConvertTo-Json -InputObject $Value -Depth 64
  # PS 5.1 escapa de más (<, '...) al serializar; se revierte para que
  # el JSON quede legible y diffeable.
  $json = [System.Text.RegularExpressions.Regex]::Replace($json, '\\u([0-9a-fA-F]{4})', {
      param($m)
      $code = [Convert]::ToInt32($m.Groups[1].Value, 16)
      # Deja escapados los caracteres que JSON exige escapar.
      if ($code -lt 0x20) { return $m.Value }
      return [char]$code
    })
  # Sin BOM: Windows Terminal y jq lo prefieren así.
  [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Write-DotText {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Content
  )
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
}

# Mezcla profunda: los valores de $Override ganan. Los arrays se reemplazan
# enteros (no se intenta fusionar elemento a elemento).
function Merge-DotHashtable {
  param($Base, $Override)
  if ($null -eq $Override) { return $Base }
  if ($null -eq $Base) { return $Override }
  if (-not ($Base -is [System.Collections.IDictionary]) -or -not ($Override -is [System.Collections.IDictionary])) {
    return $Override
  }
  $out = [ordered]@{}
  foreach ($k in $Base.Keys) { $out[$k] = $Base[$k] }
  foreach ($k in $Override.Keys) {
    if ($out.Contains($k)) { $out[$k] = Merge-DotHashtable $out[$k] $Override[$k] }
    else { $out[$k] = $Override[$k] }
  }
  return $out
}

# -------------------------------------------------- rutas de config Windows ---
# Documents puede estar redirigido a OneDrive, así que se pregunta a Windows.
function Get-DotDocumentsPath {
  $docs = [Environment]::GetFolderPath('MyDocuments')
  if ([string]::IsNullOrEmpty($docs)) { $docs = Join-Path $HOME 'Documents' }
  return $docs
}

function Get-DotProfilePath {
  return Join-Path (Get-DotDocumentsPath) 'PowerShell\Microsoft.PowerShell_profile.ps1'
}

# Windows Terminal: Store, Preview y la versión sin empaquetar (winget/scoop)
# guardan settings.json en sitios distintos.
function Get-DotWtSettingsPath {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
  )
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  # Aún no se ha abierto nunca: se usa la ruta de la instalación que exista.
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath (Split-Path -Parent $c)) { return $c }
  }
  return $null
}
