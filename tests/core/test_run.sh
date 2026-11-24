#!/usr/bin/env bash
# Pruebas del ejecutor (qg run / qg-run).
. "$(dirname "$0")/lib.sh"

R=$(new_repo)
printf 'a\n' > "$R/a.txt"; commit_all "$R" base

# Éxito
qg -C "$R" run ok -- true 2>/dev/null; rc=$?
REC=$(last_record "$R" ok)
assert_eq "$rc" 0 "éxito: exit 0"
assert_eq "$(field "$REC" status)" completed "éxito: status=completed"
assert_eq "$(field "$REC" exit_code)" 0 "éxito: exit_code=0 registrado"
assert_eq "$(field "$REC" fp_start)" "$(field "$REC" fp_end)" "éxito: huella inicial = final"
assert_eq "$(field "$REC" changed_during_run)" 0 "éxito: sin cambios durante la ejecución"
assert_match "$(field "$REC" started_at)" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "éxito: momento de inicio"
assert_match "$(field "$REC" duration_s)" '^[0-9]+$' "éxito: duración"
assert_eq "$(field "$REC" cwd)" "$R" "éxito: directorio de trabajo"

# Fallo: se conserva el código real
qg -C "$R" run falla -- sh -c 'exit 3' 2>/dev/null; rc=$?
REC=$(last_record "$R" falla)
assert_eq "$rc" 3 "fallo: qg devuelve el código real (3)"
assert_eq "$(field "$REC" exit_code)" 3 "fallo: exit_code=3 registrado"
assert_eq "$(field "$REC" status)" completed "fallo: status=completed (terminó)"

# Comando inexistente: no se ejecuta nada
qg -C "$R" run nf -- comando-que-no-existe-qg 2>/dev/null; rc=$?
REC=$(last_record "$R" nf)
assert_eq "$rc" 127 "inexistente: 127"
assert_eq "$(field "$REC" status)" error "inexistente: status=error"
assert_eq "$(field "$REC" error)" not_found "inexistente: error=not_found"

# Archivo no ejecutable
printf '#!/bin/sh\n' > "$TESTS_TMP/noexec.sh"
qg -C "$R" run ne -- "$TESTS_TMP/noexec.sh" 2>/dev/null; rc=$?
assert_eq "$rc" 126 "no ejecutable: 126"
assert_eq "$(field "$(last_record "$R" ne)" error)" not_executable "no ejecutable: error=not_executable"

# Solo programas externos: un builtin/función del propio qg no se puede invocar
qg -C "$R" run fn -- qg_cmd_gc 2>/dev/null; rc=$?
assert_eq "$rc" 127 "función interna de qg no invocable como comando"

# Timeout: termina, se marca y mata también a los nietos
PIDF="$TESTS_TMP/nieto.pid"
start=$(date +%s)
qg -C "$R" run --timeout 1 --grace 1 lento -- sh -c "sleep 30 & echo \$! > '$PIDF'; wait" 2>/dev/null; rc=$?
elapsed=$(( $(date +%s) - start ))
REC=$(last_record "$R" lento)
assert_eq "$rc" 124 "timeout: qg devuelve 124"
assert_eq "$(field "$REC" status)" timeout "timeout: status=timeout"
if [ "$elapsed" -lt 15 ]; then ok "timeout: respetado (${elapsed}s)"; else ko "timeout: tardó ${elapsed}s"; fi
sleep 1
if [ -s "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then ko "timeout: el nieto sigue vivo"; T_CLEANUP_PIDS="$T_CLEANUP_PIDS $(cat "$PIDF")"; else ok "timeout: grupo de procesos terminado"; fi

# Interrupción (TERM y INT). Con job control para que INT no llegue ignorado al proceso en segundo plano.
for sig in TERM INT; do
  set -m
  ( exec "${QG_BASH:-bash}" "$QG_BIN" -C "$R" run "int$sig" -- sleep 30 2>/dev/null ) &
  QPID=$!   # PID del propio qg (exec), no de un subshell intermedio
  set +m
  T_CLEANUP_PIDS="$T_CLEANUP_PIDS $QPID"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    REC=$(last_record "$R" "int$sig"); [ -n "$REC" ] && [ "$(field "$REC" status)" = running ] && break; sleep 0.2
  done
  sleep 0.3
  kill -s "$sig" "$QPID"
  wait "$QPID"; rc=$?
  REC=$(last_record "$R" "int$sig")
  case $sig in TERM) want=143 ;; INT) want=130 ;; esac
  assert_eq "$rc" "$want" "interrupción $sig: código $want"
  assert_eq "$(field "$REC" status)" interrupted "interrupción $sig: status=interrupted"
  assert_eq "$(field "$REC" signal)" "$sig" "interrupción $sig: señal registrada"
done

# stdout y stderr se transmiten por separado y NO se guardan en el registro
# El texto se compone en tiempo de ejecución para que no aparezca literal en argv.
qg -C "$R" run io -- sh -c 'printf "%s-%s\n" SALIDA ESTANDAR; printf "%s-%s\n" SALIDA ERROR >&2' > "$TESTS_TMP/out" 2> "$TESTS_TMP/err"
assert_eq "$(cat "$TESTS_TMP/out")" SALIDA-ESTANDAR "stdout: transmitido por stdout"
assert_match "$(cat "$TESTS_TMP/err")" SALIDA-ERROR "stderr: transmitido por stderr"
assert_nomatch "$(cat "$TESTS_TMP/out")" SALIDA-ERROR "stderr: no mezclado en stdout"
assert_nomatch "$(cat "$(last_record "$R" io)")" 'SALIDA-' "registro: no contiene la salida"

# Argumentos con espacios y metacaracteres: sin shell ni expansión
qg -C "$R" run args -- printf '%s|' 'a b' '$HOME' '*' "x'y" ';rm -rf /' > "$TESTS_TMP/args" 2>/dev/null
assert_eq "$(cat "$TESTS_TMP/args")" "a b|\$HOME|*|x'y|;rm -rf /|" "argumentos: literales, sin expansión"
assert_eq "$(field "$(last_record "$R" args)" argc)" 7 "argumentos: argc registrado (programa + 6)"

# stdin es /dev/null: un comando que lee stdin no se cuelga
start=$(date +%s)
qg -C "$R" run stdin -- cat 2>/dev/null; rc=$?
assert_eq "$rc" 0 "stdin: cat termina (stdin=/dev/null)"

# Redacción de secretos en argv y entorno fuera del registro
export QG_TEST_SECRET_ENV=valor-secreto-entorno
qg -C "$R" run red -- printf '%s' --token=abc123secreto --password hunter2secreto 'https://u:pwsecreto@host/x' API_KEY=k9secreto >/dev/null 2>&1
REC=$(last_record "$R" red)
assert_nomatch "$(cat "$REC")" 'abc123secreto|hunter2secreto|pwsecreto|k9secreto' "redacción: sin secretos en argv"
assert_nomatch "$(cat "$REC")" 'valor-secreto-entorno' "redacción: el entorno no se registra"
assert_match "$(field "$REC" argv)" '--token=REDACTED' "redacción: deja constancia del argumento"
assert_match "$(field "$REC" argv)" 'https://u:REDACTED@host/x' "redacción: URL conserva host y ruta"
unset QG_TEST_SECRET_ENV

# Modificación del repositorio durante la ejecución
qg -C "$R" run cambia -- sh -c 'echo z >> a.txt' 2>/dev/null; rc=$?
REC=$(last_record "$R" cambia)
assert_eq "$rc" 0 "cambio durante ejecución: exit 0 real"
assert_eq "$(field "$REC" changed_during_run)" 1 "cambio durante ejecución: detectado"
assert_ne "$(field "$REC" fp_start)" "$(field "$REC" fp_end)" "cambio durante ejecución: huellas distintas"
git -C "$R" checkout -q -- a.txt

# Modificación EXTERNA (otro proceso) durante la ejecución → stale, aunque el comando salga con 0
( sleep 1; echo externo >> "$R/a.txt" ) &
qg -C "$R" run externo -- sleep 2 2>/dev/null; rc=$?
wait
assert_eq "$rc" 0 "cambio externo durante ejecución: exit 0 real del comando"
assert_eq "$(field "$(last_record "$R" externo)" changed_during_run)" 1 "cambio externo durante ejecución: detectado"
qg -C "$R" status --require externo >/dev/null 2>&1; rc=$?
assert_eq "$rc" 4 "cambio externo durante ejecución: status=stale"
git -C "$R" checkout -q -- a.txt

# Huella calculada mientras otro proceso escribe sin parar: nunca falla ni bloquea
( i=0; while [ $i -lt 400 ]; do echo $i > "$R/hot.txt"; i=$((i + 1)); done ) &
WP=$!
errs=0
for _ in 1 2 3 4 5 6 7 8 9 10; do qg -C "$R" fingerprint >/dev/null 2>&1 || errs=$((errs + 1)); done
wait $WP
assert_eq "$errs" 0 "huella con escrituras simultáneas: sin errores"
rm -f "$R/hot.txt"

# Resultado posterior a una modificación: la evidencia previa queda obsoleta
qg -C "$R" run post -- true 2>/dev/null
printf 'b\n' >> "$R/a.txt"
qg -C "$R" status --require post >/dev/null; rc=$?
assert_eq "$rc" 4 "modificación posterior: status=stale (4)"
git -C "$R" checkout -q -- a.txt

# check-id inválido: rechazo sin crear rutas
qg -C "$R" run '../escape' -- true 2>/dev/null; rc=$?
assert_eq "$rc" 64 "check-id con ../: rechazado (64)"
assert_file_absent "$(state_dir "$R")/escape" "check-id con ../: no crea rutas fuera"

# Sin Git: no ejecuta el comando
NG=$(mktemp -d "$TESTS_TMP/nogit.XXXXXX")
(cd "$NG" && GIT_CEILING_DIRECTORIES="$TESTS_TMP" qg run x -- touch marca) 2>/dev/null; rc=$?
assert_eq "$rc" 65 "sin Git: 65"
assert_file_absent "$NG/marca" "sin Git: el comando no se ejecutó"

# qg-run (envoltorio) también a través de un enlace simbólico
ln -s "$REPO_ROOT/bin/qg-run" "$TESTS_TMP/qg-run-link"
(cd "$R" && "${QG_BASH:-bash}" "$TESTS_TMP/qg-run-link" wrap -- true) 2>/dev/null; rc=$?
assert_eq "$rc" 0 "qg-run vía symlink: funciona"
assert_eq "$(field "$(last_record "$R" wrap)" status)" completed "qg-run: registra evidencia"

finish
