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
- `--wait` bloquea hasta terminar: lanza el Bash con un timeout amplio (hasta 10 min) o en segundo plano si el diff es grande.

Interpretación del resultado (comprobado con 1.0.6):

| Situación | Salida | Clasificación |
|---|---|---|
| revisión ejecutada | exit 0, informe con resumen/hallazgos | `review: done` |
| alcance sin cambios | **exit 0** y "working tree is clean ... no changes to review" | `review: skipped (nothing to review)` — **no** es una revisión hecha |
| fuera de un repo Git | exit 1, "must run inside a Git repository" | `review: error` |
| CLI ausente / sin sesión | exit 1, "Codex CLI is not installed..." | `review: skipped (unavailable)` |

Cualquier exit ≠ 0 o salida sin informe de revisión es `error` o `skipped`, nunca `done`.

Privacidad: la revisión envía el diff a un servicio externo (OpenAI). Si las instrucciones del repo restringen compartir código con terceros, o el diff contiene secretos o datos sensibles, no la lances sin aprobación.

## 2. Política por riesgo

| Riesgo | Revisión |
|---|---|
| `low` | ninguna por defecto (`skipped (low risk)`), salvo petición |
| `medium` | `review` estándar sobre el alcance |
| `high` | `review` + `adversarial-review` con foco en las señales de riesgo detectadas; aprobación humana antes de cerrar |

La config opcional puede ajustar umbrales (`review.min_risk_for_review`, `review.adversarial_at`). Revisiones largas: si el diff es grande, ejecútalas en segundo plano y continúa con otras verificaciones; no esperes en bucle.

Orden: revisa **después** de que las verificaciones pasen, sobre el código final. Si corriges hallazgos de la revisión, reejecuta las verificaciones afectadas (con `qg run` si está disponible; la edición deja la evidencia anterior `stale`). No hace falta repetir la revisión completa salvo que la corrección sea amplia; la corrección de un hallazgo **crítico** exige la revisión acotada de §5. La revisión de Codex **no** se registra como verificación de `qg` ni sustituye a ninguna obligatoria.

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
3. Indica en el reporte **cómo** se sostiene cada hallazgo:
   - **por lectura de código**: se ve en el código, sin ejecutarlo;
   - **reproducido con una prueba**: un test o un caso lo demuestra;
   - **confirmado con otra evidencia**: logs, salida de un comando, documentación del proyecto;
   - **pendiente de confirmación**: no se pudo comprobar todavía;
   - **revisión impedida por el sandbox**: el revisor no pudo ejecutar lo necesario.

   Un hallazgo "por lectura" que el sandbox impidió probar **no** se invalida: intenta reproducirlo tú.
4. Corrige solo los `confirmed` dentro del alcance, aplicando el mismo límite de iteraciones de [feedback-loops](feedback-loops.md), y reejecuta las verificaciones afectadas.
5. No aceptes sugerencias sin fundamento ni reescrituras de estilo no pedidas.

## 5. Segunda revisión acotada tras corregir un hallazgo crítico

**Cuándo aplica** (las tres condiciones a la vez):

- hay un hallazgo `confirmed` de una categoría crítica: auth, autorización, multi-tenant, concurrencia, idempotencia, secretos, operaciones críticas de datos, o severidad alta/crítica;
- el hallazgo se corrigió;
- la revisión independiente está disponible y autorizada.

**Qué exige, en este orden:**

1. Reejecutar las verificaciones afectadas.
2. Una revisión independiente **acotada al diff de la corrección**, una sola vez: `adversarial-review` con el texto de foco del hallazgo. El alcance depende de dónde esté la corrección, porque con `--base <ref>` Codex revisa solo commits (`merge-base...HEAD`, comprobado en el plugin 1.0.6) y **no** ve el working tree:
   - **corrección sin commitear** y el working tree no contiene otros cambios: `--scope working-tree`, p. ej. `node "<installPath>/scripts/codex-companion.mjs" adversarial-review --wait --scope working-tree "<foco del hallazgo>"`;
   - **corrección ya commiteada** (por el usuario o con su autorización): `--base <commit previo a la corrección>`, cuyo sha anotaste antes de corregir (`git rev-parse HEAD`).
   No hagas un commit solo para poder usar `--base`: commitear sigue las reglas del repositorio. Si el working tree mezcla la corrección con otros cambios y no está commiteada, no puedes aislar su diff: revisa el working tree completo con el foco del hallazgo y dilo en el reporte.
3. Registrar el resultado en el bloque estructurado: `review.critical_fixed: true` y `review.followup` (`done` | `pending` | `not_required`).

**Sin ciclos.** Si la revisión acotada encuentra un problema nuevo Important o Critical, no hay otra ronda automática: para y repórtalo (veredicto `BLOCKED` o `FAIL` según el caso, con decisión humana). El límite de 2 iteraciones de corrección no cambia.

**Si Codex no está disponible o está prohibido:** `followup: pending`, declara la limitación con su motivo (`review.reason` o el texto del reporte) y el veredicto máximo es `PASS WITH LIMITATIONS`. Una auto-revisión no cuenta como independiente. Si Codex **funcionó en esta sesión** (la primera revisión se ejecutó), "no disponible" no vale: o haces la revisión acotada, o el reporte indica que la política del repositorio la prohíbe (prohibido, no autorizado, política…).

Las Agent Evals lo comprueban con el check `security_followup`: si el reporte declara una corrección crítica y aprueba (`PASS` o `PASS WITH LIMITATIONS`), tiene que haber una invocación de Codex posterior a la última edición, o `followup: pending` con un veredicto no superior a `PASS WITH LIMITATIONS`. Con una invocación de Codex correcta en la traza, `pending` solo se acepta si el reporte declara que la política del repositorio prohíbe la revisión; si no, falla (`suspected` cuando el hallazgo crítico solo se deduce de la tabla Markdown). El check comprueba que esa invocación existe y no terminó con error. Además, baja el `pass` a `suspected` si después de la última revisión hay comandos Bash que parecen modificar archivos (`sed -i`, `tee`, `>` a un archivo, `git apply`, `patch`, `cp`/`mv`/`rm`, `--write`/`--fix`…), o si el alcance contradice la traza: `--base` apunta al commit que creaste con la corrección, o usas `--base HEAD` o `--scope working-tree` después de commitearla. Solo da la base por confirmada si su sha aparece en la salida de un comando git anterior a la corrección (p. ej. `git rev-parse HEAD`); si no, la informa como no verificable. No comprueba qué diff vio Codex ni lo que dijo. Eso sigue siendo responsabilidad tuya. Si lanzas la revisión con `--background`, lee su resultado completo antes de declarar `followup: done`.

## 6. Aislamiento entre agentes

- Nunca dos agentes editando los mismos archivos a la vez.
- La revisión es de solo lectura. Si se delega **escritura** a otro agente (Codex `rescue`, subagentes), hazlo en un worktree aislado o de forma secuencial, y comprueba sus permisos antes.

## 7. Sin Codex

La puerta sigue funcionando. Reporta explícitamente `review: skipped (unavailable)` y, en riesgo `high`, añade como pendiente "revisión independiente no realizada" para que el humano decida. No sustituyas la revisión por una auto-revisión presentada como independiente; si haces una revisión propia, etiquétala como `self-review`.
