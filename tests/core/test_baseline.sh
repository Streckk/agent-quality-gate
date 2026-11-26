#!/usr/bin/env bash
# Pruebas de las líneas base de diagnósticos (qg run --baseline, qg baseline write, qg status).
# Cada caso usa un repo temporal y un tsc falso que imprime una salida fija y sale con un código dado.
. "$(dirname "$0")/lib.sh"

TSC="$CORE_DIR/fixtures/baseline/fake-tsc"
MIXTA="$CORE_DIR/fixtures/baseline/salida-mixta.txt"
OUT="$TESTS_TMP/salidas"; mkdir -p "$OUT"

status_rc()   { qg -C "$1" status "${@:2}" >/dev/null 2>&1; echo $?; }
status_json() { qg -C "$1" status --json "${@:2}" 2>/dev/null; }
# Resultado y motivo de un check en el JSON de status.
check_json()  { status_json "$1" --require "$2" | sed -n 's/.*"checks":\[\(.*\)\],"corrupt_records".*/\1/p'; }
sha_of()      { git -C "$1" hash-object --no-filters -- "$2"; }

# Genera N diagnósticos sintéticos (formato con paréntesis). $2: desplazamiento de línea (mover código).
# Los índices 1..N son estables: el diagnóstico i siempre tiene la misma firma.
gen() {   # gen <desde> <hasta> [desplazamiento]
  local i=$1 off=${3:-0}
  while [ "$i" -le "$2" ]; do
    printf 'src/mod%d.ts(%d,5): error TS2322: Type '"'"'Valor%d'"'"' is not assignable to type '"'"'Destino'"'"'.\n' \
      $((i % 12)) $((i + off)) "$i"
    i=$((i + 1))
  done
}

new_base_repo() {   # repo con src/ versionado y una línea base de 238 diagnósticos en tipos.baseline
  local r; r=$(new_repo)
  mkdir -p "$r/src"; printf 'export const a = 1;\n' > "$r/src/mod0.ts"
  gen 1 238 > "$OUT/base238"
  printf 'Found 238 errors in 12 files.\n' >> "$OUT/base238"
  qg -C "$r" baseline write --format typescript --output tipos.baseline -- "$TSC" "$OUT/base238" 2 >/dev/null 2>&1
  commit_all "$r" base
  printf '%s' "$r"
}

run_bl() {   # run_bl <repo> <check> <salida> <exit> → imprime el exit de qg
  qg -C "$1" run --baseline tipos.baseline --baseline-format typescript "$2" -- "$TSC" "$3" "$4" >/dev/null 2>&1
  echo $?
}

R=$(new_base_repo)
BL="$R/tipos.baseline"

# --- baseline write: formato del archivo
assert_eq "$(head -n 1 "$BL")" "# qg-baseline 1 format=typescript" "write: cabecera"
assert_eq "$(sed 1d "$BL" | awk -F '\t' '{s += $1} END {print s}')" 238 "write: 238 diagnósticos contados"
assert_eq "$(sed 1d "$BL" | grep -c .)" 238 "write: una línea por firma"
assert_eq "$(sed 1d "$BL" | cut -f2 | LC_ALL=C sort -c 2>&1 && echo ordenado)" ordenado "write: firmas ordenadas (LC_ALL=C)"
assert_match "$(sed -n 2p "$BL")" $'^1\tTS2322\\|src/mod[0-9]+\\.ts\\|Type .Valor[0-9]+. is not assignable' "write: firma TSnnnn|archivo|mensaje sin línea ni columna"
SHA0=$(sha_of "$R" "$BL")

# --- 238 iguales → passed (contra la línea base); el exit original se conserva
rc=$(run_bl "$R" tipos "$OUT/base238" 2)
REC=$(last_record "$R" tipos)
assert_eq "$rc" 2 "iguales: qg run devuelve el exit real del comando (2)"
assert_eq "$(field "$REC" exit_code)" 2 "iguales: exit_code=2 en el registro"
assert_eq "$(field "$REC" baseline_result)" passed "iguales: baseline_result=passed"
assert_eq "$(field "$REC" baseline_known)" 238 "iguales: known=238"
assert_eq "$(field "$REC" baseline_new)" 0 "iguales: new=0"
assert_eq "$(field "$REC" baseline_fixed)" 0 "iguales: fixed=0"
assert_eq "$(field "$REC" baseline_ref)" tipos.baseline "iguales: baseline_ref"
assert_eq "$(field "$REC" baseline_format)" typescript "iguales: baseline_format"
assert_eq "$(field "$REC" baseline_sha)" "$SHA0" "iguales: baseline_sha = hash del archivo"
assert_eq "$(status_rc "$R" --require tipos)" 0 "iguales: status valid"
C=$(check_json "$R" tipos)
assert_match "$C" '"result":"passed","reason":"baseline:known=238,fixed=0","exit_code":2' "iguales: passed marcado como línea base, exit 2 visible"
assert_match "$C" '"baseline":\{"ref":"tipos.baseline","format":"typescript","known":238,"new":0,"fixed":0,"result":"passed"\}' "iguales: objeto baseline en status --json"
J=$(status_json "$R" --require tipos)
assert_match "$J" '^\{"schema":1,"qg_version":"[^"]+","result":"valid",' "json: result sigue en su posición"
assert_match "$J" '"baseline_checks":\["tipos"\]\}$' "json: baseline_checks en la raíz"
assert_match "$(qg -C "$R" status --require tipos 2>/dev/null)" 'tipos +passed +\(baseline:known=238,fixed=0\) exit=2' "texto: passed con marca de línea base"
assert_file_absent "$REC.new" "iguales: sin firmas nuevas no hay archivo .new"
assert_eq "$(sha_of "$R" "$BL")" "$SHA0" "qg run no modifica la línea base"

# --- la salida cruda no se guarda en el estado; los temporales de captura se borran
ST=$(state_dir "$R")
assert_eq "$(grep -rl 'Valor17' "$ST" 2>/dev/null | wc -l | tr -d ' ')" 0 "estado: la salida cruda no se persiste"
assert_eq "$(find "$ST" -name '*.tmp.*' | wc -l | tr -d ' ')" 0 "estado: sin temporales de captura tras la ejecución"

# --- mover código (cambian línea y columna) no crea errores nuevos
gen 1 238 7 > "$OUT/movido"
rc=$(run_bl "$R" tipos "$OUT/movido" 2)
assert_eq "$(field "$(last_record "$R" tipos)" baseline_result)" passed "movido: línea/columna fuera de la firma → passed"

# --- −2 conocidos y +2 nuevos con el mismo total (238) → failed
{ gen 3 238; gen 900 901; } > "$OUT/swap"
assert_eq "$(grep -c 'error TS' "$OUT/swap")" 238 "swap: el total sigue siendo 238"
rc=$(run_bl "$R" tipos "$OUT/swap" 2)
REC=$(last_record "$R" tipos)
assert_eq "$(field "$REC" baseline_result)" failed "swap: mismo total pero 2 nuevos → failed"
assert_eq "$(field "$REC" baseline_new)" 2 "swap: new=2"
assert_eq "$(field "$REC" baseline_fixed)" 2 "swap: fixed=2"
assert_eq "$(field "$REC" baseline_known)" 236 "swap: known=236"
assert_eq "$(status_rc "$R" --require tipos)" 1 "swap: status failed (1)"
assert_match "$(check_json "$R" tipos)" '"result":"failed","reason":"baseline:new=2"' "swap: motivo baseline:new=2"
assert_eq "$(grep -c . "$REC.new")" 2 "swap: archivo .new con las 2 firmas nuevas"
assert_match "$(cat "$REC.new")" 'Valor900' "swap: .new contiene la firma nueva"
assert_nomatch "$(cat "$REC.new")" 'Valor17' "swap: .new no contiene firmas conocidas"

# --- baja real → passed con fixed=2
gen 3 238 > "$OUT/baja"
rc=$(run_bl "$R" tipos "$OUT/baja" 2)
REC=$(last_record "$R" tipos)
assert_eq "$(field "$REC" baseline_result)" passed "baja: passed"
assert_eq "$(field "$REC" baseline_fixed)" 2 "baja: fixed=2"
assert_match "$(check_json "$R" tipos)" '"reason":"baseline:known=236,fixed=2"' "baja: motivo con fixed=2"

# --- sube → failed
{ gen 1 238; gen 500 501; } > "$OUT/sube"
rc=$(run_bl "$R" tipos "$OUT/sube" 2)
assert_eq "$(field "$(last_record "$R" tipos)" baseline_new)" 2 "sube: new=2"
assert_eq "$(status_rc "$R" --require tipos)" 1 "sube: status failed"

# --- multiplicidad: un duplicado más de una firma conocida es un error nuevo
{ gen 1 238; gen 5 5; } > "$OUT/dup"
rc=$(run_bl "$R" tipos "$OUT/dup" 2)
REC=$(last_record "$R" tipos)
assert_eq "$(field "$REC" baseline_result)" failed "multiconjunto: firma repetida una vez más → failed"
assert_eq "$(field "$REC" baseline_new)" 1 "multiconjunto: new=1"

# --- error nuevo en un archivo modificado → failed
printf 'export const b: number = "x";\n' > "$R/src/nuevo.ts"
{ gen 1 238; printf 'src/nuevo.ts(1,14): error TS2322: Type '"'"'string'"'"' is not assignable to type '"'"'number'"'"'.\n'; } > "$OUT/modificado"
rc=$(run_bl "$R" tipos "$OUT/modificado" 2)
assert_eq "$(field "$(last_record "$R" tipos)" baseline_result)" failed "archivo modificado: error nuevo → failed"
assert_match "$(cat "$(last_record "$R" tipos).new")" $'^1\tTS2322\\|src/nuevo\\.ts\\|' "archivo modificado: firma nueva con la ruta del archivo"
rm -f "$R/src/nuevo.ts"

# --- un mensaje que cambia (p. ej. un tipo renombrado) cuenta como nuevo (intencional)
gen 1 238 | sed 's/Destino/DestinoRenombrado/' > "$OUT/renombrado"
rc=$(run_bl "$R" tipos "$OUT/renombrado" 2)
assert_eq "$(field "$(last_record "$R" tipos)" baseline_result)" failed "mensaje cambiado → failed (se prefiere revisar a un falso PASS)"

# --- limpio: exit 0 sin diagnósticos → passed sin marca de línea base
printf 'Found 0 errors.\n' > "$OUT/limpio"
rc=$(run_bl "$R" tipos "$OUT/limpio" 0)
assert_eq "$rc" 0 "limpio: exit 0"
C=$(check_json "$R" tipos)
assert_match "$C" '"result":"passed","reason":"","exit_code":0' "limpio: passed sin marca"
assert_nomatch "$C" '"baseline"' "limpio: sin objeto baseline"
assert_match "$(status_json "$R" --require tipos)" '"baseline_checks":\[\]' "limpio: baseline_checks vacío"

# --- exit 3 (fuera de {0,1,2}) → blocked
rc=$(run_bl "$R" tipos "$OUT/base238" 3)
REC=$(last_record "$R" tipos)
assert_eq "$rc" 3 "exit 3: qg run devuelve 3"
assert_eq "$(field "$REC" exit_code)" 3 "exit 3: exit_code=3"
assert_eq "$(field "$REC" baseline_result)" inconclusive "exit 3: inconclusive"
assert_eq "$(status_rc "$R" --require tipos)" 2 "exit 3: status blocked (2)"
assert_match "$(check_json "$R" tipos)" '"result":"blocked","reason":"baseline:exit_code_unknown"' "exit 3: motivo"

# --- salida irreconocible: una línea con 'error TS' que no se reconoce → blocked
{ gen 1 238; printf 'src/raro.ts: error TS2322 sin el formato esperado\n'; } > "$OUT/raro"
rc=$(run_bl "$R" tipos "$OUT/raro" 2)
assert_eq "$(status_rc "$R" --require tipos)" 2 "irreconocible: blocked"
assert_match "$(check_json "$R" tipos)" '"reason":"baseline:unrecognized_output"' "irreconocible: motivo"
# diagnóstico global sin archivo (error de configuración) → también irreconocible
{ gen 1 238; printf 'error TS5083: Cannot read file '"'"'tsconfig.base.json'"'"'.\n'; } > "$OUT/global"
rc=$(run_bl "$R" tipos "$OUT/global" 1)
assert_eq "$(status_rc "$R" --require tipos)" 2 "diagnóstico sin archivo: blocked"
# exit ≠ 0 sin diagnósticos → blocked
: > "$OUT/sin-diag"
rc=$(run_bl "$R" tipos "$OUT/sin-diag" 1)
assert_match "$(check_json "$R" tipos)" '"result":"blocked","reason":"baseline:no_diagnostics"' "exit≠0 sin diagnósticos: blocked"
# Solo se reconoce la salida de tsc: cualquier otra línea → blocked (--baseline envuelve tsc directamente)
printf 'Algo salió mal y no hay diagnósticos.\n' > "$OUT/texto"
rc=$(run_bl "$R" tipos "$OUT/texto" 1)
assert_match "$(check_json "$R" tipos)" '"result":"blocked","reason":"baseline:unrecognized_output"' "texto ajeno sin diagnósticos: blocked"
{ gen 1 238; printf ' RUN  v1.6.0 /repo\n\n ✓ src/a.test.ts (3 tests) 5ms\n'; } > "$OUT/vitest"
rc=$(run_bl "$R" tipos "$OUT/vitest" 1)
assert_match "$(check_json "$R" tipos)" '"result":"blocked","reason":"baseline:unrecognized_output"' "salida de otra herramienta (tipo vitest) tras tsc: blocked"
{ gen 1 238; printf '/repo/node_modules/typescript/lib/tsc.js:120\n        throw e;\n        ^\n\nError: boom\n    at Object.<anonymous> (/repo/x.js:1:1)\n'; } > "$OUT/node-crash"
rc=$(run_bl "$R" tipos "$OUT/node-crash" 1)
assert_match "$(check_json "$R" tipos)" '"result":"blocked","reason":"baseline:unrecognized_output"' "traza de Node tras los diagnósticos: blocked"
{ printf '\n> pkg@1.0.0 check\n> tsc --noEmit\n\n'; gen 1 238; } > "$OUT/npm"
rc=$(run_bl "$R" tipos "$OUT/npm" 2)
assert_match "$(check_json "$R" tipos)" '"result":"blocked","reason":"baseline:unrecognized_output"' "envoltorio npm run: blocked"
# diagnósticos en stderr también cuentan
: > "$OUT/vacio"
rc=$(qg -C "$R" run --baseline tipos.baseline --baseline-format typescript tipos -- "$TSC" "$OUT/vacio" 2 "$OUT/base238" >/dev/null 2>&1; echo $?)
assert_eq "$(field "$(last_record "$R" tipos)" baseline_result)" passed "stderr: los diagnósticos de stderr se analizan"

# --- la salida sigue viéndose en la terminal
assert_match "$(qg -C "$R" run --baseline tipos.baseline --baseline-format typescript tipos -- "$TSC" "$OUT/swap" 2 2>/dev/null)" 'Valor900' "terminal: la salida del comando se sigue mostrando"
E=$(qg -C "$R" run --baseline tipos.baseline --baseline-format typescript tipos -- "$TSC" "$OUT/swap" 2 2>&1 >/dev/null)
assert_match "$E" 'baseline=failed' "terminal: resumen de la línea base en stderr"

# --- sin línea base → blocked; qg run no la crea
R2=$(new_repo); printf 'x\n' > "$R2/x"; commit_all "$R2" b
rc=$(run_bl "$R2" tipos "$OUT/base238" 2)
assert_eq "$rc" 2 "sin línea base: exit real"
assert_eq "$(status_rc "$R2" --require tipos)" 2 "sin línea base: blocked"
assert_match "$(check_json "$R2" tipos)" '"reason":"baseline:baseline_missing"' "sin línea base: motivo"
assert_file_absent "$R2/tipos.baseline" "qg run no crea la línea base"
# …pero un resultado limpio no necesita línea base
rc=$(run_bl "$R2" tipos "$OUT/limpio" 0)
assert_eq "$(status_rc "$R2" --require tipos)" 0 "sin línea base pero limpio: valid"

# --- corrupta → blocked
R3=$(new_repo)
printf '# qg-baseline 1 format=typescript\n1\tTS1|a|b\nbasura\n' > "$R3/tipos.baseline"; commit_all "$R3" b
rc=$(run_bl "$R3" tipos "$OUT/base238" 2)
assert_match "$(check_json "$R3" tipos)" '"result":"blocked","reason":"baseline:baseline_corrupt"' "corrupta: blocked"
printf '# qg-baseline 1 format=typescript\n1\tTS2|b|c\n1\tTS1|a|b\n' > "$R3/tipos.baseline"; commit_all "$R3" desordenada
rc=$(run_bl "$R3" tipos "$OUT/base238" 2)
assert_match "$(check_json "$R3" tipos)" '"reason":"baseline:baseline_corrupt"' "desordenada: corrupta"
printf '# qg-baseline 1 format=typescript\n1\tTS1|a|b\n2\tTS1|a|b\n' > "$R3/tipos.baseline"; commit_all "$R3" duplicada
rc=$(run_bl "$R3" tipos "$OUT/base238" 2)
assert_match "$(check_json "$R3" tipos)" '"reason":"baseline:baseline_corrupt"' "firma duplicada: corrupta"
printf '# qg-baseline 1 format=typescript\n0\tTS1|a|b\n' > "$R3/tipos.baseline"; commit_all "$R3" cero
rc=$(run_bl "$R3" tipos "$OUT/base238" 2)
assert_match "$(check_json "$R3" tipos)" '"reason":"baseline:baseline_corrupt"' "conteo 0: corrupta"

# --- versión o formato desconocidos → blocked (unsupported)
printf '# qg-baseline 2 format=typescript\n' > "$R3/tipos.baseline"; commit_all "$R3" v2
rc=$(run_bl "$R3" tipos "$OUT/base238" 2)
assert_match "$(check_json "$R3" tipos)" '"result":"blocked","reason":"baseline:baseline_unsupported"' "versión desconocida: blocked"
printf '# qg-baseline 1 format=eslint\n' > "$R3/tipos.baseline"; commit_all "$R3" eslint
rc=$(run_bl "$R3" tipos "$OUT/base238" 2)
assert_match "$(check_json "$R3" tipos)" '"reason":"baseline:baseline_unsupported"' "formato distinto: blocked"

# --- la línea base cambia después de ejecutar → nunca passed
R4=$(new_base_repo)
rc=$(run_bl "$R4" tipos "$OUT/base238" 2)
assert_eq "$(status_rc "$R4" --require tipos)" 0 "cambio posterior: antes, valid"
printf '1\tTS9999|z.ts|añadido a mano\n' >> "$R4/tipos.baseline"
assert_eq "$(status_rc "$R4" --require tipos)" 4 "línea base versionada modificada: stale (huella)"
# línea base ignorada por Git: la huella no cambia, el sha sí
R5=$(new_repo); mkdir -p "$R5/ci"; printf 'ci/\n' > "$R5/.gitignore"; printf 'x\n' > "$R5/x"; commit_all "$R5" b
qg -C "$R5" baseline write --format typescript --output ci/tipos.baseline -- "$TSC" "$OUT/base238" 2 >/dev/null 2>&1
qg -C "$R5" run --baseline ci/tipos.baseline --baseline-format typescript tipos -- "$TSC" "$OUT/base238" 2 >/dev/null 2>&1
assert_eq "$(status_rc "$R5" --require tipos)" 0 "ignorada: antes, valid"
printf '1\tTS9999|z.ts|añadido a mano\n' >> "$R5/ci/tipos.baseline"
assert_eq "$(status_rc "$R5" --require tipos)" 4 "ignorada y modificada: stale (sha distinto)"
assert_match "$(check_json "$R5" tipos)" '"result":"stale","reason":"baseline:baseline_changed"' "ignorada y modificada: motivo"
rm -f "$R5/ci/tipos.baseline"
assert_match "$(check_json "$R5" tipos)" '^\{"id":"tipos","result":"stale"' "ignorada y borrada: stale, nunca passed"

# --- rutas: absoluta y '..' se rechazan; symlink fuera del repo → blocked
qg -C "$R" run --baseline "$BL" --baseline-format typescript abs -- "$TSC" "$OUT/base238" 2 >/dev/null 2>&1; rc=$?
assert_eq "$rc" 64 "ruta absoluta: uso inválido (64)"
qg -C "$R" run --baseline ../fuera.baseline --baseline-format typescript up -- "$TSC" "$OUT/base238" 2 >/dev/null 2>&1; rc=$?
assert_eq "$rc" 64 "ruta con ..: uso inválido (64)"
qg -C "$R" run --baseline tipos.baseline --baseline-format eslint fmt -- "$TSC" "$OUT/base238" 2 >/dev/null 2>&1; rc=$?
assert_eq "$rc" 64 "formato no admitido: uso inválido (64)"
qg -C "$R" run --baseline tipos.baseline sinfmt -- "$TSC" "$OUT/base238" 2 >/dev/null 2>&1; rc=$?
assert_eq "$rc" 64 "--baseline sin --baseline-format: uso inválido (64)"
cp "$BL" "$TESTS_TMP/fuera.baseline"
R6=$(new_repo); ln -s "$TESTS_TMP/fuera.baseline" "$R6/tipos.baseline"; commit_all "$R6" enlace
rc=$(run_bl "$R6" tipos "$OUT/base238" 2)
assert_match "$(check_json "$R6" tipos)" '"result":"blocked","reason":"baseline:baseline_outside_repo"' "symlink fuera del repo: blocked"
R7=$(new_repo); mkdir "$R7/ci"; cp "$BL" "$R7/ci/real.baseline"; ln -s real.baseline "$R7/ci/tipos.baseline"; commit_all "$R7" enlace
qg -C "$R7" run --baseline ci/tipos.baseline --baseline-format typescript tipos -- "$TSC" "$OUT/base238" 2 >/dev/null 2>&1
assert_eq "$(status_rc "$R7" --require tipos)" 0 "symlink dentro del repo: válido"

# --- formatos de línea de tsc: paréntesis y pretty (ANSI, CR) dan la misma firma; ruta relativa al repo
R8=$(new_repo); mkdir -p "$R8/src"; printf 'x\n' > "$R8/src/x"; commit_all "$R8" b
qg -C "$R8" baseline write --format typescript --output tipos.baseline -- "$TSC" "$MIXTA" 2 >/dev/null 2>&1
assert_eq "$(sed 1d "$R8/tipos.baseline")" "$(printf '1\tTS2304|src/pretty.ts|Cannot find name '"'"'zeta'"'"'.\n1\tTS2322|src/mixto(1).ts|Type '"'"'A'"'"' is not assignable to type '"'"'B'"'"'.')" "parser: ambos formatos, ANSI y espacios normalizados"
commit_all "$R8" linea-base
printf 'src/pretty.ts(30,1): error TS2304: Cannot find name '"'"'zeta'"'"'.\n./src/x/../mixto(1).ts:99:2 - error TS2322: Type '"'"'A'"'"' is not assignable to type '"'"'B'"'"'.\n' > "$OUT/otro-formato"
rc=$(run_bl "$R8" tipos "$OUT/otro-formato" 2)
assert_eq "$(status_rc "$R8" --require tipos)" 0 "parser: formato cruzado y ruta normalizada → passed"
# ejecutado desde un subdirectorio: tsc imprime rutas relativas al cwd
sed 's#src/##' "$OUT/otro-formato" > "$OUT/desde-src"
qg -C "$R8/src" run --baseline tipos.baseline --baseline-format typescript tipos -- "$TSC" "$OUT/desde-src" 2 >/dev/null 2>&1
assert_eq "$(field "$(last_record "$R8" tipos)" baseline_result)" passed "parser: rutas relativas al cwd se normalizan al repo"

# --- salida --pretty real (marcos de código, info relacionada, resumen y tabla) → se analiza
R10=$(new_repo); printf 'x\n' > "$R10/x"; commit_all "$R10" b
qg -C "$R10" baseline write --format typescript --output tipos.baseline -- "$TSC" "$CORE_DIR/fixtures/baseline/salida-pretty.txt" 2 >/dev/null 2>&1
assert_eq "$(sed 1d "$R10/tipos.baseline" | cut -f2 | tr '\n' ' ')" "TS2304|src/b.ts|Cannot find name 'foo'. TS2322|src/a.ts|Type 'string' is not assignable to type 'number'. " "pretty real: 2 firmas"
commit_all "$R10" linea-base
qg -C "$R10" run --baseline tipos.baseline --baseline-format typescript tipos -- "$TSC" "$CORE_DIR/fixtures/baseline/salida-pretty.txt" 2 >/dev/null 2>&1
assert_eq "$(status_rc "$R10" --require tipos)" 0 "pretty real: passed"

# --- separador: '|' y '\' en ruta o mensaje se escapan (firma inequívoca)
printf 'src/a|b.ts(1,1): error TS1005: x\n' > "$OUT/sep1"
printf 'src/a.ts(1,1): error TS1005: b.ts|x\n' > "$OUT/sep2"
R11=$(new_repo); printf 'x\n' > "$R11/x"; commit_all "$R11" b
qg -C "$R11" baseline write --format typescript --output tipos.baseline -- "$TSC" "$OUT/sep1" 2 >/dev/null 2>&1
assert_eq "$(sed 1d "$R11/tipos.baseline")" "$(printf '1\tTS1005|src/a\\|b.ts|x')" "separador: '|' escapado en la ruta"
commit_all "$R11" linea-base
rc=$(run_bl "$R11" tipos "$OUT/sep2" 2)
assert_eq "$(field "$(last_record "$R11" tipos)" baseline_result)" failed "separador: ruta y mensaje distintos no colisionan"

# --- línea base con CRLF (checkout con autocrlf) se acepta
R12=$(new_repo); printf 'x\n' > "$R12/x"; commit_all "$R12" b
qg -C "$R12" baseline write --format typescript --output tipos.baseline -- "$TSC" "$OUT/base238" 2 >/dev/null 2>&1
sed 's/$/\r/' "$R12/tipos.baseline" > "$R12/crlf" && mv "$R12/crlf" "$R12/tipos.baseline"; commit_all "$R12" crlf
rc=$(run_bl "$R12" tipos "$OUT/base238" 2)
assert_eq "$(status_rc "$R12" --require tipos)" 0 "CRLF: la línea base se lee igual"

# --- captura completa aunque el lado de la terminal se cierre (| head) o falle la escritura
R13=$(new_repo); printf 'x\n' > "$R13/x"; commit_all "$R13" b
gen 1 3000 > "$OUT/grande"
qg -C "$R13" baseline write --format typescript --output tipos.baseline -- "$TSC" "$OUT/grande" 2 2>/dev/null | head -c 1 >/dev/null
assert_eq "$(sed 1d "$R13/tipos.baseline" | awk -F '\t' '{s += $1} END {print s}')" 3000 "write | head: línea base completa"
commit_all "$R13" linea-base
{ gen 1 3000; printf 'src/z.ts(1,1): error TS9999: nuevo al final.\n'; } > "$OUT/grande-nuevo"
qg -C "$R13" run --baseline tipos.baseline --baseline-format typescript tipos -- "$TSC" "$OUT/grande-nuevo" 2 2>/dev/null | head -c 1 >/dev/null
REC=$(last_record "$R13" tipos)
assert_eq "$(field "$REC" baseline_result)" failed "run | head: el error nuevo del final se detecta"
assert_eq "$(field "$REC" baseline_new)" 1 "run | head: new=1"
assert_eq "$(field "$REC" exit_code)" 2 "run | head: exit real"
( ulimit -f 16; qg -C "$R13" run --baseline tipos.baseline --baseline-format typescript tipos -- "$TSC" "$OUT/grande" 2 >/dev/null 2>&1 )
assert_match "$(check_json "$R13" tipos)" '"result":"blocked","reason":"baseline:capture_failed"' "fallo al escribir la captura: blocked capture_failed"
E=$( ( ulimit -f 16; qg -C "$R13" baseline write --replace --format typescript --output tipos.baseline -- "$TSC" "$OUT/base238" 2 2>&1 >/dev/null ); echo "rc=$?")
assert_match "$E" 'capturar.*rc=65' "write con fallo de captura: se niega (65)"
assert_eq "$(sed 1d "$R13/tipos.baseline" | awk -F '\t' '{s += $1} END {print s}')" 3000 "write con fallo de captura: archivo intacto"
assert_eq "$(find "$(state_dir "$R13")" -path '*capture*' -type f | wc -l | tr -d ' ')" 0 "captura: sin temporales tras fallos"

# --- qg gc durante una ejecución larga no toca la captura; sí retira la de un proceso muerto
printf '#!/bin/sh\ncat "$1"; sleep 2; exit 2\n' > "$TESTS_TMP/tsc-lento"; chmod +x "$TESTS_TMP/tsc-lento"
qg -C "$R13" run --baseline tipos.baseline --baseline-format typescript tipos -- "$TESTS_TMP/tsc-lento" "$OUT/grande" >/dev/null 2>&1 &
QPID=$!
sleep 1
CAPD=$(state_dir "$R13")/capture
find "$CAPD" -exec touch -t 200001010000 {} + 2>/dev/null   # aparenta ser antigua
qg -C "$R13" gc 2>/dev/null
wait "$QPID"
assert_eq "$(field "$(last_record "$R13" tipos)" baseline_result)" passed "gc durante la ejecución: la captura sigue completa"
mkdir -p "$CAPD/999999999.1"; : > "$CAPD/999999999.1/out"; touch -t 200001010000 "$CAPD/999999999.1"
qg -C "$R13" gc 2>/dev/null
assert_file_absent "$CAPD/999999999.1" "gc: retira la captura abandonada de un proceso muerto"

# --- baseline write: se niega a sobrescribir sin --replace; se niega con salida irreconocible
qg -C "$R" baseline write --format typescript --output tipos.baseline -- "$TSC" "$OUT/baja" 2 >/dev/null 2>&1; rc=$?
assert_eq "$rc" 65 "write sin --replace sobre existente: 65"
assert_eq "$(sha_of "$R" "$BL")" "$SHA0" "write sin --replace: archivo intacto"
qg -C "$R" baseline write --format typescript --output tipos.baseline -- "$TSC" "$OUT/raro" 2 >/dev/null 2>&1; rc=$?
assert_eq "$rc" 65 "write con salida irreconocible: 65"
qg -C "$R" baseline write --replace --format typescript --output tipos.baseline -- "$TSC" "$OUT/raro" 2 >/dev/null 2>&1; rc=$?
assert_eq "$rc" 65 "write --replace con salida irreconocible: 65"
qg -C "$R" baseline write --replace --format typescript --output tipos.baseline -- "$TSC" "$OUT/base238" 3 >/dev/null 2>&1; rc=$?
assert_eq "$rc" 65 "write con exit 3: 65"
assert_eq "$(sha_of "$R" "$BL")" "$SHA0" "write rechazado: archivo intacto"
S=$(qg -C "$R" baseline write --replace --format typescript --output tipos.baseline -- "$TSC" "$OUT/baja" 2 2>&1 >/dev/null); rc=$?
assert_eq "$rc" 0 "write --replace: 0"
assert_match "$S" '236' "write: imprime el resumen"
assert_eq "$(sed 1d "$BL" | grep -c .)" 236 "write --replace: contenido nuevo"
qg -C "$R" baseline write --format typescript --output /tmp/x.baseline -- "$TSC" "$OUT/baja" 2 >/dev/null 2>&1; rc=$?
assert_eq "$rc" 64 "write con ruta absoluta: 64"
assert_eq "$(find "$(state_dir "$R")" -name '*.tmp.*' | wc -l | tr -d ' ')" 0 "write: sin temporales"

# --- gc no confunde el archivo .new con un registro
R9=$(new_base_repo)
rc=$(run_bl "$R9" tipos "$OUT/swap" 2)
REC=$(last_record "$R9" tipos)
qg -C "$R9" gc 2>/dev/null
assert_eq "$(ls "$(state_dir "$R9")/quarantine" 2>/dev/null | wc -l | tr -d ' ')" 0 "gc: el .new no va a cuarentena"
[ -f "$REC.new" ] && ok "gc: el .new de un registro vigente se conserva" || ko "gc: el .new desapareció"
assert_eq "$(qg -C "$R9" show tipos 2>/dev/null | grep -c CORRUPTO)" 0 "show: el .new no aparece como registro"
assert_eq "$(status_rc "$R9" --require tipos)" 1 "status: el .new no cuenta como registro corrupto"
# poda: con QG_KEEP_RECORDS=1 el registro antiguo y su .new se eliminan
rc=$(run_bl "$R9" tipos "$OUT/base238" 2)
QG_KEEP_RECORDS=1 qg -C "$R9" gc 2>/dev/null
assert_file_absent "$REC.new" "gc: el .new se poda con su registro"

# --- interfaz 4
assert_match "$(qg version --json)" '"interface":4' "version: interfaz 4"

finish
