#!/usr/bin/env bash
# Comprueba que validate.sh falla ante errores conocidos (evita un validador que siempre pasa).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
failures=0

copy_repo() { rm -rf "$tmp/r"; mkdir -p "$tmp/r"; (cd "$REPO" && tar --exclude=.git -cf - .) | (cd "$tmp/r" && tar -xf -); }

expect_fail() {
  local label="$1"
  if bash "$HERE/validate.sh" "$tmp/r" >/dev/null 2>&1; then
    echo "ERROR: el validador no detectó: $label" >&2; failures=$((failures + 1))
  else
    echo "ok: detecta $label"
  fi
}

copy_repo
bash "$HERE/validate.sh" "$tmp/r" >/dev/null 2>&1 || { echo "ERROR: la copia limpia no valida" >&2; exit 1; }
echo "ok: copia limpia valida"

copy_repo; sed -i 's/^name: quality-gate$/name: otra-cosa/' "$tmp/r/skills/quality-gate/SKILL.md"
expect_fail "name distinto del directorio"

copy_repo; sed -i '/^description:/d' "$tmp/r/skills/quality-gate/SKILL.md"
expect_fail "description ausente"

copy_repo; echo '[roto](references/no-existe.md)' >> "$tmp/r/skills/quality-gate/SKILL.md"
expect_fail "enlace interno roto"

copy_repo; rm "$tmp/r/skills/quality-gate/references/guardrails.md"
expect_fail "referencia obligatoria ausente"

copy_repo; printf '\nCo-Authored-By: Bot <x@y>\n' >> "$tmp/r/CHANGELOG.md"
expect_fail "trailer de coautoría"

# Regresión: antes se ignoraba cualquier línea de un README.md o guardrails.md
copy_repo; printf '\nCo-Authored-By: Bot <x@y>\n' >> "$tmp/r/README.md"
expect_fail "trailer de coautoría en README (hueco anterior)"

copy_repo; printf '\nCo-Authored-By: Bot <x@y>\n' >> "$tmp/r/examples/README.md"
expect_fail "trailer de coautoría en examples/README"

# Regresión de política: defectos confirmados en la validación funcional
copy_repo; sed -i 's/NOT VERIFIED/SIN VERIFICAR/g' "$tmp/r/skills/quality-gate/references/report-format.md"
expect_fail "regla Discover-only (NOT VERIFIED) eliminada"

copy_repo; sed -i 's/nothing to review/sin cambios/g' "$tmp/r/skills/quality-gate/references/agent-evals.md"
expect_fail "regla de Codex con árbol limpio eliminada"

copy_repo; echo 'Compruébalo con `git stash` si quieres.' >> "$tmp/r/skills/quality-gate/references/feedback-loops.md"
expect_fail "recomendación de git stash reintroducida"

# Evidencia ejecutable: sin eval y con bit de ejecución
copy_repo; printf '\nx=1; eval "y=$x"\n' >> "$tmp/r/bin/qg"
expect_fail "eval introducido en bin/qg"

copy_repo; chmod -x "$tmp/r/bin/qg"
expect_fail "bin/qg sin bit de ejecución"

# Integración con qg: no se pueden perder sus garantías documentales
copy_repo; sed -i 's/no equivale a `PASS`/equivale a PASS/' "$tmp/r/skills/quality-gate/references/evidence-qg.md"
expect_fail "regla 'valid no equivale a PASS' eliminada"

# Plugin y hooks
copy_repo; sed -i 's/"author"/"license": "MIT", "author"/' "$tmp/r/.claude-plugin/plugin.json"
expect_fail "licencia declarada sin decisión del propietario"

copy_repo; sed -i 's|\\"\${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh\\"|${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh|' "$tmp/r/hooks/hooks.json"
sed -i 's|\\"\${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\\"|${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh|; s|\\"\${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh\\"|${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh|' "$tmp/r/hooks/hooks.json"
expect_fail "rutas de hooks sin comillas"

copy_repo; printf '\nx=1; eval "y=$x"\n' >> "$tmp/r/hooks/stop.sh"
expect_fail "eval introducido en un hook"

copy_repo; chmod -x "$tmp/r/hooks/stop.sh"
expect_fail "hook sin bit de ejecución"

(( failures == 0 )) && echo "OK: selftest completo" || { echo "FALLÓ: $failures caso(s)" >&2; exit 1; }
