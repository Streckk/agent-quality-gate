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

La aprobación vale para la acción concreta que se pidió, no para acciones similares posteriores.

## 3. Comandos

- Solo comandos que existen en el repo o son estándar del toolchain detectado.
- Lee un script antes de ejecutarlo si su nombre o contenido sugiere efectos externos.
- Respeta `forbidden_commands` de `.agent/verification.yaml` y los `deny` de permisos.
- Nada de `curl | sh` ni binarios descargados sin verificar.

## 4. Veredicto

- Una condición obligatoria en `failed` o `blocked` → el veredicto **no** puede ser `PASS`.
- Documenta la evidencia del bloqueo y qué haría falta para desbloquearlo.

## 5. Autoría

No añadas trailers ni créditos de IA (`Co-Authored-By`, `Generated-by`, etc.) en commits, PRs o archivos de autoría si el repositorio o el usuario lo prohíben. No cambies la identidad Git.
