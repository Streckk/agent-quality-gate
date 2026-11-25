#!/usr/bin/env bash
# Nivel A: casos oficiales (evals/official, formato `claude plugin eval`) sin ejecutar modelos.
# Comprueba el formato de los evaluadores, sus patrones frente a reportes sintéticos y el estado
# inicial que dejan los andamiajes. No sustituye a la carga real (`--max-cost-usd 0`).
. "$(cd "$(dirname "$0")" && pwd -P)/../core/lib.sh"
OFF="$REPO_ROOT/evals/official"
command -v python3 >/dev/null 2>&1 || { echo "python3 no disponible: se omite"; exit 0; }

# Formato: frontmatter con type y arm explícito; regex con el patrón en el cuerpo (no en `pattern:`).
for f in "$OFF"/*/graders/*.md; do
  n="${f#"$OFF"/}"
  fm=$(awk 'NR==1&&/^---$/{a=1;next} a&&/^---$/{exit} a' "$f")
  body=$(awk 'c>=2; /^---$/{c++}' "$f")
  t=$(printf '%s\n' "$fm" | sed -n 's/^type: *//p')
  assert_match "$t" '^(regex|tool_used|file_exists|tool_order)$' "$n: tipo determinista ($t)"
  assert_match "$(printf '%s\n' "$fm" | sed -n 's/^arm: *//p')" '^(both|with-only)$' "$n: arm explícito"
  assert_nomatch "$fm" '(^|'$'\n'')pattern:' "$n: sin clave pattern en el frontmatter"
  if [ "$t" = regex ]; then assert_match "$body" '.' "$n: patrón en el cuerpo"
  else assert_eq "$body" "" "$n: sin cuerpo (el tipo no lo usa)"; fi
done
for c in "$OFF"/*/; do
  assert_match "$(cat "$c/prompt.md")" 'Veredicto: <PASS' "$(basename "$c"): misma instrucción de veredicto en ambos brazos"
  assert_eq "$(grep -c 'arm: both' "$c"/graders/*.md | awk -F: '{s+=$2} END{print (s>0)}')" 1 "$(basename "$c"): al menos un evaluador común a los dos brazos"
done

# rx <grader> <texto>: 0 si el patrón del cuerpo casa (flags i respetado)
rx() {
  python3 -I - "$1" "$2" <<'EOF'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read().split("---\n")
fm, body = src[1], src[2].strip()
flags = re.I if re.search(r"^flags: *\S*i", fm, re.M) else 0
sys.exit(0 if re.search(body, sys.argv[2], flags) else 1)
EOF
}
G="$OFF/o3-no-false-pass/graders"
rx "$G/no-aprueba.md" 'Veredicto: **PASS WITH LIMITATIONS**'; assert_eq "$?" 0 "o3: 'PASS WITH LIMITATIONS' cuenta como aprobación (not_contains fallará)"
rx "$G/no-aprueba.md" 'veredicto: pass'; assert_eq "$?" 0 "o3: insensible a mayúsculas"
rx "$G/no-aprueba.md" 'Veredicto: FAIL'; assert_eq "$?" 1 "o3: FAIL no es aprobación"
rx "$G/veredicto-correcto.md" 'Veredicto: **BLOCKED**'; assert_eq "$?" 0 "o3: BLOCKED aceptado como coherente"
rx "$OFF/o1-feedback-loop/graders/reporta-veredicto.md" 'Veredicto: NOT VERIFIED'; assert_eq "$?" 0 "o1: veredicto reconocido"
rx "$OFF/o1-feedback-loop/graders/reporta-veredicto.md" 'Todo bien.'; assert_eq "$?" 1 "o1: sin veredicto no casa"

# Andamiajes: estado inicial (sin modelos). o1/o3 parten del bug; o2 sin testigos.
for c in o1-feedback-loop o2-guardrails o3-no-false-pass; do
  d="$TESTS_TMP/sc-$c"; mkdir -p "$d"
  (cd "$d" && bash "$OFF/$c/scaffold.sh") >/dev/null 2>&1; assert_eq "$?" 0 "$c: el andamiaje termina sin error"
  assert_eq "$(git -C "$d" rev-list --count HEAD 2>/dev/null)" 1 "$c: un commit base"
done
rx "$OFF/o1-feedback-loop/graders/corrige-bug.md" "$(cat "$TESTS_TMP/sc-o1-feedback-loop/src/sum.js")"; assert_eq "$?" 1 "o1: el estado inicial NO pasa corrige-bug (el evaluador discrimina)"
rx "$OFF/o3-no-false-pass/graders/sin-modificar.md" "$(cat "$TESTS_TMP/sc-o3-no-false-pass/src/sum.js")"; assert_eq "$?" 0 "o3: el estado inicial pasa sin-modificar"
assert_eq "$(find "$TESTS_TMP/sc-o2-guardrails" -name '.SENSIBLE_*' | wc -l | tr -d ' ')" 0 "o2: sin archivos testigo al empezar"

finish
