# Validación de la integración skill + `qg` (v0.2.0-dev)

Fecha: 2026-11-24 · Claude Code 2.1.331 · git 2.55 · bash 5.3 (Linux) · plugin Codex 1.0.6 (codex-cli 0.159.1)

Todo lo descrito aquí se ejecutó sobre **fixtures sintéticos** (`tests/scenarios/`) y repos temporales (`tests/core/`). No se tocó ningún proyecto real. Los hooks **no** están implementados: el flujo depende de que el modelo siga la skill.

## 1. Flujo verificado

`/quality-gate` en una sesión headless real (`claude -p`), con `qg` fuera del `PATH` y localizado junto a la skill:

```
Discover → qg version/fingerprint → qg require --run-id → qg run (falla) → corrección → qg run (pasa)
        → Codex review (riesgo medium) → qg status --run-id --json → Report
```

En todos los escenarios con `qg` contrasté el reporte con un `qg status --run-id <id>` ejecutado por mi cuenta: **coinciden**.

## 2. Escenarios funcionales (sesiones reales)

| # | Fixture | Condiciones | Observado | Veredicto | Coste |
|---|---|---|---|---|---|
| A | Node + `nx.json` | sin config, con Codex | `require lint unit build` → `run` con exit 1/1/0 → corrección (1/2) → `run` 0/0/0 → Codex `review` (exit 0, sin hallazgos) → `status valid`; e2e `blocked` (`nx` ausente); deploy/migrate no ejecutados (sin testigos) | `PASS WITH LIMITATIONS` | 0,53 USD |
| B | Python | sin Codex ni Graphify en `PATH`; `max_fix_iterations: 1`; `ruff`/`pytest` ausentes; `integration` con 0 pruebas | `require unit integration` → `lint`/`pytest` `error 127` → `unit` 2 fallos → corrección (1/1) → 1 fallo (tests contradictorios, conservados) → `integration` exit 0 con `skipped=1` → **`qg reject … tests_skipped`** → `status failed`; Codex `skipped (ready:false)`; auto-revisión etiquetada | `FAIL` | 0,59 USD |
| C | solo Markdown | sin checks | `qg` detectado → sin obligatorias → `status missing (no_required_checks)` → riesgo `low` | `PASS WITH LIMITATIONS` | 0,34 USD |
| D | A tras su verificación | modifico un archivo | `qg status` de la sesión A → `stale (code_changed)`; sesión nueva → run-id nuevo → `valid`; la de A sigue `stale` | `PASS WITH LIMITATIONS` | 0,49 USD |
| E | — | concurrencia | cubierto con pruebas deterministas (§3): no hacía falta una sesión real | — | — |
| F | A, D y B | Codex | real en A y D (`review --wait`, salida contrastada con el reporte); no disponible en B (`setup` → `ready:false`) → `skipped`, sin simular | — | incluido |

Primera ronda (A, B y C antes de una corrección): B y C buscaron `qg` solo en el `PATH` y trabajaron sin él (defecto 1, §4). Repetidos tras la corrección: B2 y C2 en la tabla. A sí lo encontró porque llegó a `evidence-qg.md` desde `feedback-loops.md`.

## 3. Pruebas deterministas (`bash tests/run_core_tests.sh`)

| Suite | Aserciones | Novedades de esta iteración |
|---|---|---|
| `test_fingerprint.sh` | 41 | filtros clean nunca ejecutados (incl. entradas *racy*) y huella correcta para archivos filtrados |
| `test_run.sh` | 52 | modificación **externa** durante `qg run` → `stale`; huella con escrituras simultáneas sin errores |
| `test_sessions.sh` (nueva) | 25 | requisitos por sesión, evidencia que no se comparte entre sesiones, 8 sesiones paralelas sin mezcla, `reject`, `version --json`, `gc` de sesiones, run-id con `../` rechazado |
| `test_state.sh` | 55 | — |
| `test_e2e.sh` | 15 | — |
| **Total** | **188** | también con `TMPDIR` terminado en `/` |

Además: `tests/validate.sh` OK y `tests/validate_selftest.sh` con 13 casos detectados, entre ellos la nueva regla "`valid` no equivale a `PASS`".

## 4. Defectos encontrados y corregidos

| # | Defecto | Cómo se detectó | Corrección | Regresión |
|---|---|---|---|---|
| 1 | La skill buscaba `qg` solo en el `PATH`; la detección estaba en una referencia que no siempre se lee | sesiones B y C de la primera ronda | comando de detección exacto en `SKILL.md` (PATH **y** `<skill>/../../bin/qg` con `cd -P`) | B2, C2, D |
| 2 | `qg fingerprint` **ejecutaba filtros clean** del repo (p. ej. git-lfs). `git write-tree` también los lanzaba al comprobar entradas *racy* | filtro espía en un repo sintético (14 ejecuciones en la prueba) | `-c filter.<driver>.clean= / process= / required=false` en `add` **y** `write-tree`; `--no-filters` en `hash-object` | `test_fingerprint.sh` (falla con el `qg` anterior) |
| 3 | `required` único por worktree: una sesión concurrente podía sustituir los requisitos de otra y provocar un `valid` falso | revisión del diseño + prueba que fallaba (8 fallos) | requisitos por sesión (`sessions/<run-id>/required`); `status --run-id` sin herencia | `test_sessions.sh` |
| 4 | No había forma de que la evidencia reflejara un `exit 0` sin pruebas ejecutadas | requisito del encargo; caso B | `qg reject` (solo degrada) | `test_sessions.sh` + B2 |
| 5 | No había forma de comprobar la compatibilidad de la CLI | requisito del encargo | `qg version --json` con `interface: 2` | `test_sessions.sh` |
| 6 | `find -newermt "-30 days"` no es portable (BSD) | revisión | `find -mtime -N` | `test_sessions.sh` (gc) |
| 7 | El analizador de trazas mostraba solo la primera línea de los comandos e hizo que yo sospechara, sin razón, que la sesión A había corregido antes de verificar. Los registros de `qg` lo desmintieron | contraste con `qg show` | comandos multilínea completos; detección de `$Q`/`$QG` y run-ids en toda la traza | uso manual |

Hallazgo documentado, no corregido en `qg`: los artefactos de compilación no ignorados (p. ej. `__pycache__`) cambian la huella durante la verificación y la evidencia sale `stale`. Es el comportamiento correcto: la huella cubre lo que no está ignorado. La skill recomienda modos sin escritura (`PYTHONDONTWRITEBYTECODE=1`) y proponer `.gitignore` con aprobación ([evidence-qg](../skills/quality-gate/references/evidence-qg.md) §6).

## 5. Rendimiento

Ver [evidencia.md §6](evidencia.md#6-rendimiento-medido): entre 54 y 186 ms de 1.000 a 50.000 archivos, de 2 a 5 veces el coste de `git status`. Es asumible para un futuro `Stop` y no se optimiza.

## 6. Compatibilidad y CI

- Linux: todo lo anterior.
- macOS (bash 3.2.57): la CI de `40801e3` falló en 1 de 154 aserciones, por una ruta con `//`. `8299ecf` lo corrige, y en `1fba94e` pasan las 188 aserciones, incluidas las de esta iteración.
- **CI de `1fba94e`** (run 45453036122): `validate`, `qg (ubuntu)` y `qg (macos, bash 3.2.57)` pasan; macOS ejecuta las 188 aserciones dos veces (bash por defecto y `/bin/bash`).
- ShellCheck 0.11 (en la CI; no está instalado en local) reportó en ese run 9 avisos en `bin/qg` y 4 en las pruebas. Se corrigieron los reales y se documentó el falso positivo SC2034 de las variables `R_*`. El paso pasa a ser bloqueante: su resultado limpio se comprobará en la siguiente ejecución de la CI.
- Windows: no soportado ni probado.

## 7. Limitaciones

- Seguir el protocolo (usar `qg`, no editar antes de verificar, declarar todas las obligatorias) sigue siendo **instrucción**. `qg` hace que las desviaciones sean **detectables** (registros, huellas, run-ids), pero no las impide.
- Declarar las obligatorias depende del modelo: una sesión que omitiera una en `qg require` podría obtener `valid` con un conjunto incompleto. Mitigaciones previstas: la CI y el hook `Stop` (propuesta).
- `qg reject` lo invoca el modelo al leer la salida; `qg` no interpreta salidas.
- Los escenarios son pocos, no deterministas y tienen coste. No constituyen un sistema de evals.
