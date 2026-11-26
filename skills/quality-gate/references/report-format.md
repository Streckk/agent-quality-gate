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
| typecheck | `node_modules/.bin/tsc --noEmit` | passed (línea base: 236 conocidos, 2 corregidos) | 2 | sin diagnósticos nuevos | sí |
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
- obligatoria (cierra el alcance): <acción o decisión>   → `pending_required`
- opcional (nadie la pidió): <push, PR…>   → `pending_optional`

<bloque estructurado: ver abajo; siempre al final>
```

## Bloque estructurado (obligatorio, al final del reporte)

El Markdown es para la persona. Las herramientas leen además un bloque JSON pequeño, en un fence ` ```json `, como **último elemento** del reporte. Repite lo que ya dice el Markdown; no añade información nueva ni sustituye a `qg`.

Hay dos esquemas:
- **Esquema 1:** un solo repositorio. Sigue siendo válido.
- **Esquema 2:** obligatorio cuando el alcance abarca **varios repositorios** (por ejemplo un backend y un frontend en repos Git distintos, aunque estén en carpetas hermanas). Es válido también con un solo repo.

### Esquema 1 (un repositorio)

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

### Esquema 2 (varios repositorios)

`evidence` sale de la raíz y se declara **por repositorio**; `approvals` es obligatorio. En el Markdown, una tabla de verificaciones por repo con el mismo `id`.

```json
{
  "kind": "quality-gate-report",
  "schema": 2,
  "verdict": "PASS WITH LIMITATIONS",
  "risk": "medium",
  "repos": [
    { "id": "api", "evidence": { "provider": "qg", "run_id": "cc-<session_id>", "status": "valid", "fingerprint": "sha1:<huella api>" } },
    { "id": "web", "evidence": { "provider": "qg", "run_id": "cc-<session_id>", "status": "valid", "fingerprint": "sha1:<huella web>" } }
  ],
  "approvals": { "pending_required": 0, "pending_optional": 1 },
  "review": { "status": "skipped", "reason": "unavailable: codex ready:false" }
}
```

En el Markdown, una tabla por repo bajo un encabezado con el mismo `id`:

```markdown
### Verificaciones — api
| id | comando | estado | exit | evidencia | obligatoria |
|----|---------|--------|------|-----------|-------------|
| unit | `pnpm test` | passed | 0 | 120/120 | sí |

### Verificaciones — web
| id | comando | estado | exit | evidencia | obligatoria |
|----|---------|--------|------|-----------|-------------|
| typecheck | `node_modules/.bin/tsc --noEmit` | passed (línea base: 12 conocidos, 0 corregidos) | 2 | sin diagnósticos nuevos | sí |
```

Con dos repos, `qg status --run-id <ID> --json` se consulta **en cada uno** (`qg -C <repo> status …`); la huella y el `status` de cada `evidence` son los de su repo.

| Campo | Obligatorio | Valores |
|---|---|---|
| `kind` | sí | `"quality-gate-report"` |
| `schema` | sí | entero `1` o `2` |
| `verdict` | sí | `PASS`, `PASS WITH LIMITATIONS`, `FAIL`, `BLOCKED`, `NOT VERIFIED` (el mismo del encabezado) |
| `risk` | sí | `low`, `medium`, `high` (el mismo de la línea **Riesgo**) |
| `evidence.provider` | esquema 1: sí | `qg` o `none` |
| `evidence.run_id` | si `provider=qg` | el run-id de **esta** sesión (`qg session id`) |
| `evidence.status` | si `provider=qg` | el `result` de `qg status --run-id <ID> --json`, sin reinterpretar |
| `evidence.fingerprint` | no | `fingerprint` del mismo `qg status` |
| `evidence.reason` | si `provider=none` | motivo corto: `no-git`, `qg-unavailable`, `discover-only`… Un repo sin registros de `qg` se declara con `provider=none` |
| `repos` | esquema 2: sí (1 a 16) | lista de `{id, evidence}`; `evidence` con las mismas reglas que arriba. En el esquema 1 está prohibido |
| `repos[].id` | sí | etiqueta `^[a-z0-9][a-z0-9_-]{0,31}$`, única. **No** una ruta |
| `approvals.pending_required` | esquema 2: sí; esquema 1: opcional | entero ≥ 0 |
| `approvals.pending_optional` | ídem | entero ≥ 0 |
| `review.status` | sí | `done`, `skipped`, `not_required` |
| `review.kind` | si `done` | `review` o `adversarial` |
| `review.reason` | si `skipped` | motivo corto (`unavailable: …`, `by user`, …) |
| `review.critical_fixed` | no | booleano: `true` si corregiste un hallazgo `confirmed` crítico (agent-evals §5) |
| `review.followup` | no para el validador; declararlo siempre con `critical_fixed: true` | `done`, `pending`, `not_required`: la revisión acotada posterior a esa corrección |

### Aprobaciones (`approvals`)

- **`pending_required`:** aprobaciones que hacen falta para **cerrar el alcance** y siguen sin darse. Ejemplos: el usuario pidió migrar la base y falta su confirmación; una dependencia nueva hay que instalarla para poder ejecutar la verificación. Con `pending_required > 0` el veredicto es `BLOCKED` (nunca `PASS` ni `PASS WITH LIMITATIONS`).
- **`pending_optional`:** acciones posteriores que **nadie pidió** y que solo se ofrecen: un `git push`, abrir un PR, publicar. No bloquean ni cambian el veredicto; se listan en "Pendiente de aprobación humana".
- Es un conteo, no una lista: el detalle va en el Markdown.

Reglas:
- Textos de una línea y de menos de 200 caracteres. **Nunca** secretos, tokens, rutas privadas ni salidas de comandos. En el esquema 2 ningún texto del bloque puede contener rutas absolutas.
- Sin `qg`: `"evidence": {"provider": "none", "reason": "<motivo>"}`; no inventes `run_id` ni `status`.
- Copia `status` y `fingerprint` del `qg status` que acabas de consultar. Si la huella cambió después, vuelve a consultarlo.
- El bloque no es una prueba: quien evalúa lo contrasta con `qg status`, los registros y la traza, repo por repo. Un bloque que contradiga al Markdown o a `qg` es un defecto del reporte.
- Si una versión futura cambia el formato, se incrementará `schema`. Los lectores deben rechazar los esquemas que no conozcan.

## Veredictos

Evalúa las condiciones **en este orden**; el primer veredicto que aplique es el final:

| # | Veredicto | Condición |
|---|---|---|
| 1 | `NOT VERIFIED` | el usuario limitó la ejecución a Discover (o pidió no ejecutar verificaciones). No es un fallo ni un éxito |
| 2 | `FAIL` | alguna obligatoria `failed` (aunque se haya agotado el límite de iteraciones), o hallazgo `confirmed` sin resolver |
| 3 | `BLOCKED` | alguna obligatoria `blocked`; existen verificaciones aplicables pero no se pudo ejecutar ninguna; **hay una aprobación obligatoria pendiente** (`pending_required > 0`); o la huella de evidencia está obsoleta y no se reejecutó |
| 4 | `PASS WITH LIMITATIONS` | obligatorias `passed`, pero hay opcionales `blocked`/`skipped`, revisión no disponible en riesgo `medium`/`high`, fallos preexistentes, **alguna verificación pasó solo contra una línea base** (`passed (línea base: K conocidos, F corregidos)`), una corrección crítica sin su revisión acotada (`followup: pending`), o **no existe ninguna verificación aplicable** y el riesgo es `low` |
| 5 | `PASS` | todas las obligatorias `passed`, sin hallazgos `confirmed` abiertos y sin limitaciones relevantes |

- Con varios repositorios, el veredicto es el del **peor** repo: uno `failed` da `FAIL`; uno `blocked`, `incomplete`, `stale` o `missing` impide `PASS` y `PASS WITH LIMITATIONS`. Nunca un `PASS` global por mirar solo el primero.
- Un repositorio **sin verificaciones aplicables** (por ejemplo, solo documentación, o un repo hermano que el cambio no toca) no se lista en `repos`: queda fuera del alcance y se dice en "Omitido y limitaciones". Si forma parte del alcance y no se puede verificar, su `status` es `missing` y el veredicto es `BLOCKED` (o `NOT VERIFIED` si solo se pidió Discover). Nunca se lista con `missing` junto a un `PASS`.
- Una verificación que pasó contra una línea base nunca da `PASS` limpio: máximo `PASS WITH LIMITATIONS`. Y no es una forma de aprobar errores nuevos: con diagnósticos nuevos el check es `failed`.
- Una aprobación obligatoria pendiente da `BLOCKED`; una opcional (`pending_optional`) no cambia el veredicto.
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

- Un `passed` desde caché total no se presenta como ejecución real: indícalo (evidence-qg §4c).
- No omitas filas: toda verificación descubierta aparece, aunque sea `skipped`.
- Resume salidas; no pegues logs completos.
- "No existen verificaciones" y "existen pero no se pudieron ejecutar" son situaciones distintas; aplica la fila que corresponda.
