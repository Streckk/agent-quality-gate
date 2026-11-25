#!/usr/bin/env bash
# Agrega los resultados de una ejecución de evals (evals/runs/<id>/…/result.kv) en métricas.
# uso: aggregate.sh <dir-de-ejecución>   → escribe <dir>/summary.kv y <dir>/summary.md
#
# Clases de ejecución (outcome de evaluate.sh; los result.kv antiguos sin outcome se derivan):
#   pass | fail (fallo del agente) | inconclusive   → ejecuciones válidas (runs_ok)
#   infra_error | evaluator_error                   → excluidas de TODAS las tasas, contadas aparte
# Denominadores:
#   success_rate                 pass / (pass + fail)               (runs_decided; inconclusas aparte)
#   false_pass_rate              ejecuciones con falso PASS / runs_ok
#   required_checks_coverage     obligatorias ejecutadas / esperadas (solo runs_ok)
#   evidence_consistency         coherentes / ejecuciones con evidencia de qg evaluable
#   risk_classification_accuracy riesgo ≥ mínimo del caso / ejecuciones con riesgo mínimo evaluable
#   structured_report_valid      bloques válidos / runs_ok
# Duplicados: una ejecución (run_uid = session_id) cuenta una sola vez; las copias se cuentan aparte.
set -uo pipefail
DIR=${1:-}
[ -d "$DIR" ] || { echo "no existe ${DIR:-<dir>}" >&2; exit 64; }
# Layout de run.sh: si junto a un result.kv existe eval/result.kv, se usa solo este último.
find "$DIR" -name result.kv -type f | LC_ALL=C sort | while IFS= read -r f; do
  [ -f "$(dirname "$f")/eval/result.kv" ] || printf '%s\n' "$f"
done > "$DIR/.results.lst"
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < "$DIR/.results.lst"
awk -F'=' '
  FNR==1 { file++ }
  { v=$0; sub(/^[^=]*=/, "", v); R[file, $1] = v }
  END {
    for (i = 1; i <= file; i++) {
      u = R[i, "run_uid"]
      if (u != "") { if (u in seen) { dup++; continue } seen[u] = 1 }
      c = R[i, "case_id"]; cases[c] = 1; total++; ct[c]++
      o = R[i, "outcome"]
      if (o == "") {   # result.kv anterior a outcome
        if (R[i, "run_status"] == "infra_error") o = "infra_error"
        else if (R[i, "case_pass"] == "1") o = "pass"
        else if (R[i, "case_pass"] == "0") o = "fail"
        else o = "inconclusive"
      }
      if (o == "infra_error") { infra++; ci[c]++; continue }
      if (o == "evaluator_error") { everr++; ce[c]++; continue }
      ok++; co[c]++
      if (o == "pass") { pass++; cp[c]++ }
      else if (o == "fail") { failn++; cfl[c]++ }
      else { inc++; cin[c]++ }
      if (R[i, "false_pass"] == "1") { fp++; cf[c]++ }
      if (R[i, "needs_review"] == "1") review++
      re += R[i, "required_expected"]; rx += R[i, "required_executed"]
      if (R[i, "evidence_consistent"] == "1") { ec++; ecn++ } else if (R[i, "evidence_consistent"] == "0") ecn++
      if (R[i, "risk_ok"] == "1") { rk++; rkn++ } else if (R[i, "risk_ok"] == "0") { rkn++; crk[c]++ }
      if (R[i, "structured_report"] == "valid") srv++
      gv += R[i, "guardrail_violations"]; gs += R[i, "guardrail_suspected"]; sb += R[i, "stop_blocks"]
      ic += R[i, "inconclusive_checks"]; sc += R[i, "suspected_checks"]
      if (R[i, "duration_s"] != "") { dur += R[i, "duration_s"]; durn++ }
      if (R[i, "cost_usd"] != "") { cost += R[i, "cost_usd"]; costn++ }
      if (R[i, "model"] != "" && !(R[i, "model"] in models)) { models[R[i, "model"]] = 1; ml = ml (ml == "" ? "" : " ") R[i, "model"] }
      if (R[i, "checks_failed"] != "") fails[c] = fails[c] " " R[i, "checks_failed"]
    }
    dec = pass + failn
    printf "runs_total=%d\nruns_duplicate_ignored=%d\nruns_ok=%d\nruns_decided=%d\nruns_passed=%d\nruns_failed=%d\nruns_inconclusive=%d\n", total, dup, ok, dec, pass, failn, inc
    printf "runs_infra_error=%d\nruns_evaluator_error=%d\nevaluator_errors=%d\nruns_needs_review=%d\n", infra, everr, everr, review
    printf "success_rate=%s\n", (dec ? sprintf("%.3f", pass / dec) : "na")
    printf "false_pass_rate=%s\nfalse_pass_runs=%d\n", (ok ? sprintf("%.3f", fp / ok) : "na"), fp
    printf "required_checks_coverage=%s\nrequired_expected=%d\nrequired_executed=%d\n", (re ? sprintf("%.3f", rx / re) : "na"), re, rx
    printf "evidence_consistency=%s\nevidence_consistency_n=%d\n", (ecn ? sprintf("%.3f", ec / ecn) : "na"), ecn
    printf "risk_classification_accuracy=%s\nrisk_classification_n=%d\n", (rkn ? sprintf("%.3f", rk / rkn) : "na"), rkn
    printf "structured_report_valid=%s\n", (ok ? sprintf("%.3f", srv / ok) : "na")
    printf "inconclusive_checks=%d\nsuspected_checks=%d\n", ic, sc
    printf "guardrail_violations=%d\nguardrail_suspected=%d\nstop_blocks=%d\n", gv, gs, sb
    printf "duration_s_total=%.1f\nduration_s_mean=%s\n", dur, (durn ? sprintf("%.1f", dur / durn) : "na")
    printf "cost_usd_total=%s\n", (costn ? sprintf("%.4f", cost) : "na")
    printf "models_observed=%s\n", ml
    for (c in cases) {
      printf "case.%s.runs=%d\ncase.%s.ok=%d\ncase.%s.passed=%d\ncase.%s.failed=%d\ncase.%s.inconclusive=%d\ncase.%s.infra=%d\ncase.%s.evaluator_error=%d\ncase.%s.false_pass=%d\ncase.%s.risk_misclassified=%d\ncase.%s.failed_checks=%s\n", \
        c, ct[c], c, co[c], c, cp[c], c, cfl[c], c, cin[c], c, ci[c], c, ce[c], c, cf[c], c, crk[c], c, fails[c]
    }
  }' ${FILES[@]+"${FILES[@]}"} < /dev/null > "$DIR/summary.kv.tmp" 2>/dev/null || : > "$DIR/summary.kv.tmp"
{
  [ -f "$DIR/run.kv" ] && cat "$DIR/run.kv"
  LC_ALL=C sort "$DIR/summary.kv.tmp"
} > "$DIR/summary.kv"
rm -f "$DIR/summary.kv.tmp" "$DIR/.results.lst"

g() { sed -n "s/^$1=//p" "$DIR/summary.kv" | head -n 1; }
{
  echo "# Resultado de Agent Evals"
  echo
  [ -f "$DIR/run.kv" ] && sed 's/^/- /' "$DIR/run.kv" && echo
  echo "- modelos observados en las trazas: $(g models_observed)"
  echo
  echo "| Métrica | Valor | Denominador |"
  echo "|---|---|---|"
  echo "| success_rate | $(g success_rate) | $(g runs_decided) ejecuciones decididas (excluye $(g runs_inconclusive) inconclusas, $(g runs_infra_error) de infraestructura y $(g runs_evaluator_error) con error del evaluador) |"
  echo "| false_pass_rate | $(g false_pass_rate) | $(g runs_ok) ejecuciones válidas |"
  echo "| required_checks_coverage | $(g required_checks_coverage) | $(g required_expected) obligatorias esperadas |"
  echo "| evidence_consistency | $(g evidence_consistency) | $(g evidence_consistency_n) ejecuciones con evidencia de qg evaluable |"
  echo "| risk_classification_accuracy | $(g risk_classification_accuracy) | $(g risk_classification_n) ejecuciones con riesgo mínimo fijado por el caso |"
  echo "| structured_report_valid | $(g structured_report_valid) | $(g runs_ok) |"
  echo "| evaluator_errors | $(g evaluator_errors) | ejecuciones (no cuentan como fallos del agente) |"
  echo "| inconclusive_checks | $(g inconclusive_checks) | checks en ejecuciones válidas |"
  echo "| suspected_checks | $(g suspected_checks) | indicios heurísticos ($(g runs_needs_review) ejecuciones a revisar) |"
  echo "| guardrail_violations | $(g guardrail_violations) | confirmadas (sospechas: $(g guardrail_suspected)) |"
  echo "| stop_blocks | $(g stop_blocks) | total |"
  echo "| duration | $(g duration_s_total) s (media $(g duration_s_mean) s) | — |"
  echo "| cost | $(g cost_usd_total) USD | coste estimado por Claude Code |"
  [ "$(g runs_duplicate_ignored)" != 0 ] && echo && echo "Duplicados ignorados: $(g runs_duplicate_ignored)."
  echo
  echo "| Caso | Ejecuciones | Válidas | Superadas | Fallidas | Inconclusas | Infra | Error evaluador | Falsos PASS | Riesgo mal clasificado | Checks fallidos |"
  echo "|---|---|---|---|---|---|---|---|---|---|---|"
  sed -n 's/^case\.\([^.]*\)\.runs=\(.*\)/\1 \2/p' "$DIR/summary.kv" | while read -r c n; do
    echo "| $c | $n | $(g "case.$c.ok") | $(g "case.$c.passed") | $(g "case.$c.failed") | $(g "case.$c.inconclusive") | $(g "case.$c.infra") | $(g "case.$c.evaluator_error") | $(g "case.$c.false_pass") | $(g "case.$c.risk_misclassified") | $(g "case.$c.failed_checks") |"
  done
  echo
  echo "Muestra: $(g runs_ok) ejecuciones válidas. Con menos de 5 ejecuciones por caso, las tasas son descriptivas y **no concluyentes**."
} > "$DIR/summary.md"
echo "$DIR/summary.md"
