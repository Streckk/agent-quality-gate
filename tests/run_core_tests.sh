#!/usr/bin/env bash
# Ejecuta las pruebas deterministas de bin/qg. Uso: bash tests/run_core_tests.sh
# QG_BASH=/ruta/a/bash permite probar qg con otro intérprete (p. ej. /bin/bash 3.2 en macOS).
here=$(cd "$(dirname "$0")" && pwd -P)
failed=0
printf 'bash para qg: %s\n' "$("${QG_BASH:-bash}" -c 'echo "$BASH_VERSION"')"
printf 'git: %s\n' "$(git --version)"
for t in "$here"/core/test_*.sh; do
  printf '\n== %s\n' "$(basename "$t")"
  if ! "${QG_BASH:-bash}" "$t"; then failed=$((failed + 1)); fi
done
printf '\n'
if [ "$failed" -gt 0 ]; then echo "FALLÓ: $failed suite(s)"; exit 1; fi
echo "OK: todas las suites"
