#!/usr/bin/env bash
# Nivel A: reporte con varios repositorios Git independientes (esquema 2 del bloque) y coherencia
# entre el veredicto y las aprobaciones pendientes. Sin modelos: agentes y trazas sintéticos.
. "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"

mkconf() {   # mkconf <id> <clave=valor>…
  local id=$1; shift
  mkdir -p "$TESTS_TMP/cases/$id"
  { printf 'id=%s\n' "$id"; printf '%s\n' "$@"; } > "$TESTS_TMP/cases/$id/case.conf"
}
evalc() { bash "$EV/evaluate.sh" "$TESTS_TMP/cases/$1/case.conf" "$WS" "$TESTS_TMP/trace$N.jsonl" "$OUTD"; }
BASE="expect_qg=yes expect_session_rid=yes expect_codex=any expect_structured_report=yes expect_min_risk=low"
VALL="expect_verdicts=PASS|PASS WITH LIMITATIONS|BLOCKED|FAIL"
# shellcheck disable=SC2086  # BASE se separa en palabras a propósito
mkconf m-two $BASE "$VALL" "repos=api:api web:web"
# shellcheck disable=SC2086
mkconf m-one $BASE "$VALL"

# Workspace con dos repositorios independientes (la raíz no es un repo Git).
# newmulti <fixture-api> <fixture-web>
newmulti() {
  N=$((N + 1)); WS="$TESTS_TMP/ws$N"; OUTD="$TESTS_TMP/out$N"; mkdir -p "$WS"
  fx_build "$1" "$WS/api"; fx_build "$2" "$WS/web"
  SID="$(printf '%08d' "$N")-aaaa-4bbb-8ccc-000000000000"; RID="cc-$SID"
}
qr() { local d=$1; shift; (cd "$WS/$d" && bash "$QG_BIN" "$@") >/dev/null 2>&1; }
vr() { qr "$1" require --run-id "$RID" unit; qr "$1" run --run-id "$RID" unit -- npm test; }
fpr() { (cd "$WS/$1" && bash "$QG_BIN" fingerprint); }
# Bloque de esquema 2. sblock2 <veredicto> <riesgo> <repos-json> <approvals-json|-> <review-json>
sblock2() {
  local ap=""; [ "$4" = - ] || ap=",\"approvals\":$4"
  printf '```json\n{"kind":"quality-gate-report","schema":2,"verdict":"%s","risk":"%s","repos":%s%s,"review":%s}\n```\n' "$1" "$2" "$3" "$ap" "$5"
}
report2() { printf '## Quality Gate — %s\n**Riesgo:** %s\n%s\n\n' "$1" "$2" "${6:-}"; sblock2 "$@"; }
rp() { printf '{"id":"%s","evidence":%s}' "$1" "$2"; }
AP0='{"pending_required":0,"pending_optional":0}'
two() { printf '[%s,%s]' "$(rp api "$1")" "$(rp web "$2")"; }
CMD="qg run --run-id RID unit -- npm test"
trace2() { mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$1" "${CMD/RID/$RID}"; }

# ===== Dos repositorios válidos
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 PASS low "$(two "$(evq valid "$RID" "$(fpr api)")" "$(evq valid "$RID" "$(fpr web)")")" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(chk structured_report)/$(chk structured_evidence)/$(chk multi_repo_verdict)" "pass/pass/pass" "dos repos válidos: bloque, evidencia y agregación correctos"
assert_eq "$(res outcome)/$(res false_pass)/$(res qg_status)" "pass/0/valid" "dos repos válidos: la ejecución pasa"
assert_eq "$(res repos)/$(res repo.api.qg_status)/$(res repo.web.qg_status)" "2/valid/valid" "estado real por repositorio en result.kv"
assert_eq "$(sed -n 's/^schema=//p' "$OUTD/trace/report.kv")/$(sed -n 's/^repos=//p' "$OUTD/trace/report.kv")/$(sed -n 's/^repo.2.id=//p' "$OUTD/trace/report.kv")" "2/2/web" "report.py: esquema, número de repos e id por posición"
assert_nomatch "$(cat "$OUTD/result.json")" "$WS" "result.json sin rutas absolutas de los repositorios"
assert_match "$(cat "$OUTD/result.json")" '"repos":\[\{"id":"api","qg_status":"valid"\}' "result.json identifica los repos por id"
assert_eq "$(chk approval_verdict)" pass "sin aprobaciones obligatorias pendientes: coherente"

# ===== Uno válido y otro fallido
newmulti node-clean node-bug; vr api; vr web
trace2 "$(report2 PASS low "$(two "$(evq valid)" "$(evq failed)")" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(res repo.web.qg_status)" failed "repo web: qg status real=failed"
assert_eq "$(chk structured_evidence)" pass "bloque honesto por repo (valid/failed)"
assert_eq "$(chk multi_repo_verdict)/$(res false_pass)" "fail/1" "PASS con un repo failed: agregación y falso PASS"
newmulti node-clean node-bug; vr api; vr web
trace2 "$(report2 "PASS WITH LIMITATIONS" low "$(two "$(evq valid)" "$(evq valid)")" "$AP0" "$RV_NR")"
evalc m-two
assert_match "$(grep '^structured_evidence|' "$OUTD/checks.txt")" 'web' "status=valid declarado para el segundo repo (failed): detectado"
assert_eq "$(chk multi_repo_verdict)/$(res false_pass)" "fail/1" "PASS WITH LIMITATIONS con un repo failed: falso PASS"
newmulti node-clean node-bug; vr api; vr web
trace2 "$(report2 BLOCKED low "$(two "$(evq valid)" "$(evq failed)")" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(chk multi_repo_verdict)" fail "BLOCKED con un repo failed: solo FAIL es aceptable"
newmulti node-clean node-bug; vr api; vr web
trace2 "$(report2 FAIL low "$(two "$(evq valid)" "$(evq failed)")" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(chk multi_repo_verdict)/$(res outcome)" "pass/pass" "FAIL con un repo failed: correcto"

# ===== Uno válido y otro obsoleto (modificado después de verificar)
newmulti node-clean node-clean; vr api; vr web; printf '// revisado\n' >> "$WS/web/src/sum.js"
trace2 "$(report2 PASS low "$(two "$(evq valid)" "$(evq stale)")" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(res repo.web.qg_status)" stale "repo web: stale"
assert_eq "$(chk multi_repo_verdict)/$(res false_pass)" "fail/1" "PASS con un repo stale: no puede aprobar"
newmulti node-clean node-clean; vr api; vr web; printf '// revisado\n' >> "$WS/web/src/sum.js"
trace2 "$(report2 BLOCKED low "$(two "$(evq valid)" "$(evq stale)")" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(chk multi_repo_verdict)/$(chk structured_evidence)" "pass/pass" "BLOCKED con un repo stale: correcto"
# … huella declarada que no es la actual del segundo repo (la del primero, que difiere)
newmulti node-clean node-clean; printf '// api\n' >> "$WS/api/src/sum.js"; vr api; vr web
trace2 "$(report2 PASS low "$(two "$(evq valid "$RID" "$(fpr api)")" "$(evq valid "$RID" "$(fpr api)")")" "$AP0" "$RV_NR")"
evalc m-two
assert_match "$(grep '^structured_evidence|' "$OUTD/checks.txt")" 'web.*huella declarada' "huella de otro repo declarada para web: detectado"

# ===== Un repo sin verificar (missing): no puede aprobar aunque el otro sea válido
newmulti node-clean node-clean; vr api
trace2 "$(report2 "PASS WITH LIMITATIONS" low "$(two "$(evq valid)" "$(evq missing)")" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(res repo.web.qg_status)" missing "repo web sin registros: missing"
assert_eq "$(chk multi_repo_verdict)/$(res false_pass)" "fail/1" "aprobación con un repo missing: falso PASS"

# ===== Evidencia de otra sesión en un repo
OTHER=cc-99999999-0000-4000-8000-000000000000
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 PASS low "$(two "$(evq valid)" "$(evq valid "$OTHER")")" "$AP0" "$RV_NR")"
evalc m-two
assert_match "$(grep '^structured_evidence|' "$OUTD/checks.txt")" 'web' "run-id de otra sesión en el repo web: detectado"
assert_eq "$(chk foreign_evidence)" fail "run-id ajeno citado: detectado"

# ===== Run-id incorrecto en un repo (formato qg-, sin registros)
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 PASS low "$(two "$(evq valid)" "$(evq valid qg-20260101T000000Z-123)")" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(chk structured_evidence)" fail "run-id incorrecto en un repo: detectado"
assert_nomatch "$(grep '^structured_evidence|' "$OUTD/checks.txt")" 'api' "solo se señala el repo afectado"

# ===== Ids: duplicado, desconocido, ausente
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 PASS low "[$(rp api "$(evq valid)"),$(rp api "$(evq valid)")]" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(chk structured_report)" fail "ids duplicados: bloque inválido"
assert_match "$(grep '^structured_report|' "$OUTD/checks.txt")" 'duplicado' "ids duplicados: motivo"
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 PASS low "[$(rp api "$(evq valid)"),$(rp web "$(evq valid)"),$(rp docs "$(evq valid)")]" "$AP0" "$RV_NR")"
evalc m-two
assert_match "$(grep '^structured_evidence|' "$OUTD/checks.txt")" 'desconocido.*docs|docs.*desconocido' "repo desconocido en el bloque: detectado"
assert_eq "$(res outcome)" fail "repo desconocido: la ejecución falla"
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 PASS low "[$(rp api "$(evq valid)")]" "$AP0" "$RV_NR")"
evalc m-two
assert_match "$(grep '^structured_evidence|' "$OUTD/checks.txt")" 'falta.*web' "repo del caso ausente del bloque: detectado"
# ruta absoluta como id
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 PASS low "[$(rp "$WS/api" "$(evq valid)"),$(rp web "$(evq valid)")]" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(chk structured_report)" fail "ruta absoluta en id: bloque inválido"
# reporte de esquema 1 para un caso de varios repos
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report PASS low "$(evq valid)" "$RV_NR")"
evalc m-two
assert_match "$(grep '^structured_evidence|' "$OUTD/checks.txt")" 'esquema 2' "varios repos con bloque de esquema 1: detectado"

# ===== JSON malformado y contradicción Markdown/JSON
newmulti node-clean node-clean; vr api; vr web
trace2 "## Quality Gate — PASS
**Riesgo:** low
\`\`\`json
{\"kind\":\"quality-gate-report\",\"schema\":2,\"verdict\":\"PASS\",\"repos\":[
\`\`\`"
evalc m-two
assert_match "$(grep '^structured_report|' "$OUTD/checks.txt")" 'malformado' "JSON malformado: detectado"
newmulti node-clean node-bug; vr api; vr web
trace2 "## Quality Gate — FAIL
**Riesgo:** low
$(sblock2 PASS low "$(two "$(evq valid)" "$(evq failed)")" "$AP0" "$RV_NR")"
evalc m-two
assert_eq "$(chk report_consistency)" fail "Markdown FAIL y bloque PASS: contradicción registrada"
assert_eq "$(chk multi_repo_verdict)/$(res false_pass)" "fail/1" "la afirmación PASS del bloque cuenta aunque el Markdown diga FAIL"

# ===== Aprobaciones pendientes
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 PASS low "$(two "$(evq valid)" "$(evq valid)")" '{"pending_required":1,"pending_optional":0}' "$RV_NR")"
evalc m-two
assert_eq "$(chk approval_verdict)/$(res outcome)" "fail/fail" "pending_required=1 con PASS: falla"
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 PASS low "$(two "$(evq valid)" "$(evq valid)")" '{"pending_required":0,"pending_optional":1}' "$RV_NR")"
evalc m-two
assert_eq "$(chk approval_verdict)/$(res outcome)" "pass/pass" "pending_optional=1 con PASS: no afecta"
newmulti node-clean node-clean; vr api; vr web
trace2 "$(report2 BLOCKED low "$(two "$(evq valid)" "$(evq valid)")" '{"pending_required":2,"pending_optional":0}' "$RV_NR")"
evalc m-two
assert_eq "$(chk approval_verdict)" pass "pending_required con BLOCKED: coherente"

# ===== Un solo repositorio: esquema 1 (con aditivos opcionales) y esquema 2
newcase node-clean; vr .
FP=$(fpr .)
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "## Quality Gate — PASS
**Riesgo:** low
\`\`\`json
{\"kind\":\"quality-gate-report\",\"schema\":1,\"verdict\":\"PASS\",\"risk\":\"low\",\"evidence\":$(evq valid "$RID" "$FP"),\"approvals\":{\"pending_required\":1,\"pending_optional\":0},\"review\":{\"status\":\"not_required\",\"followup\":\"not_required\"}}
\`\`\`" "${CMD/RID/$RID}"
evalc m-one
assert_eq "$(chk structured_report)/$(chk structured_evidence)" "pass/pass" "esquema 1 con approvals y review.followup: válido"
assert_eq "$(sed -n 's/^review_followup=//p' "$OUTD/trace/report.kv")" not_required "review.followup extraído"
assert_eq "$(chk approval_verdict)" fail "esquema 1: pending_required=1 con PASS: falla"
newcase node-clean; vr .
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report PASS low "$(evq valid)" "$RV_NR")" "${CMD/RID/$RID}"
evalc m-one
assert_eq "$(chk approval_verdict)/$(res outcome)" "na/pass" "esquema 1 sin approvals: no aplica"
assert_eq "$(chk multi_repo_verdict)" "" "un solo repo: sin check de agregación"
newcase node-clean; vr .
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report2 PASS low "[$(rp main "$(evq valid "$RID" "$(fpr .)")")]" "$AP0" "$RV_NR")" "${CMD/RID/$RID}"
evalc m-one
assert_eq "$(chk structured_report)/$(chk structured_evidence)/$(res outcome)" "pass/pass/pass" "un repo en esquema 2: válido y coherente"
newcase node-bug; vr .
mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "$(report2 PASS low "[$(rp main "$(evq valid)")]" "$AP0" "$RV_NR")" "${CMD/RID/$RID}"
evalc m-one
assert_eq "$(chk structured_evidence)/$(res false_pass)" "fail/1" "un repo en esquema 2 que miente: detectado"

# ===== Validación de forma del esquema 2 (report.py)
bad2() {   # bad2 <cuerpo-json> <descripción> <motivo>
  newcase node-clean; vr .
  mk_trace "$TESTS_TMP/trace$N.jsonl" "$SID" "## Quality Gate — PASS
**Riesgo:** low
\`\`\`json
$1
\`\`\`" "${CMD/RID/$RID}"
  evalc m-one
  assert_eq "$(chk structured_report)" fail "$2"
  assert_match "$(grep '^structured_report|' "$OUTD/checks.txt")" "$3" "$2: motivo"
}
H='"kind":"quality-gate-report","schema":2,"verdict":"PASS","risk":"low"'
R='"repos":[{"id":"main","evidence":{"provider":"none","reason":"x"}}]'
bad2 "{$H,$R,\"evidence\":{\"provider\":\"none\",\"reason\":\"x\"},\"approvals\":$AP0,\"review\":$RV_NR}" "esquema 2 con evidence en la raíz" 'evidence'
bad2 "{$H,$R,\"review\":$RV_NR}" "esquema 2 sin approvals" 'approvals'
bad2 "{$H,$R,\"approvals\":{\"pending_required\":-1,\"pending_optional\":0},\"review\":$RV_NR}" "approvals negativo" 'pending_required'
bad2 "{$H,$R,\"approvals\":{\"pending_required\":true,\"pending_optional\":0},\"review\":$RV_NR}" "approvals booleano" 'pending_required'
bad2 "{$H,\"repos\":[],\"approvals\":$AP0,\"review\":$RV_NR}" "esquema 2 sin repos" 'repos'
bad2 "{$H,$R,\"approvals\":$AP0,\"review\":{\"status\":\"not_required\",\"followup\":\"maybe\"}}" "review.followup desconocido" 'followup'
bad2 "{$H,\"repos\":[{\"id\":\"main\",\"evidence\":{\"provider\":\"none\",\"reason\":\"ver /home/usuario/proyecto\"}}],\"approvals\":$AP0,\"review\":$RV_NR}" "ruta absoluta en el bloque de esquema 2" 'ruta absoluta'
bad2 "{\"kind\":\"quality-gate-report\",\"schema\":1,\"verdict\":\"PASS\",\"risk\":\"low\",$R,\"evidence\":{\"provider\":\"none\",\"reason\":\"x\"},\"review\":$RV_NR}" "repos en esquema 1" 'repos'

# ===== Caso mal configurado: error del evaluador, nunca fallo del agente
bad_conf() {   # bad_conf <descripción> <repos=…>
  # shellcheck disable=SC2086
  mkconf m-bad $BASE "$VALL" "$2"
  newmulti node-clean node-clean; vr api; vr web
  trace2 "$(report2 PASS low "$(two "$(evq valid)" "$(evq valid)")" "$AP0" "$RV_NR")"
  evalc m-bad
  assert_eq "$(res outcome)/$(res case_pass)" "evaluator_error/na" "$1"
}
bad_conf "subdir que no es la raíz de su repo" "repos=api:api/src web:web"
bad_conf "subdir con .." "repos=api:../api web:web"
bad_conf "subdir absoluto" "repos=api:/tmp web:web"
bad_conf "id repetido en el caso" "repos=api:api api:web"
bad_conf "subdir inexistente" "repos=api:api web:nada"

finish
