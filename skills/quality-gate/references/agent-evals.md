# Fase 3 — Review (Agent Evals)

Objetivo: obtener una segunda opinión **independiente** proporcional al riesgo, y tratar sus hallazgos como hipótesis a verificar.

## 0. Tres cosas distintas — no las confundas en el reporte

| Tipo | Qué demuestra | Qué no demuestra |
|---|---|---|
| **Pruebas deterministas** (tests, lint, tipos) | que el código cumple lo que los tests comprueban | lo que no está cubierto |
| **Revisión por otro modelo** (Codex) | que un revisor independiente no encontró (o encontró) problemas en esta pasada | repetibilidad; otra ejecución puede dar otro resultado |
| **Evaluaciones repetibles** (rúbrica + casos fijos + puntuación a lo largo del tiempo) | tendencia de calidad medible | — |

Esta versión de la skill hace las dos primeras. Una revisión puntual de Codex **no** es un sistema de evals; no la presentes como tal.

## 1. Detectar Codex

No asumas que existe ni que sus comandos coinciden con la documentación. Comprueba en este orden:

1. ¿Aparecen skills/comandos `codex:*` en la sesión? (p. ej. `codex:rescue`, `codex:setup`).
2. Localiza el plugin instalado: `~/.claude/plugins/installed_plugins.json` → entrada `codex@openai-codex` → `installPath`.
3. Lista lo que ofrece **esa versión**: `ls "<installPath>/commands"` y `node "<installPath>/scripts/codex-companion.mjs" help`.
4. Comprueba que el CLI está listo: `node "<installPath>/scripts/codex-companion.mjs" setup --json` (solo lectura del estado; **no** uses `--enable-review-gate` ni `--disable-review-gate` sin que el usuario lo pida).

Si cualquier paso falla → `review: skipped (unavailable: <motivo>)` y continúa.

Notas verificadas con el plugin 1.0.6 (revalida si la versión cambia):

- `/codex:review` y `/codex:adversarial-review` tienen `disable-model-invocation: true`: Claude no puede lanzarlos como skill. Opciones:
  - ejecutar el script equivalente con Bash: `node "<installPath>/scripts/codex-companion.mjs" review --wait --scope <auto|working-tree|branch> [--base <ref>]` (o `adversarial-review ... [foco]`), o
  - pedir al usuario que ejecute el slash command y comparta la salida.
- `review` es de solo lectura y no admite texto de foco; para foco o enfoque adversarial, `adversarial-review`.
- `rescue`/`task --write` **escriben** código: no los uses para revisar.

## 2. Política por riesgo

| Riesgo | Revisión |
|---|---|
| `low` | ninguna por defecto (`skipped (low risk)`), salvo petición |
| `medium` | `review` estándar sobre el alcance |
| `high` | `review` + `adversarial-review` con foco en las señales de riesgo detectadas; aprobación humana antes de cerrar |

La config opcional puede ajustar umbrales (`review.min_risk_for_review`, `review.adversarial_at`). Revisiones largas: si el diff es grande, ejecútalas en segundo plano y continúa con otras verificaciones; no esperes en bucle.

## 3. Criterios que se piden al revisor

Al usar foco (adversarial), formula criterios verificables:

- corrección funcional frente a los criterios de aceptación,
- casos límite y manejo de errores,
- regresiones en llamadores/dependientes,
- seguridad (entrada no confiable, autorización, secretos, inyección),
- aislamiento entre tenants cuando aplique,
- arquitectura y mantenibilidad (acoplamiento, duplicación) — sin imponer preferencias estéticas.

## 4. Tratamiento de hallazgos

Cada hallazgo es una **hipótesis**:

1. Reprodúcelo o compruébalo en el código (leer la ruta, escribir un test que falle, ejecutar un caso).
2. Clasifícalo: `confirmed` | `rejected` (con motivo) | `needs-human` (depende de intención de producto o de información no disponible).
3. Corrige solo los `confirmed` dentro del alcance, aplicando el mismo límite de iteraciones de [feedback-loops](feedback-loops.md), y reejecuta las verificaciones afectadas.
4. No aceptes sugerencias sin fundamento ni reescrituras de estilo no pedidas.

## 5. Aislamiento entre agentes

- Nunca dos agentes editando los mismos archivos a la vez.
- La revisión es de solo lectura. Si se delega **escritura** a otro agente (Codex `rescue`, subagentes), hazlo en un worktree aislado o de forma secuencial, y comprueba sus permisos antes.

## 6. Sin Codex

La puerta sigue funcionando. Reporta explícitamente `review: skipped (unavailable)` y, en riesgo `high`, añade como pendiente "revisión independiente no realizada" para que el humano decida. No sustituyas la revisión por una auto-revisión presentada como independiente; si haces una revisión propia, etiquétala como `self-review`.
