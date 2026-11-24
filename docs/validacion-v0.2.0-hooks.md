# Validación del plugin y los hooks (v0.2.0-dev)

Fecha: 2026-11-24 · Claude Code 2.1.331 · git 2.55 · bash 5.3 / gawk 5.4 (Linux)

Todo se ejecutó sobre **fixtures sintéticos** y repos temporales. El plugin se cargó con `--plugin-dir`, **sin instalarlo**, sin activar hooks globales y sin tocar `settings.json`.

## 1. Contrato de Claude Code verificado (no solo documentado)

Plugin sonda con `--plugin-dir` que registraba la entrada de cada hook:

| Aspecto | Observado |
|---|---|
| Entrada de `SessionStart` | `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `source: "startup"` |
| Entrada de `PreToolUse` | además `tool_name`, `tool_input.command`, `permission_mode`, `prompt_id` |
| `Stop` | `{"decision":"block","reason":…}` hace que Claude continúe. El siguiente `Stop` llega con `stop_hook_active: true` |
| Entorno de los hooks | `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT` y `CLAUDE_CODE_SESSION_ID` (= `session_id` del JSON) |
| Bash del modelo | `CLAUDE_CODE_SESSION_ID` presente; `CLAUDE_PROJECT_DIR` **ausente** |
| `bin/` del plugin | en el `PATH` del Bash del modelo |
| `ask` en modo `-p` (sin humano) | se convierte en **`permission_denied`** (`decision_reason_type: hook`) |
| `claude plugin validate --strict .` | ✔ sin avisos (tras entrecomillar `${CLAUDE_PLUGIN_ROOT}` y añadir `author`) |

## 2. Pruebas deterministas

| Suite | Aserciones |
|---|---|
| `tests/core/` (qg) | 189 |
| `tests/hooks/test_json.sh`: parser con awk, gawk `--posix` y gawk `--traditional` | 86 |
| `tests/hooks/test_session_stop.sh` | 47 |
| `tests/hooks/test_pretool.sh` | 36 |
| `tests/hooks/test_integration.sh` | 21 |
| **Total** | **379** |

Además: `tests/validate.sh` OK y `tests/validate_selftest.sh` con 17 casos detectados.

Cubren los casos pedidos:

- **`SessionStart`:** desactivado, activado, `resume` sin sobrescritura, sesiones concurrentes, sin Git, fallo al registrar, JSON e id inválidos.
- **`Stop`:**
  - sin cambios, `missing`, `stale` y `valid`;
  - `failed`, `blocked` e `incomplete`;
  - `stop_hook_active`, primer y segundo bloqueo, cambio posterior, límite configurable;
  - `QG_DISABLE`, `QG_HOOKS=0` y la configuración del proyecto (válida y malformada);
  - cambios previos a la sesión, cambios revertidos, solo docs, sin estado inicial, estado corrupto;
  - sesiones simultáneas y JSON malformado.
- **`PreToolUse`:**
  - trailers en `-m`, en minúsculas, en heredoc, `Generated-by`, `git -C`;
  - menciones sin `:`, caracteres especiales;
  - `-F` dentro y fuera del repo, `-F -`, `-C`, `--amend`;
  - `push` y `gh pr create` con y sin evidencia, comandos irrelevantes y ambiguos, otra herramienta;
  - nunca devuelve `allow` y no toca `git config`.
- **Integración:**
  - mismo run-id en la skill y en los hooks, flujo completo;
  - sin reutilizar evidencia entre sesiones;
  - **ningún modelo ni suite ejecutados** (trampas en el `PATH`);
  - sin escrituras fuera de `.git/quality-gate/` (`HOME` y `TMPDIR` aislados);
  - hooks desactivados sin efectos.

## 3. Escenarios reales con Claude Code (`claude -p --plugin-dir`)

| # | Escenario | Entrada | Evidencia observada | Resultado |
|---|---|---|---|---|
| 1 | Flujo automático (`QG_HOOKS=1`) | "Añade `double(x)` … termina con un resumen" | `stop-marks`: 1 (el `Stop` bloqueó). Claude invocó la skill → `qg session id` → `cc-<sid>` → `require unit` → `run` exit 0 → `qg status --run-id cc-<sid>` = **valid** → terminó | ✔ |
| 2 | Fallo legítimo | "Cambia `sum` a `a - b` … ejecuta /quality-gate … no corrijas" | `qg status` = **failed**; `stop-marks`: 0 (el `Stop` dejó terminar); reporte `FAIL` | ✔ |
| 3 | Evidencia obsoleta | "triple → /quality-gate → añade `// revisado` → termina" | registro `valid` (huella `cbfd…`), luego comentario → `stale` → `stop-marks`: 1 → Claude reejecutó `qg run` → **valid** (huella `8f24…`) | ✔ |
| 4 | Desactivado (sin `QG_HOOKS`) | igual que el 1 | sin `.git/quality-gate/sessions`, sin bloqueo, terminó normalmente | ✔ |
| 5 | Convivencia | todas las sesiones | 3 `SessionStart` (Superpowers, el nuestro y Codex), todos `success`; el nuestro sin salida; review gate de Codex sin activar; ningún hook lanzó Codex | ✔ |
| 6 | `PreToolUse` (`QG_HOOKS=pretool`) | commit con `Co-Authored-By:` → commit limpio → `git push` | commit con trailer **rechazado** por el hook (no se creó); commit limpio permitido; `push` → `ask` → **`permission_denied`** en modo `-p` | ✔ |

Primera ronda de los escenarios 1 y 3: los prompts decían "no verifiques por iniciativa propia". El `Stop` bloqueó una vez, Claude explicó que la instrucción del usuario prevalecía y terminó **sin bucle** (1 marca). Era la vía prevista ("…o explica por qué no corresponde verificar"). Los repetí con prompts neutros (1 y 3 en la tabla).

Coste aproximado de las sesiones reales: 8 sesiones cortas, de 7 a 39 s cada una.

## 4. Defectos encontrados y corregidos en esta iteración

| # | Defecto | Detección | Corrección | Regresión |
|---|---|---|---|---|
| 1 | La huella **actualizaba el mtime de objetos existentes** en `.git/objects`: git los "refresca" si los encuentra en un almacén alternativo | aserción de aislamiento de la integración, al corregirla (antes era vacía) | sin almacén alternativo + `write-tree --missing-ok`; mismas huellas | `test_fingerprint.sh` (falla con el `qg` anterior: 2 archivos tocados) |
| 2 | Una aserción de aislamiento era vacía (comparaba con un archivo recién restaurado) | revisión de la propia prueba | marcador de tiempo previo + control positivo que demuestra que detecta escrituras | — |
| 3 | `plugin.json` declaraba licencia MIT sin que exista LICENSE ni decisión del propietario | revisión | campo eliminado | `validate.sh` + autotest |
| 4 | `${CLAUDE_PLUGIN_ROOT}` sin comillas en los comandos de los hooks | `claude plugin validate` | comandos entrecomillados | `validate.sh` + autotest |
| 5 | Pruebas mal planteadas (`\\n` frente a `\n` en el JSON, `HOOK_RC` en un subshell, argumento de herramienta ignorado) | fallos de la primera ejecución | pruebas corregidas; los escapes `\u` se verifican con los bytes exactos | — |

## 4b. Actualización (iteración de Agent Evals)

Verificado después en sesiones reales ([validacion-v0.2.0-evals.md](validacion-v0.2.0-evals.md)):
- `--resume`, `--continue`, `--fork-session`, `/clear` y subagentes;
- el diálogo interactivo de `ask` y que la aprobación no es permanente;
- el `deny` interactivo.

`PreToolUse` también se corrigió para mensajes no verificables (`-F -`, pipes, `$VAR`…).

## 5. Observaciones y limitaciones

- **Skill duplicada:** con el symlink global apuntando a esta misma copia, Claude Code registró **una sola** skill (`quality-gate`), probablemente porque deduplica por ruta real. Con el plugin instalado en otra ruta habría dos (ver [hooks.md §2](hooks.md#evitar-la-skill-duplicada)).
- **`ask` no interactivo:** en `claude -p` equivale a denegar. En sesión interactiva se mostraría el diálogo. No se ha probado de forma automática, porque requiere una persona.
- **Sin probar:** `--resume`/`--continue` reales; `/clear`; subagentes reales (el hook no se registra en `SubagentStop`); repositorios grandes con hooks (la huella se midió por separado: 75–190 ms hasta 50.000 archivos).
- **macOS/BWK awk y bash 3.2:** pendiente de la CI tras el push. En local se cubrieron gawk `--posix` y `--traditional`.
- ShellCheck no está en local; la CI lo ejecuta, también sobre `hooks/` y `tests/hooks/`.
