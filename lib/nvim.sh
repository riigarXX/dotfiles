# shellcheck shell=bash
# =============================================================================
#  Helpers de Neovim compartidos por install.sh y theme.sh (equivalente de
#  Invoke-DotNvimSync en powershell/lib/dotfiles.ps1). Usa el warn() de quien
#  lo carga.
# =============================================================================

# LazyVim aborta con "Press any key to exit" en versiones anteriores, y en
# --headless esa espera no termina nunca.
NVIM_MIN_VERSION="0.11.2"
NVIM_SYNC_TIMEOUT="${NVIM_SYNC_TIMEOUT:-300}"

# 0 si la línea de `nvim --version` ("NVIM v0.11.2", "NVIM v0.12.0-dev...")
# es >= NVIM_MIN_VERSION.
nvim_version_ok() {
  local parsed ma mi pa min_ma min_mi min_pa
  parsed="$(printf '%s\n' "${1:-}" | sed -n 's/^NVIM v\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2 \3/p')"
  [ -n "$parsed" ] || return 1
  read -r ma mi pa <<<"$parsed"
  IFS=. read -r min_ma min_mi min_pa <<<"$NVIM_MIN_VERSION"
  [ $((10#$ma * 1000000 + 10#$mi * 1000 + 10#$pa)) -ge \
    $((10#$min_ma * 1000000 + 10#$min_mi * 1000 + 10#$min_pa)) ]
}

# Avisa (y devuelve 1) si el nvim instalado es demasiado antiguo para LazyVim.
nvim_check_version() {
  local line shown
  line="$(nvim --version 2>/dev/null | head -n 1 || true)"
  nvim_version_ok "$line" && return 0
  shown="${line#NVIM }"
  [ -n "$shown" ] || shown="(versión desconocida)"
  warn "Neovim $shown es demasiado antiguo (LazyVim necesita >= $NVIM_MIN_VERSION); actualízalo con: brew upgrade neovim  (en Linux, el neovim de apt suele estar desfasado: usa el AppImage o el PPA oficial)"
  return 1
}

# Sincroniza los plugins sin colgarse nunca: stdin vacío (nada a lo que
# esperar) y tiempo máximo. macOS no trae `timeout`; se prueba gtimeout
# (coreutils) y si no, perl con alarm.
nvim_sync() {
  command -v nvim >/dev/null 2>&1 || { warn "nvim no está en el PATH; ejecútalo a mano para instalar los plugins"; return 1; }
  nvim_check_version || return 1

  local rc=0
  local -a cmd=(nvim --headless "+Lazy! sync" +qa)
  if command -v timeout >/dev/null 2>&1; then
    timeout "$NVIM_SYNC_TIMEOUT" "${cmd[@]}" </dev/null >/dev/null 2>&1 || rc=$?
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$NVIM_SYNC_TIMEOUT" "${cmd[@]}" </dev/null >/dev/null 2>&1 || rc=$?
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV or exit 127' "$NVIM_SYNC_TIMEOUT" "${cmd[@]}" </dev/null >/dev/null 2>&1 || rc=$?
    # SIGALRM -> 128 + 14
    if [ "$rc" -eq 142 ]; then rc=124; fi
  else
    "${cmd[@]}" </dev/null >/dev/null 2>&1 || rc=$?
  fi

  if [ "$rc" -eq 124 ]; then
    warn "La sincronización de plugins de Neovim superó ${NVIM_SYNC_TIMEOUT}s; se ha cancelado"
  fi
  return "$rc"
}
