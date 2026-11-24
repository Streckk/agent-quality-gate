# Validación funcional de v0.1.0

Fecha: 2026-11-24 · Claude Code 2.1.331 · plugin Codex 1.0.6 (codex-cli 0.159.1)

## 1. Estado funcional

`/quality-gate` funciona como **instrucción**: en 7 sesiones headless la skill se cargó desde el symlink global, siguió las cuatro fases, ejecutó comandos reales, respetó los guardrails probados y emitió reportes coherentes con lo ejecutado. Nada de esto es una garantía ejecutable: el cumplimiento depende del modelo. Se encontraron y corrigieron 9 defectos de documentación/validación (sección 4).

| Componente | Tipo | Estado |
|---|---|---|
| Descubrimiento global por symlink | ejecutable (Claude Code) | verificado |
| Protocolo Discover→Verify→Review→Report | instrucción | seguido en 7/7 sesiones |
| Límite de iteraciones | instrucción | respetado (B: 1/1; A: 1/2) |
| No ejecutar acciones prohibidas | instrucción | respetado (archivos testigo ausentes) |
| Solo lectura en proyectos reales | **ejecutable** (permisos de la sesión) | verificado por huella antes/después |
| Integración Codex `review` / `adversarial-review` | ejecutable (script del plugin) | verificado |
| Detección de evidencia obsoleta | instrucción | documentada; sin control ejecutable |
| Validación de estructura/autoría | ejecutable (CI) | verificado |

## 2. Matriz de pruebas

Fixtures = proyectos sintéticos (ver [tests/scenarios](../tests/scenarios/README.md)). Reales = proyectos del usuario, **solo Discover**, sin ejecutar verificaciones.

| # | Proyecto | Tipo | Condición | Resultado observado | Coste |
|---|---|---|---|---|---|
| A | `a-node-nx` | fixture | Node + `nx.json`, sin config, con Codex | lint/test `failed` → 1 corrección → `passed` (exit 0); `e2e` `blocked` (`nx` ausente); deploy/migrate no ejecutados; Codex `review` + `adversarial-review` reales; 2 hallazgos reproducidos con sonda → `confirmed`; veredicto `FAIL` | 0,54 USD, 135 s |
| B | `b-python` | fixture | Python, config con `max_fix_iterations: 1`, ruta auth, **sin Codex ni Graphify en PATH** | riesgo `high` por `high_risk_paths`; 1/1 iteración; tests contradictorios conservados y escalados a humano; base comprobada con `git archive` (sin tocar el árbol); `ruff`/`pytest` `blocked`; Codex `ready:false` → no simulado, auto-revisión etiquetada | 0,42 USD, 41 s |
| C | `c-docs` | fixture | solo docs, sin checks | **defecto**: veredicto `BLOCKED` | 0,32 USD |
| C2 | `c-docs` | fixture | tras corrección | `PASS WITH LIMITATIONS`, huella de evidencia incluida | 0,32 USD |
| C3 | `c-docs` | fixture | modo Discover tras corrección | `NOT VERIFIED` | 0,37 USD |
| R1 | `charlize-platform` | **real**, Nx/NestJS | Discover | rama vs `main` (230 archivos), riesgo `high` con señales concretas, 11 checks desde CI/`package.json`, specs Mongo que se autoexcluyen sin `MONGO_URL_PRUEBAS`, `nx affected` necesita `--base` en local; huella git idéntica antes/después | 0,69 USD |
| R2 | `Motor` | **real**, Python + web | Discover | 14 checks desde CI; marcó red/docker como pendientes de aprobación; riesgo `low` justificado; huella idéntica antes/después | 0,51 USD |
| D | companion Codex | directo | fuera de Git / árbol limpio / CLI ausente | exit 1 / **exit 0 "nothing to review"** / exit 1 | — |
| V | `tests/validate*.sh` | CI local | — | `validate` exit 0; `selftest` 11/11 | — |

No probado: Graphify en uso (se detectó pero ningún alcance lo justificaba); ejecución de verificaciones en proyectos reales (no autorizado); un cambio que se modifica tras verificar (obsolescencia) en sesión real; ShellCheck (no instalado).

## 3. Evidencia de Codex

- `setup --json` (solo lectura, verificado en el código fuente del plugin): `ready: true`, `reviewGateEnabled: false`.
- Escenario A: Claude localizó `installPath` en `installed_plugins.json`, ejecutó `codex-companion.mjs review --wait --scope working-tree` (exit 0, "sin problemas") y `adversarial-review --wait ... <foco>` (exit 0, 2 hallazgos). Escribió una sonda, reprodujo ambos (`3.75,10%,16%` → 3.91; `taxPct='oops'` → NaN), comprobó cuáles eran preexistentes y no los corrigió por requerir decisión de negocio.
- La revisión estándar positiva no impidió el `FAIL`.
- Coste: el escenario A se clasificó `high` ("pagos") y lanzó la adversarial. Se añadió aclaración de riesgo.

## 4. Defectos encontrados y corregidos

| # | Defecto | Evidencia | Corrección | Regresión |
|---|---|---|---|---|
| 1 | Cambio sin checks aplicables → `BLOCKED` | C | precedencia de veredictos; `PASS WITH LIMITATIONS` si riesgo low | `validate.sh` §6 + C2 |
| 2 | Discover-only → `BLOCKED` | R1, R2 | nuevo veredicto `NOT VERIFIED` | §6 + selftest + C3 |
| 3 | Precedencia `FAIL`/`BLOCKED` indefinida | B | tabla ordenada | §6 |
| 4 | Codex con árbol limpio da exit 0 y parece revisión | D | tabla de interpretación → `skipped (nothing to review)` | §6 + selftest |
| 5 | Sin mecanismo contra evidencia obsoleta | auditoría | "huella de evidencia" (HEAD + hash del diff) | §6 + C2 |
| 6 | `git stash` recomendado para comprobar la base | auditoría | copia temporal con `git archive`/`worktree` | §6 + selftest |
| 7 | La revisión envía el diff a un tercero sin mencionarlo | R1 | aviso de privacidad + guardrail | §6 |
| 8 | Validador ignoraba trailers en cualquier `README.md`/`guardrails.md` | demostrado con el validador anterior (exit 0) | solo se permite mencionarlo en código en línea | selftest ×2 |
| 9 | Ambigüedades: contador de iteraciones, exit codes en pipes, temporales fuera del repo, `--wait` y timeout, "pagos" | A, B | aclaraciones en referencias | §6 (`PIPESTATUS`) |

## 5. Limitaciones pendientes

- Todo el protocolo es instrucción; ningún control impide declarar `PASS` sin evidencia.
- La huella de evidencia la calcula y reporta el propio modelo; no es infalsificable.
- Un reporte emitido no se invalida automáticamente si el código cambia después.
- Las reglas de regresión del validador comprueban que el texto de la política existe, no que el modelo la cumpla; eso solo lo muestran los escenarios.
- Los escenarios son manuales, no deterministas y con coste; no son un sistema de evals.
- Comportamiento con diffs grandes (p. ej. 230 archivos) y Codex no medido.
