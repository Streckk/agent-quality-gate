# Guardrails

## 1. Instrucciones frente a controles ejecutables

| Tipo | Ejemplos | ¿Garantiza algo? |
|---|---|---|
| **Instrucción** | `CLAUDE.md`, `AGENTS.md`, esta `SKILL.md` | No. Orienta al agente; puede ignorarse o malinterpretarse. |
| **Permisos de Claude Code** | `permissions.allow/deny` en `settings.json` | Sí, dentro de Claude Code y para las herramientas que cubren. |
| **Hooks** | `PreToolUse`, `Stop` en `settings.json` | Sí, si están configurados y el evento ocurre. |
| **Tests / lint / tipos** | suite del repo | Sí, para lo que comprueban. |
| **CI y protección de ramas** | workflows obligatorios, reviews requeridas | Sí, en el servidor, para lo que bloquean. |

En el reporte, **no llames "obligatorio" a un guardrail que solo está escrito en texto**. Indica qué control lo hace cumplir, o "solo instrucción".

Esta skill es una instrucción. No proporciona garantías por sí misma.

Los **hooks opcionales del plugin** (`Stop`, `PreToolUse`; ver `docs/hooks.md` del repositorio) son controles ejecutables **locales**:
- piden verificar los cambios sin evidencia vigente;
- rechazan commits con trailers de IA;
- piden confirmación para `push`/PR sin evidencia.

Están desactivados por defecto, se pueden desactivar en cualquier momento (`QG_DISABLE=1`) y no ven scripts, alias ni otras herramientas: no sustituyen a la CI ni a la protección de ramas.

## 2. Acciones que requieren aprobación explícita del usuario

Aunque una verificación o corrección parezca necesitarlas:

- despliegues (cualquier entorno compartido; producción siempre),
- migraciones, seeds, borrados o escrituras sobre datos reales,
- crear, leer en claro, rotar o modificar secretos y credenciales,
- `git push`, force push, reescritura de historial, cambios de remotos o de visibilidad,
- publicar paquetes, crear releases, abrir/cerrar PRs o issues,
- modificar CI, hooks, permisos, reglas de lint/umbrales de cobertura,
- instalar herramientas globales o descargar y ejecutar scripts,
- cambiar `git config` (identidad incluida),
- enviar código a servicios externos (p. ej. revisión de Codex) cuando el repo lo restrinja o el diff contenga secretos o datos sensibles.

Además, por clase de efecto (`qg classify`): `installs-dependencies`, `external-side-effects` y `unknown` con indicios externos requieren aprobación antes de ejecutar; `writes-source` también, porque modifica código. Y crear o actualizar una línea base de errores (`qg baseline write`) requiere petición explícita del usuario.

En el reporte, separa lo que bloquea de lo que solo se ofrece: una aprobación **obligatoria** para cerrar el alcance pendiente da `BLOCKED` (`approvals.pending_required`); una acción posterior que nadie pidió (push, PR) no bloquea y va como `pending_optional`. Ver [report-format](report-format.md).

La aprobación vale para la acción concreta que se pidió, no para acciones similares posteriores.

## 3. Comandos

- Solo comandos que existen en el repo o son estándar del toolchain detectado.
- Lee un script antes de ejecutarlo si su nombre o contenido sugiere efectos externos.
- Respeta `forbidden_commands` de `.agent/verification.yaml` y los `deny` de permisos.
- Nada de `curl | sh` ni binarios descargados sin verificar.

## 4. Veredicto

- Una condición obligatoria en `failed` o `blocked` → el veredicto **no** puede ser `PASS`.
- Una verificación que pasó solo contra una línea base → como máximo `PASS WITH LIMITATIONS`.
- Una aprobación obligatoria pendiente → `BLOCKED`.
- Documenta la evidencia del bloqueo y qué haría falta para desbloquearlo.

## 5. Autoría

No añadas trailers ni créditos de IA (`Co-Authored-By`, `Generated-by`, etc.) en commits, PRs o archivos de autoría si el repositorio o el usuario lo prohíben. No cambies la identidad Git.
