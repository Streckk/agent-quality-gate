# evals/

Agent Evals de `/quality-gate`. La documentación completa está en [docs/agent-evals.md](../docs/agent-evals.md).

- `cases/`: casos propios (`case.conf` con criterios + `task.md`), evaluados con evidencia real de `qg` por `evaluate.sh`.
- `official/`: casos en formato `claude plugin eval` (aislamiento y comparación con y sin plugin).
- `lib/fixtures.sh`: fixtures Git sintéticos y reproducibles. **Nunca** uses proyectos reales.
- `runs/`, `results/`: resultados locales; no se versionan ni se publican.

```bash
bash tests/run_eval_tests.sh                        # nivel A: sin modelos (también en CI)
bash evals/run.sh --dry-run                         # nivel B: consume cuota; nunca en CI
```
