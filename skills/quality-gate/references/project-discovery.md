# Fase 1 — Discover

Objetivo: saber **qué** revisar, **con qué** comandos reales y **cuánto** riesgo hay, sin asumir ningún stack.

## 1. Alcance del cambio

Por orden de preferencia:

1. Lo que indique el usuario (rutas, rama, PR, commit).
2. Si hay cambios sin commitear: `git status --short --untracked-files=all` y `git diff --stat` (+ `--cached`).
3. Si el working tree está limpio y la rama no es la principal: `git diff --stat <base>...HEAD`, donde `<base>` es la rama principal detectada (`git symbolic-ref refs/remotes/origin/HEAD`, o `main`/`master` si existen).
4. Si no es un repositorio Git: pide al usuario el alcance; no revises todo el disco.
5. **Varios repositorios** (p. ej. backend y frontend en repos Git distintos, aunque estén en carpetas hermanas): aplica los pasos 1–3 **en cada repo** por separado, con su propia base. Cada repo tiene su huella, sus verificaciones y su fila en el reporte (esquema 2, [report-format](report-format.md)). Un repo hermano que el cambio no toca queda fuera del alcance y se dice.

Anota los archivos tocados: determinan qué paquetes/verificaciones son relevantes.

## 2. Fuentes de contexto (orden de prioridad)

1. **Instrucciones del repo**: `CLAUDE.md`, `AGENTS.md`, `.claude/`, reglas por carpeta. Mayor prioridad.
2. **Configuración opcional** `.agent/verification.yaml` (ver esquema abajo).
3. **Documentación y decisiones**: `docs/`, `knowledge/`, ADRs, `CONTRIBUTING.md`.
4. **Grafo de dependencias** con Graphify — solo si está instalado y el cambio afecta módulos con dependientes no evidentes. Comprueba antes (`command -v graphify` o la skill/herramienta correspondiente). Si no está: sigue sin él; no es un requisito.
5. **Manifiestos y herramientas reales**: ver tabla.

Si dos fuentes se contradicen (p. ej. `CLAUDE.md` dice `pnpm test` pero no hay `pnpm-lock.yaml`), **explica la discrepancia** en el reporte y respeta la de mayor prioridad, o pregunta si la ejecución podría ser dañina. No edites documentación ni políticas para "arreglar" la discrepancia por iniciativa propia.

## 3. Descubrimiento de verificaciones

Una verificación solo es candidata si **existe en el repositorio**. Registra siempre su origen (`package.json#scripts.test`, `Makefile:lint`, `.github/workflows/ci.yml`, ...).

| Señal | Dónde buscar comandos reales |
|---|---|
| `package.json` | `scripts`; gestor según lockfile (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `bun.lock*`) |
| `nx.json` / `turbo.json` | targets del workspace; preferir los de proyectos afectados (`nx affected`) si el repo ya los usa |
| `pyproject.toml`, `setup.cfg`, `tox.ini`, `noxfile.py` | secciones `[tool.*]`, entornos tox/nox, `pytest`, `ruff`, `mypy` configurados |
| `Cargo.toml` | `cargo check`, `cargo test`, `cargo clippy` (estándar del toolchain) |
| `go.mod` | `go vet ./...`, `go test ./...` |
| `Makefile`, `justfile`, `Taskfile.yml` | targets declarados |
| CI (`.github/workflows`, `.gitlab-ci.yml`, ...) | los pasos que CI ejecuta son la mejor pista de lo que el proyecto considera obligatorio |

Reglas:

- Los comandos estándar de un toolchain (`cargo test`, `go test`) son válidos si el manifiesto existe y la herramienta está instalada (`command -v`).
- Una herramienta referenciada pero no instalada → la verificación queda `blocked` (motivo: herramienta ausente). No la instales sin aprobación.
- Si dudas de que un comando sea seguro (scripts con `deploy`, `migrate`, `seed`, `publish`, `release`, acceso a red o a datos reales), **no lo ejecutes**: márcalo `skipped` y explícalo. Lee el script antes si hace falta.
- Comandos que requieren servicios externos (BD, docker, credenciales) → solo si el entorno ya los tiene y el usuario lo autoriza; si no, `blocked`.

**Efectos secundarios (con `qg`):** pasa cada candidata por `qg classify -- <comando>` ([evidence-qg](evidence-qg.md) §4b) y anota la clase en la tabla de verificaciones (`read-only`, `writes-generated`, `writes-source`, `installs-dependencies`, `external-side-effects`, `unknown`). Las clases `writes-source`, `installs-dependencies`, `external-side-effects` y `unknown` con indicios externos piden aprobación antes de ejecutar; `read-only` y `writes-generated` no. Si crees que `classify` exagera (falso positivo), lee su `motivo` y el script, y aplica evidence-qg §4b. Para evitar instalaciones implícitas, usa las formas que el propio gestor documente y solo si existen; no inventes flags. Sin `qg`, lee el script y aplica el mismo criterio.

Clasifica cada verificación como **obligatoria** (CI la exige, la config la marca `required`, o es lint/tipos/tests del área afectada) u **opcional**.

## 4. Integraciones opcionales

Comprueba disponibilidad real, no la documentación:

- **Codex**: ver [agent-evals](agent-evals.md#1-detectar-codex).
- **Graphify**: `command -v graphify` o skill disponible en la sesión.
- **Superpowers / frontend-design**: aparecen en la lista de skills de la sesión. Solo se mencionan; esta skill no las invoca por su cuenta.

Ninguna es obligatoria. Si falta alguna, la puerta sigue con lo disponible y declara la limitación en el reporte: sin Codex, `review: skipped (unavailable: <motivo>)` (con sus efectos en el veredicto, agent-evals §7); sin `qg`, `Evidencia: sin qg (<motivo>)`; sin Graphify, el análisis de dependientes se hace leyendo el código y se dice si el cambio tiene dependientes no evidentes. No instales ninguna para completar la puerta.
- **`qg`** (evidencia ejecutable): detección, compatibilidad (`qg version --json`, interfaz ≥ 2), run-id y `qg require` en [evidence-qg](evidence-qg.md) §1–3. Declara con `qg require` **todas** las verificaciones obligatorias que salgan de este descubrimiento.

## 5. Nivel de riesgo

| Nivel | Señales |
|---|---|
| `high` | autenticación/autorización, aislamiento entre tenants, pagos, criptografía, manejo de secretos, migraciones o escrituras masivas de datos, concurrencia, infraestructura/CI/permisos, APIs públicas con contrato externo |
| `medium` | lógica de negocio, cambios en varios módulos, dependencias nuevas o actualizadas, cambios de configuración de build |
| `low` | documentación, tests aislados, cambios locales pequeños sin efecto en contratos |

Ante la duda, sube un nivel. Una sola señal `high` hace el cambio `high`.

"Pagos" significa movimiento real de dinero (cobros, procesadores, conciliación). Un cálculo de importes sin movimiento de dinero es `medium` salvo que el repo diga otra cosa. Para fijarlo sin ambigüedad usa `high_risk_paths` en la config opcional. Indica siempre en el reporte qué señal determinó el nivel: el nivel decide el coste de la revisión.

## 6. Configuración opcional `.agent/verification.yaml`

No es necesaria. Si existe, tiene prioridad sobre la heurística de descubrimiento (pero no sobre `CLAUDE.md`/`AGENTS.md`). Si falta o es inválida, avisa y continúa con el descubrimiento normal.

```yaml
version: 1
max_fix_iterations: 2          # límite de autocorrección (por defecto 2)
default_risk: medium           # nivel mínimo para este repo
checks:
  - id: lint
    run: pnpm lint             # comando literal; debe existir en el repo
    required: true
  - id: unit
    run: pnpm test -- --run
    required: true
    timeout_seconds: 600
  - id: e2e
    run: pnpm e2e
    required: false
    needs: [docker]            # requisitos de entorno; si faltan → blocked
  - id: typecheck
    run: node_modules/.bin/tsc --noEmit   # con baseline: tsc directo y binario local (no npx; evidence-qg §4a)
    required: true
    baseline:                  # errores heredados; ver evidence-qg §4a
      format: typescript       # único formato admitido
      reference: .agent/baselines/typecheck.txt   # ruta relativa a la raíz del repo
review:
  min_risk_for_review: medium  # low | medium | high | never
  adversarial_at: high
high_risk_paths:               # rutas que fuerzan riesgo high
  - "apps/api/src/auth/**"
  - "**/migrations/**"
forbidden_commands:            # nunca ejecutar automáticamente
  - "pnpm deploy"
```

Validación mínima: `version: 1`, cada check con `id` y `run`; si hay `baseline`, `format: typescript` y `reference` (ruta relativa, sin `..`, dentro del repo). Un `baseline` inválido se ignora con aviso y el check se ejecuta sin línea base. La línea base la crea solo el usuario (`qg baseline write`). Campos desconocidos → ignorar con aviso. Incluso con config, verifica que el binario del comando exista antes de ejecutarlo.
