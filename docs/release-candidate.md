# Preparación de la primera versión estable (release candidate)

Estado a 2026-11-24, sobre `v0.2.0-dev` con los cambios de la iteración de evaluación robusta ([validacion-v0.2.0-rc.md](validacion-v0.2.0-rc.md)). **No se ha creado ningún tag ni release.**

**Uso local:** listo. La licencia, el marketplace, el icono y la versión estable **no** bloquean el uso diario con `--plugin-dir` ([uso-local.md](uso-local.md), [validacion-uso-local.md](validacion-uso-local.md)). Solo afectan a la publicación.

Leyenda: ✅ cumplido · ⏳ pendiente · ⚠️ riesgo aceptable (documentado) · ⛔ bloquearía una versión estable.

## 1. Checklist

### Funcionalidad y calidad

| | Requisito | Estado / evidencia |
|---|---|---|
| ✅ | Skill `/quality-gate` (Discover → Verify → Review → Report) | validación funcional v0.1.0 y sesiones reales posteriores |
| ✅ | Funciona **sin el plugin** (symlink de la skill) | la skill localiza `qg` junto a sí misma aunque no esté en el `PATH`; sin `qg` entra en el modo v0.1 declarado |
| ✅ | Evidencia determinista `qg` (interfaz 3) | `tests/core/` en Linux y macOS (bash 3.2, awk BWK) |
| ✅ | Hooks **desactivados por defecto**; activación y desactivación (`QG_HOOKS`, bloque `hooks:`, `QG_DISABLE`) | `tests/hooks/` y sesiones reales ([validacion-v0.2.0-hooks.md](validacion-v0.2.0-hooks.md)) |
| ✅ | Política de permisos: `deny` a trailers de IA, `ask` en push/PR sin evidencia, **nunca** `allow`; diálogo interactivo verificado | [validacion-v0.2.0-evals.md](validacion-v0.2.0-evals.md) §6 |
| ✅ | Convivencia con Superpowers y Codex (SessionStart de los tres, ninguno lanza Codex) | validación de hooks, escenario 5 |
| ✅ | Reporte con bloque estructurado versionado | contrato en `report-format.md`; validador y regresiones (Nivel A) |
| ⛔ | **El bloque estructurado no se ha visto aún en una sesión real**: el contrato es nuevo y la skill nunca lo ha emitido ante el evaluador | ejecutar al menos el piloto del Nivel B ([comparacion-con-sin-plugin.md](comparacion-con-sin-plugin.md) §7) |
| ✅ | `claude plugin validate --strict .` | sin avisos en 2.1.332 |

### Pruebas, CI y evaluación

| | Requisito | Estado / evidencia |
|---|---|---|
| ✅ | Batería determinista local completa | ver [validacion-v0.2.0-rc.md](validacion-v0.2.0-rc.md) §1 |
| ⏳ | **CI remota de esta iteración** (ShellCheck obligatorio, macOS, bash 3.2) | la última CI en verde es la de `3500982`; estos cambios no se han publicado. ShellCheck no está instalado en local |
| ✅ | Sin modelos en CI | el Nivel B y `claude plugin eval` quedan fuera de Actions |
| ⏳ | Nivel B con muestra suficiente (≥ 3–5 ejecuciones por caso) | solo 3 ejecuciones reales (1 por caso) |
| ⏳ | Comparación con y sin plugin | preparada, sin ejecutar: requiere `socat` y presupuesto |
| ⚠️ | Detección de tests debilitados y del riesgo en Markdown por patrones | las heurísticas producen **sospechas**, no violaciones; el bloque estructurado da el riesgo exacto |

### Distribución y documentación

| | Requisito | Estado / evidencia |
|---|---|---|
| ✅ | README con instalación (skill global/local, plugin con `--plugin-dir`), uso, límites y mantenimiento | `README.md` |
| ⛔ | **Licencia** | sin `LICENSE`: en un repositorio público, por defecto **nadie** puede reutilizar ni modificar el código legalmente. Es decisión del propietario (§3) |
| ⏳ | Instalación como plugin con `claude plugin install` | requiere un marketplace (decisión del propietario). Hoy: `--plugin-dir` o symlink de la skill |
| ⏳ | Guía para contribuir (`CONTRIBUTING.md`: cómo ejecutar las pruebas, política de autoría, regla de bash 3.2, cómo añadir un caso de eval) | parte está repartida en README y `docs/agent-evals.md` |
| ⏳ | Versión `0.2.0` en `plugin.json` y `CHANGELOG`, tag y release | solo con autorización |
| ⏳ | Icono | decisión del propietario |
| ⚠️ | Documentación solo en español | decisión de alcance; limita a contribuyentes no hispanohablantes |
| ✅ | Reproducibilidad de evaluaciones | fixtures sintéticos con identidad y fechas fijas, `--session-id`, `--model`, metadatos por ejecución, resultados locales fuera de git |

## 2. Riesgos y límites conocidos

**Aceptables (documentados):**
- La skill es una instrucción para un modelo: puede no seguirla perfectamente. Por eso existen `qg`, los hooks, la CI y los evals.
- Los hooks son **controles locales, no garantías**: se pueden desactivar, y no cubren todas las formas de crear commits (alias, scripts, hooks de Git) ni impiden un push fuera de Claude Code.
- `PreToolUse` es conservador: pregunta en algunos comandos legítimos (p. ej. `cd "$DIR" && git commit -m x`).
- Skill duplicada si conviven el symlink global y el plugin instalado en otra ruta ([hooks.md](hooks.md)).
- La revisión de Codex es puntual, no determinista y envía el diff a un servicio externo.
- Soporte: Linux y macOS. Windows sin probar.

**Bloquearían una versión estable:** la ausencia de licencia y que el bloque estructurado no se haya validado con Claude real (§1). La CI de los cambios nuevos también debe pasar antes de etiquetar.

## 3. Licencia: MIT frente a Apache-2.0 (informativo; no se añade ningún archivo)

| | MIT | Apache-2.0 |
|---|---|---|
| Extensión | muy corta | larga |
| Uso, modificación, redistribución y uso comercial | sí | sí |
| Concesión **expresa de patentes** | no | sí, con terminación si el licenciatario demanda por patentes |
| Obligaciones al redistribuir | conservar el aviso de copyright y la licencia | lo mismo, más el archivo `NOTICE` si existe y la indicación de los archivos modificados |
| Contribuciones | sin cláusula específica | las contribuciones se entienden licenciadas bajo Apache-2.0, salvo indicación en contra |
| Compatibilidad con GPL | GPLv2 y GPLv3 | solo GPLv3 |

Para una herramienta pequeña de scripts y documentación, MIT es la opción más simple. Apache-2.0 aporta protección de patentes y una regla clara para las contribuciones, a cambio de más texto y formalidades. **La decisión es del propietario**, y no se añadirá `LICENSE` hasta que la tome.

## 4. Decisiones reservadas al propietario

Licencia · marketplace · icono · paso a versión estable (`0.2.0`) · tags y releases · activación global de hooks · presupuesto de evaluaciones (plan mínimo/ampliado y Nivel B) · instalación de `socat` · consumo de Codex en el Nivel B · cada push.

## 5. Camino propuesto hacia la versión estable

1. Push de esta iteración (con aprobación) → CI en verde en Linux y macOS.
2. Instalar `socat` (con autorización) y ejecutar el **plan mínimo** como piloto, con las comprobaciones de [comparacion-con-sin-plugin.md](comparacion-con-sin-plugin.md) §2.
3. Ejecutar el Nivel B B-3 ([comparacion-con-sin-plugin.md](comparacion-con-sin-plugin.md) §7): confirma el bloque estructurado y el riesgo con Claude real. Corregir lo que aparezca.
4. Decidir la licencia y añadir `LICENSE`; añadir `CONTRIBUTING.md`.
5. Plan ampliado si el piloto es válido; documentar los resultados sin sobreinterpretarlos.
6. Versión `0.2.0` en `plugin.json` y en el CHANGELOG, tag y release, solo con autorización expresa.
