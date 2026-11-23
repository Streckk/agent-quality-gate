# Fase 4 — Report

El reporte es la salida verificable de la puerta. Debe poder auditarse: cada `passed` tiene un comando y un exit code detrás.

## Plantilla

```markdown
## Quality Gate — <VEREDICTO>

**Alcance:** <working tree | rama X vs main | rutas>  ·  **Riesgo:** <low|medium|high> (<señales>)
**Fuentes:** <CLAUDE.md, .agent/verification.yaml, package.json, CI...>

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

| Veredicto | Condición |
|---|---|
| `PASS` | todas las obligatorias `passed`; sin hallazgos `confirmed` abiertos |
| `PASS WITH LIMITATIONS` | obligatorias `passed`, pero hay opcionales `blocked`/`skipped`, revisión no disponible en riesgo `medium`, o fallos preexistentes |
| `FAIL` | alguna obligatoria `failed`, o hallazgo `confirmed` sin resolver |
| `BLOCKED` | alguna obligatoria `blocked`, se alcanzó el límite de iteraciones, o falta una aprobación requerida |

En riesgo `high` sin revisión independiente el veredicto máximo es `PASS WITH LIMITATIONS`.

## Reglas

- No omitas filas: toda verificación descubierta aparece, aunque sea `skipped`.
- Resume salidas; no pegues logs completos.
- Si no se pudo ejecutar nada, el veredicto es `BLOCKED`, no `PASS`.
