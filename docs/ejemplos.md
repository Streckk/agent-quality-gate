# Ejemplos genéricos

Cinco situaciones habituales y cómo se ven con la puerta de calidad. Los nombres, rutas y salidas son inventados; sirven para reconocer el patrón, no para copiarlos.

En los comandos, `qg` representa la ruta absoluta resuelta una vez por la skill ([evidence-qg.md](../skills/quality-gate/references/evidence-qg.md) §1).

## 1. Proyecto TypeScript con errores heredados

`npx tsc --noEmit` falla con 236 errores que ya existían. La puerta no puede darlos por buenos ni arreglarlos todos en un cambio pequeño. Si el equipo decide convivir con ellos, se declara una línea base en `.agent/verification.yaml` (ver [examples/nodejs/verification.yaml](../examples/nodejs/verification.yaml)):

```yaml
checks:
  - id: typecheck
    run: npx tsc --noEmit
    required: true
    baseline:
      format: typescript
      reference: .agent/baselines/typecheck.txt
```

**La línea base la crea el usuario, no la skill.** Solo si lo pides expresamente:

```bash
qg baseline write --format typescript --output .agent/baselines/typecheck.txt -- npx tsc --noEmit
```

Con la línea base presente, la skill ejecuta `qg run --baseline … typecheck -- npx tsc --noEmit`. Los errores conocidos no cuentan; uno nuevo hace fallar el check, aunque el total no suba. Si tu cambio corrige 3 errores heredados, el reporte lo refleja:

```text
| typecheck | `npx tsc --noEmit` | passed (línea base: 233 conocidos, 3 corregidos) | 2 | sin diagnósticos nuevos | sí |
```

Veredicto: `PASS WITH LIMITATIONS` como máximo, con "236 errores de TypeScript heredados" en las limitaciones. Si el comando es un script (`npm run typecheck`) o encadena otra herramienta, `qg` lo rechaza (`blocked`): hay que darle `tsc` directo.

## 2. Workspace con backend y frontend (esquema 2)

Dos repositorios Git hermanos, `api/` y `web/`, y un cambio que toca los dos. La skill verifica cada repo con su `qg status` y emite una tabla por repo y un bloque de esquema 2:

```json
{
  "kind": "quality-gate-report",
  "schema": 2,
  "verdict": "PASS WITH LIMITATIONS",
  "risk": "medium",
  "repos": [
    { "id": "api", "evidence": { "provider": "qg", "run_id": "cc-<session_id>", "status": "valid", "fingerprint": "sha1:<huella api>" } },
    { "id": "web", "evidence": { "provider": "qg", "run_id": "cc-<session_id>", "status": "valid", "fingerprint": "sha1:<huella web>" } }
  ],
  "approvals": { "pending_required": 0, "pending_optional": 1 },
  "review": { "status": "skipped", "reason": "unavailable: codex ready:false" }
}
```

El `pending_optional: 1` es un `git push` que nadie pidió: se ofrece, no bloquea. Si `web` estuviera `stale` o `failed`, no habría `PASS` global: el veredicto es el del peor repo.

## 3. Corrección de un hallazgo de seguridad con revisión acotada

La revisión independiente confirma que un endpoint no comprueba la pertenencia del recurso al usuario (autorización). La skill:

1. confirma el hallazgo (lo reproduce con una prueba que falla);
2. lo corrige dentro del alcance y reejecuta las verificaciones afectadas;
3. pide **una** revisión adversarial acotada al diff de la corrección (`--base <commit previo>` y el foco del hallazgo);
4. declara `"review": { "status": "done", "kind": "adversarial", "critical_fixed": true, "followup": "done" }`.

Si la revisión acotada encuentra otro problema Important o Critical, no abre otra ronda: lo reporta y el veredicto pasa a `BLOCKED` o `FAIL`. Si Codex no está disponible, `followup: pending` y el máximo es `PASS WITH LIMITATIONS`. Las Agent Evals lo comprueban con `security_followup` ([agent-evals.md](agent-evals.md)).

## 4. Una verificación que genera archivos

El script `test:report` escribe un informe en `reports/`. Antes de ejecutarlo:

```bash
qg classify -- npm run test:report
# → writes-generated (el script escribe en reports/)
```

`writes-generated` se ejecuta, pero se anota: el informe cambia la huella si no está ignorado por Git, y la evidencia podría quedar `stale` (`changed_during_run`). Opciones, de mejor a peor: un modo del propio proyecto que no escriba; ignorar `reports/` (un cambio del repo: se propone, no se hace sin aprobación); o declararlo en el reporte. Si la clase fuera `installs-dependencies`, `external-side-effects` o `unknown` con indicios externos, la skill pide aprobación antes de ejecutar.

`qg classify` es una heurística: puede dar `read-only` a un comando con formas poco comunes de escribir (`-bu`, `--updateSnapshot=true`). Complementa a leer el script, no lo sustituye.

## 5. Una ejecución desde caché

Un monorepo con Turborepo. La salida de `turbo run test` termina con:

```text
 Tasks:    4 successful, 4 total
Cached:    4 cached, 4 total
```

Exit 0, pero no se ejecutó ninguna prueba: todo salió de caché. La skill lo reporta citando esa línea y sin inventar conteos:

```text
| unit | `pnpm turbo run test` | passed (caché total: "4 cached, 4 total") | 0 | resultado reutilizado | sí |
```

Si el cambio afecta a lo cacheado, se reejecuta sin caché con la opción que documente la herramienta. Con caché parcial se indica qué tareas salieron de caché; si la salida no permite saberlo, `passed (caché: desconocido)`.
