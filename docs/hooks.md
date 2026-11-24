# Plugin y hooks de agent-quality-gate (v0.2.0-dev)

> Estado: **en desarrollo**. Validado con pruebas deterministas y con sesiones reales de Claude Code sobre fixtures (ver [validacion-v0.2.0-hooks.md](validacion-v0.2.0-hooks.md)). Los hooks están **desactivados por defecto**.

Principio: **la skill decide** qué verificar, **`qg`** ejecuta y conserva la evidencia, y **los hooks detectan** cuándo corresponde exigirla. Codex sigue siendo un revisor opcional, y la CI es el mecanismo de cumplimiento obligatorio.

Los hooks son controles **locales**. Mejoran el flujo dentro de Claude Code, pero **no son una garantía de seguridad**: se pueden desactivar, no se ejecutan fuera de Claude Code y solo ven lo que Claude Code les pasa (ver [Limitaciones](#limitaciones)).

## 1. Estructura del plugin

```text
.claude-plugin/plugin.json   manifiesto (name: agent-quality-gate)
skills/quality-gate/         la skill (/agent-quality-gate:quality-gate con el plugin; /quality-gate con symlink)
hooks/hooks.json             SessionStart, Stop, PreToolUse (Bash)
hooks/*.sh, hooks/lib/       scripts de los hooks + parser JSON en awk + utilidades
bin/qg, bin/qg-run           en el PATH del Bash de Claude mientras el plugin está habilitado
```

`claude plugin validate --strict .` pasa sin avisos.

## 2. Instalación

### Probar sin instalar (recomendado para empezar)

```bash
git clone https://github.com/Streckk/agent-quality-gate.git
cd mi-proyecto
QG_HOOKS=1 claude --plugin-dir /ruta/a/agent-quality-gate      # hooks activados solo en esta sesión
```

`--plugin-dir` carga el plugin para esa sesión, sin instalarlo ni modificar `settings.json`.

### Instalar como plugin

El repositorio todavía no está publicado en ningún marketplace. Cuando lo esté, se instalará con `/plugin install`. Mientras tanto, la vía soportada es `--plugin-dir` (también mediante `CLAUDE_CODE_PLUGIN_DIRS`).

### Solo la skill, sin plugin ni hooks

```bash
ln -s /ruta/a/agent-quality-gate/skills/quality-gate ~/.claude/skills/quality-gate
```

La skill encuentra `qg` junto a sí misma (`<skill>/../../bin/qg`). No hay hooks.

### Evitar la skill duplicada

Observado en 2.1.331: si el symlink apunta a **la misma copia** que cargas como plugin (`--plugin-dir` de ese repo), Claude Code registra **una sola** skill (`quality-gate`). Parece que deduplica por ruta real. Si el plugin se instala en otra ruta (caché de plugins), habrá **dos** skills con el mismo contenido: `quality-gate` (symlink) y `agent-quality-gate:quality-gate` (plugin). Funcionan igual y comparten evidencia, porque usan el mismo `qg` y el mismo run-id de sesión, pero conviene usar una sola vía:

- **con plugin:** elimina el symlink (`rm ~/.claude/skills/quality-gate`);
- **sin plugin:** mantén el symlink.

## 3. Activación voluntaria

**Instalar o cargar el plugin no activa nada.** Los hooks solo actúan si se activan de forma explícita, y la activación se evalúa en este orden (gana la primera que aplica):

| # | Fuente | Efecto |
|---|---|---|
| 1 | `QG_DISABLE=1` (también `true`/`yes`/`on`; cualquier valor no vacío ni falso) | **todo desactivado** |
| 2 | `QG_HOOKS=0` / `off` / `none` | todo desactivado |
| 2 | `QG_HOOKS=1` / `on` / `all` | todo activado |
| 2 | `QG_HOOKS=stop` / `pretool` / `stop,pretool` | solo los indicados |
| 3 | `.agent/verification.yaml` del repositorio (bloque `hooks:`) | por hook |
| 4 | — | desactivado |

Bloque admitido en `.agent/verification.yaml`. Es un **subconjunto estricto** de YAML que se lee sin ejecutar nada:

```yaml
hooks:
  stop: on        # on | off | true | false
  pretool: off
```

Cualquier otra forma (valores entre comillas, mapas en línea, claves desconocidas, duplicados o dos bloques `hooks:`) **invalida el bloque completo** y deja los hooks desactivados, con un aviso. Un `QG_HOOKS` con un valor no reconocido se ignora.

**Consentimiento:**
- `QG_HOOKS` es una decisión de quien inicia la sesión.
- El bloque `hooks:` lo decide quien mantiene el repositorio, para todas las sesiones en él.

Los hooks solo pueden **añadir** fricción (pedir verificar, pedir confirmación o rechazar un trailer de IA): nunca conceden permisos.

Consultar el estado efectivo: `qg hooks status` (o `--json`) dentro del repositorio.

## 4. Identidad de sesión

- El run-id de una sesión de Claude Code es **`cc-<session_id>`** (`qg session id`).
- Los hooks lo derivan del `session_id` de su entrada JSON. La skill lo deriva de `CLAUDE_CODE_SESSION_ID`, que Claude Code exporta en el Bash del modelo y en los hooks. Comprobado en Claude Code 2.1.331: ambos coinciden.
- Requisitos (`qg require`), evidencia (`qg run`/`reject`) y estado de sesión quedan aislados por run-id y por worktree (`.git/quality-gate/v1/`).
- Sin `CLAUDE_CODE_SESSION_ID` válido, la skill genera su propio run-id (`qg-<fecha>-<aleatorio>`). Esa evidencia no la ven los hooks, que entonces se comportan como si no hubiera evidencia de la sesión.

| Situación | Comportamiento |
|---|---|
| sesión nueva | `SessionStart` (`startup`) registra la huella inicial |
| sesión reanudada (`--resume <id>`) | mismo `session_id`: se conserva la huella inicial original y no se sobrescribe |
| `/clear` | Claude Code cambia el `session_id`: empieza una sesión nueva con su propia huella inicial |
| varias invocaciones de `/quality-gate` en la misma sesión | comparten run-id; la última declaración de obligatorias sustituye a la anterior |
| dos sesiones simultáneas en el mismo worktree | run-ids distintos: ni requisitos ni evidencia se mezclan; el código es compartido, así que un cambio de una deja `stale` a la otra |
| worktrees distintos | estado separado (`git rev-parse --git-path`) |
| cambios de directorio | `SessionStart`/`Stop` usan `CLAUDE_PROJECT_DIR` (raíz donde empezó la sesión); `PreToolUse` usa el `cwd` del comando |
| identificador ausente o inválido | los hooks no actúan (exit 0) |

## 5. Hooks

Ningún hook invoca modelos (Claude, Codex u otros), ejecuta suites de pruebas ni escribe fuera de `.git/quality-gate/` y de sus temporales, que borra al terminar. Ante cualquier error interno terminan con `exit 0` y sin decisión: **un fallo del hook nunca bloquea al usuario**.

### SessionStart

- Solo actúa si `stop` está activado.
- Registra la huella inicial (`qg session start`) **una vez por sesión**. `resume`, `compact` y `clear` con el mismo id no la sobrescriben.
- No imprime nada ni inyecta contexto, así que convive con el `SessionStart` de Superpowers.
- Fuera de un repositorio Git no hace nada y no impide iniciar la sesión.

### Stop

La decisión la toma `qg session stop` (determinista):

| Condición | Resultado |
|---|---|
| hooks desactivados, `QG_DISABLE`, sin identidad o sin huella inicial registrada | deja terminar |
| `stop_hook_active = true` (ya continúa por un bloqueo) | deja terminar |
| huella actual = huella inicial (sin cambios, solo lectura, o cambios revertidos) | deja terminar |
| `qg status --run-id <sesión>` = `valid` | deja terminar |
| `failed`, `blocked`, `incomplete` | **deja terminar**: son resultados legítimos que el reporte debe explicar (dependencias ausentes, decisión humana pendiente) |
| `stale` o `missing` | **bloquea una vez** con `{"decision":"block","reason":"…"}` |
| ya bloqueó con esta misma huella | deja terminar |
| ya bloqueó `QG_STOP_MAX_BLOCKS` veces en la sesión (3 por defecto) | deja terminar |

Política para los casos especiales:
- **Cambios previos a la sesión:** forman parte de la huella inicial y no provocan bloqueo. El hook cubre los cambios **de esta sesión**.
- **Cambios solo de documentación, sin verificaciones aplicables:** bloquea una vez (`missing`). Tras ejecutar la puerta, que reporta que no hay verificaciones aplicables, el siguiente `Stop` con la misma huella deja terminar.
- **Ejecución interrumpida:** `incomplete`, no bloquea.
- **Subagentes:** el hook solo se registra para `Stop` y no para `SubagentStop`, así que los subagentes no se bloquean. El agente principal se evalúa al terminar.
- **Estado ilegible o corrupto:** deja terminar.

Mensaje al bloquear: *"agent-quality-gate: hay cambios en esta sesión sin evidencia vigente (qg status: stale, run-id cc-…). Ejecuta /quality-gate o explica por qué no corresponde verificar este alcance. Este aviso no se repetirá para el mismo contenido."*

Coste por evento: una huella y una lectura de registros. Medido: 75–190 ms entre 1.000 y 50.000 archivos.

### PreToolUse (matcher `Bash`)

Complementa los permisos nativos, que siguen siendo la primera línea de defensa. **Nunca devuelve `allow`**: no concede permisos.

| Comando detectado | Decisión |
|---|---|
| `git commit` cuyo texto contiene un trailer o crédito de IA (`Co-Authored-By:`, `Co-developed-by:`, `Generated/Assisted… by/with Claude/Codex/…`) | `deny` |
| `git commit -F <archivo>` con trailer (archivo literal dentro del repositorio) | `deny` |
| `git commit -F` con archivo fuera del repo, inexistente o ruta no literal (`"$VAR"`) | `ask` |
| `git commit -c/-C` (reutiliza otro mensaje) | `ask` |
| `git commit --amend` sin mensaje nuevo, si el commit actual tiene un trailer | `deny` |
| `git push` / `gh pr create` sin evidencia `valid` de la sesión | `ask`. La aprobación vale solo para esa operación |
| cualquier otro caso | sin decisión: rigen los permisos normales |

Las expresiones regulares solo se usan para **detectar palabras** (`git`, `commit`, `push`…) y **extraer rutas literales simples**. Si algo no se puede analizar con fiabilidad, el resultado es `ask` o ninguna decisión, nunca una aprobación. La detección es **conservadora**: `bash -c "git push"` también pide confirmación.

## 6. Convivencia con otros plugins

- **Superpowers** (7.0.2) solo registra `SessionStart`. El nuestro no inyecta contexto ni duplica `verification-before-completion`: exige *evidencia*, no instrucciones.
- **Codex** (1.0.6) tiene su propio `Stop` (*review gate*, desactivado por defecto). El nuestro **nunca** lanza Codex ni exige revisión. Si se activan ambos, cada uno bloquea por su motivo y el nuestro está limitado a una vez por huella. No conviene activar los dos sin necesidad.
- Los permisos nativos (`permissions.deny`) se aplican antes que nuestro `PreToolUse` y no se debilitan.

## 7. Desactivar

- Una sesión: `QG_DISABLE=1 claude …` (o `QG_HOOKS=0`).
- Un repositorio: `hooks: { stop: off }` en el bloque de `.agent/verification.yaml`.
- Todos los hooks de Claude Code: `"disableAllHooks": true` en la configuración (mecanismo nativo).
- Quitar el plugin: no cargarlo (`--plugin-dir`) o deshabilitarlo (`claude plugin disable agent-quality-gate`).

## 8. Limitaciones

- **No es una garantía.** Un hook local se puede desactivar y no ve:
  - **wrappers, scripts, alias o funciones de shell** que ejecuten `git push`/`commit` indirectamente (`./release.sh`, `alias gp='git push'`);
  - otras herramientas o MCP que hagan operaciones Git;
  - trailers añadidos por `commit.template`, por hooks de Git (`prepare-commit-msg`) o por el editor.
  
  Las políticas que deben cumplirse para cualquier colaborador van en **CI y protección de ramas**.
- **`Stop` depende de que la skill use el run-id de la sesión.** Si `CLAUDE_CODE_SESSION_ID` no está disponible, la evidencia de la skill no cuenta para el hook, que pedirá verificar una vez.
- Al reanudar con `--continue`/`--resume` sin id, Claude Code puede exponer un id distinto en el Bash. No se ha probado; podría causar un bloqueo de más, nunca un `valid` de más.
- `ask` en modo no interactivo (`claude -p`): ver el resultado observado en [validacion-v0.2.0-hooks.md](validacion-v0.2.0-hooks.md).
- La huella excluye los archivos ignorados y los cambios dentro de submódulos ([evidencia.md](evidencia.md)).
- Windows no está soportado ni probado.

## 9. Solución de problemas

| Síntoma | Comprobación |
|---|---|
| Los hooks no hacen nada | `qg hooks status` en el repo: ¿`off (default)`? Activa con `QG_HOOKS=1`. ¿Aparece un aviso de bloque malformado? |
| `Stop` no bloquea pese a haber cambios | `qg session info --run-id "$(qg session id)"`: ¿hay huella inicial? Si los hooks se activaron a mitad de sesión, no la hay (por diseño) |
| `Stop` bloquea aunque ya verifiqué | ¿La skill usó `cc-<session_id>` como run-id? Compruébalo con `qg status --run-id "$(qg session id)"` |
| Aviso "entrada JSON inválida" | el hook no actuó (por seguridad); revisa la versión de Claude Code |
| Quiero ver qué decidió `Stop` sin Claude | `qg session stop --run-id <id>`: imprime `decision=` y `reason=` (y registra la marca si bloquea) |
