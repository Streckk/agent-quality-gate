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

Salida: un reporte con veredicto `PASS`, `PASS WITH LIMITATIONS`, `FAIL` o `BLOCKED`, y una tabla de verificaciones `passed | failed | blocked | skipped` con comando y exit code. Formato en [report-format.md](skills/quality-gate/references/report-format.md).

### Configuración opcional por proyecto

`.agent/verification.yaml` permite declarar checks, límite de iteraciones, umbrales de revisión, rutas de alto riesgo y comandos prohibidos. Es opcional. Esquema en [project-discovery.md](skills/quality-gate/references/project-discovery.md#6-configuración-opcional-agentverificationyaml) y ejemplos en [examples/](examples/).

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
```

CI ejecuta ambos en cada push y PR (`.github/workflows/validate.yml`), sin secretos.

Actualizar: `git pull` en el clon; con symlink no hace falta reinstalar. Si cambia la versión del plugin Codex, revalida las notas de `agent-evals.md`.

## Política de autoría

Los commits de este repositorio van solo a nombre del propietario. No se añaden trailers `Co-Authored-By`, créditos de IA ni entradas en archivos de autoría. `tests/validate.sh` comprueba que el contenido no los incluya.

## Limitaciones

- Es una instrucción: Claude puede no seguirla perfectamente. Para garantías, combínala con permisos, hooks y CI.
- La revisión de Codex es puntual y no determinista; no equivale a un sistema de evals.
- El descubrimiento de comandos depende de que el repo los declare (manifiestos, Makefile, CI, config).

## Hooks opcionales (propuesta para v2)

No incluidos en la v1. Candidatos:

- **`Stop`**: bloquear el cierre del turno si hubo ediciones y no existe un reporte de quality-gate reciente. Bloqueo verificable: el hook devuelve `decision: block`.
- **`PreToolUse` sobre Bash**: denegar comandos de `forbidden_commands` de `.agent/verification.yaml`. Bloqueo verificable: el comando no se ejecuta.
- **`PreToolUse` sobre `git commit`**: rechazar mensajes con trailers de coautoría de IA.
