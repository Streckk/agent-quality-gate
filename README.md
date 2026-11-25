# agent-quality-gate

Skill global para Claude Code, **agnóstica del stack**, que coordina una puerta de calidad sobre cualquier cambio de código: `/quality-gate`.

No es un motor ni una CLI. Es un conjunto de instrucciones (`SKILL.md` + referencias en Markdown) que indica a Claude cómo **descubrir** las verificaciones reales del repositorio, **ejecutarlas** con un bucle de corrección acotado, pedir **revisión independiente** a Codex según el riesgo y **reportar** con evidencia.

Funciona sin Nx, sin Node, sin Graphify y sin Codex. Las integraciones opcionales se detectan en tiempo de ejecución y, si faltan, se reportan como `skipped`, nunca se simulan.

## Los tres pilares

| Pilar | Qué hace la v1 | Referencia |
|---|---|---|
| **Feedback Loops** | descubre y ejecuta lint/tipos/tests/build reales, corrige con máximo 2 iteraciones (configurable), reejecuta lo afectado | [feedback-loops.md](skills/quality-gate/references/feedback-loops.md) |
| **Agent Evals** | revisión independiente con el plugin Codex según riesgo; hallazgos tratados como hipótesis | [agent-evals.md](skills/quality-gate/references/agent-evals.md) |
| **Guardrails** | distingue instrucciones de controles ejecutables; exige aprobación para acciones sensibles | [guardrails.md](skills/quality-gate/references/guardrails.md) |

Lo que la v1 **no** ofrece: un sistema de evals repetibles (rúbricas + casos + histórico), hooks que bloqueen acciones, ni garantías ejecutables propias. Ver [Limitaciones](#limitaciones).

## Skills, herramientas, hooks y garantías

| Concepto | Qué es | ¿Impone algo? |
|---|---|---|
| **Skill** (esta) | instrucciones que Claude carga cuando son relevantes o al invocar `/quality-gate` | No. Orienta; no garantiza. |
| **Herramienta** | lo que Claude puede ejecutar (Bash, Edit, MCP) | Ejecuta, no decide. |
| **Permisos** (`settings.json`) | allow/deny de herramientas y comandos | Sí, dentro de Claude Code. |
| **Hooks** | scripts en eventos (`PreToolUse`, `Stop`...) | Sí, si están configurados. |
| **CI / protección de ramas** | checks en el servidor | Sí, para lo que bloquean. |

Una regla solo es "obligatoria" si un control de las tres últimas filas la hace cumplir.

## Instalación

### Global (todas las sesiones) — recomendado para desarrollo

```bash
git clone https://github.com/Streckk/agent-quality-gate.git ~/Desarrollo/agent-quality-gate
mkdir -p ~/.claude/skills
ln -s ~/Desarrollo/agent-quality-gate/skills/quality-gate ~/.claude/skills/quality-gate
```

Claude Code descubre skills en `~/.claude/skills/<nombre>/SKILL.md` y sigue symlinks (comprobado en esta máquina con otra skill instalada así). Al ser un symlink, cualquier cambio en el repo se refleja en la siguiente sesión.

### Local (un proyecto)

```bash
mkdir -p .claude/skills
cp -r /ruta/a/agent-quality-gate/skills/quality-gate .claude/skills/
```

### Comprobar

Abre una sesión nueva de Claude Code y ejecuta `/quality-gate`. También se activa sola cuando pides "verifica esto", "revísalo antes de commitear", etc.

## Uso

```text
/quality-gate                         # cambios del working tree
/quality-gate branch main             # rama actual vs main
/quality-gate src/auth --risk high    # rutas concretas, forzando riesgo alto
/quality-gate --no-review             # sin revisión externa
```

Salida: un reporte con veredicto `NOT VERIFIED`, `FAIL`, `BLOCKED`, `PASS WITH LIMITATIONS` o `PASS` (en ese orden de precedencia), una tabla de verificaciones `passed | failed | blocked | skipped` con comando y exit code, y una huella de evidencia (HEAD + hash del diff) que indica si la evidencia corresponde al código actual. Formato en [report-format.md](skills/quality-gate/references/report-format.md).

### Configuración opcional por proyecto

`.agent/verification.yaml` permite declarar checks, límite de iteraciones, umbrales de revisión, rutas de alto riesgo y comandos prohibidos. Es opcional. Esquema en [project-discovery.md](skills/quality-gate/references/project-discovery.md#6-configuración-opcional-agentverificationyaml) y ejemplos en [examples/](examples/).

## Evidencia ejecutable: `qg` (v0.2.0-dev, en desarrollo)

`bin/qg` (bash + git, sin otras dependencias) registra qué código se verificó, qué comando se ejecutó, su exit code real y si esa evidencia sigue vigente. Funciona sin Claude Code:

```bash
export PATH="$HOME/Desarrollo/agent-quality-gate/bin:$PATH"
qg require lint unit
qg-run lint -- npm run lint
qg-run unit -- pytest -q
qg status        # valid | failed | blocked | incomplete | stale | missing
qg require --run-id mi-sesion lint unit       # requisitos y evidencia aislados por sesión
```

**Integrado en la skill:** si `qg` está disponible (en el `PATH` o junto a la skill instalada por symlink) y su interfaz es compatible, `/quality-gate` sigue el flujo `qg require → qg run → qg status` con un run-id por invocación, y el reporte se basa en esa evidencia. `valid` permite aprobar, pero no aprueba por sí solo. Sin `qg`, la skill se comporta como en v0.1 y lo indica. Ver [evidence-qg.md](skills/quality-gate/references/evidence-qg.md).

Diseño, límites y correspondencia con los veredictos en [docs/evidencia.md](docs/evidencia.md). Validación en [docs/validacion-v0.2.0-dev.md](docs/validacion-v0.2.0-dev.md).

## Plugin y hooks opcionales (v0.2.0-dev, en desarrollo)

El repositorio es también un **plugin de Claude Code** (`.claude-plugin/plugin.json`): skill + `qg` en el `PATH` + tres hooks **desactivados por defecto**.

```bash
QG_HOOKS=1 claude --plugin-dir /ruta/a/agent-quality-gate     # probar sin instalar; hooks solo en esta sesión
```

| Hook | Qué hace | Qué no hace |
|---|---|---|
| `SessionStart` | registra la huella inicial de la sesión | no inyecta contexto ni ejecuta nada |
| `Stop` | si la sesión cambió código y la evidencia es `stale`/`missing`, pide **una vez** ejecutar `/quality-gate` | no bloquea con `failed`/`blocked`/`incomplete`, ni dos veces por la misma huella |
| `PreToolUse` (Bash) | `deny` a commits con trailers de IA; `ask` para `git push`/`gh pr create` sin evidencia `valid` | nunca concede permisos (`allow`) |

Los hooks no invocan modelos ni ejecutan pruebas. Comparten con la skill el run-id de sesión (`cc-<session_id>`). Se activan con `QG_HOOKS=1` o con el bloque `hooks:` de `.agent/verification.yaml`, y se desactivan con `QG_DISABLE=1`. Son **controles locales, no garantías**: lo obligatorio para todos los colaboradores va en CI y protección de ramas. Detalle: [docs/hooks.md](docs/hooks.md). Validación: [docs/validacion-v0.2.0-hooks.md](docs/validacion-v0.2.0-hooks.md).

## Agent Evals (v0.2.0-dev)

Evaluaciones repetibles del comportamiento de `/quality-gate`, con criterios objetivos. Un evaluador determinista consulta `qg status --json`, los registros, `git` y la traza, y detecta:

- falsos `PASS` y verificaciones obligatorias omitidas;
- evidencia obsoleta o de otra sesión;
- tests debilitados y cambios fuera de alcance;
- operaciones sensibles;
- revisiones de Codex simuladas o innecesarias;
- un riesgo declarado inferior al mínimo que fija el caso (el riesgo no lo decide el agente);
- contradicciones entre el reporte Markdown, su bloque estructurado y la evidencia real.

Separa las violaciones **confirmadas** de las **sospechas** heurísticas y de los resultados **inconclusos**. Los errores de infraestructura y del propio evaluador nunca cuentan como fallos del agente.

El reporte de `/quality-gate` termina con un bloque JSON pequeño y versionado (`"kind": "quality-gate-report"`, `schema` 1; ver [report-format](skills/quality-gate/references/report-format.md)). Las herramientas lo contrastan con `qg`; no es una prueba en sí mismo.

```bash
bash tests/run_eval_tests.sh                 # nivel A: sin modelos (CI)
bash evals/run.sh --case e2-feedback-loop    # nivel B: Claude real, bajo demanda (consume cuota)
```

Detalle: [docs/agent-evals.md](docs/agent-evals.md). Resultados: [docs/validacion-v0.2.0-evals.md](docs/validacion-v0.2.0-evals.md) y [docs/validacion-v0.2.0-rc.md](docs/validacion-v0.2.0-rc.md). Comparación con y sin plugin (preparada, sin ejecutar): [docs/comparacion-con-sin-plugin.md](docs/comparacion-con-sin-plugin.md). Estado para una versión estable: [docs/release-candidate.md](docs/release-candidate.md).

## Integraciones opcionales

| Integración | Uso | Si falta |
|---|---|---|
| [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) | revisión `review` / `adversarial-review` | `review: skipped (unavailable)` |
| Graphify | contexto de dependencias para cambios con impacto no evidente | se omite |
| Superpowers | planificación, TDD y depuración (no se duplican aquí) | se omite |
| frontend-design | criterio de interfaz (no se duplica aquí) | se omite |

Nota sobre Codex (plugin 1.0.6): `/codex:review` y `/codex:adversarial-review` no se pueden invocar por el modelo (`disable-model-invocation`). La skill usa el script `codex-companion.mjs` del plugin instalado o te pide ejecutar el comando. Detalles en [agent-evals.md](skills/quality-gate/references/agent-evals.md#1-detectar-codex).

## Probar en un proyecto real

1. Instala la skill globalmente (arriba).
2. En un repo con cambios sin commitear, abre Claude Code y ejecuta `/quality-gate`.
3. Comprueba en el reporte que cada `passed` tiene comando y exit code reales, y que lo omitido aparece como `skipped`/`blocked` con motivo.
4. Prueba en un repo sin Codex o con `--no-review` para ver la degradación.

## Mantenimiento

```bash
bash tests/validate.sh            # estructura, frontmatter, enlaces, autoría
bash tests/validate_selftest.sh   # el validador detecta errores conocidos
bash tests/run_core_tests.sh      # pruebas deterministas de bin/qg (repos temporales)
bash tests/run_hook_tests.sh      # pruebas de los hooks con entradas JSON simuladas
bash tests/run_eval_tests.sh      # Agent Evals nivel A (sin modelos)
claude plugin validate --strict . # validación oficial del plugin
```

CI ejecuta ambos en cada push y PR (`.github/workflows/validate.yml`), sin secretos. `validate.sh` incluye reglas de regresión que impiden borrar las políticas corregidas tras la validación funcional.

Validación funcional (manual, consume cuota): [tests/scenarios](tests/scenarios/README.md). Resultados de v0.1.0 en [docs/validacion-v0.1.0.md](docs/validacion-v0.1.0.md). La propuesta original de v0.2.0 ([docs/propuesta-v0.2.0.md](docs/propuesta-v0.2.0.md)) ya está implementada: evidencia con `qg`, hooks opcionales y Agent Evals.

Actualizar: `git pull` en el clon; con symlink no hace falta reinstalar. Si cambia la versión del plugin Codex, revalida las notas de `agent-evals.md`.

## Política de autoría

Los commits de este repositorio van solo a nombre del propietario. No se añaden trailers `Co-Authored-By`, créditos de IA ni entradas en archivos de autoría. `tests/validate.sh` comprueba que el contenido no los incluya.

## Limitaciones

- Es una instrucción: Claude puede no seguirla perfectamente. Para garantías, combínala con permisos, hooks y CI.
- La revisión de Codex es puntual y no determinista; no equivale a un sistema de evals.
- El descubrimiento de comandos depende de que el repo los declare (manifiestos, Makefile, CI, config).

## Hooks

Implementados en v0.2.0-dev (ver arriba y [docs/hooks.md](docs/hooks.md)). `forbidden_commands` de `.agent/verification.yaml` **no** se aplica con hooks: para eso están los `permissions.deny` nativos de Claude Code.
