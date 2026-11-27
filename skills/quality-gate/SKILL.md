---
name: quality-gate
description: Coordina una puerta de calidad sobre cambios de código (propios o del usuario) en cualquier stack. Descubre y ejecuta las verificaciones reales del repositorio (lint, tipos, tests, build), corrige fallos con un límite de reintentos, pide revisión independiente a Codex según el riesgo y emite un reporte con evidencia (passed/failed/blocked/skipped). Usar cuando el usuario invoque /quality-gate, pida "verifica", "pasa la puerta de calidad", "revisa antes de commitear/mergear", o antes de declarar terminado un cambio no trivial.
argument-hint: "[alcance: working-tree | branch <base> | rutas...] [--risk low|medium|high] [--no-review] | setup [--scope project|user] [--status|--remove|--dry-run]"
---

# quality-gate

Capa ligera de **coordinación** de calidad. No sustituye a otras skills:

- Brainstorming, planes y TDD → Superpowers (si está instalado). No los rehagas aquí.
- Diseño de interfaces → frontend-design. Aquí solo se valida que el resultado compile, pase pruebas y no rompa nada.
- Revisión independiente → plugin Codex (opcional).
- Contexto de dependencias → Graphify (opcional).

Funciona igual sobre código escrito por el usuario que sobre código generado por Claude.

Argumentos de esta invocación: `$ARGUMENTS`

## Subcomando `setup` (configurar CLAUDE.md)

**Solo** si los argumentos de esta invocación empiezan por la palabra `setup`, no ejecutes el protocolo: lee [setup](references/setup.md) y sigue sus pasos. En cualquier otro caso, ignora esta sección.

Script: `qg-setup` si está en el `PATH` (plugin); si no, `${CLAUDE_SKILL_DIR}/../../bin/qg-setup` (`${CLAUDE_SKILL_DIR}` es el directorio de esta skill; resuélvelo con `cd -P` porque puede ser un symlink).

## Reglas no negociables

1. **Nunca afirmes que algo pasó sin evidencia** (exit code y salida reales). Lo que no se ejecutó es `skipped` o `blocked`, nunca `passed`.
2. **Nunca simules una revisión independiente.** Si Codex no está disponible: `review: skipped (unavailable)`.
3. **Solo ejecutas comandos que existen en el repositorio** (scripts del manifiesto, Makefile, CI, config opcional). No inventes comandos ni descargues herramientas.
4. **Máximo 2 iteraciones de autocorrección** por defecto (configurable). Después: reporta el bloqueo.
5. **Acciones sensibles requieren aprobación explícita**: despliegues, migraciones o borrados de datos, secretos, push, publicación, cambios en CI/permisos/hooks. Ver [guardrails](references/guardrails.md).
6. **Corrige solo dentro del alcance** del cambio revisado. Fuera del alcance → anótalo como pendiente.
7. **Si `qg` está disponible y es compatible, cada verificación se ejecuta con `qg run`** y el reporte se basa en `qg status`. Si no lo está, se usa el modo sin `qg` y se declara así. Ver [evidence-qg](references/evidence-qg.md).

## Protocolo

Sigue las cuatro fases en orden. Carga cada referencia solo cuando llegues a su fase.

### 1. Discover
Lee [project-discovery](references/project-discovery.md). Determina:
- Alcance: qué cambios se revisan (working tree, rama vs base, rutas indicadas). Si abarca **varios repositorios**, cada uno con su base, su huella y sus verificaciones (`qg` repo a repo con el mismo run-id: evidence-qg §3a).
- Instrucciones del repo (`CLAUDE.md`, `AGENTS.md`, reglas de carpeta) y config opcional `.agent/verification.yaml`.
- Verificaciones disponibles con su comando real y su origen.
- Integraciones disponibles (Codex, Graphify, `qg`) — comprobadas, no supuestas. Ninguna es obligatoria: si falta, sigue con lo disponible y declara la limitación; no la instales.
- **`qg` (siempre, antes de verificar):** resuélvelo **una vez** a una ruta absoluta (primero el `PATH`, después junto a esta skill con `cd -P`; `qg` no tiene por qué estar en el `PATH`) y reutiliza esa ruta literal y entre comillas en todos los comandos, sin exportar variables globales. Receta en [evidence-qg](references/evidence-qg.md) §1. Si existe, sigue sus §1–3 (compatibilidad, run-id, `qg require`). Solo si no aparece en ninguno de los dos sitios, o no es compatible, usa el modo sin `qg`.
- **Efectos secundarios (con `qg`):** `qg classify -- <comando>` por cada verificación candidata, antes de ejecutarla; anota su clase en la tabla. `writes-source`, `installs-dependencies`, `external-side-effects` o `unknown` con indicios externos **piden aprobación**; no las ejecutes por tu cuenta. `classify` requiere interfaz ≥ 4: con un `qg` anterior, lee tú el script (package.json, Makefile, archivos de shell) y aplica las mismas clases. Es una heurística: no sustituye a leer el script ni a [guardrails](references/guardrails.md). Solo rebajas una clase si puedes citar el `motivo` de `classify` y la evidencia que lo contradice (evidence-qg §4b); si no, pide aprobación.
- Nivel de riesgo (`low` | `medium` | `high`). El argumento `--risk` puede subirlo, nunca bajarlo por debajo de lo que exijan las señales de alto riesgo.

### 2. Verify
Lee [feedback-loops](references/feedback-loops.md). Ejecuta las verificaciones seleccionadas (con `qg run` si está disponible), inspecciona la salida real, diagnostica, corrige de forma acotada y reejecuta lo afectado, respetando el límite de iteraciones. Un exit 0 sin pruebas ejecutadas no es `passed` (`qg reject`).

- **Línea base:** si `.agent/verification.yaml` declara `baseline` en una verificación, ejecútala con `qg run --baseline <ruta> --baseline-format typescript …` (evidence-qg §4a). Pasa solo sin diagnósticos nuevos. Crear o actualizar la línea base (`qg baseline write`) es **solo a pedido explícito** del usuario; nunca para hacer pasar un check.
- **Transparencia de caché:** anota si la salida demuestra ejecución real, caché parcial, caché total o desconocido, citando la línea de la herramienta. No inventes conteos. Una ejecución desde caché total no se presenta como ejecución real.

### 3. Review
Lee [agent-evals](references/agent-evals.md). Decide si el riesgo exige revisión independiente, úsala si está disponible y **verifica cada hallazgo** antes de actuar: indica si se sostiene por lectura, reproducido con una prueba, confirmado con otra evidencia, pendiente de confirmación o con la revisión impedida por el sandbox. Con `--no-review` la fase queda `skipped (by user)`.

Si corriges un hallazgo `confirmed` crítico (auth, autorización, multi-tenant, concurrencia, idempotencia, secretos, datos críticos, severidad alta/crítica): reejecuta las verificaciones afectadas y pide **una** revisión independiente acotada al diff de la corrección (`adversarial-review --base <commit previo>` con el foco del hallazgo). Sin ciclos: un problema nuevo Important o Critical se reporta, no abre otra ronda. Si Codex no está disponible o está prohibido, `followup: pending` y el veredicto máximo es `PASS WITH LIMITATIONS`. Declara `review.critical_fixed` y `review.followup` en el bloque estructurado (agent-evals §5).

### 4. Report
Con `qg`, consulta antes `qg status --run-id <ID> --json` (en **cada** repo del alcance) y basa en él la tabla de verificaciones (`valid` permite aprobar, no aprueba por sí solo). Emite el reporte con el formato de [report-format](references/report-format.md). El veredicto es `PASS` solo si todas las verificaciones obligatorias son `passed` sobre el código actual (huella de evidencia vigente), no quedan hallazgos confirmados sin resolver y no hay aprobaciones obligatorias pendientes. Una verificación que pasó solo contra una línea base se escribe `passed (línea base: K conocidos, F corregidos)` y limita el veredicto a `PASS WITH LIMITATIONS`. Una aprobación obligatoria pendiente para cerrar el alcance da `BLOCKED`; una acción posterior que nadie pidió (push, PR) no bloquea y se lista como `pending_optional`. Con varios repositorios, usa el esquema 2 (una tabla por repo). Si el usuario pidió solo Discover, el veredicto es `NOT VERIFIED`. Termina el reporte con el bloque estructurado (`"kind": "quality-gate-report"`, `schema` 1, o 2 con varios repositorios) que describe report-format: mismo veredicto y riesgo que el Markdown y el `status` de `qg` sin reinterpretar.

## Proporcionalidad

- Riesgo `low` (docs, cambios pequeños aislados): verificaciones rápidas del área afectada; sin revisión externa salvo petición.
- Riesgo `medium`: verificaciones completas del paquete afectado + revisión estándar si está disponible.
- Riesgo `high` (auth, permisos, multi-tenant, pagos, datos, migraciones, concurrencia, infraestructura): suite amplia + revisión adversarial + aprobación humana antes de dar por cerrado.
