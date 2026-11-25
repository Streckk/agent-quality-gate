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

<bloque estructurado: ver abajo; siempre al final>
```

## Bloque estructurado (obligatorio, al final del reporte)

El Markdown es para la persona. Las herramientas leen además un bloque JSON pequeño, en un fence ` ```json `, como **último elemento** del reporte. Repite lo que ya dice el Markdown; no añade información nueva ni sustituye a `qg`.

```json
{
  "kind": "quality-gate-report",
  "schema": 1,
  "verdict": "PASS WITH LIMITATIONS",
  "risk": "medium",
  "evidence": { "provider": "qg", "run_id": "cc-<session_id>", "status": "valid", "fingerprint": "sha1:<huella>" },
  "review": { "status": "skipped", "reason": "unavailable: codex ready:false" }
}
```

| Campo | Obligatorio | Valores |
|---|---|---|
| `kind` | sí | `"quality-gate-report"` |
| `schema` | sí | entero `1` |
| `verdict` | sí | `PASS`, `PASS WITH LIMITATIONS`, `FAIL`, `BLOCKED`, `NOT VERIFIED` (el mismo del encabezado) |
| `risk` | sí | `low`, `medium`, `high` (el mismo de la línea **Riesgo**) |
| `evidence.provider` | sí | `qg` o `none` |
| `evidence.run_id` | si `provider=qg` | el run-id de **esta** sesión (`qg session id`) |
| `evidence.status` | si `provider=qg` | el `result` de `qg status --run-id <ID> --json`, sin reinterpretar |
| `evidence.fingerprint` | no | `fingerprint` del mismo `qg status` |
| `evidence.reason` | si `provider=none` | motivo corto: `no-git`, `qg-unavailable`, `discover-only`… |
| `review.status` | sí | `done`, `skipped`, `not_required` |
| `review.kind` | si `done` | `review` o `adversarial` |
| `review.reason` | si `skipped` | motivo corto (`unavailable: …`, `by user`, …) |

Reglas:
- Textos de una línea y de menos de 200 caracteres. **Nunca** secretos, tokens, rutas privadas ni salidas de comandos.
- Sin `qg`: `"evidence": {"provider": "none", "reason": "<motivo>"}`; no inventes `run_id` ni `status`.
- Copia `status` y `fingerprint` del `qg status` que acabas de consultar. Si la huella cambió después, vuelve a consultarlo.
- El bloque no es una prueba: quien evalúa lo contrasta con `qg status`, los registros y la traza. Un bloque que contradiga al Markdown o a `qg` es un defecto del reporte.
- Si una versión futura cambia el formato, se incrementará `schema`. Los lectores deben rechazar los esquemas que no conozcan.

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

Limitación: un reporte ya emitido es texto y no se invalida solo si el código cambia después. Los hooks opcionales del plugin (desactivados por defecto; ver `docs/hooks.md`) detectan cambios sin evidencia vigente al terminar la sesión y antes de `git push`, pero no reescriben reportes ya entregados.

## Reglas

- No omitas filas: toda verificación descubierta aparece, aunque sea `skipped`.
- Resume salidas; no pegues logs completos.
- "No existen verificaciones" y "existen pero no se pudieron ejecutar" son situaciones distintas; aplica la fila que corresponda.
