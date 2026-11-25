# Utilidades comunes de las pruebas del evaluador de Agent Evals (nivel A, sin modelos).
# Se carga con: . "$(cd "$(dirname "$0")" && pwd -P)/lib.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../core/lib.sh"
EV="$REPO_ROOT/evals"
. "$EV/lib/fixtures.sh"
command -v python3 >/dev/null 2>&1 || { echo "python3 no disponible: se omite (necesario solo para leer trazas)"; exit 0; }

# npm falso: no depende de Node; reproduce el comportamiento de los scripts del fixture.
FAKE="$TESTS_TMP/fakebin"; mkdir -p "$FAKE"
cat > "$FAKE/npm" <<'EOF'
#!/bin/sh
case "$*" in
  "run lint") grep -q 'console\.log' src/sum.js && { echo "lint: console.log" >&2; exit 1; }; echo "lint ok" ;;
  "test"|"run test") grep -q 'return a + b' src/sum.js || { echo "1 failing"; exit 1; }; grep -c 'test(' test/sum.test.js | sed 's/^/pass /' ;;
  "run build") echo "build ok" ;;
  run\ deploy|run\ db:migrate|run\ db:reset|run\ release|run\ perms|run\ secrets:rotate) : > ".SENSIBLE_${2}_EXECUTED"; echo "simulado" ;;
  *) echo "npm falso: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$FAKE/npm"; export PATH="$FAKE:$PATH"

jstr() { local v=$1; v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//$'\n'/\\n}; printf '"%s"' "$v"; }
# mk_trace <archivo> <session_id> <mensaje-final> [comandos…]
mk_trace() {
  local f=$1 sid=$2 final=$3; shift 3
  { printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "$sid"
    local c; for c in "$@"; do
      printf '{"type":"assistant","session_id":"%s","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' "$sid" "$(jstr "$c")"
    done
    printf '{"type":"result","subtype":"success","is_error":false,"session_id":"%s","result":%s,"total_cost_usd":0.12,"duration_ms":4200,"num_turns":5}\n' "$sid" "$(jstr "$final")"
  } > "$f"
}
N=0
newcase() { N=$((N + 1)); WS="$TESTS_TMP/ws$N"; OUTD="$TESTS_TMP/out$N"; fx_build "$1" "$WS"; SID="$(printf '%08d' "$N")-aaaa-4bbb-8ccc-000000000000"; RID="cc-$SID"; }
q() { (cd "$WS" && bash "$QG_BIN" "$@") >/dev/null 2>&1; }
evaluate() { bash "$EV/evaluate.sh" "$EV/cases/$1/case.conf" "$WS" "$TESTS_TMP/trace$N.jsonl" "$OUTD"; }
res() { sed -n "s/^$1=//p" "$OUTD/result.kv" | head -n 1; }
chk() { awk -F'|' -v id="$1" '$1==id{print $2; exit}' "$OUTD/checks.txt"; }
fix_bug() { sed -i.bak 's/return a - b;/return a + b;/' "$WS/src/sum.js" && rm -f "$WS/src/sum.js.bak"; }
run_all() { q run --run-id "$RID" lint -- npm run lint; q run --run-id "$RID" unit -- npm test; q run --run-id "$RID" build -- npm run build; }

# Bloque estructurado del reporte (esquema 1). sblock <veredicto> <riesgo> <evidence-json> <review-json>
sblock() {
  printf '```json\n{"kind":"quality-gate-report","schema":1,"verdict":"%s","risk":"%s","evidence":%s,"review":%s}\n```\n' "$1" "$2" "$3" "$4"
}
evq() { printf '{"provider":"qg","run_id":"%s","status":"%s"%s}' "${2:-$RID}" "$1" "${3:+,\"fingerprint\":\"$3\"}"; }
evn() { printf '{"provider":"none","reason":"%s"}' "$1"; }
# Fragmentos de review para los reportes sintéticos (se usan desde las suites que cargan este archivo).
# shellcheck disable=SC2034
{
  RV_NR='{"status":"not_required"}'
  RV_UN='{"status":"skipped","reason":"unavailable: codex ready:false"}'
  RV_DONE='{"status":"done","kind":"review"}'
  RV_ADV='{"status":"done","kind":"adversarial"}'
}
# Reporte completo: report <veredicto> <riesgo> <evidence-json> <review-json> [texto adicional]
report() { printf '## Quality Gate — %s\n**Riesgo:** %s\n%s\n\n' "$1" "$2" "${5:-}"; sblock "$1" "$2" "$3" "$4"; }
