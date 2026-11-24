#!/usr/bin/env bash
# Criterio de finalización de la iteración v0.2.0 (evidencia), paso a paso y sin Claude, Codex ni Graphify.
. "$(dirname "$0")/lib.sh"

# 1. Repositorio Git temporal
R=$(new_repo)
printf 'def suma(a, b):\n    return a + b\n' > "$R/calc.py"
printf '#!/bin/sh\ngrep -q "return a + b" calc.py\n' > "$R/check.sh"; chmod +x "$R/check.sh"
commit_all "$R" base
qg -C "$R" require unit
ok "1. repositorio temporal creado"

# 2. Verificación mediante qg-run
(cd "$R" && "${QG_BASH:-bash}" "$REPO_ROOT/bin/qg-run" unit -- ./check.sh) 2>/dev/null; rc=$?
assert_eq "$rc" 0 "2. qg-run ejecuta la verificación (exit 0 real)"
FP1=$(qg -C "$R" fingerprint)

# 3. Consultar la evidencia
J=$(qg -C "$R" status --json 2>/dev/null); rc=$?
assert_eq "$rc" 0 "3. evidencia vigente (status=0)"
assert_match "$J" "\"result\":\"valid\"" "3. resultado valid"
assert_match "$J" "\"fingerprint\":\"$FP1\"" "3. la evidencia corresponde a la huella actual"

# 4. Modificar un archivo relevante
printf 'def suma(a, b):\n    return a - b\n' > "$R/calc.py"
FP2=$(qg -C "$R" fingerprint)
assert_ne "$FP2" "$FP1" "4. la modificación cambia la huella"

# 5. La evidencia anterior queda obsoleta
qg -C "$R" status >/dev/null 2>&1; rc=$?
assert_eq "$rc" 4 "5. evidencia anterior obsoleta (stale=4)"
assert_match "$(qg -C "$R" status --json 2>/dev/null)" '"reason":"code_changed"' "5. motivo code_changed"

# 6. Ejecutar nuevamente (ahora falla de verdad: la regresión es real)
(cd "$R" && "${QG_BASH:-bash}" "$REPO_ROOT/bin/qg-run" unit -- ./check.sh) 2>/dev/null; rc=$?
assert_eq "$rc" 1 "6. nueva ejecución conserva el exit real (1)"
qg -C "$R" status >/dev/null 2>&1; rc=$?
assert_eq "$rc" 1 "6. estado actual: failed"
# se corrige y se reejecuta
printf 'def suma(a, b):\n    return a + b  # corregido\n' > "$R/calc.py"
(cd "$R" && "${QG_BASH:-bash}" "$REPO_ROOT/bin/qg-run" unit -- ./check.sh) 2>/dev/null; rc=$?
assert_eq "$rc" 0 "6. tras corregir: exit 0"

# 7. La nueva evidencia corresponde al estado actual
FP3=$(qg -C "$R" fingerprint)
J=$(qg -C "$R" status --json 2>/dev/null); rc=$?
assert_eq "$rc" 0 "7. evidencia vigente de nuevo"
assert_match "$J" "\"fingerprint\":\"$FP3\"" "7. corresponde a la huella actual"
assert_ne "$FP3" "$FP1" "7. y no es la huella verificada originalmente"
assert_eq "$(field "$(last_record "$R" unit)" fp_end)" "$FP3" "7. el último registro se tomó sobre este contenido"

finish
