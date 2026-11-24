#!/usr/bin/env bash
# Valida estructura, frontmatter, enlaces internos y convenciones de las skills.
# Sin dependencias más allá de bash + coreutils + grep/sed/awk.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
ok()   { echo "ok: $*"; }

# 1. Archivos obligatorios
for f in README.md CHANGELOG.md \
         skills/quality-gate/SKILL.md \
         skills/quality-gate/references/feedback-loops.md \
         skills/quality-gate/references/agent-evals.md \
         skills/quality-gate/references/guardrails.md \
         skills/quality-gate/references/project-discovery.md \
         skills/quality-gate/references/report-format.md \
         skills/quality-gate/references/evidence-qg.md \
         bin/qg bin/qg-run docs/evidencia.md tests/run_core_tests.sh \
         .claude-plugin/plugin.json hooks/hooks.json hooks/session-start.sh hooks/stop.sh \
         hooks/pre-tool-use.sh hooks/lib/common.sh hooks/lib/json.awk tests/run_hook_tests.sh \
         docs/hooks.md docs/agent-evals.md evals/README.md evals/evaluate.sh evals/run.sh \
         evals/aggregate.sh evals/compare.sh evals/lib/fixtures.sh evals/lib/trace.py tests/run_eval_tests.sh; do
  [[ -f "$ROOT/$f" ]] && ok "existe $f" || fail "falta $f"
done

# 1b. Ejecutables de evidencia: sintaxis bash y bit de ejecución
for f in bin/qg bin/qg-run; do
  [[ -f "$ROOT/$f" ]] || continue
  bash -n "$ROOT/$f" 2>/dev/null && ok "sintaxis $f" || fail "$f: error de sintaxis bash"
  [[ -x "$ROOT/$f" ]] && ok "ejecutable $f" || fail "$f: sin bit de ejecución"
done
# Agent Evals: cada caso tiene case.conf (con id y criterios) y task.md; scripts con sintaxis válida
for d in "$ROOT"/evals/cases/*/; do
  [ -d "$d" ] || continue
  c=${d%/}; c=${c##*/}
  [[ -f "$d/case.conf" && -f "$d/task.md" ]] || { fail "evals/cases/$c: falta case.conf o task.md"; continue; }
  grep -q "^id=$c$" "$d/case.conf" || fail "evals/cases/$c: id distinto del directorio"
  grep -qE '^expect_(verdicts|required|qg_status|codex|report_regex|stop_blocks_max)=' "$d/case.conf" || fail "evals/cases/$c: sin criterios de éxito"
done
for f in evals/evaluate.sh evals/run.sh evals/aggregate.sh evals/compare.sh evals/lib/fixtures.sh; do
  [[ -f "$ROOT/$f" ]] && { bash -n "$ROOT/$f" 2>/dev/null || fail "$f: error de sintaxis bash"; }
done
grep -qx 'runs/' "$ROOT/evals/.gitignore" 2>/dev/null && ok "evals: resultados crudos fuera de git" || fail "evals/.gitignore debe excluir runs/"

# Hooks: sintaxis y bit de ejecución
for f in hooks/session-start.sh hooks/stop.sh hooks/pre-tool-use.sh; do
  [[ -f "$ROOT/$f" ]] || continue
  bash -n "$ROOT/$f" 2>/dev/null && ok "sintaxis $f" || fail "$f: error de sintaxis bash"
  [[ -x "$ROOT/$f" ]] && ok "ejecutable $f" || fail "$f: sin bit de ejecución"
done
# Manifiesto y hooks.json: estructura mínima sin dependencias (el validador oficial se usa aparte)
if [[ -f "$ROOT/.claude-plugin/plugin.json" ]]; then
  grep -q '"name"[[:space:]]*:[[:space:]]*"agent-quality-gate"' "$ROOT/.claude-plugin/plugin.json" && ok "plugin.json: name" || fail "plugin.json: falta name=agent-quality-gate"
  grep -qi '"license"' "$ROOT/.claude-plugin/plugin.json" && fail "plugin.json: no declarar licencia sin decisión del propietario"
fi
if [[ -f "$ROOT/hooks/hooks.json" ]]; then
  grep -q '"hooks"[[:space:]]*:' "$ROOT/hooks/hooks.json" && ok "hooks.json: envoltorio hooks" || fail "hooks.json: falta el envoltorio \"hooks\""
  grep -q '\${CLAUDE_PLUGIN_ROOT}/hooks/[a-z-]*\.sh\\"' "$ROOT/hooks/hooks.json" && ok "hooks.json: rutas entrecomilladas" || fail "hooks.json: \${CLAUDE_PLUGIN_ROOT} sin comillas"
fi

# Sin eval en los ejecutables (requisito de seguridad del ejecutor y de los hooks).
for f in bin/qg bin/qg-run hooks/session-start.sh hooks/stop.sh hooks/pre-tool-use.sh hooks/lib/common.sh; do
  if [[ -f "$ROOT/$f" ]] && grep -vE '^[[:space:]]*#' "$ROOT/$f" | grep -qE '(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)'; then
    fail "$f: usa eval"
  else
    ok "$f: sin eval"
  fi
done

# 2. Frontmatter de cada SKILL.md
while IFS= read -r skill; do
  dir_name="$(basename "$(dirname "$skill")")"
  rel="${skill#"$ROOT"/}"
  if [[ "$(head -n1 "$skill")" != "---" ]]; then
    fail "$rel: debe empezar con frontmatter '---'"; continue
  fi
  fm="$(awk 'NR==1{next} /^---$/{exit} {print}' "$skill")"
  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -n1)"
  [[ -n "$name" ]] || fail "$rel: falta 'name' en frontmatter"
  [[ "$name" == "$dir_name" ]] || fail "$rel: name '$name' no coincide con el directorio '$dir_name'"
  [[ "$name" =~ ^[a-z0-9-]{1,64}$ ]] || fail "$rel: name debe ser kebab-case en minúsculas (<=64)"
  [[ -n "$desc" ]] || fail "$rel: falta 'description' en frontmatter"
  (( ${#desc} <= 1024 )) || fail "$rel: description supera 1024 caracteres"
  lines=$(wc -l < "$skill")
  (( lines <= 200 )) || fail "$rel: $lines líneas; mantener SKILL.md conciso (<=200) y mover detalle a references/"
  ok "frontmatter $rel (name=$name)"
done < <(find "$ROOT/skills" -name SKILL.md -type f)

# 3. Enlaces Markdown internos relativos
while IFS= read -r md; do
  rel="${md#"$ROOT"/}"
  # Extrae destinos de [texto](destino), ignorando bloques de código
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    case "$target" in http://*|https://*|mailto:*|\#*) continue ;; esac
    path="${target%%#*}"
    [[ -e "$(dirname "$md")/$path" ]] || fail "$rel: enlace roto -> $target"
  done < <(awk '/^```/{c=!c; next} !c' "$md" | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\((.*)\)$/\1/')
done < <(find "$ROOT" -name '*.md' -type f -not -path '*/.git/*')
ok "enlaces internos revisados"

# 4. Política de autoría: sin créditos de IA en el contenido del repo.
# Solo se permite *mencionar* un trailer dentro de código en línea (`Co-Authored-By`), p. ej. para documentar la política.
authorship_hits="$(
  find "$ROOT" -type f \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' \) -not -path '*/.git/*' -print0 \
  | while IFS= read -r -d '' f; do
      sed 's/`[^`]*`//g' "$f" \
      | grep -inE 'co-authored-by|generated[- ]by:? *claude|assisted[- ]by:? *claude' \
      | sed "s#^#${f#"$ROOT"/}:#"
    done
)"
if [[ -n "$authorship_hits" ]]; then
  printf '%s\n' "$authorship_hits" >&2
  fail "se encontraron créditos/trailers de IA en el contenido"
else
  ok "sin trailers de autoría de IA"
fi

# 6. Reglas de regresión de la política (defectos confirmados en la validación de v0.1.0)
REFS="$ROOT/skills/quality-gate/references"
require() { grep -qF -- "$2" "$REFS/$1" || fail "$1: falta regla de regresión: $2"; }
forbid()  { ! grep -qE -- "$2" "$REFS/$1" || fail "$1: contiene patrón prohibido: $2"; }
require report-format.md 'NOT VERIFIED'                 # Discover-only no debe salir como BLOCKED
require report-format.md 'no existe ninguna verificación aplicable'   # docs sin checks no es BLOCKED
require report-format.md 'Huella de evidencia'          # evidencia obsoleta
require report-format.md 'nunca** compensa'             # Codex positivo no tapa fallos
require agent-evals.md   'nothing to review'            # árbol limpio con exit 0 no es revisión hecha
require agent-evals.md   'servicio externo'             # privacidad del diff
require feedback-loops.md 'PIPESTATUS'                  # exit code real tras pipes
forbid  feedback-loops.md 'con `git stash`'             # no tocar el working tree del usuario
# Integración con qg (v0.2.0-dev)
require evidence-qg.md   'no equivale a `PASS`'          # qg status=valid no aprueba por sí solo
require evidence-qg.md   'qg reject'                    # exit 0 sin pruebas no cuenta como passed
require evidence-qg.md   '--run-id <ID>'                # aislamiento entre sesiones
require evidence-qg.md   'Modo sin `qg`'                # degradación a v0.1 sin simular evidencia
require report-format.md 'qg status --run-id'           # el reporte se basa en la evidencia de qg
require evidence-qg.md   'session id'                   # run-id compartido con los hooks (cc-<session_id>)
grep -qF 'references/evidence-qg.md' "$ROOT/skills/quality-gate/SKILL.md" || fail "SKILL.md no enlaza evidence-qg.md"
ok "reglas de regresión de la política"

# 5. Alcance de la v1: sin Rust ni motores propios
if find "$ROOT" -name 'Cargo.toml' -not -path '*/.git/*' -not -path '*/examples/*' | grep -q .; then
  fail "v1 no debe incluir crates Rust fuera de examples/"
else
  ok "sin código Rust fuera de examples/"
fi

if (( errors > 0 )); then
  echo "FALLÓ: $errors error(es)" >&2; exit 1
fi
echo "OK: validación completa"
