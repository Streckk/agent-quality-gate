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

# --- ronda de correcciones 1: nunca read-only por error
F=$(new_repo)
cat > "$F/package.json" <<'JSON'
{
  "scripts": {
    "u1": "eslint . \u0026\u0026 rm -rf dist",
    "u2": "eslint .\u000a--fix",
    "u3": "eslint . \u003e salida.txt",
    "snap": "jest -u",
    "snap2": "jest",
    "bg": "eslint . & rm -rf dist",
    "amp": "eslint . &> out.txt",
    "var": "eslint $FLAGS",
    "var2": "eslint \"${FLAGS}\"",
    "lit": "eslint '$FLAGS'"
  },
  "scripts": {
    "ok": "eslint .",
    "snap2": "jest",
    "gosrc": "go mod tidy"
  }
}
JSON
assert_ne "$(cls "$F" npm run ok)" unknown "scripts duplicado: gana el último (ok existe)"
assert_eq "$(cls "$F" npm run u1)" unknown "scripts duplicado: el primero se descarta"
G=$(new_repo)
cat > "$G/package.json" <<'JSON'
{ "scripts": {
  "u1": "eslint . \u0026\u0026 rm -rf dist",
  "u2": "eslint .\u000a--fix",
  "u3": "eslint . \u003e salida.txt",
  "snap": "jest -u",
  "snap2": "jest",
  "snap3": "jest --updateSnapshot",
  "bg": "eslint . & rm -rf dist",
  "bg2": "eslint . &",
  "amp": "eslint . &> out.txt",
  "amp2": "eslint . >& out.txt",
  "var": "eslint $FLAGS",
  "var2": "eslint \"${FLAGS}\"",
  "lit": "eslint '$FLAGS' && echo \"a & b\"",
  "devnull": "eslint . &>/dev/null",
  "fd": "eslint . 2>&1"
} }
JSON
assert_eq "$(cls "$G" npm run u1)" unknown "\\u0026\\u0026 se decodifica: eslint . && rm -rf dist no es read-only"
assert_nomatch "$(cls "$G" npm run u2)" '^read-only$' "\\u000a --fix no es read-only"
assert_eq "$(cls "$G" npm run u2)" unknown "u000a(salto)--fix → no es read-only"
assert_eq "$(cls "$G" npm run u3)" writes-generated "\\u003e (>) se decodifica como redirección"
U=$(new_repo); printf '{"scripts":{"u4":"eslint . %su00e9"}}\n' '\' > "$U/package.json"
assert_eq "$(cls "$U" npm run u4)" unknown "\\u no ASCII → parse_error (unknown)"
assert_match "$(clsj "$U" npm run u4)" 'parse_error' "\\u no ASCII: parse_error"
assert_eq "$(cls "$G" npm run snap)" writes-source "jest -u en un script → writes-source"
assert_eq "$(cls "$G" npm run snap3)" writes-source "jest --updateSnapshot → writes-source"
assert_eq "$(cls "$G" npm run snap2)" read-only "jest sin -u → read-only"
assert_eq "$(cls "$G" npm run snap2 -- -u)" writes-source "npm run a -- -u → writes-source"
assert_eq "$(cls "$G" jest -u)" writes-source "jest -u → writes-source"
assert_eq "$(cls "$G" vitest run -u)" writes-source "vitest -u → writes-source"
assert_eq "$(cls "$G" playwright test --update-snapshots)" writes-source "playwright --update-snapshots → writes-source"
assert_eq "$(cls "$G" pytest --snapshot-update)" writes-source "pytest --snapshot-update → writes-source"
assert_eq "$(cls "$G" biome check --apply .)" writes-source "biome --apply → writes-source"
assert_eq "$(cls "$G" biome check --apply-unsafe .)" writes-source "biome --apply-unsafe → writes-source"
assert_eq "$(cls "$G" biome check .)" read-only "biome check → read-only"
assert_eq "$(cls "$G" go test ./...)" read-only "go test → read-only"
assert_eq "$(cls "$G" go vet ./...)" read-only "go vet → read-only"
# Flags de Go de un guion con "u" (-run, -count, -timeout, -cpu): no son -u agrupado
assert_eq "$(cls "$G" go test -run TestAuth)" read-only "go test -run TestAuth → read-only"
assert_eq "$(cls "$G" go test -count 1)" read-only "go test -count 1 → read-only"
assert_eq "$(cls "$G" go test -timeout 30s)" read-only "go test -timeout 30s → read-only"
assert_eq "$(cls "$G" go test -cpu 4 ./...)" read-only "go test -cpu 4 → read-only"
assert_eq "$(cls "$G" go test -run TestUpdate -count=1 -timeout 30s -race ./...)" read-only "flags de Go combinados → read-only"
assert_eq "$(cls "$G" go test -run=TestAuth ./...)" read-only "go test -run=X → read-only"
assert_eq "$(cls "$G" go vet -unusedresult ./...)" read-only "go vet -unusedresult → read-only"
assert_eq "$(cls "$G" bash -c "go test -run TestAuth -count 1 ./...")" read-only "go test -run dentro de bash -c → read-only"
assert_eq "$(cls "$G" go test -run TestAuth -u)" writes-source "go con -u literal sigue siendo writes-source"
assert_eq "$(cls "$G" go get -u ./...)" writes-source "go get -u → writes-source"
assert_eq "$(cls "$G" go test ./... -update)" writes-source "go test -update (golden) → writes-source"
assert_eq "$(cls "$G" go test ./... -update=true)" writes-source "go test -update=true → writes-source"
assert_eq "$(cls "$G" go test ./... -update-golden)" writes-source "go test -update-golden → writes-source"
assert_eq "$(cls "$G" go test ./... -golden)" writes-source "go test -golden → writes-source"
assert_eq "$(cls "$G" go test -run TestAuth ">" out.txt)" writes-generated "go test -run con redirección → writes-generated"
assert_eq "$(cls "$G" vitest -u)" writes-source "vitest -u → writes-source"
assert_eq "$(cls "$G" eslint --fix .)" writes-source "eslint --fix → writes-source"
assert_eq "$(cls "$G" jest -cu)" writes-source "jest -cu (agrupado) → writes-source"
assert_eq "$(cls "$G" vitest run -wu)" writes-source "vitest -wu (agrupado) → writes-source"
assert_eq "$(cls "$G" jest --ci -u)" writes-source "jest --ci -u → writes-source"
assert_eq "$(cls "$G" vitest run -uw)" writes-source "vitest -uw (u primero en el grupo) → writes-source"
assert_eq "$(cls "$G" jest -ci)" read-only "jest -ci (grupo sin u) → read-only"
assert_eq "$(cls "$G" eslint -w .)" writes-source "-w sigue detectándose → writes-source"
assert_eq "$(cls "$G" cargo clippy)" read-only "cargo clippy → read-only"
assert_eq "$(cls "$G" cargo check)" read-only "cargo check → read-only"
assert_eq "$(cls "$G" go run .)" unknown "go run → unknown"
assert_eq "$(cls "$G" cargo run)" unknown "cargo run → unknown"
assert_eq "$(cls "$G" cargo fmt)" writes-source "cargo fmt → writes-source"
assert_eq "$(cls "$G" cargo update)" writes-source "cargo update → writes-source"
assert_eq "$(cls "$G" go get x)" writes-source "go get → writes-source"
assert_eq "$(cls "$G" go mod tidy)" writes-source "go mod tidy → writes-source"
assert_eq "$(cls "$G" cargo publish)" external-side-effects "cargo publish → external"
assert_eq "$(cls "$G" cargo build)" writes-generated "cargo build → writes-generated"
assert_eq "$(cls "$G" cargo install x)" installs-dependencies "cargo install → installs"
assert_eq "$(cls "$G" go)" unknown "go sin subcomando → unknown"
assert_eq "$(cls "$G" npm run bg)" unknown "eslint . & rm -rf dist → no read-only"
assert_eq "$(cls "$G" npm run bg2)" read-only "eslint . & (segundo vacío) → read-only"
assert_eq "$(cls "$G" npm run amp)" writes-generated "&> archivo → redirección"
assert_eq "$(cls "$G" npm run amp2)" writes-generated ">& archivo → redirección"
assert_eq "$(cls "$G" npm run devnull)" read-only "&>/dev/null no es escritura"
assert_eq "$(cls "$G" npm run fd)" read-only "2>&1 no es escritura"
assert_eq "$(cls "$G" npm run var)" unknown "eslint \$FLAGS → unknown"
assert_match "$(clsj "$G" npm run var)" 'expansion' "\$FLAGS: motivo expansion"
assert_eq "$(cls "$G" npm run var2)" unknown "\"\${FLAGS}\" → unknown"
assert_eq "$(cls "$G" npm run lit)" read-only "\$ entre comillas simples y & entre comillas dobles → read-only"
# make: el globbing no se aplica a los prerequisitos
H=$(new_repo); printf 'all: *\n\teslint .\n' > "$H/Makefile"; : > "$H/zzz"
assert_eq "$(cls "$H" make all)" unknown "prerequisito con comodín no se expande ni se ejecuta"

# Monorepos: cd, workspaces y el package.json más cercano (nunca el de otro directorio)
W=$(new_repo); mkdir -p "$W/api/src" "$W/web"
printf '{"scripts":{"verify":"cd api && npm run check","verify2":"pushd api && npm run check; popd","check":"tsc --noEmit"}}\n' > "$W/package.json"
printf '{"scripts":{"check":"prisma migrate deploy && tsc --noEmit"}}\n' > "$W/api/package.json"
assert_eq "$(cls "$W" npm run verify)" unknown "cd api && npm run check (script raíz) → unknown, no read-only"
assert_match "$(clsj "$W" npm run verify)" 'cwd_change' "cd dentro del script: motivo cwd_change"
assert_eq "$(cls "$W" npm run verify2)" unknown "pushd/popd → unknown"
assert_eq "$(cls "$W" cd api)" unknown "cd suelto → unknown (cwd_change)"
assert_eq "$(cls "$W" npm run check -w api)" unknown "npm run check -w api → unknown, no el check de la raíz"
assert_match "$(clsj "$W" npm run check -w api)" 'workspace' "-w: motivo workspace"
assert_eq "$(cls "$W" npm run check --workspace api)" unknown "--workspace api → unknown"
assert_eq "$(cls "$W" npm run check --workspace=api)" unknown "--workspace=api → unknown"
assert_eq "$(cls "$W" npm --workspaces run check)" unknown "--workspaces → unknown"
assert_eq "$(cls "$W" pnpm --filter api check)" unknown "pnpm --filter → unknown"
assert_eq "$(cls "$W" pnpm -F api check)" unknown "pnpm -F → unknown"
assert_eq "$(cls "$W" pnpm -r check)" unknown "pnpm -r → unknown"
assert_eq "$(cls "$W" pnpm --recursive run check)" unknown "pnpm --recursive → unknown"
assert_eq "$(cls "$W" pnpm -C api check)" unknown "pnpm -C api → unknown"
assert_match "$(clsj "$W" pnpm -C api check)" 'cwd_change' "pnpm -C: motivo cwd_change"
assert_eq "$(cls "$W" npm --prefix api run check)" unknown "npm --prefix api → unknown"
assert_eq "$(cls "$W" npm --prefix=api run check)" unknown "npm --prefix=api → unknown"
assert_eq "$(cls "$W" pnpm --dir api check)" unknown "pnpm --dir → unknown"
assert_eq "$(cls "$W" yarn --cwd api check)" unknown "yarn --cwd → unknown"
assert_eq "$(cls "$W" bun --cwd=api run check)" unknown "bun --cwd= → unknown"
assert_eq "$(cls "$W" npm run check)" read-only "sin cambio de directorio: el check de la raíz sigue siendo read-only"
assert_eq "$(cls "$W/api/src" npm run check)" external-side-effects "desde api/src se usa api/package.json (el más cercano), no el de la raíz"
assert_match "$(clsj "$W/api/src" npm run check)" 'api/package.json' "el origen citado es api/package.json"
assert_eq "$(cls "$W/web" npm run check)" read-only "sin package.json en web/: sube hasta la raíz del repo"

# Huecos baratos: --updateSnapshot=*, --update-snapshots=*, --force-regen, >| y -u en racimos
assert_eq "$(cls "$G" jest --updateSnapshot=true)" writes-source "--updateSnapshot=true → writes-source"
assert_eq "$(cls "$G" playwright test --update-snapshots=all)" writes-source "--update-snapshots=all → writes-source"
assert_eq "$(cls "$G" pytest --force-regen)" writes-source "pytest --force-regen → writes-source"
assert_eq "$(cls "$G" jest -bu)" writes-source "jest -bu (racimo con u) → writes-source"
assert_eq "$(cls "$G" jest -b)" read-only "jest -b → read-only"
assert_eq "$(cls "$G" eslint . '>|' out.txt)" writes-generated ">| archivo → redirección"
assert_eq "$(cls "$G" eslint . '>|out.txt')" writes-generated ">|archivo → redirección"
assert_match "$(clsj "$G" eslint . '>|out.txt')" 'redirección a out.txt' ">|archivo: el destino se cita sin la barra"
K=$(new_repo); printf '{"scripts":{"clob":"eslint . >| out.txt"}}\n' > "$K/package.json"
assert_eq "$(cls "$K" npm run clob)" writes-generated ">| dentro de un script no se parte como tubería"
assert_match "$(clsj "$W" pnpm -F api check)" 'workspace' "pnpm -F: motivo workspace"
assert_match "$(clsj "$W" yarn workspace api check)" 'workspace' "yarn workspace: motivo workspace"

finish
