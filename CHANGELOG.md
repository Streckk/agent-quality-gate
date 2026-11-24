# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado semántico.

## [Unreleased]

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
- CI: ShellCheck como paso informativo (no bloquea).

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
