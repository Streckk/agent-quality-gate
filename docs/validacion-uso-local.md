# Validación: uso local diario (v0.2.0-dev)

Fecha: 2026-11-25 · Claude Code 2.1.332 · Linux (bash 5.3, git 2.55, node 24.18, python 3) · commit base `f0c326f`

Objetivo: demostrar que el plugin se carga, se activa y se desactiva de forma fiable **sin instalarlo**, sin tocar `~/.claude/settings.json` y sin alterar el symlink global ni Superpowers/Codex. Todo se probó en proyectos temporales del scratchpad, nunca en proyectos reales.

## 1. CI del último commit

Run 45533343638 sobre `f0c326f`: **verde**, sin ningún paso fallido.

| Trabajo | Resultado |
|---|---|
| `validate` (con ShellCheck) | ✔ |
| `qg (ubuntu-latest)` | ✔ |
| `qg (macos-latest)` (bash 3.2) | ✔ |

## 2. Carga real sin coste

Técnica: `claude -p … --model modelo-inexistente-qg --output-format stream-json`.
- El evento `init` (skills, plugins, comandos) y el hook `SessionStart` se ejecutan **antes** de la llamada a la API.
- La API responde "modelo no disponible", con `total_cost_usd: 0`.
- Así se observa la carga real del plugin y de los hooks sin consumir cuota. Solo `Stop` y el trabajo del modelo quedan fuera.

| Variante | Skills `quality-gate` | Plugin cargado | Sesión registrada por `SessionStart` | Coste |
|---|---|---|---|---|
| `claude` (solo symlink) | `quality-gate` | no | no | 0 |
| `--plugin-dir`, sin `QG_HOOKS` | `quality-gate` (**una**) | sí | **no** (desactivado por defecto) | 0 |
| `--plugin-dir`, `QG_HOOKS=0` | una | sí | no | 0 |
| `--plugin-dir`, `QG_HOOKS=1 QG_DISABLE=1` | una | sí | no | 0 |
| `--plugin-dir`, `QG_HOOKS=1` | una | sí | **sí**: `cc-<session_id>` con `start` (huella, `source=startup`) | 0 |

- **No hay skill duplicada.** Con el symlink apuntando al mismo clon que `--plugin-dir`, solo aparece `quality-gate` en `skills` y en `slash_commands`; no aparece `agent-quality-gate:quality-gate`. No hace falta tocar el symlink.
- Superpowers, Codex, frontend-design y el resto de plugins del usuario siguieron cargados sin cambios.
- **No se modificaron** el symlink, `~/.claude/settings.json` ni otros plugins.

## 3. Escenarios

### A — Uso manual (`qg`) ✔ realizado

Proyecto Node temporal (`node --test`, `node --check`), con la sesión que registró el `SessionStart` real de §2:
- `qg session id` devuelve el mismo `cc-<session_id>` que creó el hook. La skill y los hooks comparten identidad.
- `qg require … lint unit` → `qg run` (exit 0 y 0) → `qg status --json` = `valid`, con `lint`/`unit` en `passed`.
- Un test roto da `unit failed (exit=1)` y `lint stale (code_changed)`, y `qg status` sale con 1 (`failed`).

**Pendiente (requiere sesión con modelo):** que Claude ejecute `/quality-gate` y emita el reporte Markdown con su bloque JSON (§4).

### B — Hooks activados ✔ realizado (hook real; el modelo, pendiente)

`hooks/stop.sh` ejecutado con la entrada JSON que envía Claude Code, sobre el estado creado por el `SessionStart` real:

| Paso | Resultado |
|---|---|
| Sin cambios | sin salida (deja terminar) |
| Tras modificar `src/sum.js` | `{"decision":"block","reason":"… qg status: missing, run-id cc-… Ejecuta /quality-gate o explica …"}` |
| Mismo contenido con `stop_hook_active=true`, y otra vez sin él | sin salida (no hay bucle) |
| Tras `qg run` → `valid` | sin salida |
| Con `failed` (test roto) | sin salida: un fallo no bloquea, se reporta |
| `qg session info` | `inicio: registrado`, `cambios en la sesión: true`, `bloqueos de Stop: 1` |

**Pendiente (requiere sesión con modelo):** el ciclo completo en el que Claude recibe el bloqueo, ejecuta `/quality-gate` y termina. Ya se observó con 2.1.331 (`validacion-v0.2.0-hooks.md`, escenarios 1 y 3, y Nivel B `e7-hooks`), pero no se ha repetido en 2.1.332.

### C — Hooks desactivados ✔ realizado

Con la sesión activa y cambios sin evidencia, `Stop` y `PreToolUse` (`git push`) **no producen salida** con:
- `QG_HOOKS=0`;
- `QG_HOOKS=1 QG_DISABLE=1`;
- `QG_HOOKS` sin definir.

Con `QG_HOOKS=1`, `PreToolUse` devuelve `ask`.

`qg hooks status` muestra:
- `off (default)` sin `QG_HOOKS`;
- `on (env:QG_HOOKS)` con `QG_HOOKS=1`;
- `stop on / pretool off` con `QG_HOOKS=stop`;
- `off (env:QG_DISABLE)` con `QG_DISABLE=1`.

### D — Codex ✔ realizado (sin revisiones)

- Plugin Codex 1.0.6 y `codex-cli` 0.159.1. `codex-companion.mjs setup --json` devuelve `ready: true` (sesión iniciada). No se lanzó ninguna revisión.
- Sin `codex` en el `PATH`, `setup` devuelve `ready: false` y `codex: not found`. La skill lo trata como `skipped (unavailable)` y limita el veredicto en riesgo `medium`/`high`. Lo cubren los casos deterministas de `tests/evals` y los casos `e4-blocked-degrade` y `e9-risk-auth`.

## 4. Reporte estructurado con Claude real: **NO cerrado**

- El contrato (`report-format.md`), su validador (`evals/lib/report.py`) y el contraste con `qg` (`evals/evaluate.sh`) tienen pruebas deterministas (`tests/evals/test_risk_report.sh`).
- **No existe todavía ninguna ejecución real** en la que Claude haya emitido el bloque. Hasta tenerla, este punto sigue abierto.

## 5. Compatibilidad con varios stacks (inspección; sin modificar proyectos)

`references/project-discovery.md` descubre las verificaciones por lo que **existe en el repositorio**, sin presuponer un stack:
- `package.json`, con el gestor deducido del lockfile;
- `nx.json`/`turbo.json`, con `nx affected` si el repo ya lo usa;
- `pyproject.toml`, `setup.cfg`, `tox.ini` y `noxfile.py`;
- `Makefile`, `justfile` y `Taskfile`;
- CI, `CLAUDE.md` y `AGENTS.md`;
- `.agent/verification.yaml`, opcional y por proyecto.

Evidencia previa de la fase Discover en proyectos reales, en modo solo lectura (`validacion-v0.1.0.md`):
- `charlize-platform` (Nx/NestJS): 11 checks obtenidos de la CI y de `package.json`; detectó que `nx affected` necesita `--base`;
- `Motor` (Python + web): 14 checks desde la CI.

Fixtures deterministas: Node y Python (`evals/lib/fixtures.sh`). Next.js como tal no se ha probado; se descubre por `package.json` como cualquier proyecto Node. El núcleo no contiene configuración de ningún proyecto concreto.

## 6. Pruebas deterministas

| Comando | Código de salida | Resultado |
|---|---|---|
| `bash tests/validate.sh` | 0 | OK: validación completa |
| `bash tests/validate_selftest.sh` | 0 | 20 errores conocidos detectados |
| `bash tests/run_core_tests.sh` | 0 | 189 (e2e 15, fingerprint 42, run 52, sessions 25, state 55) |
| `bash tests/run_hook_tests.sh` | 0 | 203 (integration 21, json 86, pretool 49, session_stop 47) |
| `bash tests/run_eval_tests.sh` | 0 | 225 (aggregate 24, evaluators 49, official 73, risk_report 79) |
| `claude plugin validate --strict .` | 0 | ✔ Validation passed |

La primera pasada de `validate.sh` y del autotest salió con 1. Fue un error de orden de la propia iteración: la batería se lanzó mientras se creaba este documento, al que ya enlazaban `hooks.md` y `uso-local.md`. Con el archivo creado, ambos salen con 0.

## 7. Pruebas pendientes de autorización (consumen cuota)

| # | Qué cierra | Comando | Estimación |
|---|---|---|---|
| P1 | **Reporte estructurado con Claude real** (§4): el bloque cumple el esquema y concuerda con `qg status` | `bash evals/run.sh --case e9-risk-auth --runs 1 --model claude-opus-5-5 --max-cost-usd 1` | ~0,5 USD; sin Codex (`path_mode=nocodex`) |
| P2 | Escenario B completo en 2.1.332: `Stop` real → `/quality-gate` → `valid` → fin sin más bloqueos | `bash evals/run.sh --case e7-hooks --runs 1 --model claude-opus-5-5 --max-cost-usd 1` | ~0,5 USD; riesgo `low`, no debería pedir Codex |
| P3 | Uso interactivo real y el prefijo `!` (§2 de `uso-local.md`) | manual: `bash -c '. evals/lib/fixtures.sh; fx_build node-bug /tmp/qg-demo'`, después `cd /tmp/qg-demo && QG_HOOKS=1 claude --plugin-dir /home/angel/Desarrollo/agent-quality-gate`, y en la sesión `! command -v qg && qg hooks status` y `/quality-gate` | cuota normal de una sesión |

P1 y P2 juntas: `bash evals/run.sh --case e9-risk-auth --case e7-hooks --runs 1 --model claude-opus-5-5 --max-cost-usd 2`. El resultado queda en `evals/runs/<ts>/`, y `evaluate.sh` informa `structured_report`, `structured_evidence`, `risk_classification` y `stop_blocks`.

## 8. Defectos encontrados

No se encontró ningún defecto que impida el uso local: la carga, el registro de sesión, `Stop`, `PreToolUse`, la desactivación y `qg` se comportaron como está documentado. Sí había un **hueco de documentación** para el uso diario (inicio, comprobación, desactivación, qué pasa si…), que se resolvió con `docs/uso-local.md` y el inicio rápido del README.

Fricción menor que **no** se cambió (no es un defecto y evita añadir funcionalidad): `qg session info` exige `--run-id`. La guía usa `qg session info --run-id "$(qg session id)"`.

## 9. `/quality-gate setup` (configuración de CLAUDE.md)

Fecha: 2026-11-25 · Claude Code 2.1.332.

**Pruebas deterministas** (`tests/run_setup_tests.sh`): 99 aserciones, todas en directorios temporales con `HOME` aislado. Cubren los 20 casos pedidos:
- sin archivo, archivo vacío o con instrucciones previas;
- repeticiones, actualización y eliminación;
- archivo sin bloque, bloque incompleto, duplicado o con los marcadores invertidos;
- CRLF y archivo sin salto final;
- rutas con espacios;
- symlinks fuera y dentro del proyecto, y `.claude` enlazado fuera;
- permisos de archivo y de directorio, y conservación de los permisos;
- `--scope user` con `HOME` temporal;
- `--dry-run` y `--status`;
- `AGENTS.md`, `.claude/CLAUDE.md` y compatibilidad con symlink y plugin.

Además: instrucciones similares fuera del bloque, errores de uso, nada escrito fuera del proyecto, ningún temporal residual y ningún `eval`.

**Idempotencia, comparando contenido exacto:**
- `setup` ×3 deja el archivo idéntico;
- `setup` → `--remove` devuelve el original **byte a byte**, también con CRLF;
- un archivo sin salto final recupera su texto, ahora con salto final.

**Mutaciones:** 9 de 9 defectos reales introducidos en el script se detectaron:
- bloque malformado tratado como ausente (7 fallos);
- symlink fuera del alcance (2);
- `--dry-run` que escribe (6);
- CRLF (1);
- `AGENTS.md` (4);
- no reconocer el bloque existente (23);
- reescribir aunque esté actualizado (5);
- duplicar instrucciones similares (1);
- `--remove` que borra todo (4).

Una décima mutación estaba mal planteada (no cambiaba el comportamiento) y se descartó.

**Claude Code, sin coste** (modelo inexistente, `total_cost_usd: 0`; se lee la transcripción que guarda Claude Code):

| Modo | Skills | Argumentos recibidos | Ruta del script expandida |
|---|---|---|---|
| solo symlink | `quality-gate` | `<command-args>setup --status</command-args>` → "Argumentos de esta invocación: `setup --status`" | `/home/…/.claude/skills/quality-gate/../../bin/qg-setup`, que se resuelve al script del repositorio (comprobado) |
| `--plugin-dir` + symlink | `quality-gate` (una) | ídem | ídem (Claude Code usa la copia del symlink, que es la misma) |

El `CLAUDE.md` del proyecto de prueba no cambió. No se tocó el `CLAUDE.md` personal del propietario.

**Pendiente de autorización (consume cuota):**

| # | Qué cierra | Comando | Estimación |
|---|---|---|---|
| S1 | que el modelo siga `references/setup.md`: ejecuta el script con los argumentos exactos y muestra su salida | en un repo temporal: `claude -p "/quality-gate setup" --plugin-dir /home/angel/Desarrollo/agent-quality-gate --model claude-opus-5-5` y, después, `cat CLAUDE.md` | ~0,1–0,2 USD |
| S2 | que una sesión nueva tiene las instrucciones y usa la skill tras modificar código | en el mismo repo (fixture `node-bug`): `claude -p "Corrige el bug de src/sum.js" --plugin-dir … --model claude-opus-5-5 --output-format stream-json --verbose`, y buscar `Skill` `quality-gate` en la traza | ~0,3–0,6 USD |

S2 es **no determinista**: `CLAUDE.md` es una instrucción, no una garantía. Una sola ejecución no prueba la tasa de uso.
