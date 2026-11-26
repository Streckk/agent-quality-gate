# Fase 2 — Verify (Feedback Loops)

Objetivo: ejecutar verificaciones reales, leer sus resultados, corregir lo corregible dentro del alcance y volver a comprobar, **sin bucles infinitos**.

## 1. Criterios de aceptación

Antes de ejecutar nada, deja claro qué significa "correcto" para este cambio:

- Criterios explícitos del usuario, del ticket o del plan (p. ej. el plan de Superpowers si existe).
- Verificaciones obligatorias detectadas en Discover.
- Si no hay criterios explícitos, dilo en el reporte: la puerta solo puede afirmar que las verificaciones automáticas pasan, no que el comportamiento sea el deseado.

## 2. Orden de ejecución

De más barato a más caro, y parando pronto si algo básico falla:

1. Formato / lint
2. Tipado / compilación (`check`, `tsc --noEmit`, `mypy`, `cargo check`)
3. Tests unitarios del área afectada
4. Build
5. Integración / e2e (solo si el riesgo lo justifica y el entorno lo permite)

Prefiere el subconjunto afectado (tests del paquete, `nx affected`, rutas concretas) si el repo ya ofrece esa forma. Para riesgo `high`, ejecuta además la suite completa que exija CI.

## 3. Captura de evidencia

Si `qg` está disponible, ejecuta cada verificación con `qg run --run-id <ID> <check-id> -- <comando>` ([evidence-qg](evidence-qg.md) §4). `qg` registra el comando, el exit code, los tiempos y la huella. Tú sigues leyendo la salida para clasificar el resultado. Sin `qg`, ejecútala directamente y registra tú los datos.

Para cada verificación registra:

- comando exacto y directorio,
- exit code,
- duración aproximada,
- resumen de salida (conteo de tests, primer error relevante; no vuelques logs enteros),
- ruta a reportes generados si existen (junit, coverage).

**Línea base:** si el check declara `baseline`, ejecútalo con `qg run --baseline` ([evidence-qg](evidence-qg.md) §4a). La salida llega al terminar. Un `passed` contra la línea base se reporta como `passed (línea base: K conocidos, F corregidos)` y limita el veredicto a `PASS WITH LIMITATIONS`. No crees ni actualices la línea base para que un check pase: solo a pedido explícito del usuario.

**Caché:** anota si la salida demuestra ejecución real, caché parcial, caché total o desconocido, citando la línea de la herramienta (evidence-qg §4c). No inventes conteos.

**Efectos secundarios:** una verificación `writes-generated` deja archivos; menciónalo en el reporte. Si `qg` marca `changed_during_run`, la evidencia queda `stale` (evidence-qg §6).

Un exit code 0 con salida que indica que no se ejecutó nada (p. ej. "no tests found", o tests que se autoexcluyen si falta una variable de entorno) es `skipped`, no `passed`. Con `qg`, regístralo además con `qg reject --run-id <ID> <check-id> --reason no_tests_executed` para que la evidencia no quede como válida.

Conserva el exit code real: en `cmd | tail` el `$?` es el de `tail`. Usa `${PIPESTATUS[0]}`, redirige a un archivo o no uses pipes.

Archivos auxiliares (sondas, copias de la base): en un directorio de `mktemp -d` fuera del repo, y bórralos al terminar. Si las verificaciones dejan residuos en el repo (`__pycache__`, cachés de build), menciónalos en el reporte.

## 4. Clasificación de resultados

| Estado | Significado |
|---|---|
| `passed` | se ejecutó y terminó con éxito, con evidencia |
| `failed` | se ejecutó y falló |
| `blocked` | debía ejecutarse pero no se pudo: herramienta ausente, permisos, servicio externo, timeout, aprobación pendiente |
| `skipped` | se decidió no ejecutarla, con motivo (fuera de alcance, riesgo bajo, comando potencialmente peligroso, sin tests) |

## 5. Bucle de corrección

```
iteración = 0          # contador global de la ejecución, no por verificación
mientras haya verificaciones obligatorias en failed:
    si iteración == max_fix_iterations (por defecto 2): parar → bloqueo
    diagnosticar la causa raíz con la salida real
    si la causa está fuera del alcance o requiere acción sensible: parar → pendiente
    aplicar la corrección mínima
    reejecutar la verificación fallida y las que dependan de los archivos tocados (con qg run si está disponible)
    iteración += 1
```

Reglas:

- Diagnostica antes de tocar código. Si Superpowers está disponible, su skill de depuración sistemática es la herramienta adecuada para fallos no triviales.
- **No** "arregles" un fallo debilitando la verificación: no borres ni saltes tests, no añadas `@ts-ignore`/`# type: ignore`/`#[allow]`, no relajes reglas de lint ni umbrales, salvo petición explícita del usuario.
- Si el proyecto tiene una línea base de errores heredados, los diagnósticos que ya figuran en ella no cuentan como nuevos; los nuevos sí, aunque el total no suba.
- Si el fallo ya existía antes del cambio, márcalo como **preexistente** y no lo cuentes contra el cambio; repórtalo igualmente. Compruébalo **sin tocar el working tree del usuario**: ejecuta la verificación sobre una copia de la base en un directorio temporal (`git archive <base> | tar -x -C "$(mktemp -d)"` o `git worktree add`). No uses `git stash`/`checkout` sobre el working tree.
- Fallos intermitentes: reintenta una vez; si cambia el resultado, repórtalo como *flaky*, no como `passed`.
- Si el cambio revisado es del usuario y no pidió correcciones, **pregunta antes de editar**: la puerta puede limitarse a informar.

## 6. Condiciones de parada

Detente y reporta (sin seguir intentando) cuando:

- se alcance el límite de iteraciones,
- falten permisos o herramientas,
- la corrección exija una acción sensible (ver [guardrails](guardrails.md)),
- la causa raíz sea ambigua y una corrección pudiera cambiar comportamiento esperado.
