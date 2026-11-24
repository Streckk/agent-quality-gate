#!/usr/bin/env bash
# Aislamiento entre sesiones concurrentes en el mismo worktree (requisitos y evidencia por run-id).
. "$(dirname "$0")/lib.sh"

src() { qg -C "$R" status --run-id "$1" >/dev/null 2>&1; echo $?; }

R=$(new_repo); printf 'x\n' > "$R/x"; commit_all "$R" base

# Sesión A exige lint+unit; sesión B solo lint. Declaradas en orden A, B.
qg -C "$R" require --run-id ses-a lint unit
qg -C "$R" require --run-id ses-b lint
qg -C "$R" run --run-id ses-a lint -- true 2>/dev/null
qg -C "$R" run --run-id ses-b lint -- true 2>/dev/null

# A no ha ejecutado unit: no puede ser valid aunque B haya declarado un conjunto menor después.
assert_eq "$(src ses-a)" 5 "sesiones: A (lint+unit, falta unit) → missing, no valid"
assert_eq "$(src ses-b)" 0 "sesiones: B (solo lint) → valid"
assert_eq "$(qg -C "$R" require --run-id ses-a | tr '\n' ' ')" "lint unit " "sesiones: requisitos de A intactos tras declarar B"
assert_eq "$(qg -C "$R" require --run-id ses-b | tr '\n' ' ')" "lint " "sesiones: requisitos de B propios"

# La evidencia de una sesión no satisface la de otra
qg -C "$R" run --run-id ses-b unit -- true 2>/dev/null       # unit ejecutado por B
assert_eq "$(src ses-a)" 5 "sesiones: unit de B no cuenta para A"
qg -C "$R" run --run-id ses-a unit -- false 2>/dev/null
assert_eq "$(src ses-a)" 1 "sesiones: unit de A falla → failed"
assert_eq "$(src ses-b)" 0 "sesiones: el fallo de A no afecta a B"

# Sesión sin requisitos propios: no hereda los del worktree ni los de otra sesión
qg -C "$R" require lint                                   # requisito de nivel worktree (sin run-id)
assert_eq "$(src ses-c)" 5 "sesiones: sesión sin requisitos propios → missing (no hereda)"
assert_match "$(qg -C "$R" status --run-id ses-c --json 2>/dev/null)" '"reason":"no_required_checks"' "sesiones: motivo no_required_checks"

# QG_RUN_ID como valor por defecto en require/run/status
QG_RUN_ID=ses-d qg -C "$R" require lint
QG_RUN_ID=ses-d qg -C "$R" run lint -- true 2>/dev/null
QG_RUN_ID=ses-d qg -C "$R" status >/dev/null 2>&1; rc=$?
assert_eq "$rc" 0 "sesiones: QG_RUN_ID aplica a require, run y status"
assert_match "$(QG_RUN_ID=ses-d qg -C "$R" status --json 2>/dev/null)" '"required_from":"session:ses-d"' "sesiones: origen de requisitos = sesión"

# Un cambio de código de una sesión deja obsoleta la evidencia de todas (worktree compartido)
printf 'y\n' >> "$R/x"
assert_eq "$(src ses-b)" 4 "sesiones: cambio en el worktree → B stale"

# Concurrencia real: 8 sesiones declaran requisitos distintos y ejecutan en paralelo
R=$(new_repo); printf 'x\n' > "$R/x"; commit_all "$R" base
pids=""
for i in 1 2 3 4 5 6 7 8; do
  ( qg -C "$R" require --run-id "p$i" "c$i" common >/dev/null 2>&1
    qg -C "$R" run --run-id "p$i" common -- true >/dev/null 2>&1
    if [ $((i % 2)) -eq 0 ]; then qg -C "$R" run --run-id "p$i" "c$i" -- true >/dev/null 2>&1; fi ) &
  pids="$pids $!"
done
for p in $pids; do wait "$p"; done
bad=0
for i in 1 2 3 4 5 6 7 8; do
  got=$(src "p$i")
  if [ $((i % 2)) -eq 0 ]; then want=0; else want=5; fi
  [ "$got" = "$want" ] || { bad=$((bad + 1)); printf '   p%s: esperado %s, obtenido %s\n' "$i" "$want" "$got"; }
  [ "$(qg -C "$R" require --run-id "p$i" | tr '\n' ' ')" = "c$i common " ] || bad=$((bad + 1))
done
assert_eq "$bad" 0 "concurrencia: 8 sesiones paralelas sin mezcla ni falsos valid"

# qg reject: degrada (exit 0 sin pruebas ejecutadas) y nunca aprueba
R=$(new_repo); printf 'x\n' > "$R/x"; commit_all "$R" base
qg -C "$R" require --run-id rj unit
qg -C "$R" run --run-id rj unit -- true 2>/dev/null
assert_eq "$(src rj)" 0 "reject: antes, valid"
qg -C "$R" reject --run-id rj unit --reason no_tests_executed 2>/dev/null; rc=$?
assert_eq "$rc" 0 "reject: registrado"
assert_eq "$(src rj)" 2 "reject: el check pasa a blocked"
assert_match "$(qg -C "$R" status --run-id rj --json 2>/dev/null)" '"reason":"rejected:no_tests_executed"' "reject: motivo visible en la evidencia"
qg -C "$R" run --run-id rj unit -- true 2>/dev/null
assert_eq "$(src rj)" 0 "reject: una nueva ejecución posterior lo sustituye"
qg -C "$R" reject --run-id rj unit 2>/dev/null; rc=$?
assert_eq "$rc" 64 "reject: --reason obligatorio"
qg -C "$R" reject --run-id rj unit --reason 'Mal Motivo!' 2>/dev/null; rc=$?
assert_eq "$rc" 64 "reject: motivo con formato inválido rechazado"
printf 'y\n' >> "$R/x"
qg -C "$R" reject --run-id rj unit --reason no_tests_executed 2>/dev/null
git -C "$R" checkout -q -- x
assert_eq "$(src rj)" 0 "reject: se aplica a la huella en que se emitió, no a otra"

# version --json: interfaz para comprobar compatibilidad
assert_match "$(qg version --json)" '^\{"name":"qg","version":"[^"]+","schema":1,"interface":[0-9]+\}$' "version: JSON con interface"

# gc elimina sesiones inactivas y conserva las recientes
R=$(new_repo); printf 'x\n' > "$R/x"; commit_all "$R" base
qg -C "$R" require --run-id vieja lint; qg -C "$R" require --run-id nueva lint
SD="$(state_dir "$R")/sessions"
touch -t 202001010000 "$SD/vieja/required" "$SD/vieja"
qg -C "$R" gc 2>/dev/null
assert_file_absent "$SD/vieja" "gc: sesión inactiva eliminada"
[ -f "$SD/nueva/required" ] && ok "gc: sesión reciente conservada" || ko "gc: sesión reciente eliminada"

# Identificador de sesión con ruta peligrosa: rechazado
qg -C "$R" require --run-id '../x' lint 2>/dev/null; rc=$?
assert_eq "$rc" 64 "sesiones: run-id con ../ rechazado"

finish
