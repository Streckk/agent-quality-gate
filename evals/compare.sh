#!/usr/bin/env bash
# Compara dos ejecuciones agregadas (summary.kv) de Agent Evals, p. ej. dos commits.
# uso: compare.sh <dir-A> <dir-B>   → informe Markdown por stdout
# No afirma mejoras: con muestras pequeñas solo describe diferencias.
set -uo pipefail
A=$1; B=$2
for d in "$A" "$B"; do [ -f "$d/summary.kv" ] || { echo "falta $d/summary.kv (ejecuta aggregate.sh)" >&2; exit 64; }; done
g() { sed -n "s/^$2=//p" "$1/summary.kv" | head -n 1; }
delta() { awk -v a="$1" -v b="$2" 'BEGIN{ if (a=="na"||b=="na"||a==""||b=="") print "—"; else printf "%+.3f", b-a }'; }
echo "# Comparación de Agent Evals"
echo
echo "| | A | B |"
echo "|---|---|---|"
for k in repo_commit qg_version claude_version started_at runs_per_case cases; do echo "| $k | $(g "$A" $k) | $(g "$B" $k) |"; done
echo
echo "| Métrica | A | B | Δ (B−A) |"
echo "|---|---|---|---|"
for k in success_rate false_pass_rate required_checks_coverage evidence_consistency guardrail_violations stop_blocks duration_s_mean cost_usd_total runs_ok runs_infra_error; do
  a=$(g "$A" $k); b=$(g "$B" $k); echo "| $k | ${a:-na} | ${b:-na} | $(delta "${a:-na}" "${b:-na}") |"
done
echo
echo "| Caso | Superadas A | Superadas B |"
echo "|---|---|---|"
{ sed -n 's/^case\.\([^.]*\)\.runs=.*/\1/p' "$A/summary.kv"; sed -n 's/^case\.\([^.]*\)\.runs=.*/\1/p' "$B/summary.kv"; } | LC_ALL=C sort -u | while read -r c; do
  echo "| $c | $(g "$A" "case.$c.passed")/$(g "$A" "case.$c.ok") | $(g "$B" "case.$c.passed")/$(g "$B" "case.$c.ok") |"
done
nA=$(g "$A" runs_ok); nB=$(g "$B" runs_ok)
echo
echo "Muestras: A=${nA:-0}, B=${nB:-0} ejecuciones válidas. Los agentes no son deterministas: diferencias con menos de ~5 ejecuciones por caso y brazo **no son concluyentes** y no deben presentarse como mejoras."
