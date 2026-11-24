#!/usr/bin/env bash
# Pruebas de la huella (qg fingerprint).
. "$(dirname "$0")/lib.sh"

R=$(new_repo)
printf 'uno\n' > "$R/a.txt"; printf 'dos\n' > "$R/b.txt"
commit_all "$R" base
CLEAN=$(fp "$R")

# Repositorio limpio: estable y coincide con el árbol de HEAD
assert_eq "$(fp "$R")" "$CLEAN" "limpio: huella estable entre llamadas"
assert_match "$CLEAN" "^(sha1|sha256):$(git -C "$R" rev-parse 'HEAD^{tree}')\$" "limpio: huella = árbol de HEAD"
assert_match "$(fpj "$R")" '"index":"matches"' "limpio: índice coincide"

# Modificación de archivo versionado (unstaged)
printf 'uno-mod\n' > "$R/a.txt"
UNSTAGED=$(fp "$R")
assert_ne "$UNSTAGED" "$CLEAN" "unstaged: cambia la huella"
assert_match "$(fpj "$R")" '"index":"differs"' "unstaged: índice difiere del working tree"

# Cambio staged del mismo contenido: misma identidad de contenido, índice ahora coincide
git -C "$R" add a.txt
assert_eq "$(fp "$R")" "$UNSTAGED" "staged: la huella identifica el contenido (igual que unstaged)"
assert_match "$(fpj "$R")" '"index":"matches"' "staged: índice coincide con el working tree"

# Staged distinto del working tree: la huella sigue al working tree; el índice se informa aparte
printf 'uno-otra\n' > "$R/a.txt"
J=$(fpj "$R")
assert_ne "$(fp "$R")" "$UNSTAGED" "staged+unstaged: la huella sigue al working tree"
assert_match "$J" '"index":"differs"' "staged+unstaged: índice difiere (un commit no incluiría lo verificado)"
git -C "$R" reset -q --hard

# Volver al contenido original devuelve la huella original
assert_eq "$(fp "$R")" "$CLEAN" "revertir: vuelve la huella limpia"

# Archivo nuevo no versionado y su modificación sin renombrar
printf 'nuevo\n' > "$R/c.txt"; N1=$(fp "$R")
assert_ne "$N1" "$CLEAN" "nuevo archivo: cambia la huella"
printf 'nuevo-mod\n' > "$R/c.txt"; N2=$(fp "$R")
assert_ne "$N2" "$N1" "nuevo archivo modificado (mismo nombre): cambia la huella"
rm "$R/c.txt"

# Eliminado
rm "$R/b.txt"; DEL=$(fp "$R")
assert_ne "$DEL" "$CLEAN" "eliminado: cambia la huella"
git -C "$R" checkout -q -- b.txt

# Renombrado: con git mv o con mv, misma identidad (se basa en contenido)
git -C "$R" mv b.txt d.txt; RN1=$(fp "$R"); git -C "$R" mv d.txt b.txt
mv "$R/b.txt" "$R/d.txt"; RN2=$(fp "$R"); mv "$R/d.txt" "$R/b.txt"
assert_ne "$RN1" "$CLEAN" "renombrado: cambia la huella"
assert_eq "$RN2" "$RN1" "renombrado: git mv y mv dan la misma huella"
assert_eq "$(fp "$R")" "$CLEAN" "renombrado revertido: huella limpia"

# Archivos ignorados: fuera del alcance (documentado)
printf 'secreto.env\n' > "$R/.gitignore"; commit_all "$R" ignore; IGN=$(fp "$R")
printf 'TOKEN=x\n' > "$R/secreto.env"
assert_eq "$(fp "$R")" "$IGN" "ignorado: no altera la huella"
printf 'TOKEN=y\n' > "$R/secreto.env"
assert_eq "$(fp "$R")" "$IGN" "ignorado modificado: no altera la huella"

# Enlace simbólico: se identifica por su destino, no por el contenido apuntado
ln -s a.txt "$R/l"; L1=$(fp "$R")
assert_ne "$L1" "$IGN" "symlink nuevo: cambia la huella"
rm "$R/l"; ln -s b.txt "$R/l"; L2=$(fp "$R")
assert_ne "$L2" "$L1" "symlink redirigido: cambia la huella"
rm "$R/l"

# Binario: un byte distinto cambia la huella
printf '\000\001\002' > "$R/bin.dat"; B1=$(fp "$R")
printf '\000\001\003' > "$R/bin.dat"; B2=$(fp "$R")
assert_ne "$B2" "$B1" "binario: un byte cambia la huella"
rm "$R/bin.dat"

# Bit de ejecución (core.fileMode=true por defecto en Linux/macOS)
chmod +x "$R/a.txt"
assert_ne "$(fp "$R")" "$IGN" "chmod +x: cambia la huella"
chmod -x "$R/a.txt"

# Nombres con espacios y salto de línea
nl_name="$R/con espacio
y salto.txt"
printf 'x\n' > "$nl_name"
WS=$(fp "$R")
assert_ne "$WS" "$IGN" "nombre con espacio y salto de línea: cambia la huella"
rm "$nl_name"

# Invocación desde un subdirectorio: misma huella (alcance = todo el repositorio)
mkdir -p "$R/sub"; printf 'x\n' > "$R/sub/s.txt"; commit_all "$R" sub
assert_eq "$(qg -C "$R/sub" fingerprint)" "$(fp "$R")" "subdirectorio: misma huella que desde la raíz"

# No modifica el índice ni el almacén de objetos del repositorio
printf 'mod\n' > "$R/a.txt"; printf 'untracked\n' > "$R/u.txt"
idx_before=$(cksum < "$R/.git/index")
obj_before=$(find "$R/.git/objects" -type f | wc -l | tr -d ' ')
fp "$R" >/dev/null; fp "$R" >/dev/null
assert_eq "$(cksum < "$R/.git/index")" "$idx_before" "sin efectos: .git/index intacto"
assert_eq "$(find "$R/.git/objects" -type f | wc -l | tr -d ' ')" "$obj_before" "sin efectos: .git/objects intacto"
assert_eq "$(git -C "$R" status --porcelain | sort | tr '\n' ' ')" " M a.txt ?? u.txt " "sin efectos: git status igual"
git -C "$R" checkout -q -- a.txt; rm "$R/u.txt"

# Repositorio sin commits
E=$(new_repo)
EMPTY_TREE=$(git -C "$E" hash-object -t tree /dev/null)
assert_match "$(fp "$E")" ":$EMPTY_TREE\$" "sin commits y vacío: árbol vacío"
printf 'x\n' > "$E/f"; E1=$(fp "$E")
assert_eq "$(fp "$E")" "$E1" "sin commits con archivo: estable"
assert_match "$(fpj "$E")" '"head":"unborn"' "sin commits: head=unborn"

# Worktrees: huellas y estados independientes
W="$TESTS_TMP/wt-$$"
git -C "$R" worktree add -q "$W" -b otra >/dev/null 2>&1
MAIN_FP=$(fp "$R")
assert_eq "$(fp "$W")" "$MAIN_FP" "worktree limpio en el mismo commit: misma huella"
printf 'solo en wt\n' > "$W/a.txt"
assert_ne "$(fp "$W")" "$MAIN_FP" "worktree modificado: su huella cambia"
assert_eq "$(fp "$R")" "$MAIN_FP" "worktree modificado: la del principal no cambia"
assert_ne "$(state_dir "$W")" "$(state_dir "$R")" "worktree: directorio de estado propio"

# Sin Git: error explícito, nunca una huella
NG=$(mktemp -d "$TESTS_TMP/nogit.XXXXXX")
out=$(cd "$NG" && GIT_CEILING_DIRECTORIES="$TESTS_TMP" qg fingerprint 2>&1); rc=$?
assert_eq "$rc" 65 "sin Git: código 65"
assert_match "$out" "no es un repositorio Git" "sin Git: mensaje claro"

finish
