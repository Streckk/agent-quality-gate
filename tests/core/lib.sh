# Utilidades comunes para las pruebas de bin/qg. Se carga con: . "$(dirname "$0")/lib.sh"
# Todas las pruebas usan repositorios temporales y una configuración de Git aislada.

CORE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$CORE_DIR/../.." && pwd -P)
QG_BIN="$REPO_ROOT/bin/qg"

# Aislar de la configuración del usuario (hooks, fsmonitor, plantillas, identidad).
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=qg-test GIT_AUTHOR_EMAIL=qg-test@example.invalid
export GIT_COMMITTER_NAME=qg-test GIT_COMMITTER_EMAIL=qg-test@example.invalid
unset QG_RUN_ID QG_TIMEOUT GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE

TESTS_TMP=$(mktemp -d "${TMPDIR:-/tmp}/qg-tests.XXXXXX")
T_PASS=0
T_FAIL=0
T_CLEANUP_PIDS=""
cleanup_tests() {
  local p
  for p in $T_CLEANUP_PIDS; do kill -KILL "$p" 2>/dev/null; done
  rm -rf "$TESTS_TMP"
}
trap cleanup_tests EXIT

qg() { "${QG_BASH:-bash}" "$QG_BIN" "$@"; }

new_repo() {
  local d
  d=$(mktemp -d "$TESTS_TMP/repo.XXXXXX")
  d=$(cd "$d" && pwd)   # normaliza la ruta lógica (en macOS TMPDIR termina en "/" y produce "//")
  git -C "$d" init -q -b main >/dev/null 2>&1 || { git -C "$d" init -q && git -C "$d" checkout -q -b main; }
  printf '%s' "$d"
}
commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }
fp() { qg -C "$1" fingerprint; }
fpj() { qg -C "$1" fingerprint --json; }
state_dir() {
  (cd "$1" && p=$(git rev-parse --git-path quality-gate) &&
   case $p in /*) printf '%s/v1' "$p" ;; *) printf '%s/%s/v1' "$PWD" "$p" ;; esac)
}
# Registro más reciente de un check.
last_record() {
  local d; d="$(state_dir "$1")/records/$2"
  ls -1 "$d" 2>/dev/null | grep '\.rec$' | LC_ALL=C sort -r | head -n 1 | sed "s#^#$d/#"
}
field() { sed -n "s/^$2=//p" "$1" | head -n 1; }

ok() { T_PASS=$((T_PASS + 1)); printf 'ok   %s\n' "$*"; }
ko() { T_FAIL=$((T_FAIL + 1)); printf 'FAIL %s\n' "$*"; }
assert_eq()    { if [ "$1" = "$2" ]; then ok "$3"; else ko "$3 (esperado '$2', obtenido '$1')"; fi; }
assert_ne()    { if [ "$1" != "$2" ]; then ok "$3"; else ko "$3 (no debía ser '$1')"; fi; }
assert_match() { if [[ $1 =~ $2 ]]; then ok "$3"; else ko "$3 ('$1' no casa con /$2/)"; fi; }
assert_nomatch() { if [[ $1 =~ $2 ]]; then ko "$3 ('$1' no debía casar con /$2/)"; else ok "$3"; fi; }
assert_file_absent() { if [ -e "$1" ]; then ko "$2 ($1 existe)"; else ok "$2"; fi; }

finish() {
  printf -- '-- %s: %d ok, %d fallos\n' "$(basename "$0")" "$T_PASS" "$T_FAIL"
  [ "$T_FAIL" -eq 0 ]
}
