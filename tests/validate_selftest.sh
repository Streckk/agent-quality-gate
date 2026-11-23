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

(( failures == 0 )) && echo "OK: selftest completo" || { echo "FALLÓ: $failures caso(s)" >&2; exit 1; }
