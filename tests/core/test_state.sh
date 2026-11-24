#!/usr/bin/env bash
# Pruebas de persistencia (registros, requeridos, lock) y de validación de evidencia (qg status).
. "$(dirname "$0")/lib.sh"

status_rc() { qg -C "$1" status "${@:2}" >/dev/null 2>&1; echo $?; }
status_json() { qg -C "$1" status --json "${@:2}" 2>/dev/null; }

R=$(new_repo)
printf 'a\n' > "$R/a.txt"; commit_all "$R" base

# --- Estado inexistente
assert_eq "$(status_rc "$R")" 5 "sin estado: missing (5)"
assert_match "$(status_json "$R")" '"reason":"no_required_checks"' "sin estado: motivo no_required_checks"
assert_match "$(qg -C "$R" require 2>&1)" "no hay verificaciones obligatorias" "require sin estado: mensaje"

# --- Escritura y lectura
qg -C "$R" require lint test
assert_eq "$(qg -C "$R" require | tr '\n' ' ')" "lint test " "require: lectura de lo escrito"
qg -C "$R" run lint -- true 2>/dev/null
qg -C "$R" run test -- true 2>/dev/null
assert_eq "$(status_rc "$R")" 0 "escritura+lectura: valid (0)"
J=$(status_json "$R")
assert_match "$J" '"result":"valid"' "json: result=valid"
assert_match "$J" '"id":"lint","result":"passed"' "json: lint passed"
if command -v jq >/dev/null 2>&1; then
  if printf '%s' "$J" | jq -e '.checks | length == 2' >/dev/null; then ok "json: válido según jq"; else ko "json: inválido según jq"; fi
else
  ok "json: jq no disponible, validación sintáctica omitida (no es dependencia)"
fi
assert_match "$(qg -C "$R" show)" 'lint +completed +0' "show: lista registros"

# --- Prevención de falsos PASS
# a) requeridos no declarados: nunca valid aunque haya registros en verde
R2=$(new_repo); printf 'x\n' > "$R2/x"; commit_all "$R2" b
qg -C "$R2" run lint -- true 2>/dev/null
assert_eq "$(status_rc "$R2")" 5 "falso PASS a) sin requeridos declarados: missing"
# b) falta una verificación requerida
assert_eq "$(status_rc "$R2" --require lint --require test)" 5 "falso PASS b) test sin ejecutar: missing"
# c) resultados parciales de estados distintos no se combinan
qg -C "$R2" run test -- true 2>/dev/null          # test pasa en F1
printf 'y\n' >> "$R2/x"
qg -C "$R2" run lint -- true 2>/dev/null          # lint pasa en F2
assert_eq "$(status_rc "$R2" --require lint --require test)" 4 "falso PASS c) lint@F2 + test@F1: stale"
# d) el registro más reciente manda: pasa y luego falla con la misma huella
qg -C "$R2" run test -- true 2>/dev/null
qg -C "$R2" run test -- false 2>/dev/null
assert_eq "$(status_rc "$R2" --require lint --require test)" 1 "falso PASS d) último test falló: failed"
# e) exit 0 pero el código cambió durante la ejecución
qg -C "$R2" run test -- sh -c 'echo z >> x' 2>/dev/null
assert_eq "$(status_rc "$R2" --require test)" 4 "falso PASS e) exit 0 con cambio durante ejecución: stale"
# f) comando inexistente: blocked, no missing ni valid
qg -C "$R2" run tipos -- no-existe-qg-cmd 2>/dev/null
assert_eq "$(status_rc "$R2" --require tipos)" 2 "falso PASS f) comando inexistente: blocked"
# g) timeout: incomplete
qg -C "$R2" run --timeout 1 --grace 1 lento -- sleep 20 2>/dev/null
assert_eq "$(status_rc "$R2" --require lento)" 3 "falso PASS g) timeout: incomplete"
# h) un registro con esquema futuro no cuenta como aprobado
R3=$(new_repo); printf 'x\n' > "$R3/x"; commit_all "$R3" b
qg -C "$R3" run lint -- true 2>/dev/null
REC=$(last_record "$R3" lint)
sed 's/^schema=1$/schema=2/' "$REC" > "$REC.tmp" && mv "$REC.tmp" "$REC"
assert_ne "$(status_rc "$R3" --require lint)" 0 "falso PASS h) registro con schema=2: no valid"
# i) registro falsificado a mano con formato inválido: no valid
R4=$(new_repo); printf 'x\n' > "$R4/x"; commit_all "$R4" b
mkdir -p "$(state_dir "$R4")/records/lint"
printf 'schema=1\ncheck_id=lint\nstatus=completed\nexit_code=0\n' > "$(state_dir "$R4")/records/lint/000000001-1795000000-1-1.rec"
assert_ne "$(status_rc "$R4" --require lint)" 0 "falso PASS i) registro incompleto/falsificado: no valid"
# j) revertir al contenido verificado vuelve a ser válido (identidad por contenido; documentado)
R5=$(new_repo); printf 'x\n' > "$R5/x"; commit_all "$R5" b
qg -C "$R5" run lint -- true 2>/dev/null
printf 'tmp\n' >> "$R5/x"
assert_eq "$(status_rc "$R5" --require lint)" 4 "revertir: tras cambio, stale"
git -C "$R5" checkout -q -- x
assert_eq "$(status_rc "$R5" --require lint)" 0 "revertir: mismo contenido, valid"

# --- JSON / registro corrupto
R6=$(new_repo); printf 'x\n' > "$R6/x"; commit_all "$R6" b
qg -C "$R6" require lint
qg -C "$R6" run lint -- true 2>/dev/null
D6="$(state_dir "$R6")/records/lint"
printf 'basura sin formato\n\001\002' > "$D6/999999999-1795000000-1-1.rec"   # el "más reciente" es ilegible
assert_eq "$(status_rc "$R6")" 3 "corrupto: un registro ilegible impide valid (incomplete)"
assert_match "$(status_json "$R6")" '"reason":"corrupt_record"' "corrupto: motivo corrupt_record"
assert_match "$(status_json "$R6")" '"corrupt_records":1' "corrupto: contabilizado"
qg -C "$R6" gc 2>/dev/null
assert_eq "$(status_rc "$R6")" 0 "corrupto: tras qg gc (cuarentena), valid"
[ -n "$(ls "$(state_dir "$R6")/quarantine" 2>/dev/null)" ] && ok "corrupto: archivo en cuarentena" || ko "corrupto: sin cuarentena"
# registro truncado (escritura interrumpida sin atomicidad)
qg -C "$R6" run lint -- true 2>/dev/null
REC=$(last_record "$R6" lint)
head -n 5 "$REC" > "$REC.cut" && mv "$REC.cut" "$REC"
assert_ne "$(status_rc "$R6")" 0 "truncado: no valid"
qg -C "$R6" gc 2>/dev/null
# archivo de requeridos corrupto
printf 'schema=1\ncheck=../../x\n' > "$(state_dir "$R6")/required"
assert_eq "$(status_rc "$R6")" 65 "requeridos corruptos: error de estado (65)"
qg -C "$R6" require --clear
assert_eq "$(status_rc "$R6")" 5 "requeridos: reparado con --clear"

# --- Interrumpido durante la escritura: temporales ignorados y limpiados
R7=$(new_repo); printf 'x\n' > "$R7/x"; commit_all "$R7" b
qg -C "$R7" require lint
qg -C "$R7" run lint -- true 2>/dev/null
D7="$(state_dir "$R7")/records/lint"
printf 'schema=1\nstatus=compl' > "$D7/000000099-1795000000-1-1.rec.tmp.123.456"
assert_eq "$(status_rc "$R7")" 0 "temporal a medio escribir: ignorado"
touch -t 202001010000 "$D7/000000099-1795000000-1-1.rec.tmp.123.456"
qg -C "$R7" gc 2>/dev/null
assert_file_absent "$D7/000000099-1795000000-1-1.rec.tmp.123.456" "temporal antiguo: eliminado por gc"

# --- qg muerto con SIGKILL durante la verificación: registro running abandonado → incomplete
set -m
( exec "${QG_BASH:-bash}" "$QG_BIN" -C "$R7" run lint -- sleep 30 2>/dev/null ) &
QPID=$!
set +m
for _ in $(seq 1 25); do [ "$(field "$(last_record "$R7" lint)" status)" = running ] && break; sleep 0.2; done
CHILD=$(pgrep -P "$QPID" 2>/dev/null | head -n 1)
assert_eq "$(status_rc "$R7")" 3 "en curso: incomplete mientras se ejecuta"
assert_match "$(status_json "$R7")" '"reason":"running"' "en curso: motivo running"
kill -KILL "$QPID"; wait "$QPID" 2>/dev/null
[ -n "$CHILD" ] && T_CLEANUP_PIDS="$T_CLEANUP_PIDS $CHILD" && kill -KILL -- "-$CHILD" 2>/dev/null
assert_eq "$(status_rc "$R7")" 3 "SIGKILL: incomplete"
assert_match "$(status_json "$R7")" '"reason":"abandoned"' "SIGKILL: motivo abandoned"

# --- Lock abandonado
R8=$(new_repo); printf 'x\n' > "$R8/x"; commit_all "$R8" b
qg -C "$R8" require a
L="$(state_dir "$R8")/lock"
sh -c 'exit 0' & DEAD=$!; wait $DEAD
mkdir "$L"; printf 'pid=%s\nhost=%s\nepoch=1\n' "$DEAD" "$(hostname 2>/dev/null || uname -n)" > "$L/owner"
out=$(QG_LOCK_TRIES=40 qg -C "$R8" require a b 2>&1); rc=$?
assert_eq "$rc" 0 "lock abandonado (pid muerto): recuperado"
assert_match "$out" "lock abandonado recuperado" "lock abandonado: se informa"
assert_eq "$(qg -C "$R8" require | tr '\n' ' ')" "a b " "lock abandonado: escritura aplicada"
mkdir "$L"; touch -t 202001010000 "$L"          # lock sin dueño y antiguo
QG_LOCK_TRIES=40 qg -C "$R8" require c 2>/dev/null; rc=$?
assert_eq "$rc" 0 "lock sin dueño y antiguo: recuperado"
mkdir "$L"; printf 'pid=%s\nhost=%s\nepoch=1\n' "$$" "$(hostname 2>/dev/null || uname -n)" > "$L/owner"
QG_LOCK_TRIES=10 qg -C "$R8" require d 2>/dev/null; rc=$?
assert_eq "$rc" 65 "lock vivo (pid activo): no se roba, error tras reintentos"
rm -rf "$L"
# Regresión (carrera TOCTOU detectada en la prueba de concurrencia): un lock reciente
# no se retira aunque su pid ya no exista; podría ser información de un dueño anterior.
mkdir "$L"; printf 'pid=%s\nhost=%s\nepoch=%s\n' "$DEAD" "$(hostname 2>/dev/null || uname -n)" "$(date +%s)" > "$L/owner"
QG_LOCK_TRIES=10 qg -C "$R8" require e 2>/dev/null; rc=$?
assert_eq "$rc" 65 "lock reciente con pid muerto: no se retira de inmediato"
rm -rf "$L"

# --- Escrituras concurrentes
R9=$(new_repo); printf 'x\n' > "$R9/x"; commit_all "$R9" b
pids=""
for i in $(seq 1 24); do
  qg -C "$R9" run "c$((i % 3))" -- true >/dev/null 2>&1 & pids="$pids $!"
  qg -C "$R9" require c0 c1 c2 >/dev/null 2>&1 & pids="$pids $!"
done
for p in $pids; do wait "$p"; done
D9="$(state_dir "$R9")/records"
n=$(ls "$D9"/c*/*.rec 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$n" 24 "concurrencia: 24 registros escritos"
bad=0
for f in "$D9"/c*/*.rec; do grep -q '^status=completed$' "$f" || bad=$((bad + 1)); done
assert_eq "$bad" 0 "concurrencia: todos los registros completos y legibles"
dups=$(for d in "$D9"/c*; do ls "$d" | cut -d- -f1 | sort | uniq -d; done | wc -l | tr -d ' ')
assert_eq "$dups" 0 "concurrencia: secuencias únicas por check"
assert_eq "$(qg -C "$R9" require | tr '\n' ' ')" "c0 c1 c2 " "concurrencia: archivo de requeridos íntegro"
assert_eq "$(status_rc "$R9")" 0 "concurrencia: valid"
residual=0; for f in "$(state_dir "$R9")"/lock*; do [ -e "$f" ] && residual=1; done
[ "$residual" = 0 ] && ok "concurrencia: sin locks residuales" || ko "concurrencia: lock residual"

# --- Dos sesiones distintas (run-id)
R10=$(new_repo); printf 'x\n' > "$R10/x"; commit_all "$R10" b
QG_RUN_ID=sesion-a qg -C "$R10" run lint -- true 2>/dev/null
qg -C "$R10" run --run-id sesion-b lint -- false 2>/dev/null
assert_eq "$(status_rc "$R10" --require lint)" 1 "sesiones: sin filtro manda el más reciente (failed)"
assert_eq "$(status_rc "$R10" --require lint --run-id sesion-a)" 0 "sesiones: filtro sesion-a → valid"
assert_eq "$(status_rc "$R10" --require lint --run-id sesion-b)" 1 "sesiones: filtro sesion-b → failed"
assert_eq "$(status_rc "$R10" --require lint --run-id sesion-c)" 5 "sesiones: sesión sin registros → missing"
assert_match "$(status_json "$R10" --require lint)" '"run_id":"sesion-b"' "sesiones: run_id en la evidencia"

# --- Aislamiento entre worktrees
W="$TESTS_TMP/wt-state-$$"
git -C "$R10" worktree add -q "$W" -b wt >/dev/null 2>&1
qg -C "$W" run solo-wt -- true 2>/dev/null
assert_eq "$(status_rc "$W" --require solo-wt)" 0 "worktrees: evidencia visible en su worktree"
assert_eq "$(status_rc "$R10" --require solo-wt)" 5 "worktrees: no visible desde el principal"

# --- Rutas inesperadas: directorio de estado como enlace simbólico
R11=$(new_repo); printf 'x\n' > "$R11/x"; commit_all "$R11" b
mkdir "$TESTS_TMP/fuera"; ln -s "$TESTS_TMP/fuera" "$R11/.git/quality-gate"
qg -C "$R11" run lint -- true 2>/dev/null; rc=$?
assert_eq "$rc" 65 "estado como symlink: rechazado"
assert_eq "$(ls "$TESTS_TMP/fuera" | wc -l | tr -d ' ')" 0 "estado como symlink: nada escrito fuera"

finish
