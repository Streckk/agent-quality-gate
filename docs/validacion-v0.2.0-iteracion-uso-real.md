# Validación: iteración basada en el uso real (v0.2.0)

Fecha: 2026-11-26 · Claude Code 2.1.332 · Linux (GNU bash 5.3.15) · rama `main`, sin push. Las suites se ejecutaron sobre `e8df7bf` (HEAD tras el commit que añadió la primera versión de este informe); el código no cambió desde `9f62852`, solo se añadieron documentos. Salidas crudas en `.superpowers/sdd/2026-11-26-iteracion-uso-real/validation-logs/`

## 1. Resumen

Se ejecutaron todas las suites deterministas del repositorio y la validación estricta del manifiesto. Resultado: **todo en verde tras reintentar; la primera pasada de `run_core_tests.sh` falló (exit 1) en `test_run.sh`**. La aserción fallida fue "huella con escrituras simultáneas: sin errores" (esperado 0, obtenido 1), una prueba de carrera ya conocida. Esa primera pasada se capturó solo parcialmente (el recuento de esa suite en ese intento, 51 ok y 1 fallo, se leyó de la salida en pantalla y no se guardó en un archivo: **no capturado**). Después, `test_run.sh` dio 52 ok, 0 fallos en tres repeticiones y `run_core_tests.sh` salió con 0 en dos pasadas completas (la segunda, y la de los logs guardados). No se tocó ninguna prueba. Ver §2 y §5.

**Nada de esto se validó en sesiones reales de Claude Code ni con Codex.** Todo lo cubierto usa fixtures sintéticos.

## 2. Resultados por suite

| Comando | Exit | Resultado |
|---|---|---|
| `bash tests/validate.sh` | 0 | 65 comprobaciones `ok`; `OK: validación completa` |
| `bash tests/validate_selftest.sh` | 0 | 21 `ok`; `OK: selftest completo` |
| `bash tests/run_core_tests.sh` (1.ª pasada) | **1** | 1 suite fallida: `test_run.sh`, aserción de huella con escrituras simultáneas; log no capturado |
| `bash tests/core/test_run.sh` (x3) | 0, 0, 0 | 52 ok, 0 fallos en cada repetición (vistas en pantalla; logs no guardados) |
| `bash tests/run_core_tests.sh` (pasada con log guardado, `validation-logs/run_core_tests.log`) | 0 | 434 ok, 0 fallos (suma de las 7 suites) |
| `bash tests/run_hook_tests.sh` | 0 | 203 ok, 0 fallos |
| `bash tests/run_eval_tests.sh` | 0 | 323 ok, 0 fallos |
| `bash tests/run_setup_tests.sh` | 0 | 99 ok, 0 fallos |
| `claude plugin validate --strict .` | 0 | `Validation passed`; 1 aviso sobre el README (sin línea de instalación desde marketplace, depende de `<owner>/<repo>`) |
| `shellcheck` | - | skipped (no instalado); pendiente de CI |
| Bash 3.2 | - | skipped (no instalado); pendiente del CI de macOS |
| `tests/scenarios/*` | - | no ejecutados: lanzan sesiones reales de Claude Code/Codex con cuota (README de escenarios) |

Desglose del core (log guardado): `test_baseline` 123, `test_classify` 122, `test_e2e` 15, `test_fingerprint` 42, `test_run` 52, `test_sessions` 25, `test_state` 55.
Hooks: `test_integration` 21, `test_json` 86, `test_pretool` 49, `test_session_stop` 47.
Evals (nivel A): `test_aggregate` 24, `test_evaluators` 49, `test_followup` 33, `test_multirepo` 65, `test_official` 73, `test_risk_report` 79.

## 3. Qué cubre cada capacidad nueva

| Capacidad | Pruebas | Recuento |
|---|---|---|
| Líneas base de diagnósticos (`qg run --baseline`, interfaz 4) | `tests/core/test_baseline.sh` | 123 |
| Clasificación previa de efectos secundarios (`qg classify`) | `tests/core/test_classify.sh` | 122 |
| Reporte esquema 2 (varios repositorios) y coherencia con aprobaciones | `tests/evals/test_multirepo.sh` | 65 |
| Segunda revisión acotada de correcciones críticas (solo cuenta si la invocación de Codex terminó bien) | `tests/evals/test_followup.sh` | 33 |
| Reporte de riesgo y bloque estructurado | `tests/evals/test_risk_report.sh` | 79 |
| Docs y política (trailers, reglas de regresión) | `tests/validate.sh` | 65 |

## 4. Solo validado con fixtures sintéticos

- Las líneas base, la clasificación y el multi-repo se ejercitan con repos Git temporales y salidas de herramientas simuladas (parser de `tsc` incluido). **No se probaron con un proyecto real ni con una sesión real de Claude Code.**
- La segunda revisión con Codex se prueba con un Codex simulado; no se invocó Codex real.
- Los escenarios manuales y el Nivel B de evals no se ejecutaron (consumen cuota).
- La skill (`SKILL.md`) y su uso de `qg classify`/aprobaciones no se observaron con un modelo.

## 5. Limitaciones conocidas (diferidas en el registro de la iteración)

Transcritas del registro `progress.md` (líneas "minor (deferred)"), no verificadas de nuevo en esta validación.

- Líneas base: `qg_cap_dir` en subshell no aborta (mensaje engañoso, resultado seguro); la limpieza puede borrar una captura viva entre usuarios/hosts tras 60 min (bloquea, no da falso PASS); con `--baseline` la salida ya no se ve en vivo. El parser de TypeScript solo acepta diagnósticos, continuaciones, marcos de código, resumen y líneas en blanco; cualquier otra línea es `inconclusive`.
- `qg classify` es heurístico: `-u` en racimos (`-bu`), `--updateSnapshot=true` y `pytest --force-regen` siguen tratándose como solo lectura; `>|` no se reconoce como redirección. `qg` detecta igualmente el cambio al ejecutar.
- Multi-repo: `REPOS_SPEC` sin comillas (glob/espacios); dos ids al mismo repo; obligatorias agregadas entre repos; `ABS_PATH` heurístico; repo sin verificaciones aplicables sin especificar.
- Segunda revisión: el filtro de `--help` mira toda la línea; `echo codex-companion.mjs review` contaría; las ediciones por Bash no se ven.
- Skill: "no hay aprobaciones pendientes" debe decir obligatorias; `classify` requiere interfaz >= 4 sin alternativa en la skill; `followup pending` requiere motivo. Pendientes para la revisión final.
- Prueba de carrera de huella (`test_run.sh`): puede fallar de forma esporádica bajo carga (visto 1 vez en esta validación, no reproducido en 3 repeticiones ni en la 2.ª pasada).

## 6. Compatibilidad

Datos leídos del código (`grep QG_INTERFACE= bin/qg` da `QG_INTERFACE=4`; `QG_SCHEMA=1`; `evals/lib/report.py` define `SUPPORTED_SCHEMAS = (1, 2)`) y de los comentarios de `bin/qg`; no se probó con lectores externos.

- Interfaz de `qg`: **4** (`QG_INTERFACE=4`). Las claves de línea base solo se escriben si el registro usa una; un `qg` de interfaz 3 las ignora y trata el registro por su `exit_code`.
- Esquema de registros de `qg`: 1, sin cambios.
- Reporte estructurado: el esquema 1 sigue siendo válido para casos de un solo repositorio; los casos con varios repositorios exigen el esquema 2 (`repos`).

## 7. Estado de Git

Lo siguiente describe el estado en el momento de la validación y no incluye el commit que añade esta versión del informe.

`git log --oneline 91d8a4d..HEAD`:

```
e8df7bf docs: validación de la iteración basada en el uso real
9f62852 docs: líneas base, varios repositorios, segunda revisión y efectos secundarios
84210d6 fix(evals): la revisión posterior solo cuenta si la invocación de Codex terminó bien
bf4f631 feat(evals): segunda revisión acotada de correcciones críticas
fb10c71 feat(evals): reporte de varios repositorios (esquema 2) y coherencia con aprobaciones
abfd650 fix(qg): classify no devuelve solo lectura ante escapes, flags de actualización y expansiones
02a6043 feat(qg): clasificación previa de efectos secundarios de las verificaciones
3ffd771 fix(qg): captura completa y salida no reconocida en líneas base
c24b150 feat(qg): líneas base de diagnósticos para errores heredados
f1f21d4 docs: encabezados de tareas del plan
e33dbde docs: plan de la iteración basada en el primer uso real
```

`git status --short` (capturado en `git-status.txt`): vacío al ejecutar las suites. Tras el commit de este informe se repitió `bash tests/validate.sh`: exit 0 (65 `ok`).

## 8. CI

**CI: pendiente — requiere push autorizado.** ShellCheck y Bash 3.2 (macOS) quedan sin evidencia hasta entonces.
