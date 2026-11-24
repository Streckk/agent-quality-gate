#!/usr/bin/env bash
# Integración skill ↔ hooks: mismo run-id, flujo completo, sin efectos fuera del estado autorizado.
. "$(dirname "$0")/lib.sh"

ISO_HOME="$TESTS_TMP/home"; ISO_TMP="$TESTS_TMP/tmp"; mkdir -p "$ISO_HOME" "$ISO_TMP"
run_hook() {   # run_hook <script> <json> [VAR=…]
  local s=$1 j=$2; shift 2
  hook "$s" "$j" HOME="$ISO_HOME" TMPDIR="$ISO_TMP" "$@" >/dev/null
}
blocks() { case $1 in *'"decision":"block"'*) echo block ;; "") echo none ;; *) echo other ;; esac; }

# 1. La skill (Bash del modelo: CLAUDE_CODE_SESSION_ID) y los hooks (session_id del JSON) usan el mismo run-id
SKILL_RID=$(CLAUDE_CODE_SESSION_ID="$SID_A" qg session id)
HOOK_RID=$(qg session id "$SID_A")
assert_eq "$SKILL_RID" "$HOOK_RID" "run-id: skill y hooks derivan el mismo (cc-<session_id>)"
assert_eq "$SKILL_RID" "cc-$SID_A" "run-id: formato cc-<session_id>"
CLAUDE_CODE_SESSION_ID='a b' qg session id >/dev/null 2>&1; assert_eq "$?" 1 "run-id: session id inválido → error (la skill usa su fallback)"
env -u CLAUDE_CODE_SESSION_ID bash "$QG_BIN" session id >/dev/null 2>&1; assert_eq "$?" 1 "run-id: sin CLAUDE_CODE_SESSION_ID → error (fallback de la skill)"

# 2. Flujo completo con hooks activados
R=$(new_repo); printf 'a\n' > "$R/a.txt"; commit_all "$R" base
STATUS_BEFORE=$(git -C "$R" status --porcelain)
MARK="$TESTS_TMP/marca-inicio"; sleep 1; : > "$MARK"     # todo lo escrito después es atribuible al flujo
run_hook session-start.sh "$(ev_session_start "$SID_A" "$R")" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1
[ -f "$(state_dir "$R")/sessions/$SKILL_RID/start" ] && ok "flujo: SessionStart registró el estado de la sesión" || ko "flujo: sin estado inicial"
printf 'cambio\n' >> "$R/a.txt"
run_hook stop.sh "$(ev_stop "$SID_A" "$R")" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1
assert_eq "$(blocks "$HOOK_OUT")" block "flujo: Stop pide verificar"
# La skill verifica con el run-id derivado de CLAUDE_CODE_SESSION_ID
CLAUDE_CODE_SESSION_ID="$SID_A" bash -c '
  rid=$(bash "$0" session id) &&
  bash "$0" -C "$1" require --run-id "$rid" unit &&
  bash "$0" -C "$1" run --run-id "$rid" unit -- true' "$QG_BIN" "$R" 2>/dev/null
run_hook stop.sh "$(ev_stop "$SID_A" "$R" true)" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1
assert_eq "$(blocks "$HOOK_OUT")" none "flujo: tras /quality-gate (stop_hook_active) Claude termina"
run_hook stop.sh "$(ev_stop "$SID_A" "$R")" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1
assert_eq "$(blocks "$HOOK_OUT")" none "flujo: evidencia valid de la misma sesión → no bloquea"
run_hook stop.sh "$(ev_stop "$SID_B" "$R")" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1
assert_eq "$(blocks "$HOOK_OUT")" none "flujo: otra sesión sin SessionStart propio no bloquea ni reutiliza evidencia"
run_hook session-start.sh "$(ev_session_start "$SID_B" "$R")" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1
printf 'otro\n' >> "$R/a.txt"
run_hook stop.sh "$(ev_stop "$SID_B" "$R")" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1
assert_eq "$(blocks "$HOOK_OUT")" block "flujo: la evidencia de A no cuenta para B"

# PreToolUse en el mismo flujo
run_hook pre-tool-use.sh "$(ev_pretool "$SID_A" "$R" 'git push')" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1
assert_match "$HOOK_OUT" '"permissionDecision":"ask"' "flujo: push tras un cambio sin reverificar → ask"

# 3. Sin efectos fuera del estado autorizado
assert_eq "$(ls -A "$ISO_HOME" | wc -l | tr -d ' ')" 0 "aislamiento: nada escrito en HOME"
assert_eq "$(ls -A "$ISO_TMP" | wc -l | tr -d ' ')" 0 "aislamiento: temporales de los hooks eliminados"
git -C "$R" checkout -q -- a.txt
assert_eq "$(git -C "$R" status --porcelain)" "$STATUS_BEFORE" "aislamiento: working tree sin cambios atribuibles a los hooks"
# (index lo reescribe el propio git checkout de la prueba)
extra=$(cd "$R/.git" && find . -newer "$MARK" -type f ! -path './quality-gate/*' ! -name index 2>/dev/null | head -5)
inside=$(cd "$R/.git" && find ./quality-gate -newer "$MARK" -type f 2>/dev/null | wc -l | tr -d ' ')
[ "$inside" -gt 0 ] && ok "aislamiento: el control detecta escrituras (quality-gate/ tiene $inside archivos nuevos)" || ko "aislamiento: control vacío"
assert_eq "$extra" "" "aislamiento: en .git solo escribe en quality-gate/"
assert_eq "$(cat "$TRAP_LOG")" "" "los hooks no ejecutan modelos ni suites de pruebas (trampas intactas)"

# 4. Hooks desactivados: ningún efecto secundario
R2=$(new_repo); printf 'a\n' > "$R2/a.txt"; commit_all "$R2" base
run_hook session-start.sh "$(ev_session_start "$SID_A" "$R2")" CLAUDE_PROJECT_DIR="$R2"
printf 'x\n' >> "$R2/a.txt"
run_hook stop.sh "$(ev_stop "$SID_A" "$R2")" CLAUDE_PROJECT_DIR="$R2"; o1=$HOOK_OUT
run_hook pre-tool-use.sh "$(ev_pretool "$SID_A" "$R2" 'git push')" CLAUDE_PROJECT_DIR="$R2"; o2=$HOOK_OUT
assert_eq "$o1$o2" "" "desactivados: sin salida"
assert_file_absent "$(state_dir "$R2")" "desactivados: no crean estado"
assert_eq "$(ls -A "$ISO_TMP" | wc -l | tr -d ' ')" 0 "desactivados: sin temporales"

# 5. Latencia del hook Stop (repo pequeño)
start=$(date +%s)
for _ in 1 2 3 4 5; do run_hook stop.sh "$(ev_stop "$SID_A" "$R")" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1; done
el=$(( $(date +%s) - start ))
if [ "$el" -le 10 ]; then ok "latencia: 5 Stop en ${el}s"; else ko "latencia: 5 Stop en ${el}s"; fi

finish
