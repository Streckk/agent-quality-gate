# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado semántico.

## [Unreleased]

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
