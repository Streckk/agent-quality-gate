# Funciones comunes de los hooks de agent-quality-gate. Se carga con ". lib/common.sh".
# Principios (docs/hooks.md):
#   - Los hooks nunca invocan modelos ni ejecutan verificaciones: solo consultan a qg.
#   - Cualquier fallo interno termina con exit 0 y sin decisión: un error del hook nunca bloquea.
#   - La entrada JSON no es de confianza: se valida con un parser estricto y nunca se interpola en shell.

QGH_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
QGH_ROOT=$(cd "$QGH_LIB/../.." && pwd -P)
# Con el plugin cargado, CLAUDE_PLUGIN_ROOT apunta a la raíz del plugin; si no, se usa la del repo.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "${CLAUDE_PLUGIN_ROOT}/bin/qg" ]; then QGH_ROOT=$CLAUDE_PLUGIN_ROOT; fi
QG_BIN="$QGH_ROOT/bin/qg"
QGH_EVENT=""
QGH_TMP=""

qgh_log() { printf 'agent-quality-gate[%s]: %s\n' "${QGH_EVENT:-hook}" "$*" >&2; }
qgh_qg() { "${BASH:-bash}" "$QG_BIN" "$@"; }
qgh_cleanup() { [ -n "$QGH_TMP" ] && rm -rf "$QGH_TMP"; }

# Cadena JSON segura para la salida.
qgh_json_str() {
  local v=$1
  v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//$'\n'/\\n}; v=${v//$'\r'/\\r}; v=${v//$'\t'/\\t}
  v=$(printf '%s' "$v" | LC_ALL=C tr -d '\000-\010\013\014\016-\037')
  printf '"%s"' "$v"
}

# Valor de un campo extraído por json.awk ("" si no existe o no es del tipo indicado).
qgh_field() {   # $1 = ruta (con . → _), $2 = tipo esperado (opcional)
  local f="$QGH_TMP/$1"
  [ -f "$f" ] || return 1
  if [ -n "${2:-}" ]; then [ "$(cat "$f.type" 2>/dev/null)" = "$2" ] || return 1; fi
  cat "$f"
}

# Inicializa: comprueba la desactivación global, parsea stdin, valida el evento y deriva el run-id.
# Define QGH_RUN_ID, QGH_CWD (cwd del JSON) y QGH_PROJECT (raíz donde empezó la sesión).
qgh_init() {   # $1 = evento esperado, $2 = rutas JSON adicionales
  QGH_EVENT=$1
  case $(printf '%s' "${QG_DISABLE:-}" | tr 'A-Z' 'a-z') in ""|0|false|no|off) ;; *) return 1 ;; esac
  [ -x "$QG_BIN" ] || { qgh_log "no se encuentra qg en $QG_BIN"; return 1; }
  QGH_TMP=$(mktemp -d "${TMPDIR:-/tmp}/qg-hook.XXXXXX") || return 1
  trap qgh_cleanup EXIT
  if ! LC_ALL=C awk -v outdir="$QGH_TMP" -v want="session_id,hook_event_name,cwd${2:+,$2}" \
       -f "$QGH_LIB/json.awk" 2>"$QGH_TMP/.err"; then
    qgh_log "entrada JSON inválida; el hook no actúa ($(head -n 1 "$QGH_TMP/.err"))"
    return 1
  fi
  local ev sid
  ev=$(qgh_field hook_event_name string) || ev=""
  [ "$ev" = "$1" ] || { qgh_log "evento inesperado '$ev'; el hook no actúa"; return 1; }
  sid=$(qgh_field session_id string) || sid=""
  QGH_RUN_ID=$(qgh_qg session id "$sid" 2>/dev/null) || { qgh_log "session_id ausente o inválido; el hook no actúa"; return 1; }
  QGH_CWD=$(qgh_field cwd string) || QGH_CWD=""
  case $QGH_CWD in /*) [ -d "$QGH_CWD" ] || QGH_CWD="" ;; *) QGH_CWD="" ;; esac
  QGH_PROJECT=${CLAUDE_PROJECT_DIR:-}
  case $QGH_PROJECT in /*) [ -d "$QGH_PROJECT" ] || QGH_PROJECT="" ;; *) QGH_PROJECT="" ;; esac
  [ -n "$QGH_PROJECT" ] || QGH_PROJECT=$QGH_CWD
  [ -n "$QGH_PROJECT" ] || { qgh_log "sin directorio de proyecto válido; el hook no actúa"; return 1; }
  return 0
}
