#!/usr/bin/env bash
# Hook Stop: si en esta sesión cambió el contenido y la evidencia de la sesión es stale o missing,
# pide una vez (por huella) que se verifique. La decisión la toma `qg session stop` (determinista).
# failed / blocked / incomplete NO bloquean: son resultados legítimos que el reporte debe explicar.
. "$(dirname "$0")/lib/common.sh"

main() {
  qgh_init Stop stop_hook_active || return 0
  qgh_qg -C "$QGH_PROJECT" hooks enabled stop 2>/dev/null || return 0
  local args=(-C "$QGH_PROJECT" session stop --run-id "$QGH_RUN_ID") out decision="" reason="" line
  [ "$(qgh_field stop_hook_active true 2>/dev/null)" = true ] && args+=(--stop-hook-active)
  out=$(qgh_qg "${args[@]}" 2>"$QGH_TMP/.qg") || { qgh_log "qg session stop falló: $(head -n 1 "$QGH_TMP/.qg")"; return 0; }
  while IFS= read -r line; do
    case $line in decision=*) decision=${line#decision=} ;; reason=*) reason=${line#reason=} ;; esac
  done <<EOF
$out
EOF
  [ "$decision" = block ] || return 0
  local msg="agent-quality-gate: hay cambios en esta sesión sin evidencia vigente (qg status: $reason, run-id $QGH_RUN_ID). Ejecuta /quality-gate o explica por qué no corresponde verificar este alcance. Este aviso no se repetirá para el mismo contenido."
  printf '{"decision":"block","reason":%s}\n' "$(qgh_json_str "$msg")"
}

main "$@"
exit 0
