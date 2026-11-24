# Propuesta técnica v0.2.0 — automatización con hooks

> Estado: la **infraestructura de evidencia está implementada** (`bin/qg`, ver [evidencia.md](evidencia.md)). Los **hooks no están implementados**. Revalidar el contrato de hooks contra la documentación vigente de Claude Code antes de implementarlos.

## Decisiones finales de la iteración de evidencia (difieren de esta propuesta)

| Propuesta original | Decisión implementada | Motivo |
|---|---|---|
| huella = HEAD + `git diff HEAD` + no versionados | árbol Git del working tree (`git add -A` + `write-tree` en índice y almacén temporales) | `git diff HEAD` no representa bien renombres, binarios ni repos sin commits; el árbol es canónico, depende del contenido, coincide con `HEAD^{tree}` en limpio y no escribe en `.git/objects` |
| un `state.json` con lock | registros inmutables por ejecución + `required` con lock | sin jq, reescribir JSON en bash es frágil; los registros hacen que las ejecuciones concurrentes no compitan entre sí |
| HMAC con clave en `~/.config` | descartado | sin una clave fuera del alcance del propio agente no protege nada; la garantía real es CI |
| scripts POSIX `sh` + PowerShell | bash ≥ 3.2 + git; sin PowerShell | `sh` POSIX no puede leer listas separadas por NUL ni pasar argv sin `eval`; PowerShell duplicaría toda la lógica sin un caso de uso probado |
| `PostToolUse` marca `dirty` | no hace falta para la validez: `qg status` recalcula la huella bajo demanda | ver "Integración de hooks" más abajo |

## Principio

Los hooks convierten **algunas** reglas de la skill en controles ejecutables locales. No garantizan que Claude siga todas las instrucciones: no ven la intención, se pueden desactivar y no se ejecutan fuera de Claude Code. Lo que debe ser obligatorio para el equipo va a CI (sección 10).

Distribución: empaquetar como **plugin de Claude Code** (`.claude-plugin/plugin.json` + `skills/` + `hooks/hooks.json`). Así la skill y los hooks se instalan y desinstalan juntos y de forma explícita (`/plugin install|uninstall`), igual que hacen Codex y Superpowers. El symlink de v0.1 sigue siendo válido para quien solo quiera la skill.

## 1. Detectar cambios relevantes (`PostToolUse`)

- Matcher: `Edit|Write|MultiEdit|NotebookEdit|Bash`. `Bash` se incluye porque los comandos también modifican archivos (formateadores, generadores, `sed -i`).
- No interpretar el comando: tras cada herramienta, recalcular la **huella** del alcance (HEAD + hash de `git diff HEAD` + lista de no versionados) y compararla con la anterior. Si cambió, marcar `dirty=true` y guardar qué rutas cambiaron.
- Filtro de relevancia: ignorar rutas de `.gitignore` y, opcionalmente, una lista `ignore_paths`. Cambios solo en docs → `dirty_docs` (no exige verificación de código).
- Coste: `git diff | sha256sum` es O(tamaño del diff). En repos enormes, usar `git status --porcelain=v2` + mtimes como prefiltro.
- Salida: silenciosa (exit 0, sin `additionalContext`), para no gastar contexto ni interferir con otras skills.

## 2. Registrar el estado de verificación de forma segura (superado: ver evidencia.md)

- Ubicación: `$(git rev-parse --git-path quality-gate)/state.json`. Queda dentro de `.git`, no se versiona y es por worktree. Sin Git: `${XDG_STATE_HOME:-~/.local/state}/quality-gate/<sha256(ruta)>.json`.
- Contenido: `{schema, session_id, fingerprint_current, dirty, last_verification: {fingerprint, verdict, checks: [{id, cmd, exit, started, ended}], report_hash}}`.
- Escritura atómica (temporal + `mv`) y lock por archivo (`mkdir` como mutex portable) para hooks concurrentes.
- **Quién escribe `last_verification`**: no el texto del modelo. Se propone un pequeño ejecutor `qg-run <id> -- <cmd>` que ejecuta el comando, captura el exit code real y la huella **en el momento de ejecutar**, y lo anexa al estado. La skill lo usaría en Verify. No es un motor de orquestación: ejecuta un único comando y lo registra.
- Limitación declarada: un agente con Bash podría editar `state.json`. Mitigación parcial: HMAC del registro con una clave en `~/.config/quality-gate/key` (fuera del repo). Disuade los errores, no a un actor malicioso con acceso al home. La garantía real es CI.

## 3. Impedir que evidencia antigua valide cambios nuevos (superado: ver evidencia.md)

- Una verificación solo cuenta si `check.fingerprint == fingerprint_current`.
- Cualquier `PostToolUse` que cambie la huella deja obsoletas todas las verificaciones previas: no se "arrastran" `passed`.
- El reporte incluye la huella. El hook `Stop` compara la del último reporte con la actual.
- `git commit` no cambia el contenido, pero sí HEAD. La huella se basa en el **árbol** (`git write-tree` del índice más el diff del working tree) para que commitear lo ya verificado no invalide la evidencia.

## 4. `Stop` sin ciclos infinitos

Bloquea el fin del turno solo si se cumplen **todas** estas condiciones:

1. `dirty=true` con cambios de código en esta sesión;
2. no existe una verificación con la huella actual;
3. `stop_hook_active` es `false` (la entrada del hook indica si ya se está continuando por un Stop);
4. el contador `stop_blocks` de esta huella es menor que 1 (configurable, máximo 2).

Si bloquea, devuelve `{"decision":"block","reason":"Cambios sin verificar (huella X). Ejecuta /quality-gate o explica por qué no aplica."}`. En cualquier otro caso deja terminar y, como mucho, avisa. Escape del usuario: `QG_DISABLE=1` o `qg off` (archivo de estado). Nunca bloquea en sesiones sin cambios ni en subagentes (`SubagentStop` no se usa).

Coexistencia con Codex: el plugin Codex tiene su propio `Stop` (review gate, `reviewGateEnabled`). Si está activo, nuestro `Stop` no exige revisión de Codex; solo exige verificaciones, para evitar dobles bloqueos y dobles costes.

## 5. `PreToolUse` para operaciones prohibidas

- Primera opción: **`permissions.deny` nativo** de Claude Code (`Bash(pnpm deploy:*)`, `Bash(git push --force:*)`). Es más robusto que un hook y no requiere código. La v0.2 generaría las reglas sugeridas a partir de `forbidden_commands`, pero el usuario las aplica.
- Hook solo para lo que `deny` no puede expresar:
  - `git commit` con un mensaje que contenga trailers de IA → `permissionDecision: "deny"` con motivo;
  - `git push` / `gh pr create` con veredicto distinto de `PASS*` para la huella actual → `"ask"` (no `deny`: la decisión es humana).
- Parseo conservador: si el comando no se entiende (subshells, `eval`, variables), no se interpreta y se deja a los permisos normales. No se promete detectar todo.

## 6. Coordinación con Codex

- La v0.2 **no** lanza Codex desde hooks: es caro, lento y envía el código fuera. La decisión sigue en la fase Review de la skill.
- El estado registra `review: {kind, exit, fingerprint, result}`. `Stop` puede exigir revisión solo si la config lo pide (`review.required_at: high`) y nunca si el Codex review gate ya está activo.
- `review` con "nothing to review" (exit 0) se registra como `skipped`, no `done` (validación v0.1, defecto 4).

## 7. Instalación y desinstalación explícitas

- Como plugin: `/plugin install agent-quality-gate@<marketplace>` y `/plugin uninstall`. Los hooks quedan en el `hooks.json` del plugin y no tocan `settings.json` del usuario.
- Interruptor por proyecto: `.agent/verification.yaml` → `hooks: { stop: on|off, pretool: on|off }`. Por defecto **off** hasta que el usuario lo active; v0.2 no debe cambiar el comportamiento de nadie sin opt-in.
- Comando `/quality-gate hooks status` que muestre qué hooks están activos y de dónde vienen.
- Desinstalar deja el estado en `.git/quality-gate/`; un `qg purge` lo elimina con confirmación.

## 8. Evitar conflictos con Superpowers y otras skills

- Superpowers solo registra `SessionStart` (comprobado en 7.0.2) y Codex `SessionStart`/`SessionEnd`/`Stop`. La v0.2 no usa `SessionStart` ni `UserPromptSubmit`: no inyecta contexto en cada turno.
- `PostToolUse` es silencioso. Solo `Stop` y `PreToolUse` hablan, y solo cuando bloquean.
- No duplicar `verification-before-completion` de Superpowers: el hook exige **evidencia** (estado), no reproduce instrucciones. El mensaje del bloqueo remite a `/quality-gate`.
- Matchers estrechos y timeouts cortos (`PostToolUse` ≤ 5 s, `Stop` ≤ 10 s; nunca ejecutar tests dentro de un hook).

## 9. Compatibilidad entre lenguajes y sistemas operativos

- Los hooks no dependen del stack del proyecto: solo usan `git` y el sistema de archivos.
- Runtime de los scripts: no se puede asumir Node ni Python en todos los entornos. Propuesta: scripts POSIX `sh` (Linux, macOS, WSL, Git Bash) más un equivalente PowerShell para Windows nativo, ambos con lógica mínima (hash, comparar, leer/escribir JSON plano). Alternativa a evaluar: un único script Node, si se confirma que el runtime del usuario siempre lo tiene; hoy no es así con el instalador nativo.
- Hash: `sha256sum` / `shasum -a 256` / `Get-FileHash`, detectados en tiempo de ejecución.
- Config: el YAML es difícil de parsear en `sh`. Los hooks leerían un `.agent/verification.json` generado, o un subconjunto clave-valor documentado; la skill sigue aceptando YAML.

## 10. Controles que deben vivir en CI, no en hooks

| Control | Motivo |
|---|---|
| lint, tipos, tests, build obligatorios como *required status checks* | los hooks se pueden desactivar y no corren para otros contribuidores |
| protección de rama `main` (PR obligatorio, sin force push) | control del servidor |
| escaneo de mensajes de commit del PR buscando trailers de IA | la política de autoría debe cumplirse también fuera de Claude Code |
| escaneo de secretos (gitleaks) | idem |
| `tests/validate.sh` y su autotest en este repo | ya existe |
| revisiones humanas requeridas para rutas de alto riesgo (`CODEOWNERS`) | decisión humana, no del agente |

## Archivos de la siguiente etapa (lista original; actualizada al final del documento)

Crear:
- `.claude-plugin/plugin.json`: manifiesto del plugin.
- `hooks/hooks.json`: registro de `PostToolUse`, `Stop` y `PreToolUse` (opt-in).
- `hooks/scripts/fingerprint.sh` y `fingerprint.ps1`: cálculo de la huella.
- `hooks/scripts/post-tool-use.sh` y `.ps1`: marca `dirty`.
- `hooks/scripts/stop.sh` y `.ps1`: lógica anti-ciclo.
- `hooks/scripts/pre-tool-use.sh` y `.ps1`: trailers y push sin veredicto.
- `bin/qg-run` (+ `.ps1`): ejecutor de un comando con registro de evidencia.
- `skills/quality-gate/references/hooks.md`: qué controla cada hook y qué no.
- `tests/hooks/*.sh`: pruebas con JSON de entrada simulados por evento (incluido el ciclo de `Stop`).
- `.github/workflows/validate.yml` (job nuevo): pruebas de hooks en `ubuntu-latest`, `macos-latest` y `windows-latest`.

Modificar:
- `skills/quality-gate/SKILL.md` y `references/feedback-loops.md`: usar `qg-run` si está disponible y degradar a la v0.1 si no.
- `references/report-format.md`: la huella sale del estado registrado.
- `references/project-discovery.md`: claves `hooks:` y `review.required_at` en el esquema.
- `examples/*/verification.yaml`: claves nuevas.
- `tests/validate.sh`: estructura del plugin y `hooks.json`.
- `README.md` y `CHANGELOG.md`.

## Integración de hooks propuesta (siguiente iteración, sobre `qg`)

Con la evidencia ya disponible, los hooks se simplifican: **no necesitan guardar estado propio**, porque preguntan a `qg`.

| Hook | Acción | Coste |
|---|---|---|
| `SessionStart` (opcional) | `qg fingerprint` → guarda la huella inicial de la sesión en `quality-gate/v1/sessions/<session_id>` | 1 huella |
| `PostToolUse` | **no necesario para la validez**. Opcional: avisar una sola vez de que la evidencia quedó obsoleta tras la primera edición | 0–1 huella por herramienta |
| `Stop` | si la huella actual ≠ la de inicio de sesión (hubo cambios) y `qg status` ≠ `valid` → `{"decision":"block","reason":"…qg status: <resultado>…"}`. No bloquea si `stop_hook_active=true`, ni más de una vez por huella (se registra en `sessions/<id>`). Escape: `QG_DISABLE=1` | 1 huella + lectura de registros (≈ coste de `git status`) |
| `PreToolUse` (Bash) | para `git commit`, rechaza trailers de IA en el mensaje. Para `git push`/`gh pr create` con `qg status` ≠ `valid` → `ask`, no `deny` | solo en esos comandos |

Requisitos para empezar:

1. Las obligatorias del proyecto declaradas con `qg require` (o derivadas por la skill de `.agent/verification.yaml`).
2. La skill usa `qg-run <id> -- <cmd>` en la fase Verify cuando `qg` esté disponible, y hace como hasta ahora si no lo está.
3. Empaquetado como plugin con hooks **desactivados por defecto**.

### Archivos de la siguiente iteración

Crear:
- `.claude-plugin/plugin.json`
- `hooks/hooks.json`
- `hooks/stop.sh`
- `hooks/pre-tool-use.sh`
- `hooks/session-start.sh`
- `tests/hooks/*.sh`, con JSON de entrada simulados por evento, incluido el ciclo de `Stop`.

Modificar:
- `skills/quality-gate/references/feedback-loops.md`: usar `qg-run`.
- `references/report-format.md`: la huella se toma de `qg status --json`.
- `references/project-discovery.md`: `qg require` a partir de los checks obligatorios.
- `bin/qg`: subcomando `session` (inicio y marcas de bloqueo).
- `.github/workflows/validate.yml`
- `README.md` y `CHANGELOG.md`
