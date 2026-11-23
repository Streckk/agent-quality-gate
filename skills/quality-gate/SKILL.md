---
name: quality-gate
description: Coordina una puerta de calidad sobre cambios de código (propios o del usuario) en cualquier stack. Descubre y ejecuta las verificaciones reales del repositorio (lint, tipos, tests, build), corrige fallos con un límite de reintentos, pide revisión independiente a Codex según el riesgo y emite un reporte con evidencia (passed/failed/blocked/skipped). Usar cuando el usuario invoque /quality-gate, pida "verifica", "pasa la puerta de calidad", "revisa antes de commitear/mergear", o antes de declarar terminado un cambio no trivial.
argument-hint: "[alcance: working-tree | branch <base> | rutas...] [--risk low|medium|high] [--no-review]"
---

# quality-gate

Capa ligera de **coordinación** de calidad. No sustituye a otras skills:

- Brainstorming, planes y TDD → Superpowers (si está instalado). No los rehagas aquí.
- Diseño de interfaces → frontend-design. Aquí solo se valida que el resultado compile, pase pruebas y no rompa nada.
- Revisión independiente → plugin Codex (opcional).
- Contexto de dependencias → Graphify (opcional).

Funciona igual sobre código escrito por el usuario que sobre código generado por Claude.

## Reglas no negociables

1. **Nunca afirmes que algo pasó sin evidencia** (exit code y salida reales). Lo que no se ejecutó es `skipped` o `blocked`, nunca `passed`.
2. **Nunca simules una revisión independiente.** Si Codex no está disponible: `review: skipped (unavailable)`.
3. **Solo ejecutas comandos que existen en el repositorio** (scripts del manifiesto, Makefile, CI, config opcional). No inventes comandos ni descargues herramientas.
4. **Máximo 2 iteraciones de autocorrección** por defecto (configurable). Después: reporta el bloqueo.
5. **Acciones sensibles requieren aprobación explícita**: despliegues, migraciones o borrados de datos, secretos, push, publicación, cambios en CI/permisos/hooks. Ver [guardrails](references/guardrails.md).
6. **Corrige solo dentro del alcance** del cambio revisado. Fuera del alcance → anótalo como pendiente.

## Protocolo

Sigue las cuatro fases en orden. Carga cada referencia solo cuando llegues a su fase.

### 1. Discover
Lee [project-discovery](references/project-discovery.md). Determina:
- Alcance: qué cambios se revisan (working tree, rama vs base, rutas indicadas).
- Instrucciones del repo (`CLAUDE.md`, `AGENTS.md`, reglas de carpeta) y config opcional `.agent/verification.yaml`.
- Verificaciones disponibles con su comando real y su origen.
- Integraciones disponibles (Codex, Graphify) — comprobadas, no supuestas.
- Nivel de riesgo (`low` | `medium` | `high`). El argumento `--risk` puede subirlo, nunca bajarlo por debajo de lo que exijan las señales de alto riesgo.

### 2. Verify
Lee [feedback-loops](references/feedback-loops.md). Ejecuta las verificaciones seleccionadas, inspecciona resultados, diagnostica, corrige de forma acotada y reejecuta lo afectado, respetando el límite de iteraciones.

### 3. Review
Lee [agent-evals](references/agent-evals.md). Decide si el riesgo exige revisión independiente, úsala si está disponible y **verifica cada hallazgo** antes de actuar. Con `--no-review` la fase queda `skipped (by user)`.

### 4. Report
Emite el reporte con el formato de [report-format](references/report-format.md). El veredicto es `PASS` solo si todas las verificaciones obligatorias son `passed` y no quedan hallazgos confirmados sin resolver.

## Proporcionalidad

- Riesgo `low` (docs, cambios pequeños aislados): verificaciones rápidas del área afectada; sin revisión externa salvo petición.
- Riesgo `medium`: verificaciones completas del paquete afectado + revisión estándar si está disponible.
- Riesgo `high` (auth, permisos, multi-tenant, pagos, datos, migraciones, concurrencia, infraestructura): suite amplia + revisión adversarial + aprobación humana antes de dar por cerrado.
