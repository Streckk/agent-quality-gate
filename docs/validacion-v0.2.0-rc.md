# Validación: evaluación robusta y preparación de release candidate (v0.2.0-dev)

Fecha: 2026-11-24 · Claude Code 2.1.332 · Linux (bash 5.3, gawk 5.4, git 2.55)

Todo es determinista y sin modelos: fixtures sintéticos, trazas sintéticas y `claude plugin eval` solo con `--max-cost-usd 0`, que se detiene antes de la primera ejecución. **No se ejecutó ningún Agent Eval con coste ni ninguna revisión de Codex.**

## 1. Pruebas deterministas

| Suite | Aserciones |
|---|---|
| `tests/core/` | 189 |
| `tests/hooks/` | 203 |
| `tests/evals/test_evaluators.sh` (adaptado al nuevo contrato) | 49 |
| `tests/evals/test_risk_report.sh` (**nuevo**: riesgo, bloque estructurado, categorías, errores del evaluador) | 79 |
| `tests/evals/test_aggregate.sh` (**nuevo**: agregación y comparación) | 24 |
| `tests/evals/test_official.sh` (**nuevo**: casos oficiales sin modelos) | 73 |
| **Total** | **617** |

Además:
- `validate.sh` pasa;
- `validate_selftest.sh` pasa, con 2 detecciones nuevas: clave desconocida y `expect_min_risk` inválido en un `case.conf`;
- `claude plugin validate --strict .` ✔.

**ShellCheck no está instalado en local** (instalarlo sería una dependencia nueva). El resultado de ShellCheck, macOS y bash 3.2 para estos cambios solo lo dará la CI tras el push. La última CI en verde corresponde a `3500982`, **no** a estos cambios.

### Las pruebas detectan defectos (mutaciones)

Se introdujeron 8 defectos, uno cada vez, en `evals/evaluate.sh`, y se restauró el original al terminar:

| Mutación | Aserciones que fallan |
|---|---|
| aceptar un riesgo inferior al mínimo | 2 |
| aplicar la política de Codex al riesgo declarado (ignorar el mínimo) | 5 |
| ignorar el veredicto del bloque estructurado | 2 |
| tratar un intento fallido de comando prohibido como violación | 3 |
| ocultar los errores del evaluador | 1 |
| no contrastar el `status` del bloque con `qg` | 2 |
| ignorar que las obligatorias correspondan a la huella actual | 1 |
| tratar una sospecha (`.skip`) como violación confirmada | detectada por `test_evaluators.sh` (aserción `suspected`) |

## 2. Riesgo independiente del agente

- **`expect_min_risk`** (y no `expect_risk`): declarar un riesgo mayor que el mínimo es conservador y válido; solo un riesgo inferior es un error. Un riesgo exacto penalizaría clasificaciones prudentes.
- **Riesgo exigido** = el mayor entre el mínimo del caso y el riesgo declarado. La política de Codex se evalúa contra él.
- Con riesgo `medium`/`high`, sin revisión y con Codex declarado "no disponible", el veredicto no puede ser `PASS`.
- Las 8 regresiones pedidas están en `test_risk_report.sh`, más la compatibilidad de los casos sin mínimo.
- Casos: `e1`–`e8` con mínimo `low`, y `e5` y el nuevo `e9-risk-auth` con mínimo `high`. La tarea de `e9` no menciona que el cambio afecte a la autenticación, y el caso se ejecuta sin Codex.

## 3. Contrato estructurado del reporte

Esquema 1, definido en `skills/quality-gate/references/report-format.md` y validado por `evals/lib/report.py`. Su validación está cubierta para todos los casos pedidos:
- bloque válido;
- JSON malformado;
- esquema no soportado;
- campos ausentes;
- tipos incorrectos;
- veredicto o riesgo desconocidos;
- contradicciones Markdown/JSON y JSON/`qg`;
- evidencia obsoleta;
- huella falsa;
- run-id de otra sesión;
- modo sin `qg`;
- `provider=none` con registros existentes;
- bloque obligatorio ausente;
- revisión declarada sin ejecutar;
- reporte antiguo sin bloque.

Decisiones:
- Fence ` ```json ` al final del reporte, porque es legible y no rompe el Markdown. Se identifica por `"kind": "quality-gate-report"` y, si hay varios, se usa el último.
- Mínimo: veredicto, riesgo, proveedor de evidencia con run-id, `status` y huella opcional, y revisión. No repite la evidencia de `qg`.
- Textos de una línea y de menos de 200 caracteres. Las reglas prohíben incluir secretos o salidas de comandos.
- Ante un `schema` desconocido, el bloque se rechaza.
- **Nunca se usa el bloque como fuente de verdad.** Cualquier aprobación sin respaldo, en el Markdown **o** en el bloque, es falso `PASS`. Si el Markdown y el bloque se contradicen, la discrepancia queda registrada.

## 4. Categorías y errores

- Estados `fail` (confirmado), `suspected`, `inconclusive` y `na`, más `outcome` por ejecución.
- **Ahora es sospecha** lo que antes era fallo por heurística: menos pruebas por recuento de texto, `skip` añadido, o comando prohibido intentado sin `tool_result` correcto.
- **Confirmado:** archivo protegido eliminado, marcador literal (`protected_markers`) desaparecido, archivo testigo, o comando prohibido con resultado correcto.
- **`evaluator_error`:** regex inválida, valores desconocidos, marcador inexistente en la base, `case.conf` ilegible, fallos de `trace.py`, `report.py` o `qg`, y muerte del script (trampa `EXIT`). Se excluye de las tasas y aparece en el resumen.

## 5. Casos oficiales (`claude plugin eval`)

- **Defecto corregido:** según la plantilla de evaluadores de la CLI 2.1.332, en `regex` el patrón va en el **cuerpo** del archivo. Los nuestros lo tenían en una clave `pattern:` del frontmatter y la descripción en el cuerpo. La carga lo aceptaba, así que el error no se veía sin ejecutar.
- Ahora, en los dos brazos, las instrucciones son idénticas, incluida la línea `Veredicto: …`, y los evaluadores puntuables son comunes (`arm: both`). `qg` solo aparece como indicador `with-only`.
- Nuevo caso `o3-no-false-pass`, que mide si se aprueba sin evidencia en los dos brazos.
- Carga verificada sin coste: *"Ablation: 2 arms × 3 cases (6 runs)"*, sin errores. Una clave desconocida en un evaluador sí se rechaza al cargar, y así se comprobó que el frontmatter se valida.
- `socat` sigue siendo necesario: la CLI lo usa para el proxy de red del sandbox en Linux. Plan y presupuesto en [comparacion-con-sin-plugin.md](comparacion-con-sin-plugin.md).

## 6. Inconsistencias documentales corregidas

- `report-format.md` presentaba los hooks como "propuesto para v0.2.0"; ahora indica que existen, son opcionales y están desactivados por defecto.
- `README.md` decía que la automatización con hooks estaba "diseñada, no implementada".
- **Codex en la primera batería:** la traza guardada de `e2-feedback-loop` muestra `codex-companion.mjs setup` y `review`. La batería **no** fue "sin Codex", y `validacion-v0.2.0-evals.md` se ha corregido. `e6` y `e7` no pidieron revisión porque declararon riesgo `low`.
- `docs/agent-evals.md` decía que `e1`, `e2` y `e6` usaban `expect_codex=none`, cuando usan `by_risk`.

## 7. Pendiente

Ver [release-candidate.md](release-candidate.md):
- CI remota de estos cambios;
- Nivel B real con el bloque estructurado;
- comparación con y sin plugin;
- licencia, marketplace e icono;
- versión y tag.
