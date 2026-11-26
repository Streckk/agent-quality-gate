# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado semántico.

## [Unreleased]

### Añadido (líneas base, varios repositorios, segunda revisión y efectos secundarios)
- **Líneas base de errores heredados** (`qg` interfaz 4): `qg run --baseline <ruta> --baseline-format typescript` compara las firmas `TSnnnn|archivo|mensaje` como multiconjunto, nunca por el total, y conserva el exit real. `qg status` marca `baseline:known=K,fixed=F`; `--json` añade `baseline` por check y `baseline_checks`. `qg baseline write` crea la línea base solo a pedido y nunca desde `qg run`. Salida irreconocible, exit inesperado o línea base ausente o corrupta → `blocked`. Limitaciones documentadas: debe envolver `tsc` directamente, la salida se muestra al terminar, rutas normalizadas respecto a la raíz (monorepos: una línea base por paquete o ejecutar desde la raíz).
- **`qg classify`**: clase de efectos secundarios (`read-only`, `writes-generated`, `writes-source`, `installs-dependencies`, `external-side-effects`, `unknown`) sin ejecutar nada. Es una heurística con falsos `read-only` conocidos.
- **Reporte de varios repositorios (esquema 2)** con `repos` y `approvals` (`pending_required` → `BLOCKED`; `pending_optional` no bloquea). El esquema 1 sigue siendo válido. El evaluador contrasta cada repo (`multi_repo_verdict`, `approval_verdict`; clave de caso `repos`).
- **Segunda revisión acotada** tras corregir un hallazgo crítico: campos `review.critical_fixed` y `review.followup`, y check `security_followup` (clave de caso `expect_followup`).
- **Skill y referencias:** resolución de `qg` una sola vez a ruta absoluta (sin exportar variables), `qg classify` en Discover, `--baseline` y transparencia de caché en Verify, veredicto máximo `PASS WITH LIMITATIONS` con línea base, `BLOCKED` con aprobación obligatoria pendiente.
- `docs/ejemplos.md`: cinco ejemplos genéricos. `examples/nodejs/verification.yaml` incluye un check con `baseline`.

### Añadido (configuración de CLAUDE.md)
- `/quality-gate setup [--scope project|user] [--status|--remove|--dry-run] [--file …] [--import-agents] [--force]`: instala, actualiza, consulta o quita un bloque administrado y versionado (`<!-- agent-quality-gate:start v1 -->`) con las instrucciones de **cuándo** usar la skill.
  - La skill recibe los argumentos con `$ARGUMENTS` y delega en el script determinista `bin/qg-setup`, que está en el `PATH` del plugin y se localiza con `${CLAUDE_SKILL_DIR}` si la skill se instaló por symlink.
  - Es idempotente y conserva byte a byte el resto del archivo (CRLF y archivos sin salto final incluidos).
  - Escribe con un temporal y `mv`, conservando los permisos.
  - Rechaza symlinks fuera del alcance, bloques malformados o duplicados y ubicaciones ambiguas.
  - Protege `AGENTS.md`, que Claude Code deja de leer si aparece un `CLAUDE.md`.
- `tests/setup/test_setup.sh` (99 aserciones; 9 de 9 mutaciones efectivas detectadas) y `tests/run_setup_tests.sh`, en la CI de Linux y macOS (también con `/bin/bash` 3.2) y con ShellCheck.
- Carga verificada sin coste: la transcripción de Claude Code 2.1.332 muestra `<command-args>setup --status</command-args>`, `$ARGUMENTS` y `${CLAUDE_SKILL_DIR}` sustituidos, con symlink y con `--plugin-dir`.

### Añadido (uso local)
- `docs/uso-local.md`: guía de uso diario con `--plugin-dir` (iniciar, comprobar la carga, verificar, qué pasa si…, desactivar, proyecto de juguete y cómo llevarlo a otros stacks).
- Inicio rápido en el README.
- `docs/validacion-uso-local.md`: carga real sin coste (modelo inexistente → `init` y `SessionStart` sin llamada facturada), sin skill duplicada con el symlink, activación y desactivación, `Stop` sobre una sesión real, disponibilidad de Codex. Deja pendientes de autorización el reporte estructurado con Claude real y el ciclo completo de `Stop` en 2.1.332.

### Añadido (evaluación robusta y preparación de release candidate)
- **Riesgo independiente del agente:** `expect_min_risk` en los casos. El evaluador detecta una clasificación inferior al mínimo (`risk_classification`) y aplica la política de Codex al riesgo **exigido** (el mayor entre el mínimo y el declarado). Una clasificación incorrecta ya no aprueba por haber omitido Codex.
- **Bloque estructurado del reporte** (`"kind": "quality-gate-report"`, `schema` 1) al final de `/quality-gate`, con contrato en `report-format.md` y validador `evals/lib/report.py` (solo stdlib).
  - El evaluador contrasta el bloque con el Markdown (`report_consistency`) y con `qg`, los registros y la traza (`structured_evidence`). Cualquier aprobación sin respaldo, en el Markdown **o** en el bloque, es un falso `PASS`.
  - Los reportes antiguos sin bloque se siguen leyendo.
- **Categorías de resultado:** `fail` (confirmado), `suspected` (heurístico, `needs_review`), `inconclusive` y `na`. Por ejecución, `outcome` ∈ {pass, fail, inconclusive, infra_error, evaluator_error}.
  - Los errores del evaluador o del caso (regex inválida, valores desconocidos, marcadores inexistentes, muerte del script) se registran como `evaluator_error`: nunca como fallo del agente y siempre visibles.
- `protected_markers` (literales que deben seguir en las pruebas protegidas), obligatorias **vigentes** (sobre la huella actual) y guardrails confirmados por el `tool_result` de la traza.
- Métricas nuevas: `risk_classification_accuracy`, `structured_report_valid`, `evaluator_errors`, `inconclusive_checks`, `suspected_checks`, `guardrail_suspected` y duplicados ignorados. `success_rate` usa como denominador las ejecuciones decididas.
- `compare.sh` muestra el brazo, el modelo y las condiciones, y avisa si difieren. `run.sh --model` registra el modelo y lo fija.
- Caso `e9-risk-auth` (auth sin pista en la tarea y sin Codex) y caso oficial `o3-no-false-pass`.
- Validador: rechaza claves desconocidas en `case.conf` (más 2 detecciones en el autotest).
- Pruebas: `tests/evals/test_risk_report.sh`, `test_aggregate.sh` y `test_official.sh`.
- Documentos: `docs/comparacion-con-sin-plugin.md` (diseño y presupuesto, sin ejecutar), `docs/release-candidate.md` y `docs/validacion-v0.2.0-rc.md`.

### Corregido (evaluación robusta)
- Evaluadores oficiales: el patrón de `regex` estaba en una clave `pattern:` del frontmatter. Según la plantilla de `claude plugin eval` 2.1.332, va en el cuerpo. Ahora las instrucciones son idénticas en los dos brazos y hay evaluadores comunes de veredicto.
- `report-format.md` presentaba los hooks como trabajo futuro; ya existen y son opcionales.
- `docs/validacion-v0.2.0-evals.md` describía la primera batería como "sin Codex", pero `e2` ejecutó una revisión estándar (comprobado en la traza).

### Añadido (Agent Evals)
- `evals/`: 11 casos (`case.conf` con criterios explícitos + `task.md`), fixtures Git reproducibles (`refs/eval/base`) y:
  - evaluador determinista que consulta `qg status --json`, registros, `git` y la traza (falsos `PASS`, obligatorias omitidas, evidencia obsoleta o ajena, tests debilitados, alcance, iteraciones, guardrails, Codex simulado o innecesario, bloqueos de `Stop`, errores de infraestructura aparte);
  - runner bajo demanda con `--session-id`, `--max-cost-usd` y casos `opt-in`;
  - agregación de métricas con denominadores y comparación entre ejecuciones.
- Nivel A en CI: `tests/run_eval_tests.sh` (48 aserciones; Linux y macOS con bash 3.2).
- `evals/official/`: casos en formato `claude plugin eval` (aislamiento y rama sin plugin). La carga se verificó sin coste; no se ejecutaron porque falta `socat`.
- `docs/agent-evals.md` y `docs/validacion-v0.2.0-evals.md`.

### Corregido (CI de 39c7a99)
- `qg` reintenta la huella si otro proceso crea o borra archivos durante `git add` ("unable to stat"); antes fallaba de forma intermitente.
- `evals/evaluate.sh` no funcionaba con bash 3.2 (macOS): `case` dentro de `$(…)`.
- Avisos de ShellCheck en `evals/` y en las pruebas.

### Corregido (hooks)
- `PreToolUse`: `git commit -F -` sin heredoc, pipes, redirecciones, `$(…)`, comillas invertidas, `$VAR` y archivos ilegibles pasaban sin decisión. Ahora devuelven `ask`; el `deny` se mantiene si se ve un trailer.

### Añadido (plugin y hooks opcionales)
- Plugin de Claude Code: `.claude-plugin/plugin.json` (sin licencia declarada; es decisión del propietario) y `hooks/hooks.json`. `claude plugin validate --strict` pasa.
- Hooks, **desactivados por defecto** (`QG_HOOKS`, bloque `hooks:` de `.agent/verification.yaml`, `QG_DISABLE`):
  - `SessionStart`: registra la huella inicial;
  - `Stop`: un bloqueo por huella si hay `stale`/`missing`; deja terminar con `failed`/`blocked`/`incomplete`; respeta `stop_hook_active`; máximo 3 por sesión;
  - `PreToolUse`: `deny` a trailers de IA en commits; `ask` en push/PR sin evidencia; nunca `allow`.
- Parser JSON estricto en awk portable (`hooks/lib/json.awk`), sin jq, Node ni Python.
- `qg` interfaz 3 (aditiva):
  - `qg session id|start|info|stop` (run-id `cc-<session_id>` compartido por la skill y los hooks);
  - `qg hooks status|enabled`.
- La skill usa `qg session id` como run-id dentro de Claude Code.
- Pruebas: `tests/hooks/` (190 aserciones), `tests/run_hook_tests.sh` en CI (Linux y macOS con bash 3.2) y ShellCheck sobre los hooks.
- Escenarios reales con `--plugin-dir`: `tests/scenarios/make_hook_fixtures.sh` y `run_hooks_e2e.sh`.
- `docs/hooks.md` y `docs/validacion-v0.2.0-hooks.md`.

### Corregido
- La huella actualizaba el mtime de objetos existentes en `.git/objects` (*freshen* de git sobre el almacén alternativo). Ahora no usa el almacén real (`write-tree --missing-ok`).

### Añadido (integración skill + `qg`)
- Referencia `evidence-qg.md`:
  - detección de `qg` (`PATH` o junto a la skill) y compatibilidad (`qg version --json`, interfaz ≥ 2);
  - run-id por invocación, `qg require`, `qg run`, `qg reject` y `qg status`;
  - correspondencia con los veredictos y el modo sin `qg`.
- `SKILL.md` y las referencias de cada fase usan `qg` cuando está disponible.
- `qg` (interfaz 2):
  - requisitos por sesión (`require/status --run-id`, sin herencia entre sesiones);
  - `qg reject` (solo degrada);
  - `qg version --json`;
  - `gc` de sesiones inactivas.
- Pruebas: `tests/core/test_sessions.sh`; filtros clean; modificaciones externas y simultáneas. Total: 188 aserciones.
- Fixture Python con una suite obligatoria que sale con exit 0 sin ejecutar pruebas. El analizador de trazas contrasta los reportes con los run-ids.
- `docs/validacion-v0.2.0-dev.md`: escenarios reales A–F, defectos y limitaciones.
- CI: ShellCheck **bloqueante** sobre `bin/` y `tests/`. Se corrigieron los avisos reales (`"$*"` en `qg_usage`, variable `exe` sin uso, `ls | grep` en las pruebas, variables sin uso). El SC2034 de las variables `R_*` se documenta como falso positivo: se leen por expansión indirecta.

### Corregido
- `qg fingerprint` ejecutaba los filtros clean configurados (p. ej. git-lfs), también desde `git write-tree` con entradas "racy". Ahora se neutralizan.
- Una sesión concurrente podía sustituir los requisitos de otra en el mismo worktree y producir un `valid` falso.
- La skill no encontraba `qg` fuera del `PATH`: el comando de detección pasa a `SKILL.md`.
- Pruebas: ruta temporal con `//` en macOS.

### Añadido (v0.2.0-dev: infraestructura de evidencia, sin hooks)
- `bin/qg` y `bin/qg-run` (bash ≥ 3.2 + git):
  - `fingerprint`: huella por contenido del working tree, sin escribir en el índice ni en `.git/objects`;
  - `run`: ejecuta un único comando sin shell, con timeout, reenvío de señales, grupo de procesos y argv redactado;
  - `require`: declara las verificaciones obligatorias;
  - `status`: `valid`/`failed`/`blocked`/`incomplete`/`stale`/`missing`;
  - `show` y `gc`.
- Estado en `.git/quality-gate/v1/`: un registro inmutable por ejecución con escritura atómica, lock con recuperación segura, aislamiento por worktree y cuarentena de registros corruptos.
- `tests/run_core_tests.sh` y `tests/core/` (154 aserciones: huella, ejecutor, persistencia, concurrencia y extremo a extremo).
- `docs/evidencia.md`: diseño, límites y correspondencia con `report-format.md`.

### Corregido (durante el desarrollo)
- Carrera al recuperar locks: un proceso podía retirar el lock recién creado por otro (detectado por la prueba de concurrencia).

### Cambiado
- `docs/propuesta-v0.2.0.md`: decisiones finales y nueva integración de hooks basada en `qg`.

### Corregido
- Veredictos: precedencia explícita; nuevo `NOT VERIFIED` para ejecuciones solo Discover; un cambio sin verificaciones aplicables y de riesgo bajo ya no sale como `BLOCKED`.
- Revisión de Codex: un árbol limpio (exit 0, "nothing to review") se clasifica `skipped`, no como revisión hecha; tabla de interpretación de resultados; aviso de que el diff se envía a un servicio externo.
- Comprobación de fallos preexistentes sin `git stash` (copia temporal de la base).
- Validador: un trailer de coautoría en cualquier `README.md` o `guardrails.md` pasaba sin detectarse.

### Añadido
- Huella de evidencia en el reporte (HEAD + hash del diff) para detectar evidencia obsoleta.
- Aclaraciones: contador de iteraciones global, exit codes en pipes, temporales fuera del repo, timeout de `--wait`, criterio de riesgo para cálculos monetarios.
- Reglas de regresión de la política en `tests/validate.sh` y 5 casos nuevos en el autotest.
- Arnés de escenarios manuales (`tests/scenarios/`) y resultados de la validación funcional (`docs/validacion-v0.1.0.md`).
- Propuesta técnica de hooks para v0.2.0 (`docs/propuesta-v0.2.0.md`), no implementada.

### Cambiado
- CI: `actions/checkout@v5`.

## [0.1.0] - 2026-11-23

### Añadido
- Skill `quality-gate` con protocolo Discover → Verify → Review → Report.
- Referencias: `project-discovery`, `feedback-loops`, `agent-evals`, `guardrails`, `report-format`.
- Esquema opcional `.agent/verification.yaml` y ejemplos para Node.js y Python.
- Validador en bash (`tests/validate.sh`) con autotest y workflow de CI sin secretos.
