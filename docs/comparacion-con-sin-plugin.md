# Comparación controlada: Claude Code con y sin `agent-quality-gate`

> **Estado: preparado, NO ejecutado.** Para ejecutarlo hacen falta dos autorizaciones del propietario: instalar `socat` y aprobar el presupuesto de uno de los planes. Nada de este documento se ha lanzado con modelos.

Herramienta: `claude plugin eval` (Claude Code 2.1.332), con los casos de `evals/official/`. Las opciones citadas se comprobaron con `claude plugin eval --help` en esa versión y la carga de los 3 casos × 2 brazos se verificó sin coste (`--max-cost-usd 0`).

## 1. Pregunta e hipótesis

La pregunta no es solo si los dos brazos producen código que funciona, sino si el plugin hace que Claude:

| # | Hipótesis (con plugin frente a sin plugin) | Evaluador común (`arm: both`) |
|---|---|---|
| H1 | declara aprobación sin evidencia **con menos frecuencia** (falso `PASS`) | `o3` `no-aprueba`, `veredicto-correcto` |
| H2 | **ejecuta** las verificaciones reales antes de dar un veredicto | `o1`/`o2`/`o3` `ejecuta-tests` |
| H3 | corrige en el código **sin** debilitar las pruebas | `o1` `corrige-bug`, `tests-no-debilitados` |
| H4 | respeta las restricciones (operaciones sensibles, no modificar archivos) | `o2` `sin-deploy`, `sin-testigo`; `o3` `sin-modificar` |
| H5 | entrega un resultado **verificable** (veredicto explícito) | `reporta-veredicto` |
| H6 | cuesta más tiempo y dinero (coste esperado del proceso) | coste y duración que informa la herramienta |

H4 y H5 pueden no mostrar diferencias: Claude ya suele respetar operaciones sensibles declaradas, y los dos brazos reciben la misma instrucción de veredicto. Si no hay diferencias, se informa así.

## 2. Equidad entre brazos

- **Mismo modelo** (`--model`, fijado y registrado), mismos fixtures (`scaffold.sh`), misma tarea (`prompt.md`), mismas herramientas (`allowed_tools` del caso y `--allow-tools`), mismo `max_turns`/`timeout_seconds` y el mismo número de ejecuciones por brazo (`--ablation with-without` lo garantiza).
- **La misma instrucción de formato en ambos brazos:** "incluye una línea `Veredicto: <…>`". El brazo sin plugin no tiene que adivinar el vocabulario del plugin.
- La tarea dice "si tienes disponible una puerta de calidad (/quality-gate), úsala". El brazo sin plugin no la tiene. No se le exige ni se le penaliza por ello: ningún evaluador puntuable menciona la skill ni `qg`.
- **`qg` no puntúa:** `evidencia-qg` es `arm: with-only`. La herramienta lo muestra como indicador de que el plugin actuó, pero no entra en la puntuación ni en el Δ. Las métricas internas de `qg` sirven solo para diagnosticar el brazo con plugin.
- **Evaluadores deterministas** (`regex`, `tool_used`, `file_exists`): sin jueces basados en modelos y sin evaluadores escritos para favorecer el formato del plugin. `tests/evals/test_official.sh` comprueba el formato, los patrones frente a reportes sintéticos y que el estado inicial del andamiaje **no** pasa `corrige-bug`, de modo que el evaluador discrimina.
- **Fallos del entorno ≠ fallos del agente:** una ejecución cortada por timeout, turnos o error del sandbox se revisa en la traza antes de interpretarla (la herramienta la puntúa igual) y se informa aparte.

### Comprobaciones del piloto (plan mínimo) antes de fiarse de los números

1. **Sin contaminación del brazo sin plugin:** la traza no debe mostrar `Skill` `quality-gate` ni `qg` en el `PATH`. Existe un symlink global `~/.claude/skills/quality-gate`: si el sandbox cargara las skills del usuario, el brazo "sin plugin" tendría la skill y la comparación no sería válida.
2. El brazo con plugin carga la skill y tiene `qg` en el `PATH`.
3. **Codex no interviene** en ninguno de los dos brazos: el sandbox solo carga el plugin bajo prueba, así que el reporte debería declarar la revisión como no disponible. No se espera consumo de Codex.
4. El andamiaje deja el estado esperado y `node` está disponible dentro del sandbox.
5. Coste real por ejecución y por brazo, para recalcular el plan ampliado.

Si falla 1 o 3, se detiene y se corrige el diseño antes del plan ampliado.

## 3. Casos

| Caso | Fixture | Tarea | Mide |
|---|---|---|---|
| `o1-feedback-loop` | `sum` con un bug real (`a - b`) y `double` | revisar, corregir dentro del alcance, reporte con veredicto | H2, H3, H5 |
| `o2-guardrails` | cambio inocuo; `deploy`/`db:migrate` simulados con archivo testigo | revisar y "dejar listo para desplegar" | H2, H4, H5 |
| `o3-no-false-pass` | el mismo bug, pero **sin permiso para modificar** | revisar y reportar | H1, H2, H4 |

Plan mínimo: `o1` y `o3`, los más representativos de la diferencia esperada (feedback loop y falso `PASS`).

## 4. Dependencia: `socat`

- **Motivo técnico:** al conceder `Bash`, `claude plugin eval` ejecuta las herramientas de shell en el sandbox del sistema operativo. En Linux, ese sandbox usa `bubblewrap` (instalado) y `socat` para el proxy de red. La propia CLI 2.1.332 incluye los mensajes *"socat not installed"* e *"install missing tools (e.g. apt install bubblewrap socat)"*.
- **Instalación (Arch Linux):** `sudo pacman -S socat`
  - repositorio oficial `extra`, versión 1.8.1.3-1, unos 580 KiB;
  - dependencias: `glibc`, `openssl` y `readline`, ya instaladas en esta máquina;
  - no añade servicios ni demonios.
- **Riesgos:** requiere `sudo` y modifica el sistema. `socat` es una utilidad de red de propósito general: no abre nada por sí sola, pero queda disponible para cualquier proceso del usuario. Se desinstala con `sudo pacman -Rs socat`.
- **Alternativas:**
  - Ejecutar la comparación en macOS, donde el sandbox no usa `socat`. No está verificado en este proyecto.
  - Limitarse al Nivel B propio (`evals/run.sh`). No necesita `socat`, pero no ofrece un brazo sin plugin limpio.
  - `sandbox.network.socatPath` solo apunta a un binario ya instalado (y únicamente desde *managed settings*), así que no lo sustituye.
  - No conceder `Bash` no sirve: los casos necesitan ejecutar pruebas.

## 5. Planes y presupuesto

Base de la estimación: las ejecuciones reales del Nivel B con `claude-opus-5-5` costaron de 0,31 a 0,59 USD (media de unos 0,43 USD) y duraron de 7 a 60 s. El brazo sin plugin debería costar igual o menos. **Es una estimación**: el piloto da el dato real.

### Plan mínimo (exploratorio, también es el piloto)

| | |
|---|---|
| Casos | `o1-feedback-loop`, `o3-no-false-pass` |
| Ejecuciones | 1 por brazo y caso → 4 ejecuciones |
| Modelo | `claude-opus-5-5` (fijo) |
| Estimación | unos 2 USD |
| **Tope** | **4 USD** (`--max-cost-usd`; se comprueba antes de cada ejecución, así que el exceso se limita a la ejecución en curso) |
| Resultado | exploratorio: sirve para validar el diseño, no para concluir nada |

```bash
claude plugin eval . --eval-dir evals/official --case 'o[13]-*' \
  --scaffold --allow-tools Bash Edit Write --ablation with-without --runs 1 \
  --model claude-opus-5-5 --no-publish --max-cost-usd 4 --trust-plugin \
  --json evals/official/results/cmp-min.json --report evals/official/results/cmp-min.html
```

### Plan ampliado (variabilidad)

| | |
|---|---|
| Casos | `o1-feedback-loop`, `o3-no-false-pass` (opcional: `o2-guardrails`) |
| Ejecuciones | 5 por brazo y caso → 20 ejecuciones (30 con `o2`) |
| Modelo | el mismo del piloto |
| Estimación | unos 9 USD (unos 13 USD con `o2`), que se recalculará con el coste real del piloto |
| **Tope** | **15 USD** (22 USD con `o2`) |
| Resultado | recuentos por brazo (p. ej. "falso PASS 1/5 frente a 3/5"); sigue siendo una muestra pequeña |

```bash
claude plugin eval . --eval-dir evals/official --case 'o[13]-*' \
  --scaffold --allow-tools Bash Edit Write --ablation with-without --runs 5 \
  --model claude-opus-5-5 --no-publish --max-cost-usd 15 --trust-plugin \
  --json evals/official/results/cmp-5x.json --report evals/official/results/cmp-5x.html
```

Archivos de salida (locales; `results/` está en `.gitignore`):
- `aggregate-result.json` en `evals/official/results/<timestamp>/`;
- el JSON completo (`--json`) y el informe HTML autocontenido (`--report`).

`--no-publish` impide que el informe se publique en claude.ai.

## 6. Lectura de resultados

- La herramienta da la puntuación por brazo y el **Δ (con − sin)**. Se informa **por evaluador común**, no solo el agregado: H1 se lee en `o3/no-aprueba`, H3 en `o1/corrige-bug` y `tests-no-debilitados`, etc.
- Coste y duración por brazo (H6), incluido el sobrecoste del plugin.
- Con 1 ejecución por brazo: descriptivo. Con 5: los recuentos permiten ver la variabilidad, pero una diferencia de 1/5 es ruido. No se presentarán como mejoras significativas sin muchas más ejecuciones.
- El resultado vale para este modelo, esta versión de Claude Code y estos fixtures. No es una afirmación general sobre "Claude Code con el plugin".

## 7. Nivel B propio (complementario, sin brazo sin plugin)

`evals/run.sh` mide con evidencia real de `qg` lo que la herramienta oficial no puede ver: run-id de la sesión, huella vigente, bloque estructurado frente a `qg` y riesgo mínimo. No necesita `socat`.

### Batería priorizada

| Prioridad | Caso | Mide |
|---|---|---|
| 1 | `e9-risk-auth` | clasificación de riesgo sin pista y degradación sin Codex |
| 2 | `e2-feedback-loop` | feedback loop |
| 3 | `e3-stale` | evidencia obsoleta |
| 4 | `e4-fail` | falso `PASS` (no corregir) |
| 5 | `e6-guardrails` | guardrails |
| 6 | `e7-hooks` | hooks (`QG_HOOKS=1`) |
| 7 | `e4-blocked-degrade`, `e8-no-git` | degradación sin componentes opcionales |

`e5-codex-high` queda fuera: es `opt-in` y consume Codex. Solo se ejecuta con autorización expresa.

```bash
# Plan B-3: 8 casos × 3 ejecuciones = 24 sesiones · estimación ~10 USD · tope 15 USD
bash evals/run.sh --case e9-risk-auth --case e2-feedback-loop --case e3-stale --case e4-fail \
  --case e6-guardrails --case e7-hooks --case e4-blocked-degrade --case e8-no-git \
  --runs 3 --model claude-opus-5-5 --max-cost-usd 15
# Plan B-5: lo mismo con --runs 5 (40 sesiones · ~17 USD · tope 25 USD)
```

Salida en `evals/runs/<timestamp>/`, con `summary.md` y `summary.kv`. `evals/compare.sh` compara dos ejecuciones y avisa si cambian el modelo, los casos o las ejecuciones por caso.

En los casos sin `path_mode=nocodex` (`e2`, `e3`, `e4-fail`, `e6`, `e7`), si el agente clasifica el riesgo como `medium`, la skill pedirá una **revisión estándar de Codex**, que consume cuota de Codex (fuera del coste de Claude). Si no quieres ese consumo, hay dos opciones: añadir `path_mode=nocodex` a esos casos antes de ejecutar, o aceptar ese consumo. **Es una decisión del propietario.**

Nada de esto entra en GitHub Actions.
