# Fase 4 — Report

El reporte es la salida verificable de la puerta. Debe poder auditarse: cada `passed` tiene un comando y un exit code detrás.

## Plantilla

```markdown
## Quality Gate — <VEREDICTO>

**Alcance:** <working tree | rama X vs main | rutas>  ·  **Riesgo:** <low|medium|high> (<señales>)
**Fuentes:** <CLAUDE.md, .agent/verification.yaml, package.json, CI...>
**Evidencia:** qg <versión> · status=<result> · huella <fp corto> · run-id <ID> · índice <matches|differs>
            (sin qg: `sin qg (<motivo>)` · HEAD `<sha>` · diff `<sha256 corto>` · <vigente | OBSOLETA>)

### Verificaciones
| id | comando | estado | exit | evidencia | obligatoria |
|----|---------|--------|------|-----------|-------------|
| lint | `pnpm lint` | passed | 0 | 0 warnings | sí |
| unit | `pnpm test -- --run` | failed | 1 | 2/148 fallan: auth.spec.ts | sí |
| e2e | `pnpm e2e` | blocked | — | docker no disponible | no |
| build | — | skipped | — | riesgo low, sin cambios de build | no |

### Revisión independiente
<codex review: done | skipped (motivo) | self-review (no independiente)>
| hallazgo | origen | estado | acción |
|----------|--------|--------|--------|
| ... | codex | confirmed / rejected / needs-human | corregido en ... / motivo |

### Correcciones aplicadas
- <archivo>: <qué y por qué> (iteración n/2)

### Omitido y limitaciones
- <qué no se verificó y por qué>
- <discrepancias entre fuentes>

### Pendiente de aprobación humana
- <acciones sensibles o decisiones abiertas>
```

## Veredictos

Evalúa las condiciones **en este orden**; el primer veredicto que aplique es el final:

| # | Veredicto | Condición |
|---|---|---|
| 1 | `NOT VERIFIED` | el usuario limitó la ejecución a Discover (o pidió no ejecutar verificaciones). No es un fallo ni un éxito |
| 2 | `FAIL` | alguna obligatoria `failed` (aunque se haya agotado el límite de iteraciones), o hallazgo `confirmed` sin resolver |
| 3 | `BLOCKED` | alguna obligatoria `blocked`; existen verificaciones aplicables pero no se pudo ejecutar ninguna; falta una aprobación requerida; o la huella de evidencia está obsoleta y no se reejecutó |
| 4 | `PASS WITH LIMITATIONS` | obligatorias `passed`, pero hay opcionales `blocked`/`skipped`, revisión no disponible en riesgo `medium`/`high`, fallos preexistentes, o **no existe ninguna verificación aplicable** y el riesgo es `low` |
| 5 | `PASS` | todas las obligatorias `passed`, sin hallazgos `confirmed` abiertos y sin limitaciones relevantes |

- Si no existe ninguna verificación aplicable y el riesgo es `medium` o `high`: `BLOCKED` (falta evidencia para un cambio que la necesita).
- En riesgo `high` sin revisión independiente el veredicto máximo es `PASS WITH LIMITATIONS`.
- Una revisión de Codex positiva **nunca** compensa una verificación obligatoria `failed` o `blocked`.
- Que se agote el límite de iteraciones se indica en "Correcciones aplicadas" (`n/max`), no cambia la precedencia.

## Huella de evidencia (anti-obsolescencia)

Un `passed` solo vale para el código exacto sobre el que se ejecutó.

**Con `qg`:** `qg status --run-id <ID> --json` calcula la huella actual y la compara con la de cada registro. Usa su resultado y la correspondencia de [evidence-qg](evidence-qg.md) §7. `valid` permite aprobar; no aprueba por sí solo.

**Sin `qg`** (modo v0.1):

1. Tras la **última** ejecución de verificaciones, registra: `git rev-parse HEAD` y un hash del estado del alcance, por ejemplo `{ git diff HEAD; git ls-files --others --exclude-standard; } | sha256sum` (sin git: hash de los archivos del alcance).
2. Justo antes de emitir el reporte, recalcúlalo. Si difiere (porque tú, otro agente o el usuario editó algo después), reejecuta las verificaciones afectadas o marca la huella como **OBSOLETA** y aplica la precedencia (`BLOCKED`).
3. Las ediciones hechas para corregir hallazgos de la revisión también invalidan la evidencia anterior.

Limitación: un reporte ya emitido no se invalida solo si el código cambia después. Es texto; detectar eso automáticamente requiere hooks (propuesto para v0.2.0).

## Reglas

- No omitas filas: toda verificación descubierta aparece, aunque sea `skipped`.
- Resume salidas; no pegues logs completos.
- "No existen verificaciones" y "existen pero no se pudieron ejecutar" son situaciones distintas; aplica la fila que corresponda.
