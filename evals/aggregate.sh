#!/usr/bin/env bash
# Agrega los resultados de una ejecución de evals (evals/runs/<id>/…/result.kv) en métricas.
# uso: aggregate.sh <dir-de-ejecución>   → escribe <dir>/summary.kv y <dir>/summary.md
# Denominadores explícitos; los errores de infraestructura se excluyen de las tasas y se cuentan aparte.
set -uo pipefail
DIR=$1
[ -d "$DIR" ] || { echo "no existe $DIR" >&2; exit 64; }
# Una ejecución cuenta UNA vez: si junto a un result.kv existe eval/result.kv (layout de run.sh),
# se usa solo este último (regresión: una copia duplicada contaba cada ejecución dos veces).
find "$DIR" -name result.kv -type f | LC_ALL=C sort | while IFS= read -r f; do
  [ -f "$(dirname "$f")/eval/result.kv" ] || printf '%s\n' "$f"
done > "$DIR/.results.lst"
awk -F'=' '
  FNR==1 { file++ }
  { v=$0; sub(/^[^=]*=/, "", v); R[file, $1] = v }
  END {
    for (i = 1; i <= file; i++) {
      c = R[i, "case_id"]; cases[c] = 1; total++; ct[c]++
      if (R[i, "run_status"] != "ok") { infra++; ci[c]++; continue }
      ok++; co[c]++
      if (R[i, "case_pass"] == "1") { pass++; cp[c]++ }
      if (R[i, "false_pass"] == "1") { fp++; cf[c]++ }
      re += R[i, "required_expected"]; rx += R[i, "required_executed"]
      if (R[i, "evidence_consistent"] == "1") { ec++; ecn++ } else if (R[i, "evidence_consistent"] == "0") ecn++
      gv += R[i, "guardrail_violations"]; sb += R[i, "stop_blocks"]
      if (R[i, "duration_s"] != "") { dur += R[i, "duration_s"]; durn++ }
      if (R[i, "cost_usd"] != "") { cost += R[i, "cost_usd"]; costn++ }
      if (R[i, "checks_failed"] != "") fails[c] = fails[c] " " R[i, "checks_failed"]
    }
    printf "runs_total=%d\nruns_ok=%d\nruns_infra_error=%d\nruns_passed=%d\n", total, ok, infra, pass
    printf "success_rate=%s\n", (ok ? sprintf("%.3f", pass / ok) : "na")
    printf "false_pass_rate=%s\n", (ok ? sprintf("%.3f", fp / ok) : "na")
    printf "false_pass_runs=%d\n", fp
    printf "required_checks_coverage=%s\nrequired_expected=%d\nrequired_executed=%d\n", (re ? sprintf("%.3f", rx / re) : "na"), re, rx
    printf "evidence_consistency=%s\nevidence_consistency_n=%d\n", (ecn ? sprintf("%.3f", ec / ecn) : "na"), ecn
    printf "guardrail_violations=%d\nstop_blocks=%d\n", gv, sb
    printf "duration_s_total=%.1f\nduration_s_mean=%s\n", dur, (durn ? sprintf("%.1f", dur / durn) : "na")
    printf "cost_usd_total=%s\n", (costn ? sprintf("%.4f", cost) : "na")
    for (c in cases) {
      printf "case.%s.runs=%d\ncase.%s.ok=%d\ncase.%s.passed=%d\ncase.%s.infra=%d\ncase.%s.false_pass=%d\ncase.%s.failed_checks=%s\n", \
        c, ct[c], c, co[c], c, cp[c], c, ci[c], c, cf[c], c, fails[c]
    }
  }' $(cat "$DIR/.results.lst") > "$DIR/summary.kv.tmp" 2>/dev/null || : > "$DIR/summary.kv.tmp"
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
  echo "| Métrica | Valor | Denominador |"
  echo "|---|---|---|"
  echo "| success_rate | $(g success_rate) | $(g runs_ok) ejecuciones válidas (excluye $(g runs_infra_error) con error de infraestructura) |"
  echo "| false_pass_rate | $(g false_pass_rate) | $(g runs_ok) |"
  echo "| required_checks_coverage | $(g required_checks_coverage) | $(g required_expected) obligatorias esperadas |"
  echo "| evidence_consistency | $(g evidence_consistency) | $(g evidence_consistency_n) ejecuciones con evidencia de qg evaluable |"
  echo "| guardrail_violations | $(g guardrail_violations) | total |"
  echo "| stop_blocks | $(g stop_blocks) | total |"
  echo "| duration | $(g duration_s_total) s (media $(g duration_s_mean) s) | — |"
  echo "| cost | $(g cost_usd_total) USD | coste estimado por Claude Code |"
  echo
  echo "| Caso | Ejecuciones | Válidas | Superadas | Falsos PASS | Checks fallidos |"
  echo "|---|---|---|---|---|---|"
  sed -n 's/^case\.\([^.]*\)\.runs=\(.*\)/\1 \2/p' "$DIR/summary.kv" | while read -r c n; do
    echo "| $c | $n | $(g "case.$c.ok") | $(g "case.$c.passed") | $(g "case.$c.false_pass") | $(g "case.$c.failed_checks") |"
  done
  echo
  echo "Muestra: $(g runs_ok) ejecuciones válidas. Con menos de 5 ejecuciones por caso, las tasas son descriptivas y **no concluyentes**."
} > "$DIR/summary.md"
echo "$DIR/summary.md"
