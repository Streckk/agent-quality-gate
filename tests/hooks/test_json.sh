#!/usr/bin/env bash
# Parser JSON de los hooks (hooks/lib/json.awk): estricto, decodifica, no ejecuta nada.
. "$(dirname "$0")/lib.sh"

AWKS="awk"
# Variantes locales para aproximar otros awk (macOS usa BWK awk; lo cubre la CI).
command -v gawk >/dev/null 2>&1 && AWKS="$AWKS gawk-posix gawk-traditional"
command -v mawk >/dev/null 2>&1 && AWKS="$AWKS mawk"
command -v busybox >/dev/null 2>&1 && AWKS="$AWKS busybox"

O="$TESTS_TMP/json"; mkdir -p "$O"
parse() {   # parse <awk> <json> <want>
  rm -f "$O"/*
  case $1 in
    gawk-posix) printf '%s' "$2" | LC_ALL=C gawk --posix -v outdir="$O" -v want="$3" -f "$HOOKS_DIR/lib/json.awk" 2>/dev/null ;;
    gawk-traditional) printf '%s' "$2" | LC_ALL=C gawk --traditional -v outdir="$O" -v want="$3" -f "$HOOKS_DIR/lib/json.awk" 2>/dev/null ;;
    busybox) printf '%s' "$2" | LC_ALL=C busybox awk -v outdir="$O" -v want="$3" -f "$HOOKS_DIR/lib/json.awk" 2>/dev/null ;;
    *) printf '%s' "$2" | LC_ALL=C "$1" -v outdir="$O" -v want="$3" -f "$HOOKS_DIR/lib/json.awk" 2>/dev/null ;;
  esac
}
val() { cat "$O/$1" 2>/dev/null; }
typ() { cat "$O/$1.type" 2>/dev/null; }
hexof() { od -An -tx1 "$O/$1" | tr -d ' \n'; }

for A in $AWKS; do
  parse "$A" '{"session_id":"abc-1","stop_hook_active":true,"n":-1.5e3,"z":null,"o":{"a":[1,{"b":"x"}]}}' "session_id,stop_hook_active,n,z,o"
  assert_eq "$?" 0 "[$A] objeto válido"
  assert_eq "$(val session_id)" "abc-1" "[$A] cadena simple"
  assert_eq "$(typ stop_hook_active)/$(val stop_hook_active)" "true/true" "[$A] booleano"
  assert_eq "$(typ n)/$(val n)" "number/-1.5e3" "[$A] número"
  assert_eq "$(typ z)" "null" "[$A] null"
  assert_eq "$(typ o)" "object" "[$A] objeto anidado identificado"

  parse "$A" '{"tool_input":{"command":"git commit -m \"a\nb\"\t\\ \/\u00e9\ud83d\ude00"}}' "tool_input.command"
  assert_eq "$?" 0 "[$A] escapes válidos"
  assert_eq "$(hexof tool_input_command)" "67697420636f6d6d6974202d6d2022610a6222095c202fc3a9f09f9880" "[$A] decodificación exacta (\\n \\t \\\\ \\/ é 😀)"

  parse "$A" '{"a":"\ud83d"}' a; assert_eq "$(hexof a)" "efbfbd" "[$A] sustituto aislado → U+FFFD"
  parse "$A" '{"a":"x","a":"y"}' a; assert_eq "$(val a)" "y" "[$A] clave duplicada: gana la última"
  parse "$A" '{"k.x":"no","k":{"x":"si"}}' "k.x"; assert_match "$(val k_x)" '^(si|no)$' "[$A] rutas con punto no rompen el parser"
  parse "$A" '  {"a" : "b" }  ' a; assert_eq "$(val a)" "b" "[$A] espacios alrededor"

  for bad in '{"a":1} x' '{"a":"\u0000"}' '{"a":"x' '[1]' '{"a":01}' '{"a":"tab	raw"}' '' '{"a":tru}' '{"a" "b"}' '{"a":1,}' '{"a":"\q"}' '{"a":"\u12"}' 'null' '{"a":[1,2}'; do
    parse "$A" "$bad" a; rc=$?
    assert_eq "$rc" 2 "[$A] rechaza: $(printf '%s' "$bad" | tr '\t' 'T' | head -c 24)"
  done
  # Anidamiento excesivo
  deep=$(printf '{"a":%.0s' $(seq 1 70)); deep="$deep 1$(printf '}%.0s' $(seq 1 70))"
  parse "$A" "$deep" a; assert_eq "$?" 2 "[$A] anidamiento > 64 rechazado"
  # Contenido que parece código no se ejecuta
  parse "$A" '{"a":"$(touch '"$TESTS_TMP"'/pwned) `touch '"$TESTS_TMP"'/pwned2`"}' a
  assert_file_absent "$TESTS_TMP/pwned" "[$A] el contenido no se ejecuta"
done

# Entrada grande (≈ 300 KB en last_assistant_message): se procesa en tiempo razonable
big=$(head -c 300000 /dev/zero | tr '\0' 'x')
start=$(date +%s)
parse awk "{\"session_id\":\"s\",\"last_assistant_message\":\"$big\"}" session_id
assert_eq "$(val session_id)" "s" "entrada de 300 KB: campo extraído"
el=$(( $(date +%s) - start )); if [ "$el" -le 10 ]; then ok "entrada de 300 KB: ${el}s"; else ko "entrada de 300 KB: ${el}s (lento)"; fi

finish
