#Requires -Version 5.1
# =============================================================================
#  theme.ps1 — equivalente de theme.sh en Windows.
#
#  Uso:  .\theme.ps1 [list | preview <tema> | apply <tema>]
#        sin argumentos abre el selector interactivo.
#
#  La fuente de verdad de los colores sigue siendo themes/<tema>/ghostty.conf,
#  compartida con macOS. Lo único que cambia es a dónde se aplica: en vez de
#  ghostty/theme.conf se genera un color scheme para Windows Terminal, y en vez
#  de ~/.config/zsh-colors.sh se genera powershell/colors.ps1.
# =============================================================================

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command,
  [Parameter(Position = 1)][string]$Name
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powershell\lib\dotfiles.ps1')

$Root = Get-DotfilesRoot
$ThemesDir = Join-Path $Root 'themes'
$WtBase = Join-Path $Root 'windows-terminal\settings.json'
$WtActive = Join-Path $Root 'windows-terminal\theme.json'
$StarshipActive = Join-Path $Root 'starship.toml'
$PsColorsActive = Join-Path $Root 'powershell\colors.ps1'
$NvimActive = Join-Path $Root 'nvim\lua\plugins\colorscheme.lua'
$OpencodeThemes = Join-Path $Root 'opencode\themes'
$OpencodeTui = Join-Path $Root 'opencode\tui.json'
$ClaudeThemes = Join-Path $Root 'claude\themes'
$ClaudeSettings = Join-Path $Root 'claude\settings.json'

function Assert-Theme {
  param([string]$ThemeName)
  if ([string]::IsNullOrWhiteSpace($ThemeName)) {
    Write-DotFail theme "Falta el nombre del tema. Disponibles: $((Get-DotThemeNames) -join ' ')"
  }
  if (-not (Test-DotTheme $ThemeName)) {
    Write-DotFail theme "Tema '$ThemeName' no existe. Disponibles: $((Get-DotThemeNames) -join ' ')"
  }
}

# Ancho "visible" en celdas: sin códigos ANSI y contando los glifos Nerd Font
# fuera del BMP (pares surrogate) como una sola celda.
function Get-DotVisibleWidth {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return 0 }
  $plain = [regex]::Replace($Text, "$ESC\[[0-9;]*m", '')
  $n = 0
  for ($i = 0; $i -lt $plain.Length; $i++) {
    if ([char]::IsLowSurrogate($plain[$i])) { continue }
    $n++
  }
  return $n
}

# =========================================================== Windows Terminal =
# Genera el color scheme del tema y lo inyecta en el settings.json real de
# Windows Terminal, mezclándolo con windows-terminal/settings.json (la base
# versionada) y preservando lo que no gestionamos (perfiles, por ejemplo).
function New-DotWtScheme {
  param([Parameter(Mandatory)][hashtable]$Theme)
  $p = $Theme.Palette
  return [ordered]@{
    name                = $Theme.Name
    background          = $Theme.Bg
    foreground          = $Theme.Fg
    cursorColor         = $Theme.Cursor
    selectionBackground = $Theme.Selection
    black               = $p[0]
    red                 = $p[1]
    green               = $p[2]
    yellow              = $p[3]
    blue                = $p[4]
    purple              = $p[5]
    cyan                = $p[6]
    white               = $p[7]
    brightBlack         = $p[8]
    brightRed           = $p[9]
    brightGreen         = $p[10]
    brightYellow        = $p[11]
    brightBlue          = $p[12]
    brightPurple        = $p[13]
    brightCyan          = $p[14]
    brightWhite         = $p[15]
  }
}

function Sync-DotWindowsTerminal {
  param([Parameter(Mandatory)][hashtable]$Scheme)

  $base = Read-DotJson $WtBase
  if ($null -eq $base) {
    Write-DotWarn theme "No se pudo leer $WtBase; se omite Windows Terminal"
    return
  }

  $livePath = Get-DotWtSettingsPath
  if (-not $livePath) {
    Write-DotWarn theme 'Windows Terminal no está instalado; solo se guardó windows-terminal/theme.json'
    return
  }

  $out = Read-DotJson $livePath
  if ($null -eq $out) { $out = [ordered]@{} }

  # 1) Claves globales de la base (todo menos lo que se trata aparte).
  $special = @('profiles', 'actions', 'keybindings', 'schemes', 'defaultProfile')
  foreach ($k in $base.Keys) {
    if ($special -notcontains $k) { $out[$k] = $base[$k] }
  }

  # 2) schemes: upsert por nombre, respetando los demás esquemas del usuario.
  #    La comparación es sensible a mayúsculas (-ceq) a propósito: así solo se
  #    reemplaza el esquema que escribimos nosotros y no uno del usuario que se
  #    llame igual con otra capitalización ("Dracula" vs "dracula").
  $schemes = New-Object System.Collections.ArrayList
  $replaced = $false
  if ($out.Contains('schemes') -and $out['schemes']) {
    foreach ($s in @($out['schemes'])) {
      if ($s -is [System.Collections.IDictionary] -and $s['name'] -ceq $Scheme['name']) {
        [void]$schemes.Add($Scheme); $replaced = $true
      } else {
        [void]$schemes.Add($s)
      }
    }
  }
  if (-not $replaced) { [void]$schemes.Add($Scheme) }
  $out['schemes'] = $schemes.ToArray()

  # 3) profiles.defaults: base gana; profiles.list no se toca nunca (ahí viven
  #    los perfiles dinámicos que detecta Windows Terminal).
  $outProfiles = [ordered]@{}
  if ($out.Contains('profiles')) {
    if ($out['profiles'] -is [System.Collections.IDictionary]) {
      foreach ($k in $out['profiles'].Keys) { $outProfiles[$k] = $out['profiles'][$k] }
    } elseif ($out['profiles']) {
      # Formato antiguo: "profiles" era directamente la lista.
      $outProfiles['list'] = @($out['profiles'])
    }
  }
  $defaults = [ordered]@{}
  if ($outProfiles.Contains('defaults') -and $outProfiles['defaults'] -is [System.Collections.IDictionary]) {
    $defaults = $outProfiles['defaults']
  }
  if ($base.Contains('profiles') -and $base['profiles'] -is [System.Collections.IDictionary] -and $base['profiles'].Contains('defaults')) {
    $defaults = Merge-DotHashtable $defaults $base['profiles']['defaults']
  }
  $defaults['colorScheme'] = $Scheme['name']
  $outProfiles['defaults'] = $defaults
  $out['profiles'] = $outProfiles

  # 4) actions: la base manda. "keybindings" es el nombre antiguo y entra en
  #    conflicto, así que se elimina.
  if ($base.Contains('actions')) { $out['actions'] = $base['actions'] }
  if ($out.Contains('keybindings')) { $out.Remove('keybindings') }

  # 5) defaultProfile: solo si ese perfil existe de verdad, para no dejar
  #    Windows Terminal apuntando a un GUID inexistente.
  if ($base.Contains('defaultProfile')) {
    $guid = $base['defaultProfile']
    $exists = $false
    if ($outProfiles.Contains('list')) {
      foreach ($p in @($outProfiles['list'])) {
        if ($p -is [System.Collections.IDictionary] -and $p['guid'] -eq $guid) { $exists = $true; break }
      }
    }
    if ($exists -or -not $out.Contains('defaultProfile')) { $out['defaultProfile'] = $guid }
  }

  Write-DotJson -Path $livePath -Value $out
}

# ================================================================ PowerShell ==
# Equivalente de themes/<tema>/zsh.sh: colores de PSReadLine (resaltado de la
# línea de comandos) + LS_COLORS, que lsd y eza también respetan en Windows.
function New-DotPsColors {
  param([Parameter(Mandatory)][hashtable]$Theme)

  $c = Get-DotThemeColors $Theme

  $lsColors = ''
  $zshFile = Join-Path $ThemesDir "$($Theme.Name)\zsh.sh"
  if (Test-Path -LiteralPath $zshFile) {
    foreach ($line in (Get-Content -LiteralPath $zshFile)) {
      if ($line -match '^\s*export\s+LS_COLORS="(.*)"\s*$') { $lsColors = $Matches[1] }
    }
  }

  # PSReadLine acepta secuencias ANSI, no hex. En el archivo generado se
  # escriben como "$e[...m" (con $e = ESC), que es legible y además funciona
  # tanto en PowerShell 5.1 como en 7+ (el escape `e es solo de 7+).
  function esc([string]$hex) {
    $rgb = Convert-DotHexToRgb $hex
    return "`$e[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
  }
  function escBg([string]$hex) {
    $rgb = Convert-DotHexToRgb $hex
    return "`$e[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
  }

  $colors = [ordered]@{
    Command                = esc $c.Blue
    Comment                = esc $c.Muted
    ContinuationPrompt     = esc $c.Muted
    Default                = esc $Theme.Fg
    Emphasis               = esc $c.Orange
    Error                  = esc $c.Red
    InlinePrediction       = esc $c.Muted
    Keyword                = esc $c.Purple
    ListPrediction         = esc $c.Muted
    Member                 = esc $Theme.Fg
    Number                 = esc $c.Orange
    Operator               = esc $c.Cyan
    Parameter              = esc $c.Cyan
    String                 = esc $c.Green
    Type                   = esc $c.Cyan
    Variable               = esc $Theme.Fg
    Selection              = (escBg $Theme.Selection) + (esc $Theme.Fg)
    ListPredictionSelected = (escBg $Theme.Selection) + (esc $Theme.Fg)
  }

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("# Colores del tema $($Theme.Name) (generado por theme.ps1)")
  [void]$sb.AppendLine('# No editar a mano: se reescribe en cada `theme apply`.')
  [void]$sb.AppendLine('')
  if ($lsColors) {
    [void]$sb.AppendLine('# lsd y eza leen LS_COLORS igual que en macOS.')
    [void]$sb.AppendLine("`$env:LS_COLORS = '$($lsColors.Replace("'", "''"))'")
    [void]$sb.AppendLine('')
  }
  [void]$sb.AppendLine('$e = [char]27')
  [void]$sb.AppendLine('if (Get-Module PSReadLine) {')
  [void]$sb.AppendLine('  Set-PSReadLineOption -Colors @{')
  foreach ($k in $colors.Keys) {
    [void]$sb.AppendLine("    $k = `"$($colors[$k])`"")
  }
  [void]$sb.AppendLine('  }')
  [void]$sb.AppendLine('}')

  Write-DotText -Path $PsColorsActive -Content $sb.ToString()
}

# ================================================================== opencode ==
# Genera opencode/themes/<tema>.json desde la paleta y selecciona ese tema en
# opencode/tui.json. Los fondos quedan "none" (transparentes) para heredar la
# opacidad del terminal (Windows Terminal: profiles.defaults.opacity).
function Set-DotOpencodeTheme {
  param([Parameter(Mandatory)][hashtable]$Theme)

  $c = Get-DotThemeColors $Theme
  $t = [ordered]@{
    # semánticos
    primary                 = $c.Blue
    secondary               = $c.Purple
    accent                  = $c.Cyan
    error                   = $c.Red
    warning                 = $c.Yellow
    success                 = $c.Green
    info                    = $c.Cyan
    # texto
    text                    = $Theme.Fg
    textMuted               = $c.Muted
    selectedListItemText    = $Theme.Bg
    # fondos: "none" = transparente
    background              = 'none'
    backgroundPanel         = 'none'
    backgroundElement       = 'none'
    backgroundMenu          = "$($Theme.Bg)B3"
    # bordes
    border                  = $c.Border
    borderActive            = $c.Blue
    borderSubtle            = $c.Border
    # diffs
    diffAdded               = $c.Green
    diffRemoved             = $c.Red
    diffContext             = $Theme.Fg
    diffHunkHeader          = $c.Muted
    diffHighlightAdded      = $c.Green
    diffHighlightRemoved    = $c.Red
    diffAddedBg             = "$($c.Green)33"
    diffRemovedBg           = "$($c.Red)33"
    diffContextBg           = 'none'
    diffLineNumber          = $c.Muted
    diffAddedLineNumberBg   = "$($c.Green)1A"
    diffRemovedLineNumberBg = "$($c.Red)1A"
    # markdown
    markdownText            = $Theme.Fg
    markdownHeading         = $c.Blue
    markdownLink            = $c.Cyan
    markdownLinkText        = $c.Blue
    markdownCode            = $c.Green
    markdownBlockQuote      = $c.Muted
    markdownEmph            = $c.Yellow
    markdownStrong          = $Theme.Fg
    markdownHorizontalRule  = $c.Muted
    markdownListItem        = $c.Blue
    markdownListEnumeration = $c.Cyan
    markdownImage           = $c.Blue
    markdownImageText       = $c.Cyan
    markdownCodeBlock       = $Theme.Fg
    # sintaxis
    syntaxComment           = $c.Muted
    syntaxKeyword           = $c.Purple
    syntaxFunction          = $c.Blue
    syntaxVariable          = $Theme.Fg
    syntaxString            = $c.Green
    syntaxNumber            = $c.Orange
    syntaxType              = $c.Cyan
    syntaxOperator          = $c.Cyan
    syntaxPunctuation       = $Theme.Fg
  }

  Write-DotJson -Path (Join-Path $OpencodeThemes "$($Theme.Name).json") -Value ([ordered]@{
      '$schema' = 'https://opencode.ai/theme.json'
      theme     = $t
    })

  $tui = Read-DotJson $OpencodeTui
  if ($null -eq $tui) { $tui = [ordered]@{ '$schema' = 'https://opencode.ai/tui.json' } }
  $tui['theme'] = $Theme.Name
  Write-DotJson -Path $OpencodeTui -Value $tui
}

# ==================================================================== claude ==
# Genera claude/themes/<tema>.json (base "dark" + overrides de la paleta) y fija
# "theme": "custom:<tema>" en claude/settings.json. Claude Code recarga
# ~/.claude/themes al vuelo.
function Set-DotClaudeTheme {
  param([Parameter(Mandatory)][hashtable]$Theme)

  $c = Get-DotThemeColors $Theme
  $dgreen = Get-DotHslDarken $c.Green
  $dred = Get-DotHslDarken $c.Red

  $o = [ordered]@{
    # acento de marca y texto
    claude                    = $c.Blue
    claudeShimmer             = $c.Cyan
    text                      = $Theme.Fg
    inverseText               = $Theme.Bg
    inactive                  = $c.Muted
    inactiveShimmer           = $c.Border
    subtle                    = $c.Border
    suggestion                = $c.Cyan
    permission                = $c.Blue
    remember                  = $c.Orange
    # estados
    success                   = $c.Green
    error                     = $c.Red
    warning                   = $c.Yellow
    warningShimmer            = $c.Orange
    merged                    = $c.Purple
    # borde del input y modos
    promptBorder              = $c.Blue
    promptBorderShimmer       = $c.Cyan
    planMode                  = $c.Purple
    autoAccept                = $c.Green
    bashBorder                = $c.Cyan
    ide                       = $c.Orange
    fastMode                  = $c.Yellow
    fastModeShimmer           = $c.Orange
    # diffs
    diffAdded                 = $dgreen
    diffRemoved               = $dred
    diffAddedDimmed           = $c.Muted
    diffRemovedDimmed         = $c.Muted
    diffAddedWord             = $c.Green
    diffRemovedWord           = $c.Red
    # modo fullscreen
    userMessageBackground     = $Theme.Bg
    userMessageBackgroundHover = $c.Border
    bashMessageBackgroundColor = $c.Border
    memoryBackgroundColor     = $c.Border
    selectionBg               = $Theme.Selection
    # medidor de uso y etiquetas de rol
    rate_limit_fill           = $c.Blue
    rate_limit_empty          = $c.Border
    briefLabelYou             = $c.Cyan
    briefLabelClaude          = $c.Blue
    # colores de subagentes
    red_FOR_SUBAGENTS_ONLY    = $c.Red
    blue_FOR_SUBAGENTS_ONLY   = $c.Blue
    green_FOR_SUBAGENTS_ONLY  = $c.Green
    yellow_FOR_SUBAGENTS_ONLY = $c.Yellow
    purple_FOR_SUBAGENTS_ONLY = $c.Purple
    orange_FOR_SUBAGENTS_ONLY = $c.Orange
    pink_FOR_SUBAGENTS_ONLY   = $c.Pink
    cyan_FOR_SUBAGENTS_ONLY   = $c.Cyan
    # rainbow del prompt (ultrathink)
    rainbow_red               = $c.Red
    rainbow_orange            = $c.Orange
    rainbow_yellow            = $c.Yellow
    rainbow_green             = $c.Green
    rainbow_blue              = $c.Blue
    rainbow_indigo            = $c.Blue
    rainbow_violet            = $c.Purple
  }

  Write-DotJson -Path (Join-Path $ClaudeThemes "$($Theme.Name).json") -Value ([ordered]@{
      name      = $Theme.Name
      base      = 'dark'
      overrides = $o
    })

  $settings = Read-DotJson $ClaudeSettings
  if ($null -eq $settings) {
    $settings = [ordered]@{ '$schema' = 'https://json.schemastore.org/claude-code-settings.json' }
  }
  $settings['theme'] = "custom:$($Theme.Name)"
  Write-DotJson -Path $ClaudeSettings -Value $settings
}

# ======================================================= mockup del terminal ==
$script:Mock = @()
$script:MockTheme = $null
$script:MockBorder = ''
$script:MockWidth = 0

function Add-DotMockRow {
  param([string]$Content)
  $eBG = Get-DotBg $script:MockTheme.Bg
  $fBD = Get-DotFg $script:MockBorder
  $vis = Get-DotVisibleWidth $Content
  $pad = $script:MockWidth - $vis
  if ($pad -lt 0) { $pad = 0 }
  # Tras cada reset interno hay que repintar el fondo de la fila: nada
  # transparente dentro del marco.
  $Content = $Content.Replace($RST, "$RST$eBG")
  $script:Mock += "$eBG$fBD│$Content$eBG$(' ' * $pad)$fBD│$RST"
}

function Build-DotMockup {
  param(
    [Parameter(Mandatory)][string]$ThemeName,
    [Parameter(Mandatory)][int]$Width,
    [switch]$Compact
  )

  $t = Get-DotTheme $ThemeName
  $c = Get-DotThemeColors $t
  $s = $t.Starship

  $script:Mock = @()
  $script:MockTheme = $t
  $script:MockBorder = Get-DotDimHex $t.Fg
  $script:MockWidth = $Width - 2
  $inner = $Width - 2

  $eBG = Get-DotBg $t.Bg
  $fBD = Get-DotFg $script:MockBorder
  $fFG = Get-DotFg $t.Fg
  $eCUR = Get-DotBg $t.Cursor
  $fClose = Get-DotFg '#FF5F56'

  # ── marco superior: controles de ventana de Windows a la derecha + título ──
  $mid = 'pwsh — 120×32'
  $name = " $ThemeName "
  $ctrlVis = 6                       # "─ ▫ ✕ "
  $segment = $inner - 1 - $ctrlVis
  $d1 = [int][Math]::Floor(($segment - $mid.Length - $name.Length) / 2)
  if ($d1 -lt 1) { $d1 = 1 }
  $d2 = $segment - $mid.Length - $name.Length - $d1
  if ($d2 -lt 1) { $d2 = 1 }
  $row = "$eBG$fBD┌─" + ('─' * $d1) + $mid + "$BOLD$fFG$name$RST$eBG$fBD" + ('─' * $d2)
  $row += "─ ▫ $fClose✕ $fBD┐$RST"
  $script:Mock += $row

  # ── prompt de starship, dos líneas como el real ──
  $darkOrange = Get-DotHslDarken $c.Orange
  $yellowSrc = $c.Yellow
  if ($s.ContainsKey('yellow')) { $yellowSrc = $s['yellow'] }
  $aquaSrc = $c.Cyan
  if ($s.ContainsKey('aqua')) { $aquaSrc = $s['aqua'] }
  $bg1Src = $c.Border
  if ($s.ContainsKey('bg1')) { $bg1Src = $s['bg1'] }
  $darkYellow = Get-DotHslDarken $yellowSrc
  $darkAqua = Get-DotHslDarken $aquaSrc
  $darkBg1 = Get-DotHslDarken $bg1Src

  $tO = Get-DotSegmentText $darkOrange $t
  $tYe = Get-DotSegmentText $darkYellow $t
  $tA = Get-DotSegmentText $darkAqua $t
  $tB1 = Get-DotSegmentText $darkBg1 $t

  $eDO = Get-DotBg $darkOrange; $fDO = Get-DotFg $darkOrange; $fO = Get-DotFg $tO
  $eDYe = Get-DotBg $darkYellow; $fDYe = Get-DotFg $darkYellow; $fYe = Get-DotFg $tYe
  $eDA = Get-DotBg $darkAqua; $fDA = Get-DotFg $darkAqua; $fA = Get-DotFg $tA
  $eDB1 = Get-DotBg $darkBg1; $fDB1 = Get-DotFg $darkBg1; $fB1 = Get-DotFg $tB1

  # Mismos segmentos que el mockup de theme.sh; 󰍲 es el símbolo de Windows en
  # starship (os.symbols.Windows) donde macOS usa 󰀵.
  Add-DotMockRow "$eDO$fDO $RST$eDO$fO󰍲 rigarxx $RST$eDYe$fDO $RST$eDYe${fYe}…/dotfiles $RST$eDA$fDYe $RST$eDA${fA}main $RST$eDB1$fDA $RST$eDB1${fB1}19:56 $RST$fDB1 $RST"

  $fGreen = Get-DotFg $c.Green
  $fBlue = Get-DotFg $c.Blue
  $fPurple = Get-DotFg $c.Purple
  $fMuted = Get-DotFg $t.Palette[8]

  Add-DotMockRow "$fGreen❯$RST$fFG ls -a"
  Add-DotMockRow "  ${fBlue}Documents$RST$fFG  ${fBlue}Downloads$RST$fFG  ${fBlue}Pictures$RST$fFG  ${fBlue}nvim$RST$fFG  theme.ps1"
  # Ojo con ${}: sin las llaves, PowerShell se comería la palabra siguiente
  # como parte del nombre de la variable ($fMutedlua, $fPurplelocal...).
  Add-DotMockRow "$fGreen❯$RST$fFG nvim ${fMuted}lua/plugins/colorscheme.lua$RST"
  # ── buffer de nvim con sintaxis ──
  Add-DotMockRow "  1  ${fPurple}local$RST$fFG theme = $fGreen`"$ThemeName`"$RST"
  Add-DotMockRow "  2  ${fPurple}vim.cmd$RST$fFG.colorscheme(theme)$RST"
  # ── línea del cursor ──
  Add-DotMockRow "  3  $eCUR$(Get-DotFg $t.Bg)  $RST"
  # ── paleta completa ──
  $strip = ' '
  for ($i = 0; $i -lt 16; $i++) {
    $strip += "$(Get-DotBg $t.Palette[$i])  $RST "
  }
  Add-DotMockRow $strip
  if (-not $Compact) {
    $nums = ' '
    for ($i = 0; $i -lt 16; $i++) { $nums += ('{0,2} ' -f $i) }
    Add-DotMockRow $nums
  }
  # ── marco inferior ──
  $script:Mock += "$eBG$fBD└" + ('─' * $inner) + "┘$RST"

  return $t
}

# ============================================================== previsualizar =
function Show-DotPreview {
  param([Parameter(Mandatory)][string]$ThemeName)
  Assert-Theme $ThemeName

  $cols = Get-DotTermWidth
  $w = $cols - 4
  if ($w -gt 96) { $w = 96 }
  if ($w -lt 52) { $w = 52 }

  $t = Build-DotMockup -ThemeName $ThemeName -Width $w
  foreach ($l in $script:Mock) { Write-Host $l }
  Write-Host ''
  Write-Host ("  {0}██{1} {2}  {3}██{4} {5}  {6}██{7} {8}" -f `
    (Get-DotFg $t.Bg), $RST, $t.Bg, `
    (Get-DotFg $t.Fg), $RST, $t.Fg, `
    (Get-DotFg $t.Cursor), $RST, $t.Cursor)
  Write-Host ''
}

# =================================================================== aplicar ==
function Invoke-DotApply {
  param([Parameter(Mandatory)][string]$ThemeName)
  Assert-Theme $ThemeName

  $steps = @(
    'windows terminal → settings.json',
    'starship → starship.toml',
    'powershell → powershell/colors.ps1',
    "opencode → themes/$ThemeName.json",
    "claude → themes/$ThemeName.json",
    'nvim → colorscheme.lua'
  )
  $n = $steps.Count
  $cols = Get-DotTermWidth
  $interactive = Test-DotInteractive

  $theme = Get-DotTheme $ThemeName

  for ($i = 0; $i -lt $n; $i++) {
    $label = $steps[$i]
    if ($interactive) {
      $bw = $cols - 5 - $label.Length
      if ($bw -lt 10) { $bw = 10 }
      $fill = [int](($i + 1) * $bw / $n)
      $bar = ('█' * $fill) + (' ' * ($bw - $fill))
      Write-Host "`r  [$bar] $label" -NoNewline
      Start-Sleep -Milliseconds 120
    } else {
      Write-Host "  → $label"
    }

    switch ($i) {
      0 {
        $scheme = New-DotWtScheme -Theme $theme
        Write-DotJson -Path $WtActive -Value $scheme
        Sync-DotWindowsTerminal -Scheme $scheme
      }
      1 {
        Copy-Item -LiteralPath (Join-Path $ThemesDir "$ThemeName\starship.toml") -Destination $StarshipActive -Force
      }
      2 {
        New-DotPsColors -Theme $theme
      }
      3 {
        if (-not (Test-Path -LiteralPath $OpencodeThemes)) {
          New-Item -ItemType Directory -Path $OpencodeThemes -Force | Out-Null
        }
        Set-DotOpencodeTheme -Theme $theme
      }
      4 {
        if (-not (Test-Path -LiteralPath $ClaudeThemes)) {
          New-Item -ItemType Directory -Path $ClaudeThemes -Force | Out-Null
        }
        Set-DotClaudeTheme -Theme $theme
      }
      5 {
        $src = Join-Path $ThemesDir "$ThemeName\nvim.lua"
        $same = $false
        if (Test-Path -LiteralPath $NvimActive) {
          $same = -not (Compare-Object `
              (Get-Content -LiteralPath $src -Raw) `
              (Get-Content -LiteralPath $NvimActive -Raw))
        }
        if (-not $same) {
          Copy-Item -LiteralPath $src -Destination $NvimActive -Force
          if (-not (Invoke-DotNvimSync -Tag theme)) {
            Write-DotWarn theme "Ejecuta 'nvim' manualmente para terminar de instalar los plugins"
          }
        }
      }
    }
  }

  if ($interactive) { Write-Host "`r$ESC[K" -NoNewline }
  Write-Host ''
  Write-Host "✔ Tema $ThemeName aplicado" -ForegroundColor Green
  Write-Host '  • powershell/starship: recarga con:  reload'
  Write-Host '  • windows terminal:    se recarga solo al guardar settings.json'
  Write-Host '  • nvim:                ya está listo'
  Write-Host '  • opencode:            reinicia la app para ver el tema nuevo'
  Write-Host '  • claude:              se recarga solo (vigila ~/.claude/themes)'
  Write-Host ''
}

# ======================================================== menú interactivo ====
function Show-DotPicker {
  $themes = Get-DotThemeNames
  if ($themes.Count -eq 0) { Write-DotFail theme "No hay temas en $ThemesDir" }
  if (-not (Test-DotInteractive)) {
    Write-DotFail theme 'El selector necesita una consola. Usa: theme.ps1 apply <tema>'
  }

  $idx = 0
  $drawn = $false
  $result = 0   # 1 = cancelado, 2 = aplicar

  try {
    try { [Console]::CursorVisible = $false } catch { }
    while ($result -eq 0) {
      $cols = Get-DotTermWidth
      $rows = Get-DotTermHeight
      $compact = $rows -lt 23          # terminales bajas: sin fila de números

      $lw = 34
      $out = New-Object System.Text.StringBuilder
      if (-not $drawn) {
        # solo el primer dibujo limpia la pantalla; el resto se repinta en sitio
        [void]$out.Append("$ESC[2J")
        $drawn = $true
      }
      [void]$out.Append("$ESC[H")

      if ($cols -ge ($lw + 52 + 4)) {
        $pw = $cols - $lw - 4
        if ($pw -gt 96) { $pw = 96 }
        if ($pw -lt 52) { $pw = 52 }
        $t = Build-DotMockup -ThemeName $themes[$idx] -Width $pw -Compact:$compact
        $menu = Build-DotMenu -Themes $themes -Index $idx -Theme $t
        for ($i = 0; $i -lt $script:Mock.Count; $i++) {
          $l = ''
          if ($i -lt $menu.Count) { $l = $menu[$i] }
          $r = $script:Mock[$i]
          $pad = $lw - (Get-DotVisibleWidth $l)
          if ($pad -lt 0) { $pad = 0 }
          [void]$out.Append("$l$(' ' * $pad)$r$ESC[K`n")
        }
      } else {
        $pw = $cols - 4
        if ($pw -gt 96) { $pw = 96 }
        if ($pw -lt 52) { $pw = 52 }
        $t = Build-DotMockup -ThemeName $themes[$idx] -Width $pw -Compact:$compact
        $menu = Build-DotMenu -Themes $themes -Index $idx -Theme $t
        foreach ($l in $menu) { [void]$out.Append("$l$ESC[K`n") }
        [void]$out.Append("$ESC[K`n")
        foreach ($r in $script:Mock) { [void]$out.Append("$r$ESC[K`n") }
      }

      [void]$out.Append("$ESC[K`n")
      [void]$out.Append(("  {0}{1}{2}  ·  {3}██{2} {4}  {5}██{2} {6}  {7}██{2} {8}$ESC[K`n" -f `
            $BOLD, $themes[$idx], $RST, `
          (Get-DotFg $t.Bg), $t.Bg, `
          (Get-DotFg $t.Fg), $t.Fg, `
          (Get-DotFg $t.Cursor), $t.Cursor))
      [Console]::Write($out.ToString())

      $key = [Console]::ReadKey($true)
      switch ($key.Key) {
        'UpArrow' { if ($idx -gt 0) { $idx-- } }
        'DownArrow' { if ($idx -lt $themes.Count - 1) { $idx++ } }
        'K' { if ($idx -gt 0) { $idx-- } }
        'J' { if ($idx -lt $themes.Count - 1) { $idx++ } }
        'Enter' { $result = 2 }
        'Q' { $result = 1 }
        'Escape' { $result = 1 }
        default {
          if ($key.KeyChar -match '^[1-9]$') {
            $pick = [int][string]$key.KeyChar
            if ($pick -le $themes.Count) { $idx = $pick - 1 }
          }
        }
      }
    }
  } finally {
    try { [Console]::CursorVisible = $true } catch { }
  }

  [Console]::Write("$ESC[2J$ESC[H")

  if ($result -eq 1) {
    Write-Host '  Cancelado.'
    return
  }
  Invoke-DotApply -ThemeName $themes[$idx]
}

function Build-DotMenu {
  param(
    [Parameter(Mandatory)][string[]]$Themes,
    [Parameter(Mandatory)][int]$Index,
    [Parameter(Mandatory)][hashtable]$Theme
  )
  $c = Get-DotThemeColors $Theme
  $menu = @("  $BOLD▸ Temas disponibles$RST", '')
  for ($i = 0; $i -lt $Themes.Count; $i++) {
    if ($i -eq $Index) {
      $menu += "    $(Get-DotFg $c.Orange)▶$RST$BOLD $($Themes[$i])$RST"
    } else {
      $menu += "      $($Themes[$i])"
    }
  }
  $menu += ''
  $menu += "  $DIM↑/↓ mover · Enter · q salir$RST"
  return $menu
}

# ====================================================================== main ==
if ($null -eq $Command) { $Command = '' }

switch ($Command) {
  '' {
    Show-DotPicker
  }
  { $_ -in @('list', 'ls') } {
    Write-Host 'Temas disponibles:'
    $i = 1
    foreach ($t in (Get-DotThemeNames)) {
      Write-Host ('{0,2}) {1}' -f $i, $t)
      $i++
    }
  }
  'preview' { Show-DotPreview -ThemeName $Name }
  'apply' { Invoke-DotApply -ThemeName $Name }
  default { Write-DotFail theme 'Uso: theme.ps1 [list|preview <tema>|apply <tema>]' }
}
