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
         skills/quality-gate/references/report-format.md; do
  [[ -f "$ROOT/$f" ]] && ok "existe $f" || fail "falta $f"
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
