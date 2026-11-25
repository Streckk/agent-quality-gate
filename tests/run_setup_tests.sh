#!/usr/bin/env bash
# Pruebas deterministas de /quality-gate setup (bin/qg-setup). Sin modelos; apto para CI.
here=$(cd "$(dirname "$0")" && pwd -P)
failed=0
for t in "$here"/setup/test_*.sh; do
  printf '\n== %s\n' "$(basename "$t")"
  "${QG_BASH:-bash}" "$t" || failed=$((failed + 1))
done
printf '\n'
if [ "$failed" -gt 0 ]; then echo "FALLÓ: $failed suite(s)"; exit 1; fi
echo "OK: todas las suites de setup"
