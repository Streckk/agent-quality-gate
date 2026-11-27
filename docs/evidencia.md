# Evidencia ejecutable: `qg` (v0.2.0-dev)

`qg` es un ejecutable pequeño (bash + git) que registra **qué código se verificó, con qué comando, con qué resultado real y si esa evidencia sigue vigente**. Funciona desde la terminal, sin Claude Code, Codex ni Graphify, y no depende del stack del proyecto.

No es un orquestador. Cada invocación de `qg run` ejecuta **un** comando. Decidir qué verificar sigue siendo trabajo de la skill (`/quality-gate`) o de la persona.

```text
bin/qg            fingerprint | run | baseline | classify | require | status | reject | show | gc | version | session | hooks
bin/qg-run        alias de `qg run`
```

Requisitos: `bash >= 3.2` y `git >= 2.25`. No usa jq, Node ni Python.

Integración con la skill: [evidence-qg.md](../skills/quality-gate/references/evidence-qg.md). Validación: [validacion-v0.2.0-dev.md](validacion-v0.2.0-dev.md).

## Uso rápido

```bash
export PATH="$HOME/Desarrollo/agent-quality-gate/bin:$PATH"
cd mi-proyecto
qg require lint unit                 # verificaciones obligatorias para este worktree
qg-run lint -- npm run lint          # ejecuta y registra (devuelve el exit code real)
qg-run unit -- pytest -q
qg status                            # valid | failed | blocked | incomplete | stale | missing
vim src/app.py                       # cualquier cambio...
qg status                            # ...deja la evidencia en stale
```

## 1. Huella (`qg fingerprint`)

**Definición:** la huella es el identificador del árbol Git que resultaría de `git add -A` sobre el working tree actual, con el formato `<formato>:<oid>` (p. ej. `sha1:0858…`). Incluye:

| Incluido | Cómo |
|---|---|
| archivos versionados, modificados o no | contenido actual del working tree |
| cambios staged | cuentan por su contenido en el working tree (lo que ejecutan las pruebas) |
| archivos nuevos no versionados y **no ignorados** | contenido |
| eliminados | ausentes del árbol |
| renombrados | `git mv` y `mv` dan la misma huella (la identidad es el contenido) |
| bit de ejecución | si `core.fileMode=true` |
| enlaces simbólicos | por su **destino** (texto del enlace), no por el contenido apuntado |
| binarios | por contenido, igual que el texto |

Cómo se calcula:
1. Se copia el índice a un archivo temporal con `cp -p`, que conserva el mtime para que siga funcionando la detección de entradas "racy" de Git.
2. Se ejecuta `git add -A` y `git write-tree --missing-ok` con `GIT_INDEX_FILE` y un `GIT_OBJECT_DIRECTORY` temporal, **sin** el almacén real como alternativo.

**No se modifica el índice ni `.git/objects` del repositorio, ni siquiera el mtime de los objetos** (lo comprueban las pruebas). Corrección v0.2.0-dev: con el almacén real como alternativo, git "refrescaba" (*freshen*) el mtime de los objetos existentes.

Propiedades:

- **Estable:** el mismo contenido da la misma huella, con independencia de mtimes, del directorio desde el que se invoque o del worktree.
- **Repo limpio:** la huella es igual a `HEAD^{tree}`. Commitear el contenido ya verificado no invalida la evidencia.
- **Repos sin commits:** funciona; vacío = árbol vacío; `head=unborn`.
- **Por contenido:** si se revierte al contenido verificado, la evidencia vuelve a ser válida, porque es el mismo código.

El **índice** se informa aparte (`qg fingerprint --json` → `index: matches|differs|conflicted`). Si difiere, un commit incluiría contenido distinto del verificado; `qg status` lo advierte, pero no invalida la evidencia del working tree.

### Fuera del alcance o con matices (limitaciones conocidas)

| Caso | Comportamiento |
|---|---|
| archivos **ignorados** (`.gitignore`, `info/exclude`) | no forman parte de la huella. Si las pruebas dependen de `.env`, `node_modules`, etc., sus cambios no invalidan la evidencia |
| submódulos | cuenta el commit del submódulo, no sus cambios sin commitear |
| filtros *clean*/*process* (p. ej. git-lfs o filtros propios) | **se neutralizan** (`-c filter.<driver>.clean=` / `process=` / `required=false` en `add` **y** en `write-tree`, que también los ejecutaba al comprobar entradas "racy"): calcular la huella no ejecuta procesos externos. Consecuencia: un archivo filtrado que cambia se identifica por su contenido **sin filtrar**; uno modificado y luego restaurado puede dar una huella distinta de `HEAD^{tree}` (evidencia `stale` de más, nunca `valid` de más) |
| `core.autocrlf`, `eol`, `ident`, `working-tree-encoding` | se aplican (conversiones internas de Git, sin procesos externos) |
| sparse-checkout | no probado |
| directorios vacíos | Git no los representa |
| cambios **mientras se calcula** la huella | el cálculo no es una instantánea atómica del sistema de archivos. `qg run` calcula la huella antes y después; si difieren, la evidencia queda `stale` (`changed_during_run`). Un cambio que se revierte durante la ejecución no se detecta |
| sin Git | `qg` termina con código 65 y un mensaje claro; **no** emite una huella "aproximada" |
| SHA-1 | Git usa SHA-1 endurecido (o SHA-256 si el repo lo usa). Suficiente para detectar cambios accidentales, no para resistir a un adversario |

## 2. Ejecutor (`qg run` / `qg-run`)

```text
qg run [--timeout S] [--grace S] [--run-id ID] <check-id> -- <comando> [args…]
```

- **Sin shell intermedio ni `eval`:** el comando se ejecuta con `exec "$@"`. Los argumentos se pasan literalmente (espacios, `$HOME`, `*`, `;` no se expanden). Solo se ejecutan programas externos: ni builtins ni funciones de `qg`. Si necesitas un pipeline, invoca la shell de forma explícita (`-- sh -c '…'`) y asume esa responsabilidad.
- **Procesos:** el comando corre en su propio grupo de procesos (job control). Tras un timeout o una interrupción se termina el grupo entero, incluidos los procesos nietos.
- **stdin** es `/dev/null`, para que una verificación no se quede esperando entrada.
- **stdout/stderr** se transmiten tal cual y **no se guardan**. El registro no contiene la salida.
- **Timeout:** `--timeout` (por defecto `QG_TIMEOUT` o 3600 s; `0` = sin límite). Al vencer se envía TERM al grupo y, tras `--grace` segundos (10 por defecto), KILL.
- **Señales:** INT/TERM/HUP se reenvían al grupo. Una segunda señal fuerza KILL.
- **No instala ni descarga nada**, y comprueba que el ejecutable exista antes de lanzarlo.

Códigos de salida de `qg run`:

| Situación | `status` en el registro | exit de `qg` |
|---|---|---|
| el comando terminó | `completed` | el código real del comando |
| timeout | `timeout` | 124 |
| interrumpido por señal n | `interrupted` (+ `signal`) | 128+n |
| no existe / no es ejecutable | `error` (+ `error=not_found/not_executable`) | 127 / 126 |
| error de uso / estado o Git | (sin registro, o registro sin completar) | 64 / 65 |

Que el comando termine con `exit 0` **no** aprueba el cambio. Solo significa que esa verificación pasó sobre esa huella.

### Qué se registra (y qué no)

`check_id`, `run_id`, `status`, `exit_code`, `signal`, `error`, `fp_start`, `fp_end`, `changed_during_run`, `index_start`, `head_start`, `started_at`/`finished_at` (UTC), `duration_s`, `timeout_s`, `pid`, `host`, `cwd`, `argc` y `argv` **redactado**.

Redacción de argv: los valores de argumentos como `--token=…`, `PASSWORD=…`, `--api-key <valor>` y las credenciales en URLs (`https://u:…@host`) se sustituyen por `REDACTED`. Es una heurística: un secreto pasado como argumento posicional sin nombre no se detecta. **No pases secretos por argv**; usa variables de entorno. El entorno **nunca** se registra, ni tampoco la salida de los comandos.

## 3. Estado persistente

Ubicación: `$(git rev-parse --git-path quality-gate)/v1/`. Queda dentro de `.git`, no se versiona y cada worktree tiene el suyo (verificado).

```text
quality-gate/v1/
  records/<check-id>/<seq9>-<epoch>-<pid>-<rand>.rec   un registro inmutable por ejecución
  required                                              verificaciones obligatorias (qg require)
  lock/                                                 lock (solo para required, gc y asignar secuencias)
  quarantine/                                           registros ilegibles retirados por qg gc
```

**Por qué registros y no un único `state.json`** (cambio respecto a la propuesta):

- Cada ejecución escribe su propio archivo con un **renombrado atómico** (temporal en el mismo directorio + `mv`). Las ejecuciones concurrentes no compiten por un archivo compartido, y una escritura interrumpida deja como mucho un `*.tmp.*`, que los lectores ignoran y `qg gc` elimina.
- Parsear y reescribir JSON de forma segura en bash sin jq es frágil. El formato `clave=valor` (valores escapados, una línea por clave) se valida estrictamente. La salida JSON se ofrece en `qg status --json` y `qg fingerprint --json`.
- El registro se escribe al **empezar** (`status=running`) y se sustituye al terminar. Si `qg` muere (SIGKILL, corte de luz), queda `running` y se clasifica como `incomplete/abandoned`.

Esquema y compatibilidad:

- `schema=1` es obligatorio. Las claves desconocidas se ignoran, así que se pueden añadir campos sin romper lectores antiguos.
- Un `schema` mayor se trata como "no soportado" y **nunca** cuenta como aprobado.
- Un cambio incompatible usará `v2/`.

Validación al leer:

- Claves conocidas con formato correcto: identificadores con regex, huellas con formato `sha1|sha256:hex`, números y enums.
- El `check_id` debe coincidir con su directorio.
- El nombre de archivo debe seguir el patrón.
- Un registro que no valida se considera **corrupto**: se cuenta, y su check no puede salir `passed` hasta que `qg gc` lo ponga en cuarentena.

Lock:

- Se toma con `mkdir`, que es atómico, y el dueño (`pid`, `host`, `epoch`) se escribe también de forma atómica.
- Un lock solo se considera abandonado en dos casos:
  - su dueño es de esta máquina, el pid ya no existe y tiene al menos `QG_LOCK_STALE_SEC` (15 s);
  - es de otra máquina o no tiene dueño legible, y tiene más de `QG_LOCK_STALE_MIN` (10 min).
- Tras retirarlo con `mv` se comprueba que era exactamente el lock evaluado y, si no, se restaura.
- `unlock` solo borra el lock propio.

La pausa de 15 s corrige una carrera real detectada en las pruebas de concurrencia: un proceso leía el dueño de un lock ya liberado y retiraba el lock nuevo de otro proceso.

Sesiones (interfaz 2):

- Cada registro lleva `run_id`, tomado de `--run-id` o de `QG_RUN_ID`, y `unspecified` si no se indica.
- **Requisitos por sesión:** `qg require --run-id X …` escribe en `sessions/X/required`. Sin run-id se usa el archivo del worktree (`required`).
- `qg status --run-id X` usa **solo** los requisitos y los registros de la sesión X. Nunca hereda los del worktree ni los de otra sesión: una sesión sin requisitos propios da `missing (no_required_checks)`.
- Motivo del cambio: con un único `required` por worktree, una sesión podía sobrescribir los requisitos de otra concurrente y hacer que esta obtuviera un `valid` falso con un conjunto menor. Lo demuestran las pruebas de `tests/core/test_sessions.sh`.
- El código es compartido: si una sesión modifica el worktree, la evidencia de **todas** queda `stale`.
- `qg gc` elimina las sesiones sin actividad desde hace más de `QG_SESSION_DAYS` días (30 por defecto).
- **Varios repositorios:** el estado vive en cada repo (`.git/quality-gate/`). Un mismo run-id sirve en todos (`qg -C <repo> require|run|status --run-id X`), y cada repo conserva su propia huella: editar uno deja `stale` solo su evidencia. El reporte usa el esquema 2 con el `status` de cada repo.

Seguridad de rutas:

- `check-id` y `run-id` se validan con listas blancas (sin `/`, sin `..`).
- Se rechaza que el directorio de estado o los de registros sean enlaces simbólicos.
- `umask 077`.

**No es una garantía frente a agentes maliciosos.** Cualquier proceso con permisos de escritura en `.git` puede fabricar registros. No se añadió HMAC: sin una clave fuera del alcance de ese mismo proceso no aportaría nada real. La garantía para el equipo es CI.

## 4. Validación de evidencia (`qg status`)

```text
qg status [--require ID]… [--run-id ID] [--json]      # --run-id por defecto: $QG_RUN_ID
```

Las verificaciones obligatorias se toman de `--require` o, en su defecto, de `qg require`. **Sin obligatorias declaradas el resultado es `missing`**: la mera existencia de registros en verde no aprueba nada.

Para cada obligatoria se busca el registro más reciente (por secuencia) **sobre la huella actual**:

| Registro más reciente sobre la huella actual | Resultado del check |
|---|---|
| `completed`, exit 0, huella inicial = final | `passed` |
| `completed`, exit ≠ 0 | `failed` |
| `completed`, la huella cambió durante la ejecución | `stale` (`changed_during_run`) |
| `error` (no encontrado / no ejecutable) | `blocked` |
| `rejected` (`qg reject`: p. ej. exit 0 sin pruebas ejecutadas) | `blocked` (`rejected:<motivo>`) |
| `timeout`, `interrupted`, `running` (vivo o abandonado), sin huella final | `incomplete` |
| ninguno sobre la huella actual, pero sí sobre otras | `stale` (`code_changed`) |
| ningún registro | `missing` |
| hay registros corruptos y el resultado sería `passed` | `incomplete` (`corrupt_record`) |

Resultado global, por precedencia: `failed` > `blocked` > `incomplete` > `stale` > `missing` > `valid`. Es `valid` solo si **todas** las obligatorias son `passed` sobre la **misma** huella actual. Los resultados de estados distintos nunca se combinan. "El más reciente manda": si un check pasa y luego falla sobre el mismo contenido, el resultado es `failed`.

Códigos de salida: `0 valid · 1 failed · 2 blocked · 3 incomplete · 4 stale · 5 missing · 64 uso · 65 estado/Git`.

### Correspondencia con `report-format.md`

| `qg status` | Estado de la verificación en el reporte | Efecto en el veredicto |
|---|---|---|
| `valid` | todas las obligatorias `passed` y huella vigente | permite `PASS` / `PASS WITH LIMITATIONS` (la revisión y los hallazgos siguen aplicando) |
| `failed` | `failed` | `FAIL` |
| `blocked` | `blocked` | `BLOCKED` |
| `incomplete` | `blocked` (no terminó) | `BLOCKED` |
| `stale` | huella OBSOLETA | `BLOCKED` hasta reejecutar |
| `missing` (sin registros) | `blocked` o `skipped` según el motivo | `BLOCKED`, salvo que no existan verificaciones aplicables (ver `report-format.md`) |
| `missing` (`no_required_checks`) | — | no hay base para aprobar; la skill debe declarar las obligatorias |

`valid` **no** equivale a `PASS`. Solo afirma que existe evidencia de verificaciones deterministas vigente para el código actual.

## 4a. Líneas base de errores heredados (`--baseline`, `qg baseline write`)

```text
qg run --baseline <ruta> --baseline-format typescript <check-id> -- node_modules/.bin/tsc --noEmit
qg baseline write --format typescript --output <ruta> [--replace] -- node_modules/.bin/tsc --noEmit
```

Para repos con errores de TypeScript preexistentes. La línea base es un archivo de texto versionable con las **firmas** de los diagnósticos (`TSnnnn|archivo|mensaje`, sin línea ni columna), con su conteo. `qg run --baseline` las compara como **multiconjunto**, nunca por el total: el check pasa solo si no hay diagnósticos nuevos. Que desaparezcan 2 y aparezcan 2 nuevos es `failed`.

- **Limitaciones.** El comando debe ser `tsc` directamente (ni `npm run`, ni `tsc && …`): cualquier línea que no sea de `tsc` da `blocked`. Salida irreconocible, diagnósticos globales sin archivo (`TS5083`), exit fuera de {0, 1, 2}, exit ≠ 0 sin diagnósticos o línea base ausente, corrupta o fuera del repo dan `blocked`, nunca `passed`.
- **Se conserva el exit real** (`qg run` y el registro). El resultado se ve en `qg status` (`baseline:known=K,fixed=F`) y en `--json`: objeto `baseline` por check y lista `baseline_checks` en la raíz. Un check sin diagnósticos y exit 0 es un `passed` normal.
- **Salida.** Se muestra al terminar el comando (no en directo). Las firmas nuevas (máximo 200) quedan en el archivo hermano `<registro>.new`, con el texto de los mensajes escapado; `qg gc` lo limpia con el registro.
- **Rutas.** Se normalizan respecto a la raíz. En un monorepo, ejecuta desde la raíz o usa una línea base por paquete, porque dos paquetes con la misma ruta relativa colisionarían.
- **Detalles.** Admite CRLF y colores. La captura de la salida usa archivos temporales en el directorio de estado (`capture.tmp.*`); si un proceso descendiente la mantiene abierta, el resultado es `capture_failed` (`blocked`).
- **Obsolescencia.** Si la línea base cambia tras el run (ignorada por Git) el check queda `stale` (`baseline_changed`); si está versionada, cambia la huella.
- **Escritura.** `qg run` nunca la escribe. `qg baseline write` se niega sobre un archivo existente sin `--replace`, sobre un symlink o ante salida irreconocible; no registra evidencia. Se ejecuta solo a pedido explícito del usuario.
- **Efecto en el veredicto:** un check que pasó contra la línea base limita el reporte a `PASS WITH LIMITATIONS` ([report-format.md](../skills/quality-gate/references/report-format.md)).

## 4c. Clasificación previa (`qg classify`)

`qg classify [--json] -- <comando>` dice, sin ejecutar nada, si una verificación es `read-only`, `writes-generated`, `writes-source`, `installs-dependencies`, `external-side-effects` o `unknown`. Lee `package.json` (scripts, un nivel de indirección), `Makefile`, archivos de shell, `.npmrc` y `pnpm-workspace.yaml`; gana la coincidencia más grave y lo que no puede inspeccionar es `unknown`, nunca `read-only`.

**Es una heurística:** puede dar falsos `read-only` con herramientas o banderas que no conoce. Un grupo de banderas cortas con `u` (`-cu`, `-uw`) cuenta como actualización; en `go`, que no agrupa banderas, `-run`, `-count`, `-timeout` o `-cpu` no cuentan, y sí `-u` y la convención de archivos golden (`-update`, `-update-golden`, `-golden`). `qg run` no cambia: sigue detectando modificaciones durante la ejecución (`changed_during_run`). La skill lo usa en Discover para pedir aprobación antes de ejecutar comandos que escriben fuentes, instalaciones, efectos externos o comandos desconocidos.

## 4b. Descartar evidencia (`qg reject`) y compatibilidad (`qg version`)

```text
qg reject [--run-id ID] <check-id> --reason <código>     # [a-z0-9_-], p. ej. no_tests_executed
qg version [--json]                                     # {"name":"qg","version":…,"schema":1,"interface":4}
```

- `reject` añade un registro `rejected` sobre la huella actual. **Solo degrada**: el check pasa a `blocked` hasta que una ejecución posterior lo sustituya. Sirve para que la evidencia refleje lo que muestra la salida: un `exit 0` que no ejecutó pruebas no debe quedar como `passed`. No afecta a otras huellas ni puede aprobar nada.
- `interface` sube cuando cambia la interfaz de la CLI. La skill exige `interface >= 2` y `schema == 1` (>= 4 para `--baseline`, `baseline write` y `classify`); si no se cumple, usa el modo sin `qg`.

## 5. Mantenimiento (`qg gc`)

- Elimina temporales de más de 10 minutos.
- Pone en cuarentena los registros ilegibles.
- Conserva los `QG_KEEP_RECORDS` más recientes por check (50 por defecto).
- No toca registros con esquema futuro ni registros `running`.

## 6. Rendimiento medido

Repos sintéticos (archivos de texto de ~20 bytes; Linux, SSD; la mediana de varias ejecuciones es similar):

| Archivos | `.git` | `qg fingerprint` limpio | con 20 cambios | `qg status` | `git status` |
|---|---|---|---|---|---|
| 1.000 | 1 MB | 54 ms | 59 ms | 75 ms | 10 ms |
| 10.000 | 2 MB | 94 ms | 109 ms | 120 ms | 36 ms |
| 50.000 | 10 MB | 151 ms | 155 ms | 186 ms | 72 ms |

El coste es de 2 a 5 veces el de `git status`. Lo dominan la copia del índice y el recorrido del working tree que hace `git add -A` (reutiliza la caché de stat). Para un futuro hook `Stop`, que haría una huella o un `status` por turno, supone unos 0,1–0,2 s en repos medianos. No se optimiza. Archivos grandes **modificados** o no versionados sí cuestan: se leen enteros para calcular su hash.

## 7. Compatibilidad

| Plataforma | Estado |
|---|---|
| Linux (bash 5.3, git 2.55) | **probado**: ver el recuento actual en `bash tests/run_core_tests.sh` |
| macOS (bash 3.2.57 del sistema) | **probado en CI** (`macos-latest`, run 45453036122): todas las suites, incluida la interfaz 2 |
| Windows | **no soportado** en esta versión. Git Bash/WSL podrían funcionar, pero no se ha probado. Una versión PowerShell duplicaría toda la lógica; se pospone hasta que haya un caso de uso |
