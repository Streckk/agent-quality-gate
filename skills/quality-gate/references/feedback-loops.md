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

Para cada verificación registra:

- comando exacto y directorio,
- exit code,
- duración aproximada,
- resumen de salida (conteo de tests, primer error relevante; no vuelques logs enteros),
- ruta a reportes generados si existen (junit, coverage).

Un exit code 0 con salida que indica que no se ejecutó nada (p. ej. "no tests found") es `skipped`, no `passed`.

## 4. Clasificación de resultados

| Estado | Significado |
|---|---|
| `passed` | se ejecutó y terminó con éxito, con evidencia |
| `failed` | se ejecutó y falló |
| `blocked` | debía ejecutarse pero no se pudo: herramienta ausente, permisos, servicio externo, timeout, aprobación pendiente |
| `skipped` | se decidió no ejecutarla, con motivo (fuera de alcance, riesgo bajo, comando potencialmente peligroso, sin tests) |

## 5. Bucle de corrección

```
iteración = 0
mientras haya verificaciones obligatorias en failed:
    si iteración == max_fix_iterations (por defecto 2): parar → bloqueo
    diagnosticar la causa raíz con la salida real
    si la causa está fuera del alcance o requiere acción sensible: parar → pendiente
    aplicar la corrección mínima
    reejecutar la verificación fallida y las que dependan de los archivos tocados
    iteración += 1
```

Reglas:

- Diagnostica antes de tocar código. Si Superpowers está disponible, su skill de depuración sistemática es la herramienta adecuada para fallos no triviales.
- **No** "arregles" un fallo debilitando la verificación: no borres ni saltes tests, no añadas `@ts-ignore`/`# type: ignore`/`#[allow]`, no relajes reglas de lint ni umbrales, salvo petición explícita del usuario.
- Si el fallo ya existía antes del cambio (compruébalo, p. ej. con `git stash` solo si es seguro, o contra la rama base), márcalo como **preexistente** y no lo cuentes contra el cambio; repórtalo igualmente.
- Fallos intermitentes: reintenta una vez; si cambia el resultado, repórtalo como *flaky*, no como `passed`.
- Si el cambio revisado es del usuario y no pidió correcciones, **pregunta antes de editar**: la puerta puede limitarse a informar.

## 6. Condiciones de parada

Detente y reporta (sin seguir intentando) cuando:

- se alcance el límite de iteraciones,
- falten permisos o herramientas,
- la corrección exija una acción sensible (ver [guardrails](guardrails.md)),
- la causa raíz sea ambigua y una corrección pudiera cambiar comportamiento esperado.
