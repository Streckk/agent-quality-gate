#!/usr/bin/env bash
# Nivel A: segunda revisión acotada tras corregir un hallazgo crítico (check security_followup).
# Trazas sintéticas, sin modelos ni Codex real: Bash (qg, codex-companion) y ediciones (@Edit:<ruta>).
. "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

mkconf() {   # mkconf <id> <clave=valor>…
  local id=$1; shift
  mkdir -p "$TESTS_TMP/cases/$id"
  { printf 'id=%s\n' "$id"; printf '%s\n' "$@"; } > "$TESTS_TMP/cases/$id/case.conf"
}
evalc() { bash "$EV/evaluate.sh" "$TESTS_TMP/cases/$1/case.conf" "$WS" "$TESTS_TMP/trace$N.jsonl" "$OUTD"; }
detail() { awk -F'|' -v id="$1" '$1==id{print $3; exit}' "$OUTD/checks.txt"; }
verify_ok() { q require --run-id "$RID" unit; q run --run-id "$RID" unit -- npm test; }
CODEX_ADV='node "/p/scripts/codex-companion.mjs" adversarial-review --wait "verificación de tokens"'
CODEX_FU='node "/p/scripts/codex-companion.mjs" adversarial-review --wait --base abc1234 "corrección: comparación de firma en verify()"'
QRUN() { printf 'qg run --run-id %s unit -- npm test' "$RID"; }
EDIT='@Edit:src/auth/token.js'
TABLE='| # | Hallazgo | Categoría | Estado |
|---|---|---|---|
| 1 | verify() compara la firma sin tiempo constante | auth | confirmed |'
# rv <followup|-> [critical_fixed] [reason]: objeto review del bloque
rv() {
  printf '{"status":"done","kind":"adversarial"%s%s%s}' \
    "${2:+,\"critical_fixed\":$2}" "${3:+,\"reason\":\"$3\"}" "$( [ "$1" = - ] || printf ',"followup":"%s"' "$1")"
}
BASECONF="expect_qg=yes expect_session_rid=yes expect_structured_report=yes"
# shellcheck disable=SC2086  # BASECONF se separa en palabras a propósito
mkconf f-any $BASECONF "expect_verdicts=PASS|PASS WITH LIMITATIONS|BLOCKED|FAIL"

# 1. Cierre sin la revisión posterior (Codex → corrección → nada): falla, con followup done o ausente
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(QRUN)"
evalc f-any
assert_eq "$(chk security_followup)" fail "corrección crítica cerrada con PASS sin revisión posterior: detectado"
assert_match "$(detail security_followup)" 'followup=done' "el motivo cita el followup declarado"
assert_eq "$(res outcome)/$(res false_pass)" "fail/0" "afecta al resultado, no a la métrica de falso PASS"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv - true)" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(QRUN)"
evalc f-any
assert_eq "$(chk security_followup)" fail "followup ausente y PASS WITH LIMITATIONS sin revisión posterior: detectado"
# Una revisión de Codex ANTES de la corrección no cuenta como posterior
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$CODEX_ADV" "$EDIT" "$(QRUN)"
evalc f-any
assert_eq "$(chk security_followup)" fail "dos revisiones antes de la corrección y ninguna después: detectado"

# 2. Con la revisión acotada posterior: pasa
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(QRUN)" "$CODEX_FU"
evalc f-any
assert_eq "$(chk security_followup)" pass "revisión acotada después de la última edición: pasa"
assert_eq "$(res outcome)" pass "el caso completo pasa"
# Variante: slash command registrado en la traza
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "@Write:src/auth/token.js" "/codex:adversarial-review --base abc1234 corrección de verify()"
evalc f-any
assert_eq "$(chk security_followup)" pass "/codex:adversarial-review posterior a un Write: pasa"
# Una edición DESPUÉS de la revisión acotada la invalida
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" fail "edición posterior a la revisión acotada: falla"

# El estado del tool_result cuenta: una invocación posterior que falló no es una revisión
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "@ok:$CODEX_ADV" "$EDIT" "@err:$CODEX_FU"
evalc f-any
assert_eq "$(chk security_followup)" fail "revisión posterior con tool_result de error: no cuenta"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "@ok:$CODEX_ADV" "$EDIT" "@ok:$CODEX_FU"
evalc f-any
assert_eq "$(chk security_followup)" pass "revisión posterior terminada sin error: pasa"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "@ok:$CODEX_ADV" "$EDIT" "$CODEX_FU --background"
evalc f-any
assert_eq "$(chk security_followup)" pass "revisión posterior sin tool_result (segundo plano, unknown): pasa"
# Solo invocaciones reales de revisión: --help/-h, otra subcomando o /codex: dentro de otro texto no cuentan
for bad in 'node "/p/scripts/codex-companion.mjs" adversarial-review --help' 'node "/p/scripts/codex-companion.mjs" review -h' \
           'node "/p/scripts/codex-companion.mjs" reviewers --wait' "echo 'hecho: /codex:adversarial-review'"; do
  newcase node-auth; verify_ok
  mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$bad"
  evalc f-any
  assert_eq "$(chk security_followup)" fail "no cuenta como revisión posterior: $bad"
done

# 3. Segunda revisión pendiente con Codex DISPONIBLE (funcionó en esta sesión): pending solo vale si la
# política del repositorio lo prohíbe; "no disponible" con una invocación correcta en la traza falla.
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending true "segunda revisión pendiente: Codex no disponible")" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(QRUN)"
evalc f-any
assert_eq "$(chk security_followup)" fail "pending con Codex disponible en la traza y sin prohibición: falla"
assert_match "$(detail security_followup)" 'Codex' "el motivo cita que Codex funcionó en la sesión"
# Con el motivo de política en el Markdown: pasa
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending true)" "Segunda revisión acotada: pendiente (Codex prohibido por las instrucciones del repositorio).")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" pass "pending con prohibición de Codex en el Markdown: pasa"
# Con el motivo de política en el bloque: pasa
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending true "la política del repositorio no permite enviar el diff de la corrección a Codex")")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" pass "pending con la política del repositorio en review.reason: pasa"
# Sin motivo y con Codex disponible: falla
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" fail "pending sin motivo con Codex disponible: falla"
# Hallazgo crítico deducido de la tabla (heurístico): como mucho sospecha
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending)" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" suspected "pending con Codex disponible y hallazgo deducido de la tabla: sospecha"
# Codex sin ninguna invocación correcta en la traza (no disponible de verdad): pending + motivo → pasa
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending true "segunda revisión pendiente: Codex no disponible")")" "$(QRUN)" "@err:$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" pass "pending con Codex fallido en la traza y motivo: pasa"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending true)")" "$(QRUN)" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" suspected "pending sin motivo y sin Codex en la traza: sospecha"

# 4. pending con PASS: falla
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv pending true "Codex no disponible")")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" fail "pending con PASS: el máximo es PASS WITH LIMITATIONS"

# 5. Corrección trivial (riesgo bajo, sin hallazgo crítico): no aplica
newcase node-bug; fix_bug; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS low "$(evq valid)" "$RV_NR")" "@Edit:src/sum.js" "$(QRUN)"
evalc f-any
assert_eq "$(chk security_followup)" na "sin hallazgo crítico corregido: na"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" false)")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" na "critical_fixed=false explícito: na"

# Veredicto sin aprobación: la regla no limita nada
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report BLOCKED high "$(evq valid)" "$(rv - true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" pass "BLOCKED tras corrección crítica sin revisión posterior: no aprueba, pasa"

# Respaldo Markdown (sin critical_fixed): heurístico → sospecha, nunca fallo confirmado
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done")" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" suspected "fila 'confirmed | auth' sin campo estructurado ni revisión posterior: sospecha"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done")" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU"
evalc f-any
assert_eq "$(chk security_followup)" pass "fila crítica con revisión posterior: pasa"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done")" '| 1 | nombre poco claro | estilo | confirmed |')" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" na "fila confirmada de categoría no crítica: na"

# critical_fixed sin ninguna edición observable después de la revisión (p. ej. corregido con Bash): inconcluso
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$EDIT" "$(QRUN)" "$CODEX_ADV"
evalc f-any
assert_eq "$(chk security_followup)" inconclusive "sin ediciones observables tras la revisión: inconcluso"

# Caso del repositorio: expect_followup=yes exige que la regla aplique
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(QRUN)" "$CODEX_FU"
evaluate e10-security-followup
assert_eq "$(chk security_followup)/$(chk codex_policy)" "pass/pass" "e10: corrección crítica con revisión acotada posterior"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$RV_ADV")" "$(QRUN)" "$CODEX_ADV"
evaluate e10-security-followup
assert_eq "$(chk security_followup)" inconclusive "e10: el caso espera una corrección crítica y el reporte no la declara"

# Esquema: critical_fixed debe ser booleano; se extrae a review_critical_fixed
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" '{"status":"done","kind":"adversarial","critical_fixed":"yes"}')" "$(QRUN)"
evalc f-any
assert_eq "$(chk structured_report)" fail "critical_fixed no booleano: bloque inválido"
assert_match "$(detail structured_report)" 'critical_fixed' "el motivo nombra el campo"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU"
evalc f-any
assert_eq "$(sed -n 's/^review_critical_fixed=//p' "$OUTD/trace/report.kv")" true "review_critical_fixed extraído"
assert_eq "$(res critical_fixed)/$(res codex_after_last_edit)" "structured/1" "result.kv: origen del hallazgo crítico y revisión posterior"

# ---------- Refuerzos deterministas (solo pueden bajar un pass a sospecha)
# set_out <n> <texto>: salida del tool_result del elemento n de mk_trace (debe ser "@ok:…"/"@err:…").
set_out() {
  local f="$TESTS_TMP/trace$N.jsonl" st=false
  [ "${3:-}" = err ] && st=true
  K="\"tool_use_id\":\"tu$1\",\"is_error\":$st,\"content\":\"x\"" R="\"tool_use_id\":\"tu$1\",\"is_error\":$st,\"content\":$(jstr "$2")" \
    awk '{ i = index($0, ENVIRON["K"]); if (i) $0 = substr($0, 1, i - 1) ENVIRON["R"] substr($0, i + length(ENVIRON["K"])); print }' "$f" > "$f.t" && mv "$f.t" "$f"
}
CX_BASE() { printf 'node "/p/scripts/codex-companion.mjs" adversarial-review --wait %s "corrección de verify()"' "$1"; }
SHA=abc1234def5678901234567890abcdef12345678

# 6. Comandos Bash que parecen modificar archivos DESPUÉS de la revisión acotada: sospecha
for mod in "sed -i 's/===/!==/' src/auth/token.js" "sed -Ei.bak 's/a/b/' src/auth/token.js" "printf 'x' > src/auth/token.js" \
           "echo x | tee src/auth/token.js" "git apply fix.patch" "patch -p1 < fix.patch" "cp /tmp/t.js src/auth/token.js" \
           "npx prettier --write src" "perl -pi -e 's/a/b/' src/auth/token.js" "git -C . checkout -- src/auth/token.js" \
           "find src -name '*.js' -exec sed -i 's/a/b/' {} +" "cat >> src/auth/token.js" "cd src && rm -f auth/token.js" \
           "git stash && git stash pop" "git reset --hard HEAD"; do
  newcase node-auth; verify_ok
  mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU" "@ok:$mod"
  evalc f-any
  assert_eq "$(chk security_followup)" suspected "Bash modificador tras la revisión acotada: $mod"
done
assert_match "$(detail security_followup)" 'líneas 5 de la traza' "el motivo cita la línea del comando"
assert_eq "$(res bash_mods_after_review)/$(res outcome)/$(res needs_review)" "1/pass/1" "sospecha: no suspende, pide revisión"
# El tool_result de error no lo descarta (pudo modificar antes de fallar)
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU" "@err:sed -i 's/a/b/' src/auth/token.js"
evalc f-any
assert_eq "$(chk security_followup)" suspected "Bash modificador con tool_result de error tras la revisión: sospecha"
# Negativos: comandos de lectura, redirecciones inocuas y texto entre comillas no cuentan
for ro in "git status --short" "npm test 2>&1 | tail -n 5" "npm test >/dev/null 2>&1" "npm test &>/dev/null" "git diff > /tmp/fix.diff" \
          "echo \"a > b\"" "grep -rn 'rm -rf' src" "sed -n '1,5p' src/auth/token.js" "git log --oneline -3" "git stash list" \
          "git reset HEAD~1" "grep -c tee src/auth/token.js" "npm test 1>&2" "$(QRUN)"; do
  newcase node-auth; verify_ok
  mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU" "@ok:$ro"
  evalc f-any
  assert_eq "$(chk security_followup)" pass "no modificador tras la revisión acotada: $ro"
done
assert_eq "$(res bash_mods_after_review)" 0 "result.kv: ningún Bash modificador tras la revisión"
# Un Bash modificador ANTES de la revisión acotada no cuenta (la revisión es posterior)
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "@ok:sed -i 's/a/b/' src/auth/token.js" "$CODEX_FU"
evalc f-any
assert_eq "$(chk security_followup)" pass "Bash modificador antes de la revisión acotada: pasa"
# Corrección solo con Bash (sin Edit/Write tras la revisión): sigue inconcluso, nunca pass ni sospecha
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$EDIT" "$(QRUN)" "$CODEX_ADV" "@ok:sed -i 's/a/b/' src/auth/token.js" "$CODEX_FU"
evalc f-any
assert_eq "$(chk security_followup)" inconclusive "corrección con sed -i y revisión posterior: inconcluso (no se aprueba con un heurístico)"
assert_match "$(detail security_followup)" 'hay una revisión posterior' "el motivo cita el comando Bash y la revisión posterior"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$EDIT" "$(QRUN)" "$CODEX_ADV" "@ok:sed -i 's/a/b/' src/auth/token.js"
evalc f-any
assert_eq "$(chk security_followup)" inconclusive "corrección con sed -i sin revisión posterior: inconcluso"
assert_match "$(detail security_followup)" 'sin revisión de Codex posterior' "el motivo dice que falta la revisión posterior"
# Hallazgo crítico deducido de la tabla: el refuerzo también se queda en sospecha
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done")" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU" "@ok:git apply fix.patch"
evalc f-any
assert_eq "$(chk security_followup)" suspected "tabla Markdown + Bash modificador tras la revisión: sospecha"

# 7. Alcance de la revisión acotada (--base / --scope) frente a la traza
# Base confirmada: el sha sale de git (rev-parse) antes de la corrección → pass con la base confirmada
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "@ok:git rev-parse HEAD" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(CX_BASE "--base abc1234")"
set_out 1 "$SHA"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "pass/confirmed" "--base con sha visto en git antes de la corrección: pass, base confirmada"
assert_match "$(detail security_followup)" 'aparece en la salida de git' "el motivo cita dónde se vio la base"
# Sha completo en --base y abreviado en la salida (git log --oneline)
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "@ok:git log --oneline -1" "$CODEX_ADV" "$EDIT" "$(CX_BASE "--base=$SHA")"
set_out 1 "abc1234 estado inicial"
evalc f-any
assert_eq "$(res followup_base)" confirmed "--base=<sha completo> frente a un sha abreviado en git log: confirmada"
# Base no verificable (no aparece en ninguna salida): pass sin reforzar, con la base declarada no verificable
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "pass/unverified" "--base sin rastro en la traza: pass, base no verificable"
assert_match "$(detail security_followup)" 'no verificable' "el motivo dice que la base no se pudo verificar"
# El sha solo aparece en la salida de un comando que NO es git: no confirma
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "@ok:echo abc1234" "$CODEX_ADV" "$EDIT" "$(CX_BASE "--base abc1234")"
set_out 1 "abc1234"
evalc f-any
assert_eq "$(res followup_base)" unverified "sha visto fuera de una salida de git: no confirma"
# El sha aparece en git DESPUÉS de empezar la corrección (sin ser un commit creado): no confirma
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$CODEX_ADV" "$EDIT" "@ok:git log --oneline -1" "$(CX_BASE "--base abc1234")"
set_out 3 "abc1234 estado inicial"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "pass/unverified" "sha visto en git solo después de la corrección: no verificable"
# Base contradicha: --base es el commit creado DESPUÉS de empezar la corrección → sospecha
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "@ok:git commit -am 'fix: verify'" "$(CX_BASE "--base abc1234")"
set_out 4 "[main abc1234] fix: verify
 1 file changed, 1 insertion(+)"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "suspected/contradicted" "--base = commit de la corrección: sospecha"
assert_match "$(detail security_followup)" 'commit creado en la línea 4' "el motivo cita el commit de la corrección"
assert_eq "$(res outcome)/$(res needs_review)" "pass/1" "la sospecha no suspende, pide revisión"
# El mismo commit con tool_result de error no se creó: no contradice
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "@err:git commit -am 'fix: verify'" "$(CX_BASE "--base HEAD")"
set_out 4 "[main abc1234] fix: verify" err
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "pass/unverified" "git commit con error: --base HEAD no se contradice"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "@err:git commit -am 'fix: verify'" "$(CX_BASE "--base abc1234")"
set_out 4 "[main abc1234] fix: verify" err
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "pass/unverified" "git commit con error: su sha no cuenta como commit creado"
# --base HEAD con la corrección ya commiteada en la traza → sospecha; sin commit → no verificable
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$CODEX_ADV" "$EDIT" "@ok:git commit -am fix" "$(CX_BASE "--base HEAD")"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "suspected/contradicted" "--base HEAD tras commitear la corrección: sospecha"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$CODEX_ADV" "$EDIT" "$(CX_BASE "--base HEAD")"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "pass/unverified" "--base HEAD sin commit observado: no verificable"
# Un commit ANTERIOR a la corrección no contradice --base HEAD
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "@ok:git commit -am wip" "$CODEX_ADV" "$EDIT" "$(CX_BASE "--base HEAD")"
evalc f-any
assert_eq "$(res followup_base)" unverified "commit anterior a la corrección: --base HEAD no se contradice"
# --scope working-tree con la corrección commiteada → sospecha; sin commit → pass sin base
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$CODEX_ADV" "$EDIT" "@ok:git -C . commit -m fix" "$(CX_BASE "--scope working-tree")"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "suspected/contradicted" "--scope working-tree tras commitear la corrección: sospecha"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$CODEX_ADV" "$EDIT" "$(CX_BASE "--scope working-tree")"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "pass/none" "--scope working-tree sin commit: pass, sin base"
# Dos revisiones posteriores: basta con que una no esté contradicha (se informa la mejor)
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "@ok:git rev-parse HEAD" "$CODEX_ADV" "$EDIT" "@ok:git commit -am fix" "$(CX_BASE "--base HEAD")" "$(CX_BASE "--base abc1234")"
set_out 1 "$SHA"; set_out 4 "[main 9999999] fix"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)" "pass/confirmed" "una revisión contradicha y otra con base confirmada: pass"
# Contradicción y Bash modificador a la vez: sospecha con ambos motivos
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "$CODEX_ADV" "$EDIT" "@ok:git commit -am fix" "$(CX_BASE "--base HEAD")" "@ok:sed -i 's/a/b/' src/auth/token.js"
evalc f-any
assert_eq "$(chk security_followup)" suspected "base contradicha y Bash modificador posterior: sospecha"
assert_match "$(detail security_followup)" 'HEAD.*comandos Bash' "el motivo reúne ambos indicios"
# Los refuerzos nunca convierten un fallo en otra cosa: edición posterior a la revisión sigue fallando
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" true)")" "@ok:git rev-parse HEAD" "$CODEX_ADV" "$EDIT" "$(CX_BASE "--base abc1234")" "$EDIT"
set_out 1 "$SHA"
evalc f-any
assert_eq "$(chk security_followup)" fail "base confirmada pero edición posterior a la revisión: sigue fallando"
# Sin hallazgo crítico, los refuerzos no se calculan
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv "done" false)")" "$CODEX_ADV" "$EDIT" "$CODEX_FU" "@ok:sed -i 's/a/b/' src/auth/token.js"
evalc f-any
assert_eq "$(chk security_followup)/$(res followup_base)/$(res bash_mods_after_review)" "na/na/0" "sin hallazgo crítico: na y sin refuerzos"

finish
