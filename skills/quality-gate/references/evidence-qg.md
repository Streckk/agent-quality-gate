# Evidencia ejecutable con `qg`

`qg` registra la evidencia de cada verificación: qué código se verificó (huella por contenido), qué comando se ejecutó y su exit code real. Además, `qg status` indica si esa evidencia sigue vigente. Cuando está disponible y es compatible, **todas** las verificaciones de la puerta se ejecutan con `qg`. Si no lo está, la puerta sigue el modo sin `qg` (sección 8) y lo dice en el reporte.

`qg` no decide qué verificar ni aprueba nada: registra procesos. La clasificación sigue siendo tuya y se basa en la salida real.

## 1. Detectar `qg` y su compatibilidad (Discover)

Resuelve `qg` **una sola vez** a una ruta absoluta: primero el `PATH` (con el plugin instalado, `bin/` del plugin está en él) y, si no está, junto a esta skill. `<SKILL_DIR>` es el directorio base de esta skill que indica Claude Code; puede ser un symlink, por eso se resuelve con `cd -P`.

```bash
QG=$(command -v qg 2>/dev/null || true)
[ -n "$QG" ] || { d=$(cd -P "<SKILL_DIR>" 2>/dev/null && cd ../.. && pwd) && [ -x "$d/bin/qg" ] && QG="$d/bin/qg"; }
printf '%s\n' "$QG"        # vacío = no encontrado → modo sin qg
"$QG" version --json        # requiere "schema":1 e "interface" >= 2 (>= 3 para `qg session id`, >= 4 para --baseline, baseline write y classify)
"$QG" -C <repo> fingerprint # exit 65 = no es un repo Git → modo sin qg
```

Copia la ruta que imprime el `printf` y úsala **literal y entre comillas** en todos los comandos siguientes (`"/ruta/con espacios/bin/qg" run …`). No exportes variables globales ni modifiques el `PATH` del usuario. La receta funciona con rutas con espacios.

Usa el modo `qg` solo si se cumplen las tres condiciones: el ejecutable existe, la interfaz es compatible y la huella funciona. En cualquier otro caso, usa el modo sin `qg` y anota el motivo (`qg no instalado`, `interfaz N < 2`, `no es repo Git`).

Las variables de shell **no persisten** entre llamadas a Bash: por eso se resuelve una vez y se reutiliza la ruta absoluta literal en cada comando (en los ejemplos siguientes, `"$QG"` representa esa ruta).

## 2. Identificador de ejecución (run-id)

Dentro de Claude Code, usa el run-id **de la sesión**. Es el mismo que usan los hooks opcionales (`Stop`, `PreToolUse`), así que la evidencia que registres es la que ellos consultan:

```bash
"$QG" session id      # → cc-<CLAUDE_CODE_SESSION_ID>; exit 1 si la variable falta o no es válida (requiere interfaz ≥ 3)
```

Solo si ese comando falla, o la interfaz es 2, genera uno propio para esta invocación:

```bash
echo "qg-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"     # p. ej. qg-20261124T171500Z-12345
```

Úsalo literalmente en todos los comandos `qg` y pásalo siempre como `--run-id <ID>`, sin depender de `QG_RUN_ID`. Si ejecutas varias veces `/quality-gate` en la misma sesión, todas comparten el run-id: la última declaración de obligatorias sustituye a la anterior, lo que es correcto porque se trata de la misma sesión. Con run-id, los requisitos y la evidencia quedan aislados de otras sesiones en el mismo worktree: nadie sustituye tus requisitos ni cuenta como tuya la evidencia de otra sesión.

## 3. Declarar las obligatorias (`qg require`)

Después de descubrir y clasificar las verificaciones:

```bash
"$QG" -C <repo> require --run-id <ID> lint unit build
```

- Declara **todas** las obligatorias del alcance, también las que sospechas que no se podrán ejecutar (herramienta ausente, aprobación pendiente). Así su falta queda en la evidencia como `missing` o `blocked`, nunca como aprobada.
- Las opcionales no se declaran, pero se ejecutan igual con `qg run` si aplican.
- `check-id`: el `id` de `.agent/verification.yaml` o un nombre corto del script (`[A-Za-z0-9._-]`, máx. 64).
- Sin obligatorias declaradas, `qg status` nunca da `valid`.

## 4. Ejecutar (`qg run`) (Verify)

```bash
"$QG" -C <dir> run --run-id <ID> --timeout <seg> <check-id> -- <comando> <args…>
```

- `<comando> <args…>` es el comando **real y descubierto**, argumento por argumento: `npm run lint`, `make test`, `uv run pytest -q`. `qg` no usa shell. Para variables de entorno usa `env VAR=valor cmd`. Usa `sh -c '…'` solo si el comando del proyecto necesita pipes o expansión, y menciónalo en el reporte.
- `-C <dir>` es el directorio donde se ejecuta, por ejemplo el subpaquete. La huella cubre siempre todo el repositorio.
- Pon al Bash un timeout mayor que `--timeout`. `qg` mata el grupo de procesos al vencer (exit 124).
- `qg` **no** filtra comandos: las reglas de [guardrails](guardrails.md) y de Discover siguen decidiendo qué se puede ejecutar. Lo que necesita aprobación no se ejecuta; queda declarado y sin registro (`missing`).
- La salida del comando se muestra en tu terminal y no se guarda en el registro. Léela.

Exit code de `qg run` → clasificación provisional:

| exit | registro | Clasificación |
|---|---|---|
| 0 | `completed` | `passed` **solo si la salida muestra que se ejecutó algo** (sección 5) |
| ≠ 0 (comando) | `completed` | `failed` |
| 124 | `timeout` | `blocked` (timeout) |
| 126 / 127 | `error` | `blocked` (no ejecutable / no encontrado) |
| 128+n | `interrupted` | `blocked` (interrumpido) |
| 64 / 65 | sin registro | error de uso de `qg` o repo no válido: corrige la llamada o cambia al modo sin `qg` |

## 4a. Línea base de errores heredados (`--baseline`)

Para proyectos con errores de TypeScript que ya existían: la línea base los registra y `qg` los compara después, de forma que solo los **nuevos** hacen fallar la verificación.

```bash
"$QG" -C <dir> run --run-id <ID> --baseline .agent/baselines/typecheck.txt --baseline-format typescript typecheck -- npx tsc --noEmit
```

- Se usa cuando `.agent/verification.yaml` declara `baseline: {format: typescript, reference: <ruta>}` en esa verificación. Sin esa declaración no inventes una línea base.
- **Debe envolver `tsc` directamente.** No `npm run typecheck`, ni `tsc && otra-herramienta`: cualquier línea que no sea de `tsc` da `blocked`. Si el script del proyecto envuelve más cosas, pide al usuario el comando directo.
- Compara las firmas `TSnnnn|archivo|mensaje` (sin línea ni columna) como multiconjunto, **nunca por el total**: si desaparecen 2 errores conocidos y aparecen 2 nuevos, es `failed`. Pasa solo si no hay diagnósticos nuevos.
- Es un parser estricto: formato irreconocible, diagnósticos globales sin archivo, exit fuera de {0, 1, 2}, exit ≠ 0 sin diagnósticos, o línea base ausente, corrupta o fuera del repo → `blocked`, nunca `passed`.
- El exit real del comando se conserva en `qg run` y en el registro. Que "pasó contra la línea base" se distingue en `qg status` (`baseline:known=K,fixed=F` y, en `--json`, el objeto `baseline` y la lista `baseline_checks`).
- Con `--baseline` la salida del comando se muestra **al terminar**, no en directo.
- Si hay firmas nuevas, `qg run` imprime las 20 primeras; el resto está en el archivo hermano `.new` del registro. El texto de los mensajes de TypeScript va escapado ahí.
- Las rutas se normalizan respecto a la raíz del repo. En un monorepo, ejecuta desde la raíz o usa una línea base por paquete: dos paquetes con la misma ruta relativa colisionarían.
- Se admite CRLF y salida con colores (se limpian antes de analizar).
- Si la línea base cambia después del run (está ignorada por Git y se editó), la evidencia queda `stale` (`baseline_changed`). Si está versionada, cambia la huella.
- **`qg run` nunca escribe la línea base.** Crearla o actualizarla es **solo a pedido explícito del usuario**:

```bash
"$QG" -C <dir> baseline write --format typescript --output .agent/baselines/typecheck.txt [--replace] -- npx tsc --noEmit
```

  Se niega sobre un archivo existente sin `--replace`, y ante salida irreconocible o exit inesperado. Actualizar la línea base para que un check pase es esconder una regresión: no lo hagas por iniciativa propia.

**Efecto en el reporte:** el check se escribe `passed (línea base: K conocidos, F corregidos)` y el veredicto no puede ser `PASS` limpio: como máximo `PASS WITH LIMITATIONS`, con los errores heredados en "Omitido y limitaciones". Un check `clean` (exit 0, sin diagnósticos) es un `passed` normal.

## 4b. Efectos secundarios antes de ejecutar (`qg classify`)

```bash
"$QG" -C <repo> classify --json -- npm run typecheck
```

No ejecuta nada: lee `package.json` (scripts), `Makefile`, archivos de shell, `.npmrc` y `pnpm-workspace.yaml` y devuelve una clase.

| Clase | Qué hacer |
|---|---|
| `read-only` | ejecutar |
| `writes-generated` | ejecutar; anotar que genera archivos (cachés, `dist/`, informes) y cómo evitarlo si hay un modo sin escritura |
| `writes-source` | no ejecutar sin aprobación: modifica código fuente (formateo con `--write`, `-u`, snapshots) |
| `installs-dependencies` | pedir aprobación |
| `external-side-effects` | pedir aprobación (despliegue, publicación, red, datos) |
| `unknown` | no es `read-only`: lee el script. Con indicios externos, pedir aprobación |

- Gana la coincidencia más grave. Lo que no se puede inspeccionar (script inexistente, más de un nivel de indirección, JSON ilegible) es `unknown`, nunca `read-only`.
- **Es una heurística.** Quedan falsos `read-only` conocidos (por ejemplo flags agrupados como `-bu` o `--updateSnapshot=true` en algunas herramientas). `qg run` sigue detectando los cambios durante la ejecución (`changed_during_run`), pero es tarde: léelo como una ayuda para decidir antes, no como una garantía.
- Para evitar instalaciones implícitas, usa las formas que el propio gestor documente (p. ej. una opción para no instalar al ejecutar scripts), solo si existen en su documentación; no inventes flags.

## 4c. Transparencia de caché

Herramientas como Turborepo, Nx o la caché de Jest pueden reproducir un resultado anterior sin ejecutar nada. Un exit 0 así demuestra menos. Lee la salida y anota, citando la línea de la herramienta:

| Lectura | Cuándo | Cómo se reporta |
|---|---|---|
| ejecución real | la salida muestra tareas o pruebas ejecutadas | `passed` normal |
| caché parcial | algunas tareas "cache hit" y otras ejecutadas | `passed`, indicando cuáles salieron de caché |
| caché total | todas desde caché (p. ej. `FULL TURBO`, `[existing outputs match the cache]`) | `passed (caché total)` con la línea citada; si el cambio afecta a lo cacheado, reejecuta sin caché con la opción que documente la herramienta |
| desconocido | la salida no permite saberlo | `passed (caché: desconocido)` |

No inventes conteos: cita lo que la herramienta imprime.

## 5. Exit 0 sin verificación real → `qg reject`

Un exit 0 **no demuestra** que se haya verificado algo. Si la salida indica que no se ejecutaron pruebas, descarta esa evidencia. Ejemplos: `0 tests`, `no tests found`, `Ran 0 tests`, todos los tests `skipped`, o una suite que se autoexcluye por falta de una variable de entorno o un servicio.

```bash
"$QG" -C <repo> reject --run-id <ID> <check-id> --reason no_tests_executed
```

- `reject` solo **degrada**: el check pasa a `blocked` (`rejected:<motivo>`) hasta que una ejecución posterior lo sustituya. No sirve para ocultar fallos ni para aprobar.
- Motivos habituales: `no_tests_executed`, `tests_skipped`, `wrong_target`.
- En el reporte el check figura como `skipped` o `blocked` con ese motivo.

## 6. Correcciones y reejecución

- Cualquier edición tuya, de otro agente o del usuario cambia la huella. La evidencia anterior queda `stale` automáticamente; no hace falta borrar nada.
- Tras cada corrección, reejecuta con `qg run` las verificaciones afectadas, y como mínimo todas las obligatorias antes del reporte.
- El límite de iteraciones de [feedback-loops](feedback-loops.md) se mantiene: `qg` no amplía los reintentos.
- Si una verificación modifica archivos (formateadores con `--write`, generadores), `qg` lo marca como `changed_during_run` y la evidencia sale `stale`. Reejecuta sin efectos de escritura o explícalo en el reporte.
- **Artefactos no ignorados** (`__pycache__/`, `.pytest_cache/`, `coverage/`, `dist/` cuando no están en `.gitignore`) cambian la huella y producen el mismo efecto. Observado en la validación con Python.
  - Opción preferida: un modo que no escriba, como `env PYTHONDONTWRITEBYTECODE=1 make test`. Es el mismo comando con una variable de entorno, y se declara en el reporte.
  - Solo puedes borrar los artefactos que **tu propia ejecución** acaba de crear, y debes decirlo.
  - Añadirlos a `.gitignore` es un cambio del repositorio: proponlo, no lo hagas sin aprobación.
  - Nunca excluyas rutas de la huella para que la evidencia salga `valid`.

## 7. Consultar la evidencia antes del reporte (Report)

```bash
"$QG" -C <repo> status --run-id <ID> --json
```

Usa su `result` y la lista `checks` tal cual. **No** reconstruyas el estado de memoria.

| `qg status` | Significado | Veredicto ([report-format](report-format.md)) |
|---|---|---|
| `valid` | todas las obligatorias `passed` sobre la huella actual | **permite** `PASS` / `PASS WITH LIMITATIONS`; la revisión, los hallazgos y las aprobaciones siguen aplicando. Si algún check lleva `baseline` (`baseline_checks`), el máximo es `PASS WITH LIMITATIONS` |
| `failed` | alguna obligatoria falló (último registro) | `FAIL` |
| `blocked` | no encontrado, no ejecutable o `reject` | `BLOCKED` |
| `incomplete` | timeout, interrupción, en curso o registro ilegible | `BLOCKED` |
| `stale` | el código cambió después de verificar | reejecutar; si no es posible, `BLOCKED` |
| `missing` | obligatoria sin ejecutar, o sin obligatorias declaradas | `BLOCKED` (o `PASS WITH LIMITATIONS` si de verdad no existen verificaciones aplicables y el riesgo es `low`) |

**`valid` no equivale a `PASS`.** Un `PASS` exige además:
- que no haya hallazgos `confirmed` abiertos;
- las limitaciones propias de cada veredicto;
- las aprobaciones humanas que procedan (en riesgo `high`, siempre).

Si `qg status` y tu lectura de las salidas discrepan, gana la opción más restrictiva y se explica la discrepancia.

En el reporte, la línea de evidencia queda así:

```
**Evidencia:** qg <versión> · status=<result> · huella <fp corto> · run-id <ID> · índice <matches|differs>
```

Si el índice difiere del working tree, avisa de que un commit incluiría contenido distinto del verificado.

## 8. Modo sin `qg`

Sigue el protocolo de v0.1 completo:
- huella manual según [report-format](report-format.md);
- exit codes observados en tus propias ejecuciones de Bash.

En el reporte escribe `Evidencia: sin qg (<motivo>)`. **Nunca** atribuyas a `qg` resultados que no produjo, ni inventes una salida de `qg status`.

## 9. Qué no hacer

- No edites `.git/quality-gate/` a mano ni fabriques registros.
- No uses `qg reject` sobre checks de otra sesión ni para ocultar fallos.
- No ejecutes `qg gc` salvo que el usuario lo pida.
- No uses el run-id de otra sesión para "heredar" su evidencia.
- No presentes `qg` como garantía frente a manipulación: es evidencia local, y la garantía final es CI.
