#!/usr/bin/env bash
# Fixtures sintéticos para probar los hooks con Claude Code real. NO son proyectos reales.
set -euo pipefail
BASE="${1:?dir base}"; shift
mk() {   # mk <nombre>: repo Node mínimo, limpio, con tests que pasan
  local d="$BASE/$1"; mkdir -p "$d/src" "$d/test"
  git -C "$d" init -q -b main
  cat > "$d/package.json" <<'J'
{ "name": "fixture-sum", "private": true, "scripts": { "test": "node --test" } }
J
  printf '// Suma dos números.\nfunction sum(a, b) {\n  return a + b;\n}\nmodule.exports = { sum };\n' > "$d/src/sum.js"
  printf 'const test = require("node:test");\nconst assert = require("node:assert");\nconst { sum } = require("../src/sum.js");\ntest("suma", () => assert.strictEqual(sum(2, 3), 5));\n' > "$d/test/sum.test.js"
  printf '# Fixture\n- Pruebas: `npm test`.\n' > "$d/CLAUDE.md"
  git -C "$d" add -A && git -C "$d" commit -q -m base
}
rm -rf "$BASE"; mkdir -p "$BASE"
for n in "$@"; do mk "$n"; done
# remoto local (bare) para probar push sin red
git init -q --bare "$BASE/remote.git"
for n in "$@"; do git -C "$BASE/$n" remote add origin "$BASE/remote.git"; done
echo "fixtures: $*"
