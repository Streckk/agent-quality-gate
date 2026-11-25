#!/usr/bin/env bash
# Nivel B: ejecuta casos de Agent Evals con Claude Code real y los evalúa de forma determinista.
# CONSUME CUOTA. Nunca se ejecuta en CI. Los casos con la etiqueta `opt-in` (p. ej. Codex) solo
# corren si se piden explícitamente con --tag.
#
# uso: evals/run.sh [--case <id>]… [--tag <tag>] [--runs N] [--model M] [--max-cost-usd X] [--out DIR] [--dry-run]
# --model fija el modelo de todas las ejecuciones (recomendado para comparar); se registra en run.kv.
# Cada ejecución: fixture limpio en un directorio temporal, `claude -p --plugin-dir <repo>
# --session-id <uuid>` (sin instalar el plugin ni tocar settings) y evaluate.sh sobre la evidencia.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P); REPO=$(cd "$HERE/.." && pwd -P)
. "$HERE/lib/fixtures.sh"
CASES=(); TAG=""; RUNS=1; MAXCOST=""; OUT=""; DRY=0; MODEL=""
while [ $# -gt 0 ]; do
  case $1 in
    --case) CASES+=("$2"); shift 2 ;;
    --tag) TAG=$2; shift 2 ;;
    --runs) RUNS=$2; shift 2 ;;
    --model) MODEL=$2; shift 2 ;;
    --max-cost-usd) MAXCOST=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "argumento desconocido: $1" >&2; exit 64 ;;
  esac
done
[[ $RUNS =~ ^[1-9][0-9]?$ ]] || { echo "--runs debe ser 1..99" >&2; exit 64; }
command -v claude >/dev/null || { echo "claude no está en el PATH" >&2; exit 65; }
command -v python3 >/dev/null || { echo "python3 es necesario para leer las trazas" >&2; exit 65; }

conf() { local l v=""; while IFS= read -r l || [ -n "$l" ]; do case $l in "$2="*) v=${l#*=} ;; esac; done < "$1/case.conf"; printf '%s' "${v:-${3:-}}"; }
sel=()
for d in "$HERE"/cases/*/; do
  d=${d%/}; id=$(conf "$d" id "$(basename "$d")"); tags=",$(conf "$d" tags),"
  if [ ${#CASES[@]} -gt 0 ]; then
    m=0; for c in "${CASES[@]}"; do [ "$c" = "$id" ] && m=1; done; [ $m = 1 ] || continue
  elif [ -n "$TAG" ]; then case $tags in *",$TAG,"*) ;; *) continue ;; esac
  else case $tags in *",level-b,"*) ;; *) continue ;; esac; fi
  # Los casos opt-in (consumen Codex u otros recursos) solo corren si se piden por id o por su etiqueta.
  case $tags in *",opt-in,"*)
    explicit=0
    [ ${#CASES[@]} -gt 0 ] && explicit=1
    if [ -n "$TAG" ] && [ "$TAG" != level-b ]; then case $tags in *",$TAG,"*) explicit=1 ;; esac; fi
    [ $explicit = 1 ] || continue ;;
  esac
  sel+=("$d")
done
[ ${#sel[@]} -gt 0 ] || { echo "ningún caso seleccionado" >&2; exit 64; }
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT=${OUT:-$HERE/runs/$TS}
mkdir -p "$OUT"
commit=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null); dirty=$( [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] && echo "+cambios-locales")
{
  echo "repo_commit=$commit$dirty"
  echo "qg_version=$(bash "$REPO/bin/qg" version 2>/dev/null)"
  echo "claude_version=$(claude --version 2>/dev/null | head -n 1)"
  echo "started_at=$TS"
  echo "runs_per_case=$RUNS"
  echo "cases=$(for d in "${sel[@]}"; do printf '%s ' "$(conf "$d" id)"; done)"
  echo "arm=with-plugin (--plugin-dir)"
  echo "model=${MODEL:-default}"
  echo "max_cost_usd=${MAXCOST:-none}"
} > "$OUT/run.kv"
echo "casos: $(sed -n 's/^cases=//p' "$OUT/run.kv")· ejecuciones por caso: $RUNS · salida: $OUT"
[ $DRY = 1 ] && { echo "(dry-run: no se lanza Claude)"; exit 0; }

uuid() { if [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid; elif command -v uuidgen >/dev/null; then uuidgen | tr 'A-Z' 'a-z'; else python3 -c 'import uuid;print(uuid.uuid4())'; fi; }
spent=0
for d in "${sel[@]}"; do
  id=$(conf "$d" id); fixture=$(conf "$d" fixture); envs=$(conf "$d" env)
  for n in $(seq 1 "$RUNS"); do
    if [ -n "$MAXCOST" ] && awk -v s="$spent" -v m="$MAXCOST" 'BEGIN{exit !(s>=m)}'; then echo "límite de coste alcanzado ($spent USD): se detiene" >&2; break 2; fi
    R="$OUT/$id/run-$n"; WS="$R/ws"; mkdir -p "$R"
    fx_build "$fixture" "$WS" >/dev/null || { echo "fixture $fixture falló" >&2; continue; }
    SID=$(uuid); start=$(date +%s)
    PATHX=$PATH
    if [ "$(conf "$d" path_mode full)" = nocodex ]; then
      PATHX=$(printf '%s' "$PATH" | tr ':' '\n' | while read -r p; do [ -x "$p/codex" ] || printf '%s:' "$p"; done); PATHX=${PATHX%:}
    fi
    ( cd "$WS" && env PATH="$PATHX" $envs claude -p "$(cat "$d/task.md")" --plugin-dir "$REPO" --session-id "$SID" ${MODEL:+--model "$MODEL"} \
        --output-format stream-json --verbose --max-turns "$(conf "$d" max_turns 60)" \
        --permission-mode acceptEdits --allowedTools "Bash Read Edit Write Glob Grep Skill" \
        > "$R/trace.jsonl" 2> "$R/claude.stderr" )
    rc=$?
    printf 'case=%s\nrun=%s\nsession_id=%s\nclaude_rc=%s\nwall_s=%s\n' "$id" "$n" "$SID" "$rc" "$(( $(date +%s) - start ))" > "$R/meta.kv"
    bash "$HERE/evaluate.sh" "$d/case.conf" "$WS" "$R/trace.jsonl" "$R/eval"
    # Si el evaluador ni siquiera dejó resultado, se registra como error del evaluador (no del agente).
    [ -s "$R/eval/result.kv" ] || { mkdir -p "$R/eval"; printf 'case_id=%s\nrun_uid=%s\nrun_status=evaluator_error\noutcome=evaluator_error\nevaluator_reason=evaluate.sh no produjo resultado\ncase_pass=na\n' "$id" "$SID" > "$R/eval/result.kv"; }
    c=$(sed -n 's/^cost_usd=//p' "$R/eval/result.kv"); [ -n "$c" ] && spent=$(awk -v s="$spent" -v c="$c" 'BEGIN{printf "%.4f", s+c}')
    printf '%-22s run %s  outcome=%s  verdict=%s  qg=%s  fallidos=[%s]  coste=%s\n' "$id" "$n" \
      "$(sed -n 's/^outcome=//p' "$R/eval/result.kv")" "$(sed -n 's/^verdict=//p' "$R/eval/result.kv")" \
      "$(sed -n 's/^qg_status=//p' "$R/eval/result.kv")" "$(sed -n 's/^checks_failed=//p' "$R/eval/result.kv")" "${c:-?}"
  done
done
bash "$HERE/aggregate.sh" "$OUT"
