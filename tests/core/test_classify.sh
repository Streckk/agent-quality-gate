#!/usr/bin/env bash
# Pruebas de qg classify: clasificación previa de efectos secundarios (nunca ejecuta el comando).
. "$(dirname "$0")/lib.sh"

# cls <dir> <cmd…> → clase en texto ("clase: x")
cls()  { qg -C "$1" classify -- "${@:2}" 2>&1 | sed -n 's/^clase: //p'; }
clsj() { qg -C "$1" classify --json -- "${@:2}" 2>&1; }
jclass() { printf '%s' "$1" | sed -n 's/^{"class":"\([^"]*\)".*/\1/p'; }

D=$(new_repo)
mkdir -p "$D/scripts"
cat > "$D/package.json" <<'JSON'
{
  "name": "demo",
  "version": "1.0.0",
  "config": { "scripts": { "falso": "rm -rf /" } },
  "scripts": {
    "lint": "eslint .",
    "lint:fix": "eslint . --fix",
    "format": "prettier --write .",
    "typecheck": "pnpm install && tsc --noEmit",
    "typecheck2": "tsc --noEmit",
    "gen": "codegen --out src/gen",
    "wrap": "npm run lint",
    "wrap2": "npm run wrap",
    "wrapinst": "npm run setup && tsc --noEmit",
    "setup": "pnpm install",
    "ambiguo": "node scripts/check.js",
    "quoted": "echo \"a && b\" && eslint .",
    "esc": "eslint --rule \"{\\\"x\\\": 1}\" .",
    "deploy": "./scripts/deploy.sh",
    "test": "vitest run",
    "pretest": "pnpm install"
  }
}
JSON
printf 'echo hola\n' > "$D/scripts/ok.sh"

assert_eq "$(cls "$D" eslint .)" read-only "eslint . → read-only"
assert_eq "$(cls "$D" eslint --fix .)" writes-source "eslint --fix → writes-source"
assert_eq "$(cls "$D" prettier --write .)" writes-source "prettier --write → writes-source"
assert_eq "$(cls "$D" npm run format)" writes-source "npm run format (prettier --write) → writes-source"
assert_eq "$(cls "$D" npm run lint)" read-only "npm run lint → read-only (lee el script)"
assert_eq "$(cls "$D" npm run lint:fix)" writes-source "script con --fix → writes-source"
assert_eq "$(cls "$D" pnpm run typecheck)" installs-dependencies "pnpm run typecheck (pnpm install && tsc) → installs-dependencies"
assert_eq "$(cls "$D" npm run typecheck2)" read-only "tsc --noEmit → read-only"
assert_eq "$(cls "$D" npm run gen)" writes-generated "script codegen → writes-generated"
assert_eq "$(cls "$D" prisma migrate deploy)" external-side-effects "prisma migrate deploy → external-side-effects"
assert_eq "$(cls "$D" docker push img)" external-side-effects "docker push → external"
assert_eq "$(cls "$D" terraform apply)" external-side-effects "terraform apply → external"
assert_eq "$(cls "$D" kubectl apply -f x.yaml)" external-side-effects "kubectl apply → external"
assert_eq "$(cls "$D" curl -X POST https://example.invalid/x)" external-side-effects "curl -X POST → external"
assert_eq "$(cls "$D" npm install)" installs-dependencies "npm install → installs"
assert_eq "$(cls "$D" npm ci)" installs-dependencies "npm ci → installs"
assert_eq "$(cls "$D" npx eslint .)" installs-dependencies "npx sin --no-install → installs"
assert_eq "$(cls "$D" npx --no-install eslint .)" read-only "npx --no-install eslint → read-only"
assert_eq "$(cls "$D" npm run build)" unknown "build sin script en package.json → unknown (script_inexistente)"
assert_match "$(clsj "$D" npm run build)" 'script_inexistente' "build inexistente: motivo script_inexistente"

# Indirección: un nivel se resuelve, dos → unknown (indirect)
assert_eq "$(cls "$D" npm run wrap)" read-only "indirecto de un nivel (wrap → lint) → read-only"
assert_eq "$(cls "$D" npm run wrapinst)" installs-dependencies "indirecto: la instalación del segundo nivel se ve"
assert_eq "$(cls "$D" npm run wrap2)" unknown "dos niveles de indirección → unknown"
assert_match "$(clsj "$D" npm run wrap2)" 'indirect' "dos niveles: motivo indirect"

# Inexistentes y ambiguos
assert_eq "$(cls "$D" herramienta-que-no-existe-xyz --check)" unknown "comando inexistente → unknown"
assert_match "$(clsj "$D" herramienta-que-no-existe-xyz)" 'not_found' "comando inexistente: motivo not_found"
assert_eq "$(cls "$D" npm run ambiguo)" unknown "script ambiguo (node script.js) → unknown"
assert_eq "$(cls "$D" npm run deploy)" external-side-effects "script deploy que llama a un .sh inexistente: indicio externo gana a unknown"
assert_match "$(clsj "$D" npm run deploy)" 'deploy' "deploy: el nombre del script se cita como indicio"
assert_eq "$(cls "$D" make test)" unknown "make sin Makefile → unknown"
assert_match "$(clsj "$D" make test)" 'not_found' "make sin Makefile: not_found"

# Entradas entrecomilladas y escapadas en package.json
assert_eq "$(cls "$D" npm run quoted)" read-only "valor con comillas escapadas y && dentro de cadena"
assert_eq "$(cls "$D" npm run esc)" read-only "valor con \\\" escapados se lee entero"
# "scripts" anidado en otra clave no cuenta
printf '{"config":{"scripts":{"x":"eslint ."}},"name":"n"}\n' > "$D/otro.json"
E=$(new_repo); cp "$D/otro.json" "$E/package.json"
assert_eq "$(cls "$E" npm run x)" unknown "scripts anidado en config no se usa → unknown"
# pre<script> se inspecciona
assert_eq "$(cls "$D" npm test)" installs-dependencies "npm test hereda pretest (pnpm install)"

# package.json roto → unknown parse_error
B=$(new_repo); printf '{"scripts": {"a": "eslint ." "b": 1}\n' > "$B/package.json"
assert_eq "$(cls "$B" npm run a)" unknown "package.json inválido → unknown"
assert_match "$(clsj "$B" npm run a)" 'parse_error' "package.json inválido: parse_error"
B2=$(new_repo); printf '{"scripts": {"a": 5}}\n' > "$B2/package.json"
assert_match "$(clsj "$B2" npm run a)" 'parse_error' "script que no es cadena: parse_error"
# sin package.json
N=$(new_repo)
assert_match "$(clsj "$N" npm run lint)" 'not_found' "sin package.json: not_found"
assert_eq "$(cls "$N" npm run lint)" unknown "sin package.json → unknown"

# pnpm con verify-deps-before-run=install
P=$(new_repo)
printf '{"scripts":{"lint":"eslint ."}}\n' > "$P/package.json"
assert_eq "$(cls "$P" pnpm run lint)" read-only "pnpm sin ajuste: read-only"
printf '# c\nverify-deps-before-run = install\n' > "$P/.npmrc"
assert_eq "$(cls "$P" pnpm run lint)" installs-dependencies "pnpm + .npmrc verify-deps-before-run=install → installs"
assert_eq "$(cls "$P" pnpm lint)" installs-dependencies "pnpm <script> con auto-instalación → installs"
assert_eq "$(cls "$P" npm run lint)" read-only "npm no se ve afectado por el ajuste de pnpm"
assert_match "$(clsj "$P" pnpm run lint)" 'verify-deps-before-run' "motivo cita el ajuste documentado"
rm "$P/.npmrc"; printf 'verifyDepsBeforeRun: install\n' > "$P/pnpm-workspace.yaml"
assert_eq "$(cls "$P" pnpm run lint)" installs-dependencies "pnpm-workspace.yaml verifyDepsBeforeRun: install → installs"
printf 'verifyDepsBeforeRun: warn\n' > "$P/pnpm-workspace.yaml"
assert_eq "$(cls "$P" pnpm run lint)" read-only "verifyDepsBeforeRun: warn no instala"

# make y bash <archivo>
M=$(new_repo)
printf 'lint:\n\teslint .\n\ngen:\n\t@codegen --out x\n\nall: lint gen\n\ndist: lint\n\t$(MAKE) other\n\nfmt:\n\tprettier --write .\n' > "$M/Makefile"
assert_eq "$(cls "$M" make lint)" read-only "make lint → read-only"
assert_eq "$(cls "$M" make gen)" writes-generated "make gen → writes-generated"
assert_eq "$(cls "$M" make fmt)" writes-source "make fmt → writes-source"
assert_eq "$(cls "$M" make all)" writes-generated "make con prerequisitos: se inspecciona un nivel"
assert_eq "$(cls "$M" make dist)" unknown "make con \$(MAKE) → unknown"
assert_eq "$(cls "$M" make nada)" unknown "make objetivo inexistente → unknown"
printf 'set -e\neslint .\nnpm publish\n' > "$M/pub.sh"
printf 'set -e\neslint .\n' > "$M/ro.sh"
printf 'eslint .\n./otro.sh\n' > "$M/ind.sh"
assert_eq "$(cls "$M" bash pub.sh)" external-side-effects "bash archivo con npm publish → external"
assert_eq "$(cls "$M" bash ro.sh)" read-only "bash archivo solo eslint → read-only"
assert_eq "$(cls "$M" bash ind.sh)" unknown "bash archivo que llama a otro → unknown"
assert_eq "$(cls "$M" bash noexiste.sh)" unknown "bash archivo inexistente → unknown"
assert_match "$(clsj "$M" bash noexiste.sh)" 'not_found' "bash inexistente: not_found"

# Rutas con espacios y -C
S=$(new_repo); mkdir -p "$S/mi carpeta"
printf '{"scripts":{"gen":"codegen"}}\n' > "$S/mi carpeta/package.json"
assert_eq "$(cls "$S/mi carpeta" npm run gen)" writes-generated "ruta con espacios (-C)"
printf 'eslint .\n' > "$S/mi carpeta/mi script.sh"
assert_eq "$(cls "$S/mi carpeta" bash "mi script.sh")" read-only "archivo con espacios en el nombre"
assert_match "$(qg -C "$S/mi carpeta" classify -- bash "mi script.sh" 2>&1)" 'mi script.sh' "texto cita el origen inspeccionado"

# JSON y redacción
J=$(clsj "$D" eslint --token=abc123 .)
assert_match "$J" '^\{"class":"read-only","reasons":\[.*\],"source":.*,"command":".*"\}$' "JSON con class, reasons, source y command"
assert_nomatch "$J" 'abc123' "el comando se redacta en el JSON"
assert_eq "$(jclass "$(clsj "$D" npm run lint:fix)")" writes-source "JSON: class"
T=$(qg -C "$D" classify -- npm run lint:fix 2>&1)
assert_match "$T" 'clase: writes-source' "texto: clase"
assert_match "$T" 'package.json' "texto: origen inspeccionado"
assert_match "$T" '--fix' "texto: motivo"

# Nunca ejecuta nada
X=$(new_repo); printf '{"scripts":{"boom":"touch EJECUTADO && eslint ."}}\n' > "$X/package.json"
printf 'touch EJECUTADO2\n' > "$X/boom.sh"
qg -C "$X" classify -- npm run boom >/dev/null 2>&1; qg -C "$X" classify -- bash boom.sh >/dev/null 2>&1
qg -C "$X" classify -- touch EJECUTADO3 >/dev/null 2>&1
assert_file_absent "$X/EJECUTADO" "classify no ejecuta scripts de package.json"
assert_file_absent "$X/EJECUTADO2" "classify no ejecuta archivos de shell"
assert_file_absent "$X/EJECUTADO3" "classify no ejecuta el comando"

# Uso
qg -C "$D" classify >/dev/null 2>&1; assert_eq "$?" 64 "sin comando → 64"
qg -C "$D" classify -- >/dev/null 2>&1; assert_eq "$?" 64 "'--' sin comando → 64"
qg -C "$D" classify --bogus -- eslint . >/dev/null 2>&1; assert_eq "$?" 64 "opción desconocida → 64"
qg -C "$D" classify -- eslint . >/dev/null 2>&1; assert_eq "$?" 0 "exit 0 si se pudo analizar"
qg -C "$D" classify -- npm run ambiguo >/dev/null 2>&1; assert_eq "$?" 0 "exit 0 también con unknown"
assert_match "$(qg help)" 'classify' "ayuda menciona classify"
assert_match "$(qg version --json)" '"interface":4' "interfaz sigue en 4"
# fuera de un repositorio también funciona (no lee estado)
O=$(mktemp -d "$TESTS_TMP/fuera.XXXXXX"); printf '{"scripts":{"l":"eslint ."}}\n' > "$O/package.json"
assert_eq "$(cls "$O" npm run l)" read-only "fuera de un repo Git"

finish
