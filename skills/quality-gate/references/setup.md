# `/quality-gate setup` — instrucciones persistentes en CLAUDE.md

Añade, actualiza, consulta o quita un bloque **breve y administrado** en `CLAUDE.md`. El bloque dice **cuándo** usar `/quality-gate`; el cómo sigue en `SKILL.md`. La operación la hace el script determinista `qg-setup`: **no edites `CLAUDE.md` a mano**.

## Pasos

1. Localiza el script con la ruta que indica `SKILL.md`. Puede no estar en el `PATH` si solo está instalada la skill:

   ```bash
   command -v qg-setup || ls -l "$(cd -P '<directorio de la skill>' && cd ../.. && pwd)/bin/qg-setup"
   ```

   Si el script no existe, dilo y no edites nada.
2. Ejecútalo desde el directorio del proyecto, pasándole **exactamente** los argumentos que escribió el usuario, sin añadir ninguno:

   ```bash
   "<ruta>/qg-setup" setup <argumentos del usuario>
   ```

   - **Nunca** añadas `--scope user`, `--force` ni `--import-agents` si el usuario no los escribió.
   - Si el usuario no está seguro, propón `--dry-run` o `--status`.
3. Muestra la salida tal cual y termina. No ejecutes verificaciones, no hagas commit y no ejecutes `/init`.
4. Si el script sale con **65** (conflicto: bloque malformado o duplicado, `CLAUDE.md` y `.claude/CLAUDE.md` a la vez, proyecto solo con `AGENTS.md`, instrucciones similares) o con **66** (enlace simbólico fuera del alcance o sin permisos):
   - explica el motivo y las opciones que da el script;
   - **no** lo resuelvas tú editando archivos;
   - **no** relances con otra opción sin que el usuario la elija.

## Sintaxis

| Comando | Efecto |
|---|---|
| `/quality-gate setup` | instala o actualiza el bloque en el `CLAUDE.md` del proyecto (raíz de Git o directorio actual) |
| `/quality-gate setup --scope user` | lo mismo en `~/.claude/CLAUDE.md` (todas tus sesiones) |
| `/quality-gate setup --status` | estado del bloque, sin modificar nada |
| `/quality-gate setup --dry-run` | diff del cambio propuesto, sin escribir |
| `/quality-gate setup --remove` | quita solo el bloque administrado |
| `--file CLAUDE.md` · `--file .claude/CLAUDE.md` | elige el archivo cuando existen ambos |
| `--import-agents` | si el proyecto solo tiene `AGENTS.md`: crea `CLAUDE.md` con `@AGENTS.md` y el bloque (`AGENTS.md` no se toca) |

## Qué no hace

No instala el plugin, no activa hooks, no toca `~/.claude/settings.json` ni `AGENTS.md`, y no garantiza que Claude invoque la skill: `CLAUDE.md` es una instrucción persistente para el modelo, no una barrera ejecutable. Las instrucciones nuevas se cargan **a partir de la próxima sesión**.
