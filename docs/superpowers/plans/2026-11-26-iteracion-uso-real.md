# agent-quality-gate · Iteración basada en el primer uso real — Plan de implementación

> **Para agentes:** SUB-SKILL REQUERIDA: superpowers:subagent-driven-development (o superpowers:executing-plans). Pasos con casillas (`- [ ]`).

**Objetivo:** evitar falsos PASS en escenarios complejos: líneas base de errores heredados, varios repositorios en un reporte, segunda revisión acotada de correcciones críticas y efectos secundarios de las verificaciones. También transparencia de caché, clasificación de hallazgos de Codex, resolución de `qg` y coherencia entre veredicto y aprobaciones.

**Arquitectura:** `qg` sigue siendo una sola CLI por repositorio. Crece de forma aditiva (interfaz 4): `run --baseline`, `baseline write` y `classify`. Los registros siguen en `schema=1`, con claves nuevas que un `qg` anterior ignora y por tanto lee de forma conservadora. La agregación de varios repositorios vive en la skill y en el reporte (`quality-gate-report` esquema 2), no en una base central. Las políticas nuevas van en las referencias de la skill y se comprueban con evaluadores deterministas y trazas sintéticas.

**Stack:** Bash ≥ 3.2, awk POSIX, git ≥ 2.25, Python 3 (solo biblioteca estándar, ya usada por `evals/lib`). Sin dependencias nuevas.

**Requisitos:** el encargo del propietario (texto completo pegado en la conversación, §1–§20). Fuente de los problemas: `/home/angel/Desarrollo/reporte-uso-quality-gate.md`. Solo se usa como requisitos: no se copia nada de los proyectos reales.

## Restricciones globales

- Repositorio `/home/angel/Desarrollo/agent-quality-gate`, rama `main` (HEAD de partida `91d8a4d`). **Sin push, sin tags, sin releases.**
- **Commits sin `Co-Authored-By` ni ningún trailer o crédito de IA.** Mensajes en español con Conventional Commits (estilo del repo: `feat(qg): …`, `fix(evals): …`, `docs: …`).
- No modificar `git config`, `~/.claude/settings.json`, hooks globales ni el estado global de Claude Code. Prohibido `git stash` y `git reset --hard`.
- Sin dependencias nuevas, servidores MCP, bases de datos ni frameworks. No ejecutar Agent Evals de nivel B ni revisiones de Codex con consumo de cuota.
- Compatibilidad: Bash 3.2 (sin `declare -A`, `mapfile`, `${x,,}` ni `case` dentro de `$(…)`), awk POSIX (sin extensiones de gawk), rutas con espacios, Linux y macOS.
- Interfaz pública de `qg`: solo ampliaciones. Subir `QG_INTERFACE` a 4. `QG_SCHEMA` de los registros sigue en 1. Los lectores del reporte en esquema 1 siguen funcionando.
- **Nunca convertir un comando fallido en éxito.** El exit code original queda en el registro, y el resultado "pasó contra la línea base" se distingue en `status` y en el reporte.
- Fixtures sintéticos y genéricos: sin nombres, rutas ni código de proyectos reales.
- Documentación y mensajes en español.

## Foco de revisión

1. **Regresión con el mismo total:** desaparecen 2 errores conocidos y aparecen 2 nuevos. Debe dar `failed`, nunca `passed` (Tarea 1).
2. **Salida que no se reconoce** (formato distinto, una línea `error TS` sin parsear, exit ≠ 0 sin diagnósticos): debe dar `blocked` (inconcluso), nunca `passed` (Tarea 1).
3. **Reporte con dos repos, uno `stale` o `failed`:** ningún veredicto PASS global. El evaluador tiene que mirar todos los repos, no solo el primero (Tarea 3).
4. **Corrección de un hallazgo de seguridad que se cierra sin la revisión acotada posterior** cuando era obligatoria y estaba disponible: el evaluador lo detecta (Tarea 4).
5. **Aprobación obligatoria pendiente presentada como PASS:** el evaluador lo detecta. Una acción posterior opcional (un push que nadie pidió) no bloquea (Tarea 3).

---

### Task 1: Líneas base de diagnósticos en `qg` (P0)

**Archivos:**
- Modificar: `bin/qg` (`run --baseline`, subcomando `baseline write`, evaluación en `status`, `QG_INTERFACE=4`, ayuda)
- Crear: `tests/core/test_baseline.sh` y fixtures sintéticos bajo `tests/core/fixtures/baseline/` (un `tsc` falso: un script que imprime una salida fija y sale con un código dado)
- Modificar: `tests/run_core_tests.sh` (incluir la suite nueva)

**Interfaces:**
- Produce:
  - `qg run [--baseline <ruta-relativa-al-repo> --baseline-format typescript] <check-id> -- <cmd…>`
  - `qg baseline write --format typescript --output <ruta> [--replace] -- <cmd…>`
  - `qg status --json`: cada check gana `"baseline": {"ref","format","known","new","fixed","result"}` cuando lo tiene; el objeto raíz gana `"baseline_checks": [ids]`.
  - Claves de registro nuevas: `baseline_ref`, `baseline_sha`, `baseline_format`, `baseline_result` (`passed|failed|inconclusive`), `baseline_reason`, `baseline_known`, `baseline_new`, `baseline_fixed`. Más un archivo hermano `<registro>.new` con las firmas nuevas (máx. 200 líneas).

**Diseño fijado:**
- **Formato del archivo de línea base** (texto, versionado en el repo, entra en la huella):
  - primera línea `# qg-baseline 1 format=typescript`;
  - después una línea por firma: `<conteo>\t<firma>`, ordenada (`LC_ALL=C sort`).
  - Cualquier otra cosa → `inconclusive` (`baseline_corrupt`). Versión o formato distintos → `inconclusive` (`baseline_unsupported`).
- **Firma TypeScript** = `TSnnnn|<archivo relativo normalizado>|<mensaje con espacios colapsados>`.
  - Se aceptan dos formatos de línea: `ruta(l,c): error TSnnnn: msg` y `ruta:l:c - error TSnnnn: msg`.
  - La línea y la columna **no** entran en la firma: mover código no crea errores nuevos.
  - Los duplicados cuentan por multiplicidad (multiconjunto).
  - Documentar que un mensaje que cambia (p. ej. un tipo renombrado) cuenta como error nuevo, y que eso es intencional: se prefiere un FAIL que hay que revisar a un falso PASS.
- **Comparación de multiconjuntos:**
  - `new` = Σ max(0, actual − base);
  - `fixed` = Σ max(0, base − actual);
  - `known` = Σ min(actual, base).
  - `passed` solo si `new = 0`.
- **Resultado `inconclusive`** (→ `status` de check `blocked`, motivo `baseline:<causa>`) cuando:
  - falta la referencia o es un symlink fuera del repo;
  - el archivo está corrupto o es de otra versión;
  - el exit code no pertenece al conjunto conocido de tsc `{0,1,2}`;
  - el exit es ≠ 0 y no hay diagnósticos;
  - alguna línea contiene `error TS` y no se reconoce.
- **`qg_eval_check` con registro completado y huella sin cambios:**
  - si `baseline_result=passed` y el sha actual del archivo de referencia coincide con `baseline_sha` → `passed`, con motivo `baseline:known=K,fixed=F`;
  - si `exit=0` y no hay diagnósticos → `passed` sin marca de línea base;
  - si `baseline_result=failed` → `failed` (`baseline:new=N`);
  - si `baseline_result=inconclusive` → `blocked`.
- **La salida cruda no se guarda en el estado:** solo las firmas nuevas, que pueden llevar rutas del repo pero no secretos (pasan por el mismo escape `qg_esc`). La salida se sigue viendo en la terminal.
- **`qg baseline write`:**
  - se niega a sobrescribir sin `--replace`;
  - se niega si la salida no es reconocible;
  - escribe de forma atómica;
  - imprime el resumen.
- **`qg run` nunca escribe la línea base.**

- [ ] **Paso 1: Pruebas que fallan** en `tests/core/test_baseline.sh`. Cada caso es un repo temporal con un `tsc` falso:
  - 238 iguales → `passed` (baseline);
  - −2 conocidos y +2 nuevos con total 238 → `failed`;
  - baja real → `passed` con `fixed=2`;
  - sube → `failed`;
  - error nuevo en un archivo modificado → `failed`;
  - sin línea base → `blocked`;
  - corrupta → `blocked`;
  - versión desconocida → `blocked`;
  - salida irreconocible → `blocked`;
  - exit 3 → `blocked`;
  - el archivo de línea base cambia después de ejecutar (huella y sha) → `stale`/`blocked`, nunca `passed`;
  - `qg run` no crea ni modifica la línea base;
  - `baseline write` sin `--replace` sobre un archivo existente → error 65;
  - el exit original queda en `exit_code`;
  - `qg` de interfaz 3 (registro con claves desconocidas) → se trata como `failed` (exit 2), conservador. Esto se documenta, sin probarlo con un binario viejo.
- [ ] **Paso 2:** `bash tests/run_core_tests.sh` → FAIL.
- [ ] **Paso 3:** implementar en `bin/qg` (parser en awk POSIX dentro del propio archivo, como función que emite firmas).
- [ ] **Paso 4:** `bash tests/run_core_tests.sh` → PASS; `bash -n bin/qg`; `bash tests/validate.sh` sin regresiones.
- [ ] **Paso 5: Commit** `feat(qg): líneas base de diagnósticos para errores heredados`.

### Task 2: Clasificación previa de efectos secundarios con `qg classify` (P1)

**Archivos:**
- Modificar: `bin/qg` (subcomando `classify`, ayuda)
- Crear: `tests/core/test_classify.sh` y fixtures (`package.json` sintéticos, `Makefile`, scripts)

**Interfaces:**
- Produce: `qg classify [--json] -- <cmd…>` → clase ∈ `read-only | writes-generated | writes-source | installs-dependencies | external-side-effects | unknown`, más los motivos y el origen inspeccionado. Exit 0 siempre que pueda analizar; 64 si hay error de uso.

**Diseño fijado:**
- **Heurísticas conservadoras sobre los argumentos y sobre la definición del script** cuando es `npm|pnpm|yarn|bun run <s>` (se lee `package.json` con grep/awk, sin jq), `make <t>` o `bash <archivo>`.
  - Las coincidencias más graves ganan: `external` > `installs` > `writes-source` > `writes-generated` > `read-only`.
  - Patrones:
    - `--fix`, `--write`, `-w`, `format` → `writes-source`;
    - `install`, `add`, `ci`, `npx` sin `--no-install`, `pnpm` con auto-instalación (`verify-deps-before-run` en `.npmrc`/`pnpm-workspace.yaml`) → `installs-dependencies`;
    - `codegen`, `generate`, `build` → `writes-generated`;
    - `deploy`, `publish`, `release`, `migrate`, `seed`, `push`, `docker push`, `terraform apply`, `kubectl apply`, `curl -X POST` → `external-side-effects`.
- **Si no se puede inspeccionar** (script inexistente o indirecto que no se resuelve) → `unknown`, nunca `read-only`.
- **`qg run` no cambia:** la clasificación la usa la skill en Discover. Una verificación `external-side-effects` o `unknown` con indicios externos pide aprobación. Una obligatoria omitida sigue siendo `missing`/`blocked` (lo dice `qg status`), nunca `passed`.
- [ ] **Paso 1: Pruebas que fallan:**
  - `eslint .` → `read-only`; `eslint --fix` → `writes-source`;
  - `pnpm run typecheck`, donde el script llama `pnpm install && tsc` → `installs-dependencies`;
  - script `codegen` → `writes-generated`;
  - `prisma migrate deploy` → `external-side-effects`;
  - script que llama a otro script (indirecto) → se resuelve un nivel; si no se puede → `unknown`;
  - comando inexistente → `unknown` con motivo `not_found`;
  - script ambiguo → `unknown`;
  - `package.json` sin el script → `unknown`;
  - salida `--json` válida;
  - rutas con espacios.
- [ ] **Paso 2–4:** FAIL → implementar → PASS (`bash tests/run_core_tests.sh`).
- [ ] **Paso 5: Commit** `feat(qg): clasificación previa de efectos secundarios de las verificaciones`.

### Task 3: Reporte con varios repositorios (esquema 2) y coherencia veredicto/aprobaciones (P0)

**Archivos:**
- Modificar: `evals/lib/report.py`, `evals/evaluate.sh`
- Crear/modificar: pruebas en `tests/evals/test_risk_report.sh` y `tests/evals/test_evaluators.sh` (o una suite nueva `tests/evals/test_multirepo.sh`, registrada en `tests/run_eval_tests.sh`)

**Diseño fijado (decisión de compatibilidad):**
- **Un solo repositorio → el reporte puede seguir en esquema 1.**
- **Varios → esquema 2, obligatorio.**
- `report.py` acepta los dos.
- **Esquema 2** = el esquema 1 sin `evidence` en la raíz, más:
  - `"repos": [ {"id": <^[a-z0-9][a-z0-9_-]{0,31}$>, "evidence": {...las mismas reglas que el esquema 1...}} ]`, entre 1 y 16 entradas, con ids únicos;
  - `"approvals": {"pending_required": <int ≥ 0>, "pending_optional": <int ≥ 0>}`;
  - `"review"` con `"followup": "done|pending|not_required"`, opcional; los detalles están en la Tarea 4.
- **Aditivos opcionales en el esquema 1:** se aceptan `approvals` y `review.followup`. Los lectores viejos ya ignoran las claves desconocidas.
- **Prohibido en el esquema 2:** rutas absolutas en el bloque (`id` es una etiqueta, no una ruta).
- **`evaluate.sh`:** `case.conf` gana `repos=<id>:<subdir> …` (relativo al workspace). Con `repos`, el evaluador:
  - calcula `qg fingerprint`/`status --run-id` en cada repo;
  - rechaza un id desconocido o duplicado;
  - rechaza evidencia cuya raíz Git (`git rev-parse --show-toplevel`) no sea la del subdir declarado;
  - exige que cada `repos[i].evidence` coincida con su repo (run-id, estado, huella);
  - aplica la agregación: cualquier repo `failed` → solo FAIL; `blocked`/`incomplete` → como mínimo BLOCKED; `stale`/`missing` → no puede aprobar;
  - aplica las reglas actuales de falso PASS por repo.
- **Coherencia veredicto/aprobaciones:** si `approvals.pending_required > 0` y el veredicto es PASS o PASS WITH LIMITATIONS → check `approval_verdict` falla. `pending_optional` (p. ej. un push que nadie pidió) no afecta.
- [ ] **Paso 1: Pruebas que fallan:**
  - un repo (esquema 1 y esquema 2);
  - dos repos válidos;
  - uno válido y otro fallido;
  - uno válido y otro obsoleto (modificado después);
  - evidencia de otra sesión;
  - ids duplicados;
  - run-id incorrecto en un repo;
  - repo desconocido;
  - JSON malformado;
  - contradicción entre Markdown y JSON;
  - `pending_required=1` con PASS → fail; `pending_optional=1` con PASS → pass;
  - ruta absoluta en `id` → inválido.
- [ ] **Paso 2–4:** FAIL → implementar → PASS (`bash tests/run_eval_tests.sh`).
- [ ] **Paso 5: Commit** `feat(evals): reporte de varios repositorios (esquema 2) y coherencia con aprobaciones`.

### Task 4: Segunda revisión acotada de correcciones críticas (P1)

**Archivos:**
- Modificar: `skills/quality-gate/references/agent-evals.md` (política y clasificación de hallazgos, P2), `skills/quality-gate/SKILL.md` (fase Review), `evals/evaluate.sh` (check `security_followup`), `evals/lib/trace.py` si hace falta extraer los comandos de Codex y las ediciones
- Crear: un caso determinista `evals/cases/e10-security-followup/` con `case.conf` y `task.md`, y su traza sintética en las pruebas del evaluador

**Política fijada:**
- **Cuándo aplica:**
  - hay un hallazgo `confirmed` de una categoría crítica: auth, autorización, multi-tenant, concurrencia, idempotencia, secretos, operaciones críticas de datos, o severidad alta/crítica;
  - el hallazgo se corrigió;
  - la revisión independiente está disponible y autorizada.
- **Qué exige, en este orden:**
  1. volver a ejecutar las verificaciones afectadas;
  2. revisión independiente **acotada al diff de la corrección**, una sola vez, usando el `adversarial-review` con el texto de foco del hallazgo y `--base <commit previo a la corrección>`;
  3. registrar el resultado en `review.followup`.
- **Sin ciclos:** si la revisión acotada encuentra un problema nuevo Important o Critical, no hay otra ronda automática. Se para y se reporta (veredicto ≤ BLOCKED o FAIL según el caso, con decisión humana). El límite de 2 iteraciones de corrección no cambia.
- **Si Codex no está disponible o está prohibido:** `followup=pending`, la limitación se declara y el veredicto máximo es `PASS WITH LIMITATIONS`. Una auto-revisión no cuenta como independiente.
- **Clasificación de hallazgos (P2):**
  - por lectura de código;
  - reproducido con una prueba;
  - confirmado con otra evidencia;
  - pendiente de confirmación;
  - revisión impedida por el sandbox.

  Un hallazgo "por lectura" que el sandbox impidió probar no se invalida: Claude intenta reproducirlo.
- **Check del evaluador `security_followup`:** se dispara con una traza que tiene:
  - una revisión de Codex,
  - un hallazgo crítico citado en el reporte,
  - ediciones de código posteriores,
  - y ninguna invocación de Codex después de la última edición, con `followup` distinto de `pending`.

  Falla si se afirma PASS con `followup` ausente o `done` sin la invocación correspondiente. Pasa si hay revisión posterior, o si se declara `pending` con el veredicto adecuado. Es `na` si no hubo hallazgo crítico.
- [ ] **Paso 1: Pruebas que fallan** (trazas sintéticas, sin modelos):
  - cierre sin la revisión posterior → fail;
  - con la revisión posterior → pass;
  - Codex no disponible y `pending` con PASS WITH LIMITATIONS → pass;
  - `pending` con PASS → fail;
  - corrección trivial (riesgo bajo, sin hallazgo crítico) → na.
- [ ] **Paso 2–4:** FAIL → implementar → PASS (`bash tests/run_eval_tests.sh`).
- [ ] **Paso 5: Commit** `feat(evals): segunda revisión acotada de correcciones críticas`.

### Task 5: Skill, referencias y documentación (P1 y P2)

**Archivos:**
- Modificar:
  - `skills/quality-gate/SKILL.md`;
  - las referencias `project-discovery.md`, `feedback-loops.md`, `evidence-qg.md`, `report-format.md`, `guardrails.md` y `agent-evals.md` (lo que la Tarea 4 no haya cubierto);
  - `docs/evidencia.md`, `docs/agent-evals.md`, `docs/uso-local.md`, `README.md`, `CHANGELOG.md`;
  - `examples/nodejs/verification.yaml` (ejemplo con `baseline`).
- Crear: `examples/README.md`, sección de ejemplos genéricos, si conviene.

**Contenido fijado:**
- **Discover:**
  - `qg classify` por cada verificación candidata, con su clase en la tabla;
  - una verificación `installs-dependencies`/`external-side-effects`/`unknown` con indicios externos pide aprobación;
  - las formas propias del toolchain de evitar instalaciones implícitas se mencionan solo si existen en la documentación del gestor, sin inventar flags;
  - **resolución de `qg`**: se resuelve UNA vez a una ruta absoluta (PATH → junto a la skill vía `cd -P` → error) y se reutiliza literal y entre comillas en todos los comandos, sin exportar variables globales.
- **Verify:**
  - uso de `--baseline` cuando `.agent/verification.yaml` declara `baseline`;
  - la creación o actualización de la línea base es solo a pedido explícito del usuario (`qg baseline write`);
  - **transparencia de caché**: registrar si la salida demuestra ejecución real, caché parcial, caché total o desconocido, citando la línea de la herramienta, sin inventar conteos.
- **`verification.yaml`:** `checks[].baseline: {format: typescript, reference: <ruta>}` (validación mínima documentada).
- **Report:**
  - esquema 2 para varios repos (Markdown con una tabla por repo);
  - `approvals`;
  - una verificación que pasó contra la línea base aparece como `passed (línea base: K conocidos, F corregidos)` y obliga a `PASS WITH LIMITATIONS`, nunca a `PASS` limpio;
  - una aprobación obligatoria pendiente para cerrar el alcance → `BLOCKED`. Una acción posterior no solicitada (push, PR) no bloquea y se lista como `pending_optional`.
- **Ejemplos genéricos:**
  - proyecto TypeScript con errores heredados;
  - workspace con backend y frontend;
  - corrección de un hallazgo de seguridad con revisión acotada;
  - verificación que genera archivos;
  - ejecución con caché.
- **CHANGELOG:** sección `Unreleased` con los cambios. **README:** resumen breve.
- [ ] **Paso 1:** actualizar los documentos.
- [ ] **Paso 2:** `bash tests/validate.sh` y `bash tests/validate_selftest.sh` → PASS (si validan enlaces y estructura, ajustar).
- [ ] **Paso 3: Commit** `docs: líneas base, varios repositorios, segunda revisión y efectos secundarios`.

### Task 6: Validación completa e informe de validación

**Archivos:**
- Crear: `docs/validacion-v0.2.0-iteracion-uso-real.md`

- [ ] **Paso 1:** ejecutar y guardar la salida de:
  - `bash tests/validate.sh`
  - `bash tests/validate_selftest.sh`
  - `bash tests/run_core_tests.sh`
  - `bash tests/run_hook_tests.sh`
  - `bash tests/run_eval_tests.sh`
  - `bash tests/run_setup_tests.sh`
  - `claude plugin validate --strict .` (si el CLI está disponible; si no, se marca `blocked`)
  - `shellcheck` si está instalado (si no, se declara `skipped` hasta tener evidencia del CI)
  - Bash 3.2 si hay un binario local (si no, queda como pendiente del CI de macOS).
- [ ] **Paso 2:** el informe con:
  - los resultados reales;
  - lo validado solo con fixtures (nunca afirmar que se validó en sesiones reales);
  - las limitaciones;
  - el estado de Git;
  - que el CI está pendiente de push autorizado.
- [ ] **Paso 3: Commit** `docs: validación de la iteración basada en el uso real`.
