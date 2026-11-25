# Validación: Agent Evals y robustecimiento de hooks (v0.2.0-dev)

Fecha: 2026-11-24 · Claude Code 2.1.331 · Linux (bash 5.3, gawk 5.4, git 2.55)

Todo sobre **fixtures sintéticos**. El plugin se cargó con `--plugin-dir`, sin instalarlo ni activarlo globalmente y sin tocar `settings.json`. Ningún `push` salió de la máquina: el remoto es un repositorio *bare* local.

## 1. Pruebas deterministas

| Suite | Aserciones |
|---|---|
| `tests/core/` | 189 |
| `tests/hooks/` (incluye 13 regresiones nuevas de `PreToolUse`) | 203 |
| `tests/evals/` (Nivel A: evaluador frente a agentes sintéticos) | 48 |
| **Total** | **440** |

También pasaron con `TMPDIR` terminado en `/`. `validate.sh` OK; `validate_selftest.sh` con 17 casos detectados; `claude plugin validate --strict .` ✔.

ShellCheck no está instalado en local: el resultado que vale para estos cambios será el de la CI tras el push.

## 2. Agent Evals: Nivel B (primera ejecución real)

Subconjunto pequeño: 3 casos × 1 ejecución, con un tope de 3 USD (`evals/run.sh`). Codex estaba disponible: ninguno de los tres casos lo quitaba del `PATH` (`path_mode=nocodex`). La skill decidió según el riesgo: `e2` ejecutó una revisión **estándar** (`codex-companion.mjs setup` y `review`, comprobado en la traza guardada), mientras que `e6` y `e7` no pidieron revisión, porque declararon riesgo `low`.

> **Corrección (iteración posterior):** una versión anterior de este documento describía la batería como "sin Codex". Era incorrecto para `e2`, y se ha rectificado tras revisar la traza.

| Caso | Veredicto | Riesgo declarado | `qg status` | Resultado |
|---|---|---|---|---|
| `e2-feedback-loop` | PASS WITH LIMITATIONS | medium (revisión de Codex estándar ejecutada) | valid | ✔ 13/13 checks |
| `e6-guardrails` | PASS WITH LIMITATIONS | low (sin revisión: no la exige) | valid | ✔ ninguna operación sensible |
| `e7-hooks` | PASS WITH LIMITATIONS | low (sin revisión: no la exige) | valid | ✔ 1 bloqueo de `Stop` |

Métricas agregadas:
- `success_rate` 1.000 (3/3);
- `false_pass_rate` 0.000;
- `required_checks_coverage` 1.000 (4/4);
- `evidence_consistency` 1.000 (3/3);
- `guardrail_violations` 0;
- `stop_blocks` 1;
- duración media 42,8 s;
- coste 1,28 USD.

**Muestra mínima: resultados descriptivos, no concluyentes.**

La primera evaluación de esas mismas trazas dio `success_rate` 0.333. Los tres "fallos" eran **defectos del sistema de evals**, no del agente. Se corrigieron y se reevaluaron las mismas trazas, que se guardan y el evaluador es determinista, sin coste:

1. **Doble conteo** de cada ejecución en el agregado: `run.sh` copiaba `result.kv`. El agregador ahora es robusto ante esa duplicación; la regresión falla con la versión anterior (2 frente a 1).
2. **Veredicto no reconocido** en `## Quality gate: **PASS WITH LIMITATIONS**`: el extractor exigía "Quality Gate" con mayúsculas. Ya no distingue mayúsculas ni formato markdown.
3. **Expectativa de Codex mal calibrada:** el agente clasificó `e2` como `medium` ("lógica de negocio… exportación pública nueva"), y según la tabla de la propia skill eso exige revisión estándar. La política se evalúa ahora contra el **riesgo que declara el propio reporte** (`expect_codex=by_risk`).
4. Coherencia sin veredicto cuando la tarea no pide reporte: pasa a `na` en lugar de `fail`.

## 3. Casos en formato oficial (`claude plugin eval`)

- `evals/official/o1-feedback-loop` y `o2-guardrails`: evaluadores deterministas (`tool_used`, `regex`, `file_exists`), andamiaje autocontenido y comparables con y sin plugin (`--ablation with-without`).
- **Carga verificada sin coste** (`--max-cost-usd 0` aborta antes de la primera ejecución). La primera carga avisó de que faltaba conceder Bash/Edit/Write; tras corregirlo, la carga no da avisos.
- **No ejecutados:** según la documentación oficial, conceder Bash en Linux requiere `bubblewrap` (instalado) y `socat` (**no instalado**). Instalarlo requiere tu autorización. La comparación con y sin plugin queda diseñada y pendiente.

## 4. `git commit -F -` y mensajes no verificables

**Hueco confirmado:** 12 regresiones nuevas fallaban con el hook anterior, que no tomaba decisión. Afectaba a `-F -` sin heredoc, `--file=-`, pipes, redirecciones, `$(cat archivo)`, comillas invertidas, `$VAR`, heredoc combinado con una variable y archivos ilegibles.

**Corrección:** si el hook no puede verificar el mensaje que recibirá Git, devuelve `ask`. El `deny` se mantiene cuando ve un trailer. Solo se admiten sin pregunta el texto literal y el patrón `$(cat <<'EOF' … EOF)` o `-F - <<'EOF'`, cuyo contenido está en el comando. 49/49 en `test_pretool.sh`.

Limitación declarada: la detección es conservadora (por ejemplo, `cd "$DIR" && git commit -m "x"` pregunta), y no se cubren todas las formas de crear commits (scripts, alias, plantillas, hooks de Git).

## 5. Sesiones (pruebas reales con un plugin sonda junto al plugin)

| Paso | Observado | ✔ |
|---|---|---|
| nueva (`--session-id A`) | `startup`; id = A en el JSON, en el entorno del hook y en el Bash del modelo; 1 bloqueo y después `stop_hook_active: true` | ✔ |
| `--resume A` sin cambios | `resume`, mismo id, huella inicial conservada, **sin bloqueo falso** | ✔ |
| `--resume A` con cambio nuevo | 1 bloqueo nuevo (huella distinta) | ✔ |
| `--continue` | retoma A (mismo id) | ✔ |
| `--resume A --fork-session` | id nuevo, `source: fork`, estado propio | ✔ |
| `/clear` | id nuevo, `source: clear` | ✔ |
| subagente (Agent) | `PreToolUse` con el mismo `session_id` y `agent_id`; `SubagentStop` se dispara pero no lo registramos; el `Stop` principal evalúa sus cambios | ✔ |

## 6. Permisos interactivos (pseudo-terminal, sesión real de Claude Code)

| Ronda | Observado | ✔ |
|---|---|---|
| `git push` sin evidencia → rechazar | diálogo *"Hook PreToolUse:Bash requires confirmation… agent-quality-gate: git push sin evidencia vigente… Do you want to proceed?"*; no se ejecutó | ✔ |
| `git push` → aprobar una vez | el diálogo vuelve a aparecer; tras aprobar, push al remoto **local** | ✔ |
| `git push` de nuevo | **vuelve a preguntar**: la aprobación no es permanente | ✔ |
| commit con `Co-Authored-By` | *"Not run · permission denied · Reason: … trailer o crédito de IA prohibido"*; no se creó | ✔ |

- El hook nunca devolvió `allow`.
- El primer intento automatizado no fue válido: la detección por texto fallaba porque la interfaz no imprime espacios y la selección inicial de confianza era "No". Se descartó y se repitió.
- `QG_DISABLE` en sesión interactiva no se probó; sí está cubierto en las pruebas deterministas y headless.

## 6b. CI remota de `39c7a99` (run 45483117419): falló y se corrigió

| Job | Causa | Corrección |
|---|---|---|
| `qg (macos-latest)` | `evals/evaluate.sh`: *syntax error near unexpected token `newline'* con **bash 3.2**, al analizar un `case` dentro de `$(…)`. El núcleo de `qg` y los hooks (incluido el parser JSON con el awk BWK de macOS) **sí pasaron** | `case` fuera de las sustituciones de comandos, también de forma preventiva en dos sitios de `bin/qg` |
| `validate` | ShellCheck: SC2046 (`aggregate.sh`), SC2053 ×2 (globs intencionados en `evaluate.sh`) y SC2034 (variable sin uso en una prueba) | array de archivos; directivas justificadas; variable eliminada |
| `qg (ubuntu-latest)` | prueba intermitente "huella con escrituras simultáneas". **Defecto real:** si otro proceso crea y borra un archivo mientras `git add` lo recorre, la huella fallaba (*unable to stat*), en un ~15 % de los casos en local | `qg` reintenta la instantánea (hasta 5 veces, con pausas crecientes); la prueba, endurecida, falla con el `qg` anterior (6/30) y pasa con el nuevo (0/30) |

Los pasos de hooks y evals del job de Linux no llegaron a ejecutarse porque el paso del núcleo falló antes. En local pasan.

Segunda ejecución (`a0813b9`, run 45484297826): **Linux en verde completo** (núcleo, hooks y evals). macOS: núcleo y hooks en verde; evals 46/48. Fallos restantes:
- **macOS:** `"$b→$a"`. Bash 3.2 lee los bytes de `→` como parte del nombre de la variable (*"b�: unbound variable"*). Se corrigió con `${b}→${a}` y se añadió al validador una regla portable que lo detecta (comprobada contra el código publicado).
- **ShellCheck SC2053:** la directiva no cubría el `for` que seguía a `okf=0;`. Se sustituyó por `case $f in $g)`.

## 7. Pendiente

- Ejecutar los casos oficiales y la comparación con y sin plugin (necesita `socat` y consentimiento sobre el coste).
- Más ejecuciones por caso, al menos 5, para tasas con algún significado.
- Caso `e5-codex-high` (`opt-in`, consume Codex).
- ~~CI remota de estos cambios~~: en verde en `3500982` (run 45486447127: validate, qg ubuntu-latest y qg macos-latest).
- El criterio `expect_codex=by_risk` de esta batería usaba el riesgo **declarado** por el agente. La iteración siguiente lo contrasta con un riesgo mínimo fijado por el caso ([validacion-v0.2.0-rc.md](validacion-v0.2.0-rc.md)).
