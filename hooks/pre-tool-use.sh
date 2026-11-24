#!/usr/bin/env bash
# Hook PreToolUse (matcher Bash). Complementa los permisos nativos; nunca concede permisos ("allow").
#   A. git commit cuyo mensaje contiene trailers/créditos de IA → deny.
#      Mensaje no verificable (-F fuera del repo, -c/-C, ruta no literal) → ask.
#   B. git push / gh pr create sin evidencia `valid` de la sesión → ask (decide la persona).
# Límites: analiza el texto del comando Bash; no ve scripts, alias, wrappers ni otras herramientas.
. "$(dirname "$0")/lib/common.sh"

# Límite de palabra: cualquier carácter que no forme parte de un nombre de comando/opción.
QGH_B='(^|[^A-Za-z0-9_.-])'
QGH_E='([^A-Za-z0-9_-]|$)'
# Trailers y créditos de IA prohibidos (insensible a mayúsculas).
QGH_TRAILERS='co-authored-by[[:space:]]*:|co-developed-by[[:space:]]*:|(generated|assisted|created|written)[[:space:]_-]+(by|with)[[:space:]]*:?[[:space:]]*\[?[[:space:]]*(claude|codex|chatgpt|anthropic|openai|copilot|gemini)'

has_word() { grep -Eq -- "${QGH_B}$1${QGH_E}" "$CMD"; }
has_trailer_file() { LC_ALL=C grep -Eiq -- "$QGH_TRAILERS" "$1"; }

decide() {   # $1 = deny|ask, $2 = motivo
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}\n' \
    "$1" "$(qgh_json_str "agent-quality-gate: $2")"
  exit 0
}

# Ruta literal simple tras -F/--file (sin comillas, $, ` ni ~). Imprime la ruta o nada.
message_file_arg() {
  local re='(^|[[:space:]])(-F|--file)([[:space:]]+|=)("([A-Za-z0-9_./@+-]+)"|'"'"'([A-Za-z0-9_./@+-]+)'"'"'|([A-Za-z0-9_./@+-]+))([[:space:]]|;|&|\||$)'
  local text; text=$(cat "$CMD")
  if [[ $text =~ $re ]]; then printf '%s%s%s' "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}" "${BASH_REMATCH[7]}"; fi
}

check_commit() {
  has_word git && has_word commit || return 0
  # 1. Trailer visible en el propio comando (-m, heredoc, $'…', etc.).
  if has_trailer_file "$CMD"; then
    decide deny "el mensaje del commit contiene un trailer o crédito de IA prohibido (Co-Authored-By, Generated-by…). Quítalo y repite el commit."
  fi
  # 2. Mensaje desde archivo.
  if grep -Eq -- '(^|[[:space:]])(-F|--file)([[:space:]=]|$)' "$CMD"; then
    local f top; f=$(message_file_arg)
    [ "$f" = "-" ] && return 0                            # stdin: el texto está en el comando (ya revisado)
    [ -n "$f" ] || decide ask "no se pudo determinar el archivo del mensaje (-F); revisa que no contenga trailers de IA antes de aprobar."
    case $f in /*) ;; *) f="$QGH_CWD/$f" ;; esac
    top=$(git -C "$QGH_CWD" rev-parse --show-toplevel 2>/dev/null) || top=""
    case $(cd "$(dirname "$f")" 2>/dev/null && pwd -P)/ in
      "$top"/*) ;;
      *) decide ask "el archivo del mensaje (-F) está fuera del repositorio y no se revisa; confirma que no contiene trailers de IA." ;;
    esac
    if [ -f "$f" ] && [ ! -L "$f" ]; then
      has_trailer_file "$f" && decide deny "el archivo del mensaje (-F) contiene un trailer o crédito de IA prohibido."
    else
      decide ask "el archivo del mensaje (-F) no existe o no es un archivo regular; confirma su contenido."
    fi
    return 0
  fi
  # 3. Mensaje reutilizado de otro commit.
  if grep -Eq -- '(^|[[:space:]])(-c|-C|--reuse-message|--reedit-message)([[:space:]=]|$)' "$CMD"; then
    decide ask "el commit reutiliza el mensaje de otro commit (-c/-C), que este hook no revisa; confirma que no contiene trailers de IA."
  fi
  # 4. --amend sin mensaje nuevo: conserva el del commit actual.
  if has_word --amend && ! grep -Eq -- '(^|[[:space:]])(-m|--message)([[:space:]=]|[^[:space:]])' "$CMD"; then
    if git -C "$QGH_CWD" --no-pager log -1 --format=%B > "$QGH_TMP/.head-msg" 2>/dev/null && has_trailer_file "$QGH_TMP/.head-msg"; then
      decide deny "--amend conservaría el mensaje actual, que contiene un trailer de IA prohibido; usa -m con un mensaje limpio."
    fi
  fi
}

check_remote() {
  local what=""
  if has_word git && has_word push; then what="git push"
  elif has_word gh && has_word pr && has_word create; then what="gh pr create"
  else return 0; fi
  local dir=${QGH_CWD:-$QGH_PROJECT} rc
  qgh_qg -C "$dir" status --run-id "$QGH_RUN_ID" >/dev/null 2>&1; rc=$?
  [ $rc -eq 0 ] && return 0
  local st
  case $rc in 1) st=failed ;; 2) st=blocked ;; 3) st=incomplete ;; 4) st=stale ;; 5) st=missing ;; *) st="no disponible" ;; esac
  decide ask "$what sin evidencia vigente de esta sesión (qg status: $st, run-id $QGH_RUN_ID). Aprueba solo si quieres publicar igualmente; la aprobación vale solo para esta operación."
}

main() {
  qgh_init PreToolUse "tool_name,tool_input.command" || return 0
  qgh_qg -C "${QGH_CWD:-$QGH_PROJECT}" hooks enabled pretool 2>/dev/null || return 0
  [ "$(qgh_field tool_name string)" = Bash ] || return 0
  CMD="$QGH_TMP/tool_input_command"
  [ -f "$CMD" ] && [ "$(cat "$CMD.type")" = string ] || return 0
  [ -z "${QGH_CWD:-}" ] && QGH_CWD=$QGH_PROJECT
  check_commit
  check_remote
}

main "$@"
exit 0
