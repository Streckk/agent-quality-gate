# Uso local diario (sin marketplace)

Guía corta para trabajar a diario con `agent-quality-gate` cargado desde el clon local. No instala nada, no toca `~/.claude/settings.json` y no activa hooks globales. Comprobado con Claude Code 2.1.332 ([validacion-uso-local.md](validacion-uso-local.md)).

Flujo: **iniciar Claude Code con el plugin → desarrollar → el hook `Stop` avisa de cambios sin verificar → `/quality-gate` → evidencia `valid` → terminar.**

## 1. Iniciar

```bash
cd <tu-proyecto>
QG_HOOKS=1 claude --plugin-dir /home/angel/Desarrollo/agent-quality-gate   # plugin + hooks, solo esta sesión
claude --plugin-dir /home/angel/Desarrollo/agent-quality-gate              # plugin sin hooks (qg en el PATH)
claude                                                                     # sin plugin: solo la skill (symlink)
```

- Los hooks están **desactivados por defecto**. `QG_HOOKS=1` los activa solo para el proceso que lanzas. También acepta `stop` o `pretool` para activar uno solo.
- Si lo usas a menudo, puedes definir un alias en tu shell, por ejemplo `alias claude-qg='QG_HOOKS=1 claude --plugin-dir /home/angel/Desarrollo/agent-quality-gate'`. Es opcional y lo decides tú: este repositorio no modifica tu configuración.
- **Symlink y plugin a la vez:** el symlink global `~/.claude/skills/quality-gate` apunta a esta misma copia, y Claude Code registra **una sola** skill `quality-gate`. No hace falta borrar nada. Solo habría duplicado (`agent-quality-gate:quality-gate`) si instalaras el plugin en **otra** ruta, por ejemplo desde un marketplace. En ese caso, deja una sola vía ([hooks.md](hooks.md#evitar-la-skill-duplicada)).

## Configurar CLAUDE.md una vez

`/quality-gate setup` añade al `CLAUDE.md` un bloque breve que le dice a Claude **cuándo** usar la skill: al terminar tareas que modifican código, pruebas, dependencias, build o CI. El **cómo** sigue en la skill. Desde la sesión siguiente, Claude lo tiene presente sin que escribas `/quality-gate`.

| Comando | Efecto |
|---|---|
| `/quality-gate setup` | instala o actualiza el bloque en el `CLAUDE.md` del proyecto (raíz de Git) |
| `/quality-gate setup --scope user` | lo mismo en `~/.claude/CLAUDE.md` (todos tus proyectos). Solo si lo pides |
| `/quality-gate setup --status` | estado: archivo, si existe, si el bloque está instalado o desactualizado, menciones fuera del bloque |
| `/quality-gate setup --dry-run` | diff del cambio, sin escribir |
| `/quality-gate setup --remove` | quita **solo** el bloque. Si el archivo no tenía nada más, lo borra |

- **Sin Claude:** también se puede ejecutar desde la terminal con `qg-setup setup [opciones]` (con el plugin cargado, está en el `PATH`) o con `<repo>/bin/qg-setup`.
- **Idempotente:** repetirlo no cambia ni un byte. Si el bloque es de una versión anterior, solo se reemplaza el bloque. Lo que hay fuera de los marcadores `<!-- agent-quality-gate:start/end -->` se conserva byte a byte, con CRLF incluido. Claude Code elimina esos comentarios antes de pasarle el archivo al modelo.
- **Se niega, sin tocar nada, cuando:**
  - el bloque está incompleto o duplicado;
  - existen `CLAUDE.md` y `.claude/CLAUDE.md` sin bloque (elige con `--file`);
  - el archivo ya menciona `/quality-gate` fuera del bloque (`--force` para añadirlo igualmente);
  - `CLAUDE.md` es un enlace simbólico fuera del proyecto;
  - no hay permiso de escritura.
- **Proyecto solo con `AGENTS.md`:** Claude Code solo lee `AGENTS.md` cuando **no** hay `CLAUDE.md`. Crear uno dejaría de cargarlo. El setup se detiene y propone `--import-agents`, que crea `CLAUDE.md` con `@AGENTS.md` y el bloque sin tocar `AGENTS.md`.
- **Qué no hace:** no instala el plugin, no activa hooks, no toca `settings.json` ni `AGENTS.md`, y no ejecuta `/init`. **No garantiza** que Claude invoque la skill: es una instrucción persistente, no una barrera. Para detectar cambios sin evidencia están los hooks (`QG_HOOKS=1`).

## 2. Comprobar que está cargado

Dentro de la sesión, el prefijo `!` ejecuta un comando de shell sin pasar por el modelo:

```text
! command -v qg && qg hooks status
! qg session info --run-id "$(qg session id)"
```

- `command -v qg` debe apuntar a `…/agent-quality-gate/bin/qg`, porque el plugin añade `bin/` al `PATH`. Sin plugin no aparece. Aun así, la skill lo localiza junto a sí misma.
- `qg hooks status` muestra `stop`/`pretool` como `on (env:QG_HOOKS)`, `off (env:QG_DISABLE)` u `off (default)`. **Ojo:** muestra el entorno del proceso desde el que lo ejecutas.
- `qg session info` muestra si `SessionStart` registró la sesión (`inicio: registrado`), la huella actual, si hubo cambios y los bloqueos de `Stop`. Si los hooks están desactivados, no habrá inicio registrado.

## 3. Verificar

- Manual: escribe `/quality-gate` o pide "verifica esto". El reporte termina con `## Quality Gate — <VEREDICTO>`, la tabla de verificaciones y el bloque JSON `quality-gate-report`.
- Desde tu terminal, en el repositorio:

```bash
Q=/home/angel/Desarrollo/agent-quality-gate/bin/qg
$Q status --run-id cc-<session_id>            # valid | failed | blocked | incomplete | stale | missing (exit 0…5)
$Q status --run-id cc-<session_id> --json     # lo mismo, para herramientas
$Q run --run-id cc-<session_id> unit -- npm test   # registrar evidencia a mano (cualquier comando)
```

El run-id de la sesión es `cc-<session_id>`. Lo devuelve `qg session id` dentro de la sesión, y también aparece en el reporte y en el aviso de `Stop`.

## 4. Qué pasa si…

| Situación | Comportamiento |
|---|---|
| Cambias código y terminas sin verificar (hooks activos) | `Stop` pide **una vez** ejecutar `/quality-gate` o explicar por qué no hace falta. No vuelve a pedirlo para el mismo contenido, y como máximo 3 veces por sesión |
| Un test falla | `qg status` = `failed`. La skill intenta corregir dentro del alcance, como máximo 2 veces. Si no lo consigue, el veredicto es `FAIL`. `Stop` **no** bloquea con `failed`: el fallo se reporta, no se esconde |
| Cambias algo después de verificar | la evidencia pasa a `stale` y `Stop` vuelve a pedir verificación. Un `PASS` anterior ya no vale |
| `git push` o `gh pr create` sin evidencia `valid` (hooks activos) | `PreToolUse` muestra un diálogo de confirmación (`ask`); tú decides. Nunca concede permisos por su cuenta |
| Commit con `Co-Authored-By` u otro trailer de IA (hooks activos) | `deny` |
| Codex no está instalado o no ha iniciado sesión | revisión `skipped (unavailable)`. En riesgo `medium`/`high`, el veredicto máximo es `PASS WITH LIMITATIONS`. Todo lo demás funciona igual |
| Proyecto sin Git | no hay huella ni `qg`. La skill trabaja en modo sin `qg` y lo declara (`provider: none`) |
| Herramienta del proyecto no instalada | verificación `blocked` con motivo. La skill no instala nada sin tu aprobación |

## 5. Desactivar y volver atrás

| Quiero… | Cómo |
|---|---|
| Sesión sin hooks | omite `QG_HOOKS` o usa `QG_HOOKS=0` |
| Apagar los hooks aunque el proyecto los active | `QG_DISABLE=1` (gana a todo) |
| Claude Code sin el plugin | lanza `claude` sin `--plugin-dir`. La skill del symlink sigue disponible |
| Borrar la evidencia local de un repo | `qg gc` (temporales, cuarentena y sesiones antiguas) o eliminar `.git/quality-gate/`. Solo es estado local y está fuera del árbol versionado |

Nada de esto deja rastro en tu configuración: `--plugin-dir` y las variables de entorno solo valen para ese proceso.

## 6. Probar sin riesgo en un proyecto de juguete

Para probar sin tocar ningún proyecto real, usa los fixtures de los evals:

```bash
cd /home/angel/Desarrollo/agent-quality-gate
bash -c '. evals/lib/fixtures.sh; fx_build node-bug /tmp/qg-demo'   # repo con un bug que rompe un test
cd /tmp/qg-demo && QG_HOOKS=1 claude --plugin-dir /home/angel/Desarrollo/agent-quality-gate
# en la sesión: "/quality-gate"
```

Otros fixtures disponibles:
- `node-clean`: sin cambios;
- `node-guardrails`: `deploy` simulado;
- `python-skip`: suite con exit 0 sin pruebas;
- `docs-only`;
- `no-git`.

## 7. Llevarlo a tus proyectos

- No hace falta configurar nada: Discover lee `CLAUDE.md`/`AGENTS.md`, `package.json` (con su lockfile), `nx.json`/`turbo.json`, `pyproject.toml`/`tox.ini`, `Makefile` y la CI.
- Para fijar lo obligatorio, añade `.agent/verification.yaml` en **ese** proyecto (ejemplos en `examples/`). No en este repositorio.
- **Nx:** si el repo usa `nx affected`, en local suele necesitar `--base`. Si no hay base, la skill lo señala.
- **Servicios externos** (bases de datos, Docker, credenciales): esas verificaciones quedan `blocked` salvo que el entorno ya los tenga y lo autorices.
- Empieza con hooks solo en sesiones concretas (`QG_HOOKS=1`). El cumplimiento obligatorio para todo el equipo va en la CI y en la protección de ramas: los hooks son controles locales, no garantías.
