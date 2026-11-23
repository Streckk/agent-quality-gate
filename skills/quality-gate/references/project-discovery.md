# Fase 1 — Discover

Objetivo: saber **qué** revisar, **con qué** comandos reales y **cuánto** riesgo hay, sin asumir ningún stack.

## 1. Alcance del cambio

Por orden de preferencia:

1. Lo que indique el usuario (rutas, rama, PR, commit).
2. Si hay cambios sin commitear: `git status --short --untracked-files=all` y `git diff --stat` (+ `--cached`).
3. Si el working tree está limpio y la rama no es la principal: `git diff --stat <base>...HEAD`, donde `<base>` es la rama principal detectada (`git symbolic-ref refs/remotes/origin/HEAD`, o `main`/`master` si existen).
4. Si no es un repositorio Git: pide al usuario el alcance; no revises todo el disco.

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

Clasifica cada verificación como **obligatoria** (CI la exige, la config la marca `required`, o es lint/tipos/tests del área afectada) u **opcional**.

## 4. Integraciones opcionales

Comprueba disponibilidad real, no la documentación:

- **Codex**: ver [agent-evals](agent-evals.md#1-detectar-codex).
- **Graphify**: `command -v graphify` o skill disponible en la sesión.
- **Superpowers / frontend-design**: aparecen en la lista de skills de la sesión. Solo se mencionan; esta skill no las invoca por su cuenta.

## 5. Nivel de riesgo

| Nivel | Señales |
|---|---|
| `high` | autenticación/autorización, aislamiento entre tenants, pagos, criptografía, manejo de secretos, migraciones o escrituras masivas de datos, concurrencia, infraestructura/CI/permisos, APIs públicas con contrato externo |
| `medium` | lógica de negocio, cambios en varios módulos, dependencias nuevas o actualizadas, cambios de configuración de build |
| `low` | documentación, tests aislados, cambios locales pequeños sin efecto en contratos |

Ante la duda, sube un nivel. Una sola señal `high` hace el cambio `high`.

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
review:
  min_risk_for_review: medium  # low | medium | high | never
  adversarial_at: high
high_risk_paths:               # rutas que fuerzan riesgo high
  - "apps/api/src/auth/**"
  - "**/migrations/**"
forbidden_commands:            # nunca ejecutar automáticamente
  - "pnpm deploy"
```

Validación mínima: `version: 1`, cada check con `id` y `run`. Campos desconocidos → ignorar con aviso. Incluso con config, verifica que el binario del comando exista antes de ejecutarlo.
