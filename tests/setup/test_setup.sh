#!/usr/bin/env bash
# Pruebas deterministas de bin/qg-setup (/quality-gate setup): bloque administrado en CLAUDE.md.
# Todo ocurre en directorios temporales con HOME aislado: nunca toca el CLAUDE.md real del usuario.
. "$(cd "$(dirname "$0")" && pwd -P)/../core/lib.sh"
S="$REPO_ROOT/bin/qg-setup"
export HOME="$TESTS_TMP/home"; mkdir -p "$HOME"

newp() { local d; d=$(mktemp -d "$TESTS_TMP/p.XXXXXX"); d=$(cd "$d" && pwd -P); git -C "$d" init -q >/dev/null 2>&1; printf '%s' "$d"; }
# st <dir> <args…>: ejecuta qg-setup en <dir>; deja la salida en $OUT y el código en $RC
st() { local d=$1; shift; OUT=$(cd "$d" && "${QG_BASH:-bash}" "$S" "$@" 2>&1); RC=$?; }
sha() { if [ -e "$1" ]; then cksum < "$1"; else echo ausente; fi; }
mode() { ls -l "$1" | cut -c1-10; }
no_tmp_left() { assert_eq "$(find "$1" -maxdepth 2 -name '.CLAUDE.md.qg-setup.*' | wc -l | tr -d ' ')" 0 "$2: sin temporales residuales"; }
# Bloque de referencia: el que el propio script escribe en un archivo nuevo
REF="$TESTS_TMP/ref.md"; P=$(newp); st "$P" setup; cp "$P/CLAUDE.md" "$REF"
assert_eq "$RC" 0 "referencia: setup sobre un proyecto sin CLAUDE.md"
assert_eq "$(head -n 1 "$REF")" '<!-- agent-quality-gate:start v1 -->' "referencia: empieza por el marcador versionado"
assert_eq "$(tail -n 1 "$REF")" '<!-- agent-quality-gate:end -->' "referencia: termina con el marcador de fin"
assert_match "$(cat "$REF")" '/quality-gate' "referencia: el bloque menciona la skill"
assert_nomatch "$(cat "$REF")" '/home/|npm |pnpm |pytest|nx ' "referencia: sin rutas absolutas ni comandos de un stack"
assert_eq "$(wc -l < "$REF" | tr -d ' ')" 10 "referencia: bloque breve (10 líneas)"

# 1. Sin CLAUDE.md → lo crea solo con el bloque
P=$(newp); st "$P" setup
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "0/$(sha "$REF")" "1. sin CLAUDE.md: lo crea con el bloque exacto"
assert_match "$OUT" 'configurado correctamente en .*CLAUDE.md' "1. mensaje con el archivo modificado"
assert_match "$OUT" 'No instala el plugin ni activa los hooks' "1. aclara que no instala ni activa hooks"
assert_eq "$(mode "$P/CLAUDE.md")" "-rw-r--r--" "1. archivo nuevo con permisos normales (umask)"
no_tmp_left "$P" "1"

# 2. CLAUDE.md vacío
P=$(newp); : > "$P/CLAUDE.md"; st "$P" setup
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "0/$(sha "$REF")" "2. CLAUDE.md vacío: queda solo el bloque"

# 3. Instrucciones existentes: se conservan byte a byte; --remove las restaura exactamente
P=$(newp); printf '# Proyecto\n\nUsa siempre `make check`.\n<!-- comentario del usuario -->\n' > "$P/CLAUDE.md"; cp "$P/CLAUDE.md" "$TESTS_TMP/o3"
st "$P" setup
n=$(wc -c < "$TESTS_TMP/o3" | tr -d ' ')
assert_eq "$(head -c "$n" "$P/CLAUDE.md" | cksum)" "$(cksum < "$TESTS_TMP/o3")" "3. el contenido previo queda intacto al principio"
assert_eq "$(tail -n 10 "$P/CLAUDE.md" | cksum)" "$(cksum < "$REF")" "3. el bloque se añade al final"
assert_eq "$(sed -n "$(( $(wc -l < "$TESTS_TMP/o3") + 1 ))p" "$P/CLAUDE.md")" "" "3. separado por una línea en blanco"

# 4. Idempotencia: ejecuciones repetidas no cambian ni un byte
h1=$(sha "$P/CLAUDE.md"); st "$P" setup; r2=$RC; st "$P" setup; r3=$RC
assert_eq "$r2/$r3/$(sha "$P/CLAUDE.md")" "0/0/$h1" "4. setup ×3: idéntico y sin duplicar"
assert_eq "$(grep -c 'agent-quality-gate:start' "$P/CLAUDE.md")" 1 "4. un solo bloque"
assert_match "$OUT" 'Sin cambios' "4. informa de que no hay cambios"

# 6. Eliminación: restaura el archivo original exactamente
st "$P" setup --remove
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "0/$(sha "$TESTS_TMP/o3")" "6. --remove: restaura exactamente el original"
# 7. --remove sin bloque: no toca el archivo
h=$(sha "$P/CLAUDE.md"); st "$P" setup --remove
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "0/$h" "7. --remove sin bloque: sin cambios"
assert_match "$OUT" 'No hay bloque' "7. lo informa"
# --remove cuando el archivo solo contenía el bloque: se borra el archivo (no hay contenido del usuario)
P=$(newp); st "$P" setup; st "$P" setup --remove
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "0/ausente" "6b. archivo que solo tenía el bloque: se elimina"

# 5. Actualización de un bloque anterior: solo cambia el bloque
P=$(newp)
printf '# Arriba\n\n<!-- agent-quality-gate:start v0 -->\n## Texto viejo\n- usa quality gate\n<!-- agent-quality-gate:end -->\n\n## Abajo\nregla final\n' > "$P/CLAUDE.md"
st "$P" setup --status; assert_match "$OUT" 'versión anterior o modificado \(v0' "5. --status detecta la versión anterior"
st "$P" setup
assert_eq "$RC" 0 "5. actualización correcta"
assert_eq "$(head -n 2 "$P/CLAUDE.md" | cksum)" "$(printf '# Arriba\n\n' | cksum)" "5. lo de arriba queda intacto"
assert_eq "$(tail -n 3 "$P/CLAUDE.md" | cksum)" "$(printf '\n## Abajo\nregla final\n' | cksum)" "5. lo de abajo queda intacto"
assert_eq "$(sed -n '3,12p' "$P/CLAUDE.md" | cksum)" "$(cksum < "$REF")" "5. el bloque es el actual"
assert_match "$OUT" 'actualizado .*v0 → v1' "5. informa de la actualización"
st "$P" setup --status; assert_match "$OUT" 'instalado y actualizado \(v1\)' "5. después: actualizado"
# Bloque editado a mano (misma versión): se detecta y se restaura solo el bloque
sed -i.bak 's/^## Control de calidad.*/## editado a mano/' "$P/CLAUDE.md"; rm -f "$P/CLAUDE.md.bak"
st "$P" setup --status; assert_match "$OUT" 'modificado' "5b. bloque editado a mano: detectado"
st "$P" setup; assert_eq "$(sed -n '3,12p' "$P/CLAUDE.md" | cksum)" "$(cksum < "$REF")" "5b. se restaura el bloque administrado"

# 8. Bloque incompleto y 9. bloques duplicados: no se toca nada
P=$(newp); printf 'x\n<!-- agent-quality-gate:start v1 -->\nsin fin\n' > "$P/CLAUDE.md"; h=$(sha "$P/CLAUDE.md")
st "$P" setup; assert_eq "$RC/$(sha "$P/CLAUDE.md")" "65/$h" "8. bloque incompleto: setup se niega (65) sin modificar"
assert_match "$OUT" 'malformado' "8. mensaje claro"
st "$P" setup --remove; assert_eq "$RC/$(sha "$P/CLAUDE.md")" "65/$h" "8. bloque incompleto: --remove tampoco modifica"
st "$P" setup --status; assert_match "$RC $OUT" '^0 .*MALFORMADO' "8. --status lo informa"
P=$(newp); { cat "$REF"; printf '\n'; cat "$REF"; } > "$P/CLAUDE.md"; h=$(sha "$P/CLAUDE.md")
st "$P" setup; assert_eq "$RC/$(sha "$P/CLAUDE.md")" "65/$h" "9. bloques duplicados: setup no modifica"
st "$P" setup --remove; assert_eq "$RC/$(sha "$P/CLAUDE.md")" "65/$h" "9. bloques duplicados: --remove no modifica"
P=$(newp); printf '<!-- agent-quality-gate:end -->\nx\n<!-- agent-quality-gate:start v1 -->\n' > "$P/CLAUDE.md"; h=$(sha "$P/CLAUDE.md")
st "$P" setup; assert_eq "$RC/$(sha "$P/CLAUDE.md")" "65/$h" "9b. marcadores en orden inverso: no modifica"

# 10. CRLF: el bloque se escribe con CRLF y --remove restaura el original
P=$(newp); printf '# Win\r\nregla\r\n' > "$P/CLAUDE.md"; cp "$P/CLAUDE.md" "$TESTS_TMP/o10"
st "$P" setup
assert_eq "$RC/$(LC_ALL=C grep -vc "$(printf '\r')\$" "$P/CLAUDE.md")" "0/0" "10. CRLF: todas las líneas mantienen CRLF"
st "$P" setup; assert_match "$OUT" 'Sin cambios' "10. CRLF: idempotente"
st "$P" setup --remove; assert_eq "$(sha "$P/CLAUDE.md")" "$(sha "$TESTS_TMP/o10")" "10. CRLF: --remove restaura exactamente"

# 11. Sin salto de línea final: se añade antes del bloque
P=$(newp); printf 'regla sin salto' > "$P/CLAUDE.md"
st "$P" setup
assert_eq "$(head -n 3 "$P/CLAUDE.md" | cksum)" "$(printf 'regla sin salto\n\n<!-- agent-quality-gate:start v1 -->\n' | cksum)" "11. sin salto final: se completa la línea y se separa"
st "$P" setup --remove
assert_eq "$(cat "$P/CLAUDE.md")" "regla sin salto" "11. --remove conserva el texto (queda con salto final)"

# 12. Ruta con espacios
P="$TESTS_TMP/con espacios/mi proyecto"; mkdir -p "$P"; git -C "$P" init -q; mkdir -p "$P/sub dir"
st "$P/sub dir" setup
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "0/$(sha "$REF")" "12. ruta con espacios: usa la raíz de Git aunque se ejecute en un subdirectorio"
assert_eq "$(sha "$P/sub dir/CLAUDE.md")" ausente "12. no crea CLAUDE.md en el subdirectorio"

# 13. Symlinks: fuera del alcance se rechaza; dentro se edita el destino sin romper el enlace
P=$(newp); OUTSIDE="$TESTS_TMP/fuera.md"; printf 'ajeno\n' > "$OUTSIDE"; ln -s "$OUTSIDE" "$P/CLAUDE.md"
st "$P" setup
assert_eq "$RC/$(cat "$OUTSIDE")" "66/ajeno" "13. symlink fuera del proyecto: rechazado (66) y destino intacto"
assert_match "$OUT" 'enlace simbólico' "13. mensaje claro"
P=$(newp); mkdir -p "$P/docs"; printf 'propio\n' > "$P/docs/IA.md"; ln -s docs/IA.md "$P/CLAUDE.md"
st "$P" setup
assert_eq "$RC" 0 "13b. symlink dentro del proyecto: permitido"
assert_eq "$( [ -L "$P/CLAUDE.md" ] && echo enlace)" enlace "13b. el enlace se conserva"
assert_match "$(cat "$P/docs/IA.md")" 'agent-quality-gate:start' "13b. se escribe en el destino"
P=$(newp); mkdir -p "$TESTS_TMP/fuera-dir"; ln -s "$TESTS_TMP/fuera-dir" "$P/.claude"
st "$P" setup --file .claude/CLAUDE.md
assert_eq "$RC/$(sha "$TESTS_TMP/fuera-dir/CLAUDE.md")" "66/ausente" "13c. .claude enlazado fuera del proyecto: rechazado"

# 14. Permisos insuficientes (se omite si el usuario puede escribir igualmente, p. ej. root)
P=$(newp); printf 'solo lectura\n' > "$P/CLAUDE.md"; chmod 444 "$P/CLAUDE.md"
if [ -w "$P/CLAUDE.md" ]; then echo "omitido 14: el usuario actual escribe en archivos de solo lectura"
else
  st "$P" setup; assert_eq "$RC/$(cat "$P/CLAUDE.md")" "66/solo lectura" "14. archivo sin permiso de escritura: 66 y sin cambios"
  P=$(newp); chmod 555 "$P"; st "$P" setup
  assert_eq "$RC/$(sha "$P/CLAUDE.md")" "66/ausente" "14b. directorio sin permiso: 66 y no crea nada"; chmod 755 "$P"
fi
# Permisos existentes se conservan
P=$(newp); printf 'x\n' > "$P/CLAUDE.md"; chmod 600 "$P/CLAUDE.md"; st "$P" setup
assert_eq "$(mode "$P/CLAUDE.md")" "-rw-------" "14c. conserva los permisos del archivo existente"

# 15. Alcance de usuario sobre un HOME temporal; el de proyecto no toca el global y viceversa
P=$(newp); st "$P" setup --scope user
assert_eq "$RC/$(sha "$HOME/.claude/CLAUDE.md")" "0/$(sha "$REF")" "15. --scope user: crea ~/.claude/CLAUDE.md (HOME temporal)"
assert_eq "$(sha "$P/CLAUDE.md")" ausente "15. --scope user no toca el proyecto"
hu=$(sha "$HOME/.claude/CLAUDE.md"); st "$P" setup
assert_eq "$(sha "$HOME/.claude/CLAUDE.md")" "$hu" "15. el setup de proyecto no modifica el global"
st "$P" setup --scope user --status; assert_match "$OUT" 'usuario .*instalado y actualizado' "15. --status de usuario"
st "$P" setup --scope=user --remove; assert_eq "$(sha "$HOME/.claude/CLAUDE.md")" ausente "15. --scope=user --remove"

# 16. --dry-run nunca escribe
P=$(newp); st "$P" setup --dry-run
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "0/ausente" "16. --dry-run sin CLAUDE.md: no lo crea"
assert_match "$OUT" 'se crearía' "16. muestra el contenido propuesto"
printf 'x\n' > "$P/CLAUDE.md"; h=$(sha "$P/CLAUDE.md"); st "$P" setup --dry-run
assert_eq "$(sha "$P/CLAUDE.md")" "$h" "16. --dry-run con archivo: no lo modifica"
assert_match "$OUT" '\+<!-- agent-quality-gate:start v1 -->' "16. muestra el diff"
st "$P" setup; h=$(sha "$P/CLAUDE.md"); st "$P" setup --remove --dry-run
assert_eq "$(sha "$P/CLAUDE.md")" "$h" "16. --remove --dry-run: no modifica"
st "$P" setup --scope user --dry-run; assert_eq "$(sha "$HOME/.claude/CLAUDE.md")" ausente "16. --scope user --dry-run: no crea el global"

# 17. --status nunca escribe
P=$(newp); st "$P" setup --status
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "0/ausente" "17. --status sin archivo: no lo crea"
assert_match "$OUT" 'existe: no' "17. informa de que no existe"
assert_match "$OUT" 'bloque: no instalado' "17. informa del bloque"

# 18. Proyecto con AGENTS.md y sin CLAUDE.md: no se crea CLAUDE.md sin decisión explícita
P=$(newp); printf '# Agentes\n' > "$P/AGENTS.md"; ha=$(sha "$P/AGENTS.md")
st "$P" setup
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "65/ausente" "18. solo AGENTS.md: no crea CLAUDE.md (dejaría de cargarse AGENTS.md)"
assert_match "$OUT" 'import-agents' "18. propone las alternativas"
st "$P" setup --status; assert_match "$OUT" 'nota: .*AGENTS.md' "18. --status lo advierte"
st "$P" setup --import-agents
assert_eq "$RC/$(head -n 1 "$P/CLAUDE.md")" "0/@AGENTS.md" "18. --import-agents: CLAUDE.md importa AGENTS.md"
assert_eq "$(sha "$P/AGENTS.md")" "$ha" "18. AGENTS.md no se modifica"
P=$(newp); printf '# Agentes\n' > "$P/AGENTS.md"; printf 'mío\n' > "$P/CLAUDE.md"; st "$P" setup
assert_eq "$RC" 0 "18b. AGENTS.md y CLAUDE.md: se usa CLAUDE.md"

# 19. .claude/CLAUDE.md
P=$(newp); mkdir -p "$P/.claude"; printf 'reglas\n' > "$P/.claude/CLAUDE.md"; st "$P" setup
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "0/ausente" "19. solo .claude/CLAUDE.md: no crea otro CLAUDE.md"
assert_match "$(cat "$P/.claude/CLAUDE.md")" 'agent-quality-gate:start' "19. el bloque va en .claude/CLAUDE.md"
P=$(newp); mkdir -p "$P/.claude"; printf 'a\n' > "$P/CLAUDE.md"; printf 'b\n' > "$P/.claude/CLAUDE.md"
st "$P" setup; assert_eq "$RC/$(cat "$P/CLAUDE.md")/$(cat "$P/.claude/CLAUDE.md")" "65/a/b" "19b. ambos sin bloque: ambiguo (65), nada modificado"
assert_match "$OUT" '--file' "19b. ofrece elegir con --file"
st "$P" setup --file .claude/CLAUDE.md; assert_eq "$RC/$(cat "$P/CLAUDE.md")" "0/a" "19c. --file .claude/CLAUDE.md elige ese archivo"
st "$P" setup; assert_match "$RC $OUT" '^0 .*Sin cambios' "19d. después, se reconoce dónde está el bloque"
cp "$REF" "$P/CLAUDE.md"; st "$P" setup
assert_eq "$RC" 65 "19e. bloque en los dos archivos: conflicto (65)"

# 20. Compatibilidad: skill instalada por symlink y como plugin (--plugin-dir)
mkdir -p "$HOME/.claude/skills"; ln -s "$REPO_ROOT/skills/quality-gate" "$HOME/.claude/skills/quality-gate"
VIA="$HOME/.claude/skills/quality-gate/../../bin/qg-setup"   # ruta que indica SKILL.md con ${CLAUDE_SKILL_DIR}
assert_eq "$( [ -x "$VIA" ] && echo ejecutable)" ejecutable "20. vía symlink: \${CLAUDE_SKILL_DIR}/../../bin/qg-setup se resuelve al script"
VIA2="$(cd -P "$HOME/.claude/skills/quality-gate" && cd ../.. && pwd)/bin/qg-setup"
assert_eq "$VIA2" "$REPO_ROOT/bin/qg-setup" "20. vía symlink con cd -P: misma ruta del repositorio"
P=$(newp); OUT=$(cd "$P" && "$VIA" setup --status 2>&1); assert_match "$OUT" 'bloque: no instalado' "20. el script funciona invocado por la ruta del symlink"
assert_eq "$( [ -x "$REPO_ROOT/bin/qg-setup" ] && echo ejecutable)" ejecutable "20. plugin: bin/qg-setup ejecutable (bin/ va al PATH con --plugin-dir)"
SK=$(cat "$REPO_ROOT/skills/quality-gate/SKILL.md")
assert_match "$SK" '\$ARGUMENTS' "20. SKILL.md recibe los argumentos con \$ARGUMENTS"
assert_match "$SK" '\$\{CLAUDE_SKILL_DIR\}/\.\./\.\./bin/qg-setup' "20. SKILL.md indica la ruta del script"
assert_match "$SK" 'argument-hint: .*setup \[--scope project\|user\]' "20. argument-hint anuncia setup"

# Otros: instrucciones similares, errores de uso, nada fuera del alcance
P=$(newp); printf 'Usa /quality-gate siempre.\n' > "$P/CLAUDE.md"; h=$(sha "$P/CLAUDE.md"); st "$P" setup
assert_eq "$RC/$(sha "$P/CLAUDE.md")" "65/$h" "21. instrucciones similares fuera del bloque: no duplica (65)"
st "$P" setup --force; assert_eq "$RC/$(grep -c 'agent-quality-gate:start' "$P/CLAUDE.md")" "0/1" "21. --force: añade el bloque"
st "$P" setup --scope global; assert_eq "$RC" 64 "22. --scope inválido: 64"
st "$P" setup --status --remove; assert_eq "$RC" 64 "22. acciones incompatibles: 64"
st "$P" setup --file otro.md; assert_eq "$RC" 64 "22. --file fuera de lo permitido: 64"
st "$P" setup --scope user --file CLAUDE.md; assert_eq "$RC" 64 "22. --file con --scope user: 64"
st "$P" setup --bogus; assert_eq "$RC" 64 "22. opción desconocida: 64"
st "$P" --help; assert_match "$RC $OUT" '^0 uso: qg-setup' "22. --help"
before=$(find "$TESTS_TMP" -newer "$REF" -type f | grep -v '/p\.' | grep -v 'con espacios' | grep -vF "$HOME/.claude" | grep -v 'fuera' | sort | cksum)
P=$(newp); st "$P" setup; st "$P" setup --remove
after=$(find "$TESTS_TMP" -newer "$REF" -type f | grep -v '/p\.' | grep -v 'con espacios' | grep -vF "$HOME/.claude" | grep -v 'fuera' | sort | cksum)
assert_eq "$after" "$before" "23. no escribe fuera del proyecto"
no_tmp_left "$P" "23"
assert_eq "$(grep -cE '(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)' "$S")" 0 "24. el script no usa eval"

finish
