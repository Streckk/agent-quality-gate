#!/usr/bin/env bash
# Ejecuta las pruebas deterministas de los hooks (entradas JSON simuladas, repos temporales).
# QG_BASH=/ruta/a/bash permite probar con otro intérprete (p. ej. /bin/bash 3.2 en macOS).
here=$(cd "$(dirname "$0")" && pwd -P)
failed=0
printf 'bash para hooks: %s\n' "$("${QG_BASH:-bash}" -c 'echo "$BASH_VERSION"')"
printf 'awk: %s\n' "$( (awk --version 2>/dev/null || awk -W version 2>/dev/null || echo 'awk (versión no disponible)') | head -n 1)"
for t in "$here"/hooks/test_*.sh; do
  printf '\n== %s\n' "$(basename "$t")"
  if ! "${QG_BASH:-bash}" "$t"; then failed=$((failed + 1)); fi
done
printf '\n'
if [ "$failed" -gt 0 ]; then echo "FALLÓ: $failed suite(s)"; exit 1; fi
echo "OK: todas las suites de hooks"
