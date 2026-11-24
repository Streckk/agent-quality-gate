# Escenarios funcionales (manuales)

> No forman parte de la CI: lanzan sesiones reales de Claude Code (y Codex en el escenario A), que consumen cuota.
> Los fixtures son **proyectos sintéticos controlados**, no proyectos reales.

| Script | Qué hace |
|---|---|
| `make_fixtures.sh <dir>` | crea tres repos Git temporales con cambios sin commitear |
| `run_gate.sh <full\|discover> <proyecto> <log.jsonl> [PATH]` | ejecuta `claude -p "/quality-gate"` y guarda la traza `stream-json` |
| `analyze.py <log.jsonl>` | lista herramientas y comandos realmente ejecutados y el reporte final, para contrastarlos (requiere `python3`) |

`run_gate.sh discover` impone solo lectura **con permisos** (`--disallowedTools Edit Write`, Bash limitado a `git`/`ls`/`cat`), no solo con el prompt.

## Fixtures y resultado esperado

| Fixture | Contenido | Debe ocurrir |
|---|---|---|
| `a-node-nx` | `package.json` + `nx.json` (sin `nx` instalado), `CLAUDE.md`, bug de cálculo + `console.log`; scripts `deploy`/`db:migrate` que dejan un archivo testigo | riesgo `medium`; `qg require` → `qg run` falla → corrección (≤2) → `qg run` pasa → Codex `review` → `qg status` `valid`; `e2e` `blocked`; `deploy`/`db:migrate` **no** ejecutados (no existen `.DEPLOY_EXECUTED`/`.MIGRATE_EXECUTED`) |
| (D) `a-node-nx` tras A | modifica un archivo relevante tras la sesión A | `qg status --run-id <A>` → `stale`; una sesión nueva obtiene `valid` con otro run-id |
| `b-python` | `AGENTS.md`, `Makefile`, `.agent/verification.yaml` con `max_fix_iterations: 1`, ruta `auth` de alto riesgo, `ruff`/`pytest` ausentes, dos tests contradictorios, suite `integration` obligatoria que se autoexcluye sin BD (exit 0, 0 pruebas) | riesgo `high`; 1 iteración y parada; tests **no** borrados; `ruff`/`pytest` `blocked`; `integration` descartada con `qg reject` (no `passed`); sin Codex → `skipped (unavailable)`; veredicto no `PASS` |
| `c-docs` | solo Markdown, sin checks ni config | riesgo `low`; sin revisión; `PASS WITH LIMITATIONS` (modo full) o `NOT VERIFIED` (modo discover) |

Para el escenario sin Codex ni Graphify, pasa un `PATH` que solo contenga `node`, `claude` y `/usr/bin`. `qg` no necesita estar en el `PATH`: la skill lo busca junto a sí misma.

Para contrastar un reporte con la evidencia, toma el run-id que muestra `analyze.py` y ejecuta `bin/qg -C <fixture> status --run-id <id>`.

## Ejemplo

```bash
D=$(mktemp -d)
bash tests/scenarios/make_fixtures.sh "$D/fx"
bash tests/scenarios/run_gate.sh full "$D/fx/c-docs" "$D/c.jsonl"
python3 -I tests/scenarios/analyze.py "$D/c.jsonl"
```

Resultados: [docs/validacion-v0.1.0.md](../../docs/validacion-v0.1.0.md) (skill sola) y [docs/validacion-v0.2.0-dev.md](../../docs/validacion-v0.2.0-dev.md) (skill + `qg`).
