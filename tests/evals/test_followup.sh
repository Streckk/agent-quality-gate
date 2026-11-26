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
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done true)" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(QRUN)"
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
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done true)")" "$(QRUN)" "$CODEX_ADV" "$CODEX_ADV" "$EDIT" "$(QRUN)"
evalc f-any
assert_eq "$(chk security_followup)" fail "dos revisiones antes de la corrección y ninguna después: detectado"

# 2. Con la revisión acotada posterior: pasa
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done true)" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(QRUN)" "$CODEX_FU"
evalc f-any
assert_eq "$(chk security_followup)" pass "revisión acotada después de la última edición: pasa"
assert_eq "$(res outcome)" pass "el caso completo pasa"
# Variante: slash command registrado en la traza
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done true)")" "$(QRUN)" "$CODEX_ADV" "@Write:src/auth/token.js" "echo '/codex:adversarial-review --base abc1234'"
evalc f-any
assert_eq "$(chk security_followup)" pass "/codex:adversarial-review posterior a un Write: pasa"
# Una edición DESPUÉS de la revisión acotada la invalida
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" fail "edición posterior a la revisión acotada: falla"

# 3. Codex no disponible para la segunda revisión: pending + PASS WITH LIMITATIONS + motivo → pasa
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending true "segunda revisión pendiente: Codex no disponible")" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(QRUN)"
evalc f-any
assert_eq "$(chk security_followup)" pass "pending con PASS WITH LIMITATIONS y motivo: pasa"
# Sin motivo en el bloque, pero declarado en el Markdown: pasa
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending true)" "Segunda revisión acotada: pendiente (Codex prohibido por las instrucciones del repositorio).")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" pass "pending con el motivo en el Markdown: pasa"
# Sin motivo en ningún sitio: sospecha (no se puede afirmar que falte)
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report "PASS WITH LIMITATIONS" high "$(evq valid)" "$(rv pending true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" suspected "pending sin motivo declarado: sospecha"

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
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done false)")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" na "critical_fixed=false explícito: na"

# Veredicto sin aprobación: la regla no limita nada
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report BLOCKED high "$(evq valid)" "$(rv - true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" pass "BLOCKED tras corrección crítica sin revisión posterior: no aprueba, pasa"

# Respaldo Markdown (sin critical_fixed): heurístico → sospecha, nunca fallo confirmado
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done)" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" suspected "fila 'confirmed | auth' sin campo estructurado ni revisión posterior: sospecha"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done)" "$TABLE")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU"
evalc f-any
assert_eq "$(chk security_followup)" pass "fila crítica con revisión posterior: pasa"
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done)" '| 1 | nombre poco claro | estilo | confirmed |')" "$(QRUN)" "$CODEX_ADV" "$EDIT"
evalc f-any
assert_eq "$(chk security_followup)" na "fila confirmada de categoría no crítica: na"

# critical_fixed sin ninguna edición observable después de la revisión (p. ej. corregido con Bash): inconcluso
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done true)")" "$EDIT" "$(QRUN)" "$CODEX_ADV"
evalc f-any
assert_eq "$(chk security_followup)" inconclusive "sin ediciones observables tras la revisión: inconcluso"

# Caso del repositorio: expect_followup=yes exige que la regla aplique
newcase node-auth; verify_ok
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$(QRUN)" "$CODEX_FU"
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
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS high "$(evq valid)" "$(rv done true)")" "$(QRUN)" "$CODEX_ADV" "$EDIT" "$CODEX_FU"
evalc f-any
assert_eq "$(sed -n 's/^review_critical_fixed=//p' "$OUTD/trace/report.kv")" true "review_critical_fixed extraído"
assert_eq "$(res critical_fixed)/$(res codex_after_last_edit)" "structured/1" "result.kv: origen del hallazgo crítico y revisión posterior"

finish
