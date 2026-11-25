#!/usr/bin/env bash
# Compara dos ejecuciones agregadas (summary.kv) de Agent Evals: dos commits, o dos brazos.
# uso: compare.sh <dir-A> <dir-B>   → informe Markdown por stdout
# No afirma mejoras: con muestras pequeñas solo describe diferencias. Avisa cuando las condiciones
# del experimento (modelo, casos, ejecuciones por caso, versión de Claude Code) no son las mismas.
set -uo pipefail
A=${1:-}; B=${2:-}
for d in "$A" "$B"; do [ -n "$d" ] && [ -f "$d/summary.kv" ] || { echo "falta ${d:-<dir>}/summary.kv (ejecuta aggregate.sh)" >&2; exit 64; }; done
g() { sed -n "s/^$2=//p" "$1/summary.kv" | head -n 1; }
delta() { awk -v a="$1" -v b="$2" 'BEGIN{ if (a=="na"||b=="na"||a==""||b=="") print "—"; else printf "%+.3f", b-a }'; }
echo "# Comparación de Agent Evals"
echo
echo "| Condición | A | B |"
echo "|---|---|---|"
for k in arm repo_commit qg_version claude_version model models_observed started_at runs_per_case cases max_cost_usd; do
  echo "| $k | $(g "$A" $k) | $(g "$B" $k) |"
done
WARN=""
for k in model claude_version runs_per_case cases; do
  [ "$(g "$A" $k)" = "$(g "$B" $k)" ] || WARN="$WARN $k"
done
[ "$(g "$A" models_observed)" = "$(g "$B" models_observed)" ] || WARN="$WARN modelos-observados"
echo
if [ -n "$WARN" ]; then
  echo "> **Condiciones distintas:**$WARN. Las diferencias pueden deberse a las condiciones y no al cambio que se quiere medir."
  echo
fi
echo "| Métrica | A | B | Δ (B−A) |"
echo "|---|---|---|---|"
for k in success_rate false_pass_rate required_checks_coverage evidence_consistency risk_classification_accuracy structured_report_valid \
         guardrail_violations guardrail_suspected stop_blocks inconclusive_checks suspected_checks duration_s_mean cost_usd_total \
         runs_ok runs_decided runs_inconclusive runs_infra_error runs_evaluator_error runs_duplicate_ignored; do
  a=$(g "$A" $k); b=$(g "$B" $k); echo "| $k | ${a:-na} | ${b:-na} | $(delta "${a:-na}" "${b:-na}") |"
done
echo
echo "| Caso | Superadas A | Superadas B |"
echo "|---|---|---|"
{ sed -n 's/^case\.\([^.]*\)\.runs=.*/\1/p' "$A/summary.kv"; sed -n 's/^case\.\([^.]*\)\.runs=.*/\1/p' "$B/summary.kv"; } | LC_ALL=C sort -u | while read -r c; do
  pa=$(g "$A" "case.$c.passed"); pb=$(g "$B" "case.$c.passed")
  echo "| $c | ${pa:-—}/$(g "$A" "case.$c.ok" | sed 's/^$/—/') válidas | ${pb:-—}/$(g "$B" "case.$c.ok" | sed 's/^$/—/') válidas |"
done
nA=$(g "$A" runs_ok); nB=$(g "$B" runs_ok)
echo
[ "${nA:-0}" != "${nB:-0}" ] && echo "Distinto número de ejecuciones válidas por brazo: compara tasas, no recuentos." && echo
echo "Muestras: A=${nA:-0}, B=${nB:-0} ejecuciones válidas. Los agentes no son deterministas: diferencias con menos de ~5 ejecuciones por caso y brazo **no son concluyentes** y no deben presentarse como mejoras."
