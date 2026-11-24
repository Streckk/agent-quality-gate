#!/usr/bin/env bash
# Hooks SessionStart y Stop con entradas simuladas de Claude Code.
. "$(dirname "$0")/lib.sh"

RA=$(qg session id "$SID_A"); RB=$(qg session id "$SID_B")
on()  { echo QG_HOOKS=1; }
sstart() { hook session-start.sh "$(ev_session_start "$1" "$2" "${3:-startup}")" CLAUDE_PROJECT_DIR="$2" "${@:4}" >/dev/null; }
sstop()  { hook stop.sh "$(ev_stop "$1" "$2" "${3:-false}")" CLAUDE_PROJECT_DIR="$2" "${@:4}"; }
blocks() { case $1 in *'"decision":"block"'*) echo block ;; "") echo none ;; *) echo other ;; esac; }

new_proj() { local r; r=$(new_repo); printf 'a\n' > "$r/a.txt"; commit_all "$r" base; printf '%s' "$r"; }

# ---------- SessionStart
R=$(new_proj)
sstart "$SID_A" "$R"
assert_eq "$HOOK_RC" 0 "SessionStart desactivado: exit 0"
assert_file_absent "$(state_dir "$R")" "SessionStart desactivado: no crea estado"
assert_eq "$HOOK_OUT" "" "SessionStart: no imprime nada (no inyecta contexto)"

sstart "$SID_A" "$R" startup QG_HOOKS=1
START_FP=$(sed -n 's/^fingerprint=//p' "$(state_dir "$R")/sessions/$RA/start")
assert_eq "$START_FP" "$(fp "$R")" "SessionStart activado: registra la huella inicial"
assert_eq "$HOOK_OUT" "" "SessionStart activado: no imprime nada"

printf 'cambio\n' >> "$R/a.txt"
sstart "$SID_A" "$R" resume QG_HOOKS=1
assert_eq "$(sed -n 's/^fingerprint=//p' "$(state_dir "$R")/sessions/$RA/start")" "$START_FP" "SessionStart resume: no sobrescribe el estado inicial"
sstart "$SID_B" "$R" startup QG_HOOKS=1
assert_ne "$(sed -n 's/^fingerprint=//p' "$(state_dir "$R")/sessions/$RB/start")" "$START_FP" "SessionStart concurrente: cada sesión tiene su propio estado"
git -C "$R" checkout -q -- a.txt

NG=$(mktemp -d "$TESTS_TMP/nogit.XXXXXX"); NG=$(cd "$NG" && pwd)
sstart "$SID_A" "$NG" startup QG_HOOKS=1 GIT_CEILING_DIRECTORIES="$TESTS_TMP"
assert_eq "$HOOK_RC" 0 "SessionStart sin Git: no impide iniciar (exit 0)"
assert_eq "$HOOK_OUT" "" "SessionStart sin Git: sin salida"

RF=$(new_proj); mkdir "$TESTS_TMP/fuera-ss"; ln -s "$TESTS_TMP/fuera-ss" "$RF/.git/quality-gate"
sstart "$SID_A" "$RF" startup QG_HOOKS=1
assert_eq "$HOOK_RC" 0 "SessionStart con fallo al registrar: exit 0"
assert_match "$(cat "$TESTS_TMP/hook.err")" "no se pudo registrar" "SessionStart con fallo: aviso por stderr"
assert_eq "$(ls "$TESTS_TMP/fuera-ss" | wc -l | tr -d ' ')" 0 "SessionStart con fallo: nada escrito fuera"

hook session-start.sh '{"session_id":"../../etc","cwd":"/","hook_event_name":"SessionStart"}' QG_HOOKS=1 CLAUDE_PROJECT_DIR="$R" >/dev/null
assert_eq "$HOOK_RC/$HOOK_OUT" "0/" "SessionStart con session_id inválido: no actúa"
hook session-start.sh '{"session_id":' QG_HOOKS=1 CLAUDE_PROJECT_DIR="$R" >/dev/null
assert_eq "$HOOK_RC/$HOOK_OUT" "0/" "SessionStart con JSON malformado: no actúa"

# ---------- Stop
R=$(new_proj)
sstart "$SID_A" "$R" startup QG_HOOKS=1
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop sin modificaciones: no bloquea"

printf 'b\n' >> "$R/a.txt"
OUT=$(sstop "$SID_A" "$R" false QG_HOOKS=1)
assert_eq "$(blocks "$OUT")" block "Stop con cambios y missing: bloquea"
assert_match "$OUT" 'qg status: missing' "Stop: el motivo indica el estado"
json_ok "$OUT" && ok "Stop: salida JSON válida" || ko "Stop: salida JSON inválida"
assert_eq "$HOOK_RC" 0 "Stop: exit 0 también al bloquear"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" true QG_HOOKS=1)")" none "Stop con stop_hook_active=true: no bloquea"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop: segundo intento con la misma huella no bloquea"

printf 'c\n' >> "$R/a.txt"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" block "Stop: cambio posterior al bloqueo vuelve a evaluar"

# valid
qg -C "$R" require --run-id "$RA" unit; qg -C "$R" run --run-id "$RA" unit -- true 2>/dev/null
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop con evidencia valid: no bloquea"
# stale: archivo modificado después de valid
printf 'd\n' >> "$R/a.txt"
OUT=$(sstop "$SID_A" "$R" false QG_HOOKS=1)
assert_eq "$(blocks "$OUT")" block "Stop con stale (modificado tras valid): bloquea"
assert_match "$OUT" 'qg status: stale' "Stop stale: motivo stale"

# failed / blocked / incomplete: no bloquean
printf 'e\n' >> "$R/a.txt"
qg -C "$R" run --run-id "$RA" unit -- false 2>/dev/null
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop con failed: no bloquea (fallo legítimo)"
qg -C "$R" run --run-id "$RA" unit -- comando-inexistente-qg 2>/dev/null
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop con blocked: no bloquea"
qg -C "$R" run --run-id "$RA" --timeout 1 --grace 1 unit -- sleep 10 2>/dev/null
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop con incomplete (timeout): no bloquea"

# Límite de bloqueos por sesión
R=$(new_proj); sstart "$SID_A" "$R" startup QG_HOOKS=1
n=0
for i in 1 2 3 4 5; do printf '%s\n' "$i" >> "$R/a.txt"; [ "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" = block ] && n=$((n + 1)); done
assert_eq "$n" 3 "Stop: máximo 3 bloqueos por sesión (QG_STOP_MAX_BLOCKS)"
n=0
for i in 6 7; do printf '%s\n' "$i" >> "$R/a.txt"; [ "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1 QG_STOP_MAX_BLOCKS=5)")" = block ] && n=$((n + 1)); done
assert_eq "$n" 2 "Stop: el límite es configurable"

# Desactivación
R=$(new_proj); sstart "$SID_A" "$R" startup QG_HOOKS=1; printf 'x\n' >> "$R/a.txt"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1 QG_DISABLE=1)")" none "Stop con QG_DISABLE=1: no bloquea (gana a QG_HOOKS=1)"
assert_eq "$(blocks "$(sstop "$SID_A" "$R")")" none "Stop con hooks desactivados: no bloquea"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=0)")" none "Stop con QG_HOOKS=0: no bloquea"
mkdir -p "$R/.agent"; printf 'hooks:\n  stop: on\n' > "$R/.agent/verification.yaml"
assert_eq "$(blocks "$(sstop "$SID_A" "$R")")" block "Stop activado por la configuración del proyecto"
printf 'z\n' >> "$R/a.txt"
printf 'hooks:\n  stop: yes please\n' > "$R/.agent/verification.yaml"
assert_eq "$(blocks "$(sstop "$SID_A" "$R")")" none "Stop: configuración malformada no activa"
printf 'hooks:\n  stop: on\n' > "$R/.agent/verification.yaml"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=0)")" none "Stop: QG_HOOKS=0 desactiva aunque el proyecto active"

# Casos especiales
R=$(new_proj); printf 'previo\n' >> "$R/a.txt"          # cambio anterior al inicio de la sesión
sstart "$SID_A" "$R" startup QG_HOOKS=1
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop: cambios previos a la sesión no bloquean"
printf 'durante\n' >> "$R/a.txt"; git -C "$R" diff --quiet || true
cp "$R/a.txt" "$TESTS_TMP/a.bak"; printf 'tmp\n' >> "$R/a.txt"; cp "$TESTS_TMP/a.bak" "$R/a.txt"
sed -i.bak '$d' "$R/a.txt" && rm -f "$R/a.txt.bak"   # revertir al contenido inicial
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop: modificación revertida al contenido inicial no bloquea"

R=$(new_proj); sstart "$SID_A" "$R" startup QG_HOOKS=1
mkdir -p "$R/docs"; printf '# Doc\n' > "$R/docs/x.md"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" block "Stop solo docs sin verificaciones: bloquea una vez"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop solo docs: tras ejecutar la puerta sin cambios, deja terminar"

R=$(new_proj)        # hooks activados a mitad de sesión: no hay estado inicial
printf 'x\n' >> "$R/a.txt"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop sin SessionStart registrado: no bloquea"

R=$(new_proj); sstart "$SID_A" "$R" startup QG_HOOKS=1
printf 'basura\n' > "$(state_dir "$R")/sessions/$RA/start"
printf 'x\n' >> "$R/a.txt"
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Stop con estado inicial corrupto: no bloquea"

# Sesiones simultáneas en el mismo worktree
R=$(new_proj); sstart "$SID_A" "$R" startup QG_HOOKS=1; sstart "$SID_B" "$R" startup QG_HOOKS=1
printf 'x\n' >> "$R/a.txt"
qg -C "$R" require --run-id "$RA" unit; qg -C "$R" run --run-id "$RA" unit -- true 2>/dev/null
assert_eq "$(blocks "$(sstop "$SID_A" "$R" false QG_HOOKS=1)")" none "Sesiones simultáneas: A verificada no bloquea"
assert_eq "$(blocks "$(sstop "$SID_B" "$R" false QG_HOOKS=1)")" block "Sesiones simultáneas: B no hereda la evidencia de A"

# Entradas malformadas o inesperadas
hook stop.sh '{"session_id":"x"' QG_HOOKS=1 CLAUDE_PROJECT_DIR="$R" >/dev/null
assert_eq "$HOOK_RC/$HOOK_OUT" "0/" "Stop con JSON malformado: exit 0, sin decisión"
hook stop.sh "$(ev_session_start "$SID_A" "$R")" QG_HOOKS=1 CLAUDE_PROJECT_DIR="$R" >/dev/null
assert_eq "$HOOK_RC/$HOOK_OUT" "0/" "Stop con evento distinto: no actúa"
hook stop.sh "$(ev_stop "$SID_A" "relativo/../x")" QG_HOOKS=1 >/dev/null
assert_eq "$HOOK_RC/$HOOK_OUT" "0/" "Stop con cwd relativo y sin CLAUDE_PROJECT_DIR: no actúa"

finish
