# Utilidades para probar los hooks con entradas JSON simuladas de Claude Code.
# Reutiliza las de tests/core (repos temporales, configuración de Git aislada, aserciones).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../core/lib.sh"
HOOKS_DIR="$REPO_ROOT/hooks"

unset QG_HOOKS QG_DISABLE CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID QG_STOP_MAX_BLOCKS

# Cadena JSON (para construir entradas de prueba).
jstr() {
  local v=$1
  v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//$'\n'/\\n}; v=${v//$'\t'/\\t}
  printf '"%s"' "$v"
}
SID_A=11111111-1111-4111-8111-111111111111
SID_B=22222222-2222-4222-8222-222222222222

ev_session_start() { printf '{"session_id":%s,"transcript_path":"/x.jsonl","cwd":%s,"hook_event_name":"SessionStart","source":%s}' "$(jstr "$1")" "$(jstr "$2")" "$(jstr "${3:-startup}")"; }
ev_stop() { printf '{"session_id":%s,"transcript_path":"/x.jsonl","cwd":%s,"permission_mode":"default","hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":"listo"}' "$(jstr "$1")" "$(jstr "$2")" "${3:-false}"; }
ev_pretool() { printf '{"session_id":%s,"transcript_path":"/x.jsonl","cwd":%s,"permission_mode":"default","hook_event_name":"PreToolUse","tool_name":%s,"tool_input":{"command":%s,"description":"x"},"tool_use_id":"t1"}' "$(jstr "$1")" "$(jstr "$2")" "$(jstr "${4:-Bash}")" "$(jstr "$3")"; }

# PATH con trampas: si un hook ejecuta modelos o suites de pruebas, queda constancia.
TRAP_BIN="$TESTS_TMP/trap-bin"; TRAP_LOG="$TESTS_TMP/trap.log"
mkdir -p "$TRAP_BIN"; : > "$TRAP_LOG"
for t in claude codex node npm npx pnpm yarn make pytest python python3 cargo go; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$t" "$TRAP_LOG" > "$TRAP_BIN/$t"; chmod +x "$TRAP_BIN/$t"
done
HOOK_PATH="$TRAP_BIN:$PATH"

# hook <script> <json> [VAR=valor…] → stdout del hook; código en HOOK_RC; stderr en $TESTS_TMP/hook.err
hook() {
  local script=$1 json=$2; shift 2
  HOOK_OUT=$(printf '%s' "$json" | env PATH="$HOOK_PATH" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" "$@" \
             "${QG_BASH:-bash}" "$HOOKS_DIR/$script" 2>"$TESTS_TMP/hook.err")
  HOOK_RC=$?
  printf '%s' "$HOOK_OUT"
}
# Valida que la salida del hook sea JSON bien formado (con el mismo parser que usan los hooks).
json_ok() { [ -z "$1" ] && return 0; printf '%s' "$1" | LC_ALL=C awk -v outdir="$TESTS_TMP" -v want="" -f "$HOOKS_DIR/lib/json.awk" 2>/dev/null; }
