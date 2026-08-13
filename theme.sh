#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$DOTFILES_DIR/themes"
GHOSTTY_ACTIVE="$DOTFILES_DIR/ghostty/theme.conf"
STARSHIP_ACTIVE="$DOTFILES_DIR/starship.toml"
NVIM_ACTIVE="$DOTFILES_DIR/nvim/lua/plugins/colorscheme.lua"
ZSH_ACTIVE="$HOME/.config/zsh-colors.sh"
OPENCODE_THEMES="$DOTFILES_DIR/opencode/themes"
OPENCODE_TUI="$DOTFILES_DIR/opencode/tui.json"
CLAUDE_THEMES="$DOTFILES_DIR/claude/themes"
CLAUDE_SETTINGS="$DOTFILES_DIR/claude/settings.json"

RST=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'

warn() { printf "\033[1;33m[theme]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[theme]\033[0m %s\n" "$*"; exit 1; }

available_themes() {
  ls -d "$THEMES_DIR"/*/ 2>/dev/null | xargs -n1 basename
}

ensure_theme() {
  [ -d "$THEMES_DIR/$1" ] || err "Tema '$1' no existe. Disponibles: $(available_themes | tr '\n' ' ')"
}

# ---------------------------------------------------------------- hex/rgb ---
fg() { printf '\033[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
bg() { printf '\033[48;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }

# Oscurece un hex (para bordes del marco del mockup y segmentos del prompt)
dim_hex() {
  local h="$1"
  printf '#%02X%02X%02X' \
    $(( (16#${h:1:2}) * 45 / 100 )) \
    $(( (16#${h:3:2}) * 45 / 100 )) \
    $(( (16#${h:5:2}) * 45 / 100 ))
}

# Color de letra para un fondo dado: oscuro si el fondo es claro, claro si no.
# Usa la propia paleta del tema (T_BG = oscuro, T_FG = claro).
seg_text() {
  local h="$1"
  local lseg=$(( (16#${h:1:2}) * 212 + (16#${h:3:2}) * 715 + (16#${h:5:2}) * 72 ))
  local ltbg=$(( (16#${T_BG:1:2}) * 212 + (16#${T_BG:3:2}) * 715 + (16#${T_BG:5:2}) * 72 ))
  if [ "$lseg" -gt "$ltbg" ]; then printf '%s' "$T_BG"; else printf '%s' "$T_FG"; fi
}

# Oscurece un color manteniendo tono y saturación (luminosidad × 0.55).
# Así los segmentos del prompt quedan profundos pero vivos, no apagados.
hsl_darken() {
  local h="$1" r g b mx mn d l s hu hh frac c x m
  local rr gg bb
  r=$((16#${h:1:2})); g=$((16#${h:3:2})); b=$((16#${h:5:2}))
  mx=$r; [ "$g" -gt "$mx" ] && mx=$g; [ "$b" -gt "$mx" ] && mx=$b
  mn=$r; [ "$g" -lt "$mn" ] && mn=$g; [ "$b" -lt "$mn" ] && mn=$b
  d=$((mx - mn))
  l=$(( (mx + mn) * 50 / 255 ))   # luminosidad 0..100
  if [ "$d" -eq 0 ]; then
    s=0; hu=0
  else
    if [ "$l" -le 50 ]; then s=$(( d * 100 / (mx + mn) ))
    else s=$(( d * 100 / (510 - mx - mn) )); fi
    if [ "$mx" -eq "$r" ]; then hu=$(( (60 * (g - b) / d + 360) % 360 ))
    elif [ "$mx" -eq "$g" ]; then hu=$(( 60 * (b - r) / d + 120 ))
    else hu=$(( 60 * (r - g) / d + 240 )); fi
  fi
  l=$(( l * 55 / 100 ))
  c=$(( (100 - ((2 * l > 100) ? (2 * l - 100) : (100 - 2 * l))) * s * 255 / 10000 ))
  hh=$(( hu / 60 )); frac=$(( hu % 60 ))
  if [ $((hh % 2)) -eq 0 ]; then x=$(( c * frac / 60 )); else x=$(( c * (60 - frac) / 60 )); fi
  case $hh in
    0) rr=$c; gg=$x; bb=0 ;;
    1) rr=$x; gg=$c; bb=0 ;;
    2) rr=0; gg=$c; bb=$x ;;
    3) rr=0; gg=$x; bb=$c ;;
    4) rr=$x; gg=0; bb=$c ;;
    *) rr=$c; gg=0; bb=$x ;;
  esac
  m=$(( l * 255 / 100 - c / 2 ))
  printf '#%02X%02X%02X' $((rr + m)) $((gg + m)) $((bb + m))
}

# Ancho "visible" en celdas (sin códigos ANSI, contando multibyte como 1 celda).
# 100% bash: salta exactamente cada secuencia \e[...m (su cuerpo solo tiene
# dígitos y ';', por eso el primer 'm' tras '[' la termina).
visw() {
  local s=$1 n=0 rest
  while [ -n "$s" ]; do
    rest=${s%%$'\e'*}
    n=$((n + ${#rest}))
    [ "${#rest}" -eq "${#s}" ] && break
    s=${s#*$'\e['}
    s=${s#*m}
  done
  printf '%s' "$n"
}

# Ancho del terminal en columnas (stty lee de stdin, que sí es la tty;
# tput dentro de $(...) falla porque su stdout es un pipe)
term_cols() {
  { stty size 2>/dev/null || echo "0 80"; } | awk '{print $2}'
}

term_rows() {
  { stty size 2>/dev/null || echo "24 0"; } | awk '{print $1}'
}

# -------------------------------------------------- carga de colores del tema -
# Deja en globales: T_BG T_FG T_CUR T_P[0..15] y T_S_* (paleta de starship)
load_theme() {
  local t="$1"
  local conf="$THEMES_DIR/$t/ghostty.conf"
  local sp="$THEMES_DIR/$t/starship.toml"
  local line k v
  T_BG=""; T_FG=""; T_CUR=""; T_P=()
  # parseo 100% bash: sin subprocesos por clave (una lectura del archivo)
  while IFS= read -r line; do
    case $line in
      'background = '*)            T_BG=${line#*= } ;;
      'foreground = '*)            T_FG=${line#*= } ;;
      'cursor-color = '*)          T_CUR=${line#*= } ;;
      'selection-background = '*)  T_SEL=${line#*= } ;;
      'palette = '*=*) k=${line#palette = }; k=${k%%=*}; v=${line#* = }; v=${v#*=}; T_P[$k]=$v ;;
    esac
  done < "$conf"
  while IFS= read -r line; do
    case $line in
      'color_'*' = '*) k=${line#color_}; k=${k%% = *}; v=${line#* = }; v=${v//\'/}
        case $k in
          orange) T_S_ORANGE=$v ;; yellow) T_S_YELLOW=$v ;; aqua) T_S_AQUA=$v ;;
          blue)   T_S_BLUE=$v   ;; bg1)    T_S_BG1=$v    ;; bg3)  T_S_BG3=$v ;;
          green)  T_S_GREEN=$v  ;; red)    T_S_RED=$v    ;; purple) T_S_PURPLE=$v ;;
          fg0)    T_S_FG0=$v ;;
        esac ;;
    esac
  done < "$sp"
  [ -n "$T_BG" ] || err "El tema '$t' no tiene ghostty.conf con colores"
}

# ------------------------------------- mockup: captura de terminal del tema --
# Deja en global: MOCK (líneas ya coloreadas y con ancho fijo)
MOCK=()
BD=''   # color del marco
CX=0    # ancho de contenido interior

# Escapes a variables sin subproceso (printf -v): evita ~200 forks por dibujo
bg_esc() { printf -v "$1" '\033[48;2;%d;%d;%dm' "0x${2:1:2}" "0x${2:3:2}" "0x${2:5:2}"; }
fg_esc() { printf -v "$1" '\033[38;2;%d;%d;%dm' "0x${2:1:2}" "0x${2:3:2}" "0x${2:5:2}"; }

mock_in() {  # fila interior: │ fondo del tema + contenido + relleno + │
  local content="$1" vis pad pad_s eBG fBD
  vis=$(visw "$content")
  pad=$((CX - vis))
  [ "$pad" -lt 0 ] && pad=0
  bg_esc eBG "$T_BG"; fg_esc fBD "$BD"
  # tras cada reset interno, repintar el fondo de la fila: nada transparente
  content=${content//$RST/${RST}${eBG}}
  printf -v pad_s '%*s' "$pad" ''
  MOCK+=("${eBG}${fBD}│${content}${eBG}${pad_s}${fBD}│${RST}")
}

mockup_build() {  # mockup_build <tema> <ancho total> [compacto]
  local t="$1" W="$2" compact="${3:-}"
  local IN=$((W - 2))   # entre │ y │
  CX=$((W - 2))
  local i segment d1 d2 mid name row strip nums
  local eBG fBD fFG eCUR fR fY fG
  local eDO fDO eDYe fDYe eDA fDA eDB1 fDB1 fO fYe fA fB1
  MOCK=()
  load_theme "$t"
  BD=$(dim_hex "$T_FG")
  bg_esc eBG "$T_BG"; fg_esc fBD "$BD"; fg_esc fFG "$T_FG"
  bg_esc eCUR "$T_CUR"
  fg_esc fR '#FF5F56'; fg_esc fY '#FFBD2E'; fg_esc fG '#27C93F'

  # ── marco superior: semáforos de macOS + título ──
  mid="zsh — 80×24"
  name=" $t "
  segment=$((IN - 8))   # entre el prefijo ┌─● ● ●─ y el sufijo ─┐
  d1=$(( (segment - ${#mid} - ${#name}) / 2 )); [ "$d1" -lt 1 ] && d1=1
  d2=$((segment - ${#mid} - ${#name} - d1));   [ "$d2" -lt 1 ] && d2=1
  local d1s d2s
  printf -v d1s '%*s' "$d1" ''; d1s=${d1s// /─}
  printf -v d2s '%*s' "$d2" ''; d2s=${d2s// /─}
  row="${eBG}${fBD}┌─"
  row+="${fR}● ${fY}● ${fG}●"
  row+="${fBD}─"
  row+="${d1s}${mid}${BOLD}${fFG}${name}${RST}${eBG}${fBD}${d2s}─┐${RST}"
  MOCK+=("$row")

  # ── prompt de starship, dos líneas como el real: módulos arriba ──
  #    segmentos oscurecidos y letra oscura sobre fondo claro (y viceversa)
  local DO DYe DA DB1 tO tYe tA tB1
  DO=$(hsl_darken "$T_S_ORANGE"); DYe=$(hsl_darken "$T_S_YELLOW")
  DA=$(hsl_darken "$T_S_AQUA");   DB1=$(hsl_darken "$T_S_BG1")
  tO=$(seg_text "$DO"); tYe=$(seg_text "$DYe")
  tA=$(seg_text "$DA"); tB1=$(seg_text "$DB1")
  bg_esc eDO "$DO";  fg_esc fDO "$DO";  fg_esc fO "$tO"
  bg_esc eDYe "$DYe"; fg_esc fDYe "$DYe"; fg_esc fYe "$tYe"
  bg_esc eDA "$DA";  fg_esc fDA "$DA";  fg_esc fA "$tA"
  bg_esc eDB1 "$DB1"; fg_esc fDB1 "$DB1"; fg_esc fB1 "$tB1"
  mock_in "${eDO}${fDO} ${RST}${eDO}${fO}󰀵 rigarxx ${RST}${eDYe}${fDO} ${RST}${eDYe}${fYe}…/dotfiles ${RST}${eDA}${fDYe} ${RST}${eDA}${fA}main ${RST}${eDB1}${fDA} ${RST}${eDB1}${fB1}19:56 ${RST}${fDB1} ${RST}"
  #    y abajo el símbolo de prompt con el comando
  mock_in "$(fg "$T_S_GREEN")❯${RST}$(fg "$T_FG") ls -a"
  mock_in "  $(fg "$T_S_BLUE")Documents${RST}$(fg "$T_FG")  $(fg "$T_S_BLUE")Downloads${RST}$(fg "$T_FG")  $(fg "$T_S_BLUE")Pictures${RST}$(fg "$T_FG")  $(fg "$T_S_BLUE")nvim${RST}$(fg "$T_FG")  theme.sh"
  mock_in "$(fg "$T_S_GREEN")❯${RST}$(fg "$T_FG") nvim $(fg "${T_P[8]}")lua/plugins/colorscheme.lua${RST}"
  # ── buffer de nvim con sintaxis ──
  mock_in "  1  $(fg "$T_S_PURPLE")local${RST}$(fg "$T_FG") theme = $(fg "$T_S_GREEN")\"$t\"${RST}"
  mock_in "  2  $(fg "$T_S_PURPLE")vim.cmd${RST}$(fg "$T_FG").colorscheme(theme)${RST}"
  # ── línea del cursor ──
  mock_in "  3  ${eCUR}$(fg "$T_BG")  ${RST}"
  # ── paleta completa (celdas de 2 + separador, alineadas con los números) ──
  strip=" "
  for ((i = 0; i < 16; i++)); do
    bg_esc eP "${T_P[$i]}"
    strip+="${eP}  ${RST} "
  done
  mock_in "$strip"
  if [ -z "$compact" ]; then
    nums=" "
    for ((i = 0; i < 16; i++)); do printf -v nums '%s%2s ' "$nums" "$i"; done
    mock_in "$nums"
  fi
  # ── marco inferior ──
  local ins
  printf -v ins '%*s' "$IN" ''; ins=${ins// /─}
  MOCK+=("${eBG}${fBD}└${ins}┘${RST}")
}

# ------------------------------------------------------------ panel del menú --
MENU=()

menu_build() {  # usa THEMES (global), IDX y T_S_ORANGE del tema seleccionado
  local i t
  MENU=()
  MENU+=("  ${BOLD}▸ Temas disponibles${RST}")
  MENU+=("")
  for i in "${!THEMES[@]}"; do
    t="${THEMES[$i]}"
    if [ "$i" -eq "$IDX" ]; then
      MENU+=("    $(fg "$T_S_ORANGE")▶${RST}${BOLD} $t${RST}")
    else
      MENU+=("      $t")
    fi
  done
  MENU+=("")
  MENU+=("  ${DIM}↑/↓ mover · Enter · q salir${RST}")
}

# ------------------------------------------------------------ previsualizar -
preview() {
  ensure_theme "$1"
  local cols W l
  cols=$(term_cols); [ -z "$cols" ] && cols=80
  W=$((cols - 4)); [ "$W" -gt 96 ] && W=96; [ "$W" -lt 52 ] && W=52
  mockup_build "$1" "$W"
  for l in "${MOCK[@]}"; do printf '%s\n' "$l"; done
  printf '\n  %s  %s\n\n' \
    "$(fg "$T_BG")██${RST} $T_BG" \
    "$(fg "$T_FG")██${RST} $T_FG  $(fg "$T_CUR")██${RST} $T_CUR"
}

# ------------------------------------------------ opencode (tema TUI) --------
# Genera opencode/themes/<tema>.json desde la paleta del tema y selecciona ese
# tema en opencode/tui.json (enlazados a ~/.config/opencode por install.sh).
# Los fondos quedan "none" (transparentes) para heredar la opacidad del
# terminal (ghostty background-opacity).
opencode_apply() {
  local t="$1"
  local out="$OPENCODE_THEMES/$t.json"
  local body="" nl=""
  local bg="${T_P[8]:-$T_FG}"      # muted / comment
  local red="${T_P[1]:-$T_FG}"
  local green="${T_P[2]:-$T_FG}"
  local yellow="${T_P[3]:-$T_FG}"
  local blue="${T_P[4]:-$T_FG}"
  local purple="${T_P[5]:-$T_FG}"
  local cyan="${T_P[6]:-$T_FG}"
  local orange="${T_S_ORANGE:-$yellow}"
  local bd="${T_S_BG3:-$bg}"       # borde sutil (panel del tema)

  add() { body+="${nl}    \"$1\": $2"; nl=$',\n'; }
  q()   { printf '"%s"' "$1"; }

  # semánticos
  add primary "$(q "$blue")"
  add secondary "$(q "$purple")"
  add accent "$(q "$cyan")"
  add error "$(q "$red")"
  add warning "$(q "$yellow")"
  add success "$(q "$green")"
  add info "$(q "$cyan")"
  # texto
  add text "$(q "$T_FG")"
  add textMuted "$(q "$bg")"
  add selectedListItemText "$(q "$T_BG")"
  # fondos: "none" = transparente (hereda la opacidad del terminal)
  add background "$(q none)"
  add backgroundPanel "$(q none)"
  add backgroundElement "$(q none)"
  add backgroundMenu "$(q "${T_BG}B3")"
  # bordes
  add border "$(q "$bd")"
  add borderActive "$(q "$blue")"
  add borderSubtle "$(q "$bd")"
  # diffs (fondo con tinte semi-transparente)
  add diffAdded "$(q "$green")"
  add diffRemoved "$(q "$red")"
  add diffContext "$(q "$T_FG")"
  add diffHunkHeader "$(q "$bg")"
  add diffHighlightAdded "$(q "$green")"
  add diffHighlightRemoved "$(q "$red")"
  add diffAddedBg "$(q "${green}33")"
  add diffRemovedBg "$(q "${red}33")"
  add diffContextBg "$(q none)"
  add diffLineNumber "$(q "$bg")"
  add diffAddedLineNumberBg "$(q "${green}1A")"
  add diffRemovedLineNumberBg "$(q "${red}1A")"
  # markdown
  add markdownText "$(q "$T_FG")"
  add markdownHeading "$(q "$blue")"
  add markdownLink "$(q "$cyan")"
  add markdownLinkText "$(q "$blue")"
  add markdownCode "$(q "$green")"
  add markdownBlockQuote "$(q "$bg")"
  add markdownEmph "$(q "$yellow")"
  add markdownStrong "$(q "$T_FG")"
  add markdownHorizontalRule "$(q "$bg")"
  add markdownListItem "$(q "$blue")"
  add markdownListEnumeration "$(q "$cyan")"
  add markdownImage "$(q "$blue")"
  add markdownImageText "$(q "$cyan")"
  add markdownCodeBlock "$(q "$T_FG")"
  # sintaxis
  add syntaxComment "$(q "$bg")"
  add syntaxKeyword "$(q "$purple")"
  add syntaxFunction "$(q "$blue")"
  add syntaxVariable "$(q "$T_FG")"
  add syntaxString "$(q "$green")"
  add syntaxNumber "$(q "$orange")"
  add syntaxType "$(q "$cyan")"
  add syntaxOperator "$(q "$cyan")"
  add syntaxPunctuation "$(q "$T_FG")"

  {
    printf '%s\n' '{'
    printf '%s\n' '  "$schema": "https://opencode.ai/theme.json",'
    printf '%s\n' '  "theme": {'
    printf '%b\n' "$body"
    printf '%s\n' '  }'
    printf '%s\n' '}'
  } > "$out"

  if [ -f "$OPENCODE_TUI" ]; then
    local tmp
    tmp=$(mktemp)
    jq --arg t "$t" '.theme = $t' "$OPENCODE_TUI" > "$tmp" && mv "$tmp" "$OPENCODE_TUI"
  else
    printf '{\n  "$schema": "https://opencode.ai/tui.json",\n  "theme": "%s"\n}\n' "$t" > "$OPENCODE_TUI"
  fi
}

# ------------------------------------------------------------ claude (tema) --
# Genera claude/themes/<tema>.json (formato de temas de Claude Code: base
# "dark" + overrides de la paleta) y fija "theme": "custom:<tema>" en
# claude/settings.json (enlazado a ~/.claude/settings.json por install.sh).
# Claude Code recarga claude/themes al vuelo; solo hay que reiniciar si el
# directorio no existía cuando arrancó la sesión.
claude_apply() {
  local t="$1"
  local out="$CLAUDE_THEMES/$t.json"
  local body="" nl=""
  local bg="${T_P[8]:-$T_FG}"      # muted / inactive
  local red="${T_P[1]:-$T_FG}"
  local green="${T_P[2]:-$T_FG}"
  local yellow="${T_P[3]:-$T_FG}"
  local blue="${T_P[4]:-$T_FG}"
  local purple="${T_P[5]:-$T_FG}"
  local cyan="${T_P[6]:-$T_FG}"
  local orange="${T_S_ORANGE:-$yellow}"
  local bd="${T_S_BG3:-$bg}"       # borde sutil
  local dgreen dred
  dgreen=$(hsl_darken "$green")    # fondo de líneas añadidas
  dred=$(hsl_darken "$red")        # fondo de líneas eliminadas

  add() { body+="${nl}    \"$1\": $2"; nl=$',\n'; }
  q()   { printf '"%s"' "$1"; }

  # acento de marca y texto
  add claude "$(q "$blue")"
  add claudeShimmer "$(q "$cyan")"
  add text "$(q "$T_FG")"
  add inverseText "$(q "$T_BG")"
  add inactive "$(q "$bg")"
  add inactiveShimmer "$(q "$bd")"
  add subtle "$(q "$bd")"
  add suggestion "$(q "$cyan")"
  add permission "$(q "$blue")"
  add remember "$(q "$orange")"
  # estados
  add success "$(q "$green")"
  add error "$(q "$red")"
  add warning "$(q "$yellow")"
  add warningShimmer "$(q "$orange")"
  add merged "$(q "$purple")"
  # borde del input y modos
  add promptBorder "$(q "$blue")"
  add promptBorderShimmer "$(q "$cyan")"
  add planMode "$(q "$purple")"
  add autoAccept "$(q "$green")"
  add bashBorder "$(q "$cyan")"
  add ide "$(q "$orange")"
  add fastMode "$(q "$yellow")"
  add fastModeShimmer "$(q "$orange")"
  # diffs: fondo oscurecido, palabra en color vivo
  add diffAdded "$(q "$dgreen")"
  add diffRemoved "$(q "$dred")"
  add diffAddedDimmed "$(q "$bg")"
  add diffRemovedDimmed "$(q "$bg")"
  add diffAddedWord "$(q "$green")"
  add diffRemovedWord "$(q "$red")"
  # modo fullscreen (fondos de mensajes)
  add userMessageBackground "$(q "$T_BG")"
  add userMessageBackgroundHover "$(q "$bd")"
  add bashMessageBackgroundColor "$(q "$bd")"
  add memoryBackgroundColor "$(q "$bd")"
  add selectionBg "$(q "${T_SEL:-$bd}")"
  # medidor de uso y etiquetas de rol
  add rate_limit_fill "$(q "$blue")"
  add rate_limit_empty "$(q "$bd")"
  add briefLabelYou "$(q "$cyan")"
  add briefLabelClaude "$(q "$blue")"
  # colores de subagentes
  add red_FOR_SUBAGENTS_ONLY "$(q "$red")"
  add blue_FOR_SUBAGENTS_ONLY "$(q "$blue")"
  add green_FOR_SUBAGENTS_ONLY "$(q "$green")"
  add yellow_FOR_SUBAGENTS_ONLY "$(q "$yellow")"
  add purple_FOR_SUBAGENTS_ONLY "$(q "$purple")"
  add orange_FOR_SUBAGENTS_ONLY "$(q "$orange")"
  add pink_FOR_SUBAGENTS_ONLY "$(q "${T_P[13]:-$purple}")"
  add cyan_FOR_SUBAGENTS_ONLY "$(q "$cyan")"
  # rainbow del prompt (ultrathink)
  add rainbow_red "$(q "$red")"
  add rainbow_orange "$(q "$orange")"
  add rainbow_yellow "$(q "$yellow")"
  add rainbow_green "$(q "$green")"
  add rainbow_blue "$(q "$blue")"
  add rainbow_indigo "$(q "$blue")"
  add rainbow_violet "$(q "$purple")"

  {
    printf '%s\n' '{'
    printf '%s\n' '  "name": "'"$t"'",'
    printf '%s\n' '  "base": "dark",'
    printf '%s\n' '  "overrides": {'
    printf '%b\n' "$body"
    printf '%s\n' '  }'
    printf '%s\n' '}'
  } > "$out"

  if [ -f "$CLAUDE_SETTINGS" ]; then
    local tmp
    tmp=$(mktemp)
    jq --arg t "custom:$t" '.theme = $t' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
  else
    printf '{\n  "$schema": "https://json.schemastore.org/claude-code-settings.json",\n  "theme": "custom:%s"\n}\n' "$t" > "$CLAUDE_SETTINGS"
  fi
}

# ------------------------------------------------------------ aplicar --------
apply() {
  local t="$1"
  ensure_theme "$t"

  local steps=(
    "ghostty → theme.conf"
    "starship → starship.toml"
    "zsh → ~/.config/zsh-colors.sh"
    "opencode → themes/$t.json"
    "claude → themes/$t.json"
    "nvim → colorscheme.lua"
  )
  local n=${#steps[@]} i j label fill b
  local cols bw
  cols=$(term_cols); [ -z "$cols" ] && cols=80

  for ((i = 0; i < n; i++)); do
    label="${steps[$i]}"
    if [ -t 1 ]; then
      bw=$((cols - 5 - ${#label})); [ "$bw" -lt 10 ] && bw=10
      fill=$(( (i + 1) * bw / n ))
      b=""
      for ((j = 0; j < bw; j++)); do
        [ "$j" -lt "$fill" ] && b+="█" || b+=" "
      done
      printf '\r  [%s] %s' "$b" "$label"
      sleep 0.12
    else
      printf '  → %s\n' "$label"
    fi

    case "$i" in
      0) cp "$THEMES_DIR/$t/ghostty.conf" "$GHOSTTY_ACTIVE" ;;
      1) cp "$THEMES_DIR/$t/starship.toml" "$STARSHIP_ACTIVE" ;;
      2) cp "$THEMES_DIR/$t/zsh.sh" "$ZSH_ACTIVE" ;;
      3)
        load_theme "$t"
        mkdir -p "$OPENCODE_THEMES"
        opencode_apply "$t"
        ;;
      4)
        load_theme "$t"
        mkdir -p "$CLAUDE_THEMES"
        claude_apply "$t"
        ;;
      5)
        if ! cmp -s "$THEMES_DIR/$t/nvim.lua" "$NVIM_ACTIVE"; then
          cp "$THEMES_DIR/$t/nvim.lua" "$NVIM_ACTIVE"
          nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || warn "Ejecuta 'nvim' manualmente para terminar de instalar"
        fi
        ;;
    esac
  done

  [ -t 1 ] && printf '\r\033[K'
  printf "\n${BOLD}\033[1;32m✔ Tema %s aplicado${RST}\n" "$t"
  printf "  • starship/zsh: recarga con:  source ~/.zshrc\n"
  printf "  • ghostty:       reinicia la app (Cmd+Q) — el recargado no aplica la paleta al 100%%\n"
  printf "  • nvim:          ya está listo\n"
  printf "  • opencode:      reinicia la app para ver el tema nuevo\n"
  printf "  • claude:        se recarga solo (vigila ~/.claude/themes)\n\n"
}

# ------------------------------------------------------------ menú interactivo
# globales: THEMES (array), IDX (selección actual)
THEMES=()
IDX=0
PICKER_DRAWN=0

draw_picker() {
  local cols rows LW=34 PW=56 i l r vis pad compact=""
  cols=$(term_cols); [ -z "$cols" ] && cols=80
  rows=$(term_rows); [ -z "$rows" ] && rows=24
  [ "$rows" -lt 23 ] && compact=1   # terminales bajas: sin fila de números
  if [ "$PICKER_DRAWN" -ne 1 ]; then
    # solo el primer dibujo limpia la pantalla; el resto se repinta en sitio
    printf '\033[2J'
    PICKER_DRAWN=1
  fi
  printf '\033[H'

  if [ "$cols" -ge $((LW + 52 + 4)) ]; then
    # lado a lado: el preview ocupa el ancho disponible (más grande)
    PW=$((cols - LW - 4)); [ "$PW" -gt 96 ] && PW=96; [ "$PW" -lt 52 ] && PW=52
    mockup_build "${THEMES[$IDX]}" "$PW" "$compact"
    menu_build
    for ((i = 0; i < ${#MOCK[@]}; i++)); do
      l="${MENU[$i]:-}"
      r="${MOCK[$i]:-}"
      vis=$(visw "$l")
      pad=$((LW - vis)); [ "$pad" -lt 0 ] && pad=0
      printf '%s%*s%s\033[K\n' "$l" "$pad" "" "$r"
    done
  else
    # estrecho: menú arriba, captura debajo a todo el ancho
    PW=$((cols - 4)); [ "$PW" -gt 96 ] && PW=96; [ "$PW" -lt 52 ] && PW=52
    mockup_build "${THEMES[$IDX]}" "$PW" "$compact"
    menu_build
    for l in "${MENU[@]}"; do printf '%s\033[K\n' "$l"; done
    printf '\033[K\n'
    for r in "${MOCK[@]}"; do printf '%s\033[K\n' "$r"; done
  fi

  printf '\033[K\n  %s%s%s  ·  %s  %s  %s\033[K\n' \
    "${BOLD}" "${THEMES[$IDX]}" "${RST}" \
    "$(fg "$T_BG")██${RST} $T_BG" \
    "$(fg "$T_FG")██${RST} $T_FG" \
    "$(fg "$T_CUR")██${RST} $T_CUR"
}

interactive() {
  local d old_stty key rest done=0
  THEMES=()
  for d in "$THEMES_DIR"/*/; do THEMES+=("$(basename "$d")"); done
  [ "${#THEMES[@]}" -eq 0 ] && err "No hay temas en $THEMES_DIR"

  old_stty=$(stty -g 2>/dev/null || true)
  # -icrnl: que el Enter llegue como CR (sin mapearse a \n, que read -n1
  # descartaría como delimitador en bash 3.2)
  stty -icanon -echo -icrnl 2>/dev/null || true
  tput civis 2>/dev/null || true
  trap 'stty "$old_stty" 2>/dev/null || true; tput cnorm 2>/dev/null || true' EXIT

  while [ "$done" -eq 0 ]; do
    draw_picker
    if ! read -r -s -n1 key; then key=""; done=1; continue; fi
    case "$key" in
      $'\x1b')
        if read -r -s -n2 -t 1 rest; then
          case "$rest" in
            '[A') [ "$IDX" -gt 0 ] && IDX=$((IDX - 1)) ;;
            '[B') [ "$IDX" -lt $((${#THEMES[@]} - 1)) ] && IDX=$((IDX + 1)) ;;
          esac
        else
          done=1
        fi
        ;;
      [kK]) [ "$IDX" -gt 0 ] && IDX=$((IDX - 1)) ;;
      [jJ]) [ "$IDX" -lt $((${#THEMES[@]} - 1)) ] && IDX=$((IDX + 1)) ;;
      $'\r'|'') done=2 ;;   # Enter (o \n, que read descarta dejando key vacía)
      [qQ]) done=1 ;;
      *)
        if [[ "$key" =~ ^[0-9]$ ]] && [ "$key" -ge 1 ] && [ "$key" -le "${#THEMES[@]}" ]; then
          IDX=$((key - 1))
        fi
        ;;
    esac
  done

  stty "$old_stty" 2>/dev/null || true
  tput cnorm 2>/dev/null || true
  trap - EXIT
  printf '\033[2J\033[H'

  if [ "$done" -eq 1 ]; then
    echo "  Cancelado."
    return
  fi

  local t="${THEMES[$IDX]}"
  apply "$t"
}

# ------------------------------------------------------------------ main -----
# Solo corre cuando se ejecuta como script; si se hace source (para generar
# temas en bucles) la entrada queda disponible sin disparar el menú.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return
fi

case "${1:-}" in
  "" ) interactive ;;
  list | ls )
    echo "Temas disponibles:"
    available_themes | nl -w2 -s') '
    ;;
  preview ) preview "$2" ;;
  apply ) apply "$2" ;;
  * ) err "Uso: theme.sh [list|preview <tema>|apply <tema>]" ;;
esac
