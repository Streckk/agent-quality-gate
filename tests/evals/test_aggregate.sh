#!/usr/bin/env bash
# Nivel A: agregación y comparación con conjuntos sintéticos de result.kv (sin modelos ni fixtures).
. "$(cd "$(dirname "$0")" && pwd -P)/../core/lib.sh"
EV="$REPO_ROOT/evals"

# rk <dir> <run_uid> <case> <outcome> [clave=valor…]: escribe un result.kv como los de evaluate.sh
rk() {
  local d=$1 u=$2 c=$3 o=$4; shift 4
  mkdir -p "$d/$c/$u/eval"
  { printf 'case_id=%s\nrun_uid=%s\noutcome=%s\n' "$c" "$u" "$o"
    case $o in infra_error) echo run_status=infra_error ;; evaluator_error) echo run_status=evaluator_error ;; *) echo run_status=ok ;; esac
    case $o in pass) echo case_pass=1 ;; fail) echo case_pass=0 ;; *) echo case_pass=na ;; esac
    printf '%s\n' "$@"
  } > "$d/$c/$u/eval/result.kv"
}
agg() { bash "$EV/aggregate.sh" "$1" >/dev/null; }
sk() { sed -n "s/^$2=//p" "$1/summary.kv" | head -n 1; }

# 1. Todo correcto
D="$TESTS_TMP/all-pass"
for i in 1 2 3; do rk "$D" "u$i" e2 pass false_pass=0 required_expected=3 required_executed=3 evidence_consistent=1 risk_ok=1 structured_report=valid duration_s=10 cost_usd=0.5 model=m1; done
agg "$D"
assert_eq "$(sk "$D" success_rate)/$(sk "$D" false_pass_rate)/$(sk "$D" risk_classification_accuracy)" "1.000/0.000/1.000" "todo correcto: tasas"
assert_eq "$(sk "$D" required_checks_coverage)/$(sk "$D" structured_report_valid)" "1.000/1.000" "todo correcto: cobertura y bloques válidos"
assert_eq "$(sk "$D" cost_usd_total)/$(sk "$D" duration_s_mean)" "1.5000/10.0" "todo correcto: coste y duración"
assert_eq "$(sk "$D" models_observed)" m1 "modelo observado registrado"

# 2. Fallos confirmados
D="$TESTS_TMP/fails"
rk "$D" u1 e2 pass false_pass=0 risk_ok=1
rk "$D" u2 e2 fail false_pass=1 risk_ok=0 checks_failed=false_pass
rk "$D" u3 e9 fail false_pass=0 risk_ok=0 checks_failed=risk_classification
rk "$D" u4 e9 pass risk_ok=1
agg "$D"
assert_eq "$(sk "$D" success_rate)/$(sk "$D" false_pass_rate)" "0.500/0.250" "fallos: success 2/4 y falso PASS 1/4"
assert_eq "$(sk "$D" risk_classification_accuracy)/$(sk "$D" risk_classification_n)" "0.500/4" "fallos: precisión de riesgo 2/4"
assert_eq "$(sk "$D" case.e9.risk_misclassified)" 1 "fallos: riesgo mal clasificado por caso"

# 3. Errores de infraestructura y del evaluador: fuera de las tasas, contados aparte
D="$TESTS_TMP/errors"
rk "$D" u1 e2 pass false_pass=0
rk "$D" u2 e2 fail false_pass=1
rk "$D" u3 e2 infra_error
rk "$D" u4 e2 evaluator_error
rk "$D" u5 e2 evaluator_error
agg "$D"
assert_eq "$(sk "$D" runs_total)/$(sk "$D" runs_ok)/$(sk "$D" runs_infra_error)/$(sk "$D" evaluator_errors)" "5/2/1/2" "errores: separados de las ejecuciones válidas"
assert_eq "$(sk "$D" success_rate)/$(sk "$D" false_pass_rate)" "0.500/0.500" "errores: no alteran las tasas del agente"
assert_match "$(cat "$D/summary.md")" 'evaluator_errors \| 2' "errores del evaluador visibles en el resumen"

# 4. Resultados inconclusos: válidos, pero fuera del denominador de success_rate
D="$TESTS_TMP/inconc"
rk "$D" u1 e2 pass inconclusive_checks=0
rk "$D" u2 e2 inconclusive inconclusive_checks=2
rk "$D" u3 e2 fail inconclusive_checks=1 suspected_checks=1 needs_review=1
agg "$D"
assert_eq "$(sk "$D" runs_ok)/$(sk "$D" runs_decided)/$(sk "$D" runs_inconclusive)" "3/2/1" "inconclusos: válidos pero no decididos"
assert_eq "$(sk "$D" success_rate)" "0.500" "inconclusos: success_rate sobre decididas (1/2)"
assert_eq "$(sk "$D" inconclusive_checks)/$(sk "$D" suspected_checks)/$(sk "$D" runs_needs_review)" "3/1/1" "inconclusos: checks inconclusos y sospechas sumados"

# 5. Duplicados: la misma ejecución (run_uid) cuenta una sola vez
D="$TESTS_TMP/dups"
rk "$D" u1 e2 pass; rk "$D" u2 e2 fail
mkdir -p "$D/copia"; cp "$D/e2/u1/eval/result.kv" "$D/copia/result.kv"
agg "$D"
assert_eq "$(sk "$D" runs_total)/$(sk "$D" runs_duplicate_ignored)" "2/1" "duplicados: ignorados y contados"
assert_eq "$(sk "$D" success_rate)" "0.500" "duplicados: no inflan las tasas"

# 6. result.kv antiguo (sin outcome): se deriva de case_pass/run_status
D="$TESTS_TMP/legacy"; mkdir -p "$D/a" "$D/b"
printf 'case_id=e1\nrun_status=ok\ncase_pass=1\n' > "$D/a/result.kv"; printf 'case_id=e1\nrun_status=infra_error\ncase_pass=na\n' > "$D/b/result.kv"
agg "$D"
assert_eq "$(sk "$D" runs_passed)/$(sk "$D" runs_infra_error)" "1/1" "formato anterior: compatible"

# 7. Comparación con distinto número de ejecuciones y condiciones distintas
A="$TESTS_TMP/cmpA"; B="$TESTS_TMP/cmpB"
for i in 1 2 3 4 5; do rk "$A" "a$i" o1 pass false_pass=0; done
rk "$B" b1 o1 pass false_pass=0; rk "$B" b2 o1 fail false_pass=1
printf 'arm=with-plugin\nmodel=m1\nruns_per_case=5\ncases=o1\nclaude_version=1\n' > "$A/run.kv"
printf 'arm=without-plugin\nmodel=m2\nruns_per_case=2\ncases=o1\nclaude_version=1\n' > "$B/run.kv"
agg "$A"; agg "$B"
CMP=$(bash "$EV/compare.sh" "$A" "$B")
assert_match "$CMP" 'Condiciones distintas:.*model.*runs_per_case' "comparación: avisa de modelo y ejecuciones distintas"
assert_match "$CMP" 'Distinto número de ejecuciones válidas' "comparación: avisa de muestras desiguales"
assert_match "$CMP" '\| success_rate \| 1.000 \| 0.500 \| -0.500 \|' "comparación: delta de success_rate"
assert_match "$CMP" '\| arm \| with-plugin \| without-plugin \|' "comparación: identifica los brazos"
assert_match "$CMP" 'no son concluyentes' "comparación: advierte sobre muestras pequeñas"
printf 'arm=with-plugin\nmodel=m1\nruns_per_case=5\ncases=o1\nclaude_version=1\n' > "$B/run.kv"; agg "$B"
for i in 3 4 5; do rk "$B" "b$i" o1 pass; done; agg "$B"
assert_nomatch "$(bash "$EV/compare.sh" "$A" "$B")" 'Condiciones distintas' "comparación: sin aviso si las condiciones coinciden"
bash "$EV/compare.sh" "$A" "$TESTS_TMP/no-existe" >/dev/null 2>&1; assert_eq "$?" 64 "comparación: falta summary.kv → uso (64)"

# 8. Directorio vacío
D="$TESTS_TMP/empty"; mkdir -p "$D"; agg "$D"
assert_eq "$(sk "$D" success_rate)/$(sk "$D" runs_total)" "na/0" "sin resultados: tasas na, no 0"

finish
