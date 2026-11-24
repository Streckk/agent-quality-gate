#!/usr/bin/env bash
# Hook SessionStart: registra la huella inicial de la sesión (solo si el hook Stop está activado).
# No imprime nada, no inyecta contexto, no ejecuta verificaciones y nunca impide iniciar la sesión.
. "$(dirname "$0")/lib/common.sh"

main() {
  qgh_init SessionStart source || return 0
  qgh_qg -C "$QGH_PROJECT" hooks enabled stop 2>/dev/null || return 0
  local source; source=$(qgh_field source string) || source=unknown
  qgh_qg -C "$QGH_PROJECT" session start --run-id "$QGH_RUN_ID" --source "$source" >/dev/null 2>"$QGH_TMP/.qg" ||
    qgh_log "no se pudo registrar el estado inicial: $(head -n 1 "$QGH_TMP/.qg")"
  return 0
}

main "$@"
exit 0
