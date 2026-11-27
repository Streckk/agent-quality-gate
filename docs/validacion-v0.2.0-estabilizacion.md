# Validación v0.2.0-dev — estabilización

Iteración sobre `062519f`. Commits: `2e13e8e` (classify), `4a46472` (skill y docs), `119fec9` (huella), `2eedd1f` (`security_followup`) y el de esta documentación. Ejecutado en Linux con el Bash del sistema; **no** probado con Bash 3.2 ni en macOS localmente (eso lo cubre la CI, que no se ha ejecutado sobre estos commits porque no están publicados).

## 1. `qg classify` y las banderas de Go

**Causa raíz.** La regla de grupos de banderas cortas (`-[A-Za-z]*u*` + `^-[A-Za-z]*u[A-Za-z]*$`) solo comprobaba que el argumento tuviera una `u`. `go test -run X`, `-count 1`, `-timeout 30s` o `-cpu 4` salían `writes-source`. Además, el glob exigía una letra antes de la `u`, así que `-uw` y `-update` nunca entraban en la regla.

**Corrección.** El grupo se evalúa con cualquier bandera de un guion. Para `go`, que no agrupa banderas, solo cuentan `-u` literal y la convención de archivos golden (`-update`, `-update=*`, `-update-*`, `-golden`). `-w` se evalúa antes que la regla general.

**Pruebas añadidas** (`tests/core/test_classify.sh`; RED: 8 fallos antes de corregir):

| Comando | Clase esperada |
|---|---|
| `go test -run TestAuth` · `-count 1` · `-timeout 30s` · `-cpu 4` | read-only |
| `go test -run TestUpdate -count=1 -timeout 30s -race ./...` · `-run=TestAuth` · `go vet -unusedresult` | read-only |
| `bash -c "go test -run TestAuth -count 1 ./..."` | read-only |
| `go test -run TestAuth -u` · `go get -u ./...` | writes-source |
| `go test ./... -update` · `-update=true` · `-update-golden` · `-golden` | writes-source |
| `go test -run TestAuth > out.txt` | writes-generated |
| `jest -u` · `vitest -u` · `eslint --fix .` · `jest -cu` · `vitest run -wu` · `vitest run -uw` · `jest --ci -u` · `eslint -w .` | writes-source |
| `jest -ci` | read-only |

## 2. Línea base con TypeScript real

Con `tsc` 5.9.3 ya instalado en la máquina (sin instalar nada), en repos temporales. Script reproducible y logs fuera del repo (scratchpad de la sesión).

| Punto | Resultado | Cómo |
|---|---|---|
| Generación explícita (`baseline write`; se niega a sobrescribir sin `--replace`, exit 65) | OK | compilador real |
| Mismos errores: exit real 2 conservado, `valid` con `baseline:known=3,fixed=0`, `baseline_checks` en `--json` | OK | compilador real |
| Desaparece un error: `known=2,fixed=1` | OK | compilador real |
| Error nuevo: `failed (baseline:new=1)` | OK | compilador real |
| Mismo total con firmas distintas: `failed` | OK | compilador real |
| Archivo modificado tras verificar, o línea base editada: `stale` | OK | compilador real |
| Salida que no es de `tsc` con `--baseline`: `blocked` | OK | compilador real |
| Veredicto limitado: `PASS` con check contra línea base → `baseline_verdict=fail`; `PASS WITH LIMITATIONS` → pass | OK | estado real de `qg` + reporte y traza sintéticos |

## 3. Esquema 2 con dos repositorios

`workspace/backend` y `workspace/frontend`, repos Git independientes con el mismo run-id.

| Punto | Resultado | Cómo |
|---|---|---|
| Evidencia por repo, mismo run-id, huellas independientes (editar frontend deja `stale` solo frontend) | OK | repos reales |
| Ambos `valid` y `PASS`: `multi_repo_verdict=pass` | OK | estado real + reporte sintético |
| Un repo `failed` y `PASS`: `multi_repo_verdict=fail`, `false_pass=1`; `FAIL` honesto pasa | OK | ídem |
| Un repo `stale` y `PASS`: fail; `BLOCKED` honesto pasa | OK | ídem |
| Esquema 1 con un repo sigue evaluándose | OK | ídem |
| Que Claude genere por sí mismo el esquema 2 | **pendiente de autorización** (consume modelo) | — |

Esto valida `qg` y el evaluador, no la ejecución real de la skill.

## 4. `security_followup`

Refuerzos deterministas, que solo pueden bajar un `pass` a `suspected`:
- comandos Bash con patrón de modificar archivos después de la última revisión;
- un alcance contradicho por la traza: `--base` igual al commit de la corrección, o `--base HEAD` / `--scope working-tree` con la corrección ya commiteada.

`followup_base=confirmed` solo dice que el sha de `--base` apareció en la salida de un comando git antes de la corrección; no demuestra qué diff vio Codex. Una corrección hecha solo con Bash sigue siendo `inconclusive`. Los patrones de Bash no son exhaustivos (`python`, `node -e`, scripts propios).

**Defecto de la guía encontrado:** en el plugin Codex 1.0.6, `--base <ref>` revisa `merge-base...HEAD` (solo commits). La skill pedía `--base <commit previo>` sin commitear antes, así que la revisión acotada podía no ver la corrección. Ahora: `--scope working-tree` si la corrección no está commiteada, `--base` si lo está, y no se commitea solo para poder usar `--base`.

## 5. Fallo intermitente de `test_run.sh`

La prueba que falló es "huella con escrituras simultáneas: sin errores". Es una carrera real: `git add -A` falla con "unable to stat" en un 15-17 % de los intentos si un archivo se crea y borra sin parar, y con 5 reintentos quedaba ~1e-4 por cálculo (~0,2 % por ejecución del test).

| Medida | Antes | Después |
|---|---|---|
| Test completo, 280 ejecuciones | 0 fallos (no reproducido a ese nivel) | — |
| Componente en la condición del test | 1 de 12.800 llamadas | — |
| Componente en condición agravada | 16 de 300 | 0 de 300 |
| Test bajo carga | — | 0 de 80 |

Corrección: 12 intentos para errores de archivo desaparecido (los demás, 5). No se tocó ninguna aserción. Mitiga, no elimina. Riesgo latente no tocado: la prueba "cambio externo" depende de tiempos (`sleep 1` frente a `sleep 2`); no ha fallado.

## 6. Pruebas deterministas (estado final)

| Comando | Exit | Resultado |
|---|---|---|
| `bash tests/validate.sh` | 0 | 65 `ok:` |
| `bash tests/validate_selftest.sh` | 0 | 21 ok |
| `bash tests/run_core_tests.sh` | 0 | 492 ok, 0 fallos |
| `bash tests/run_hook_tests.sh` | 0 | 203 ok, 0 fallos |
| `bash tests/run_eval_tests.sh` | 0 | 402 ok, 0 fallos (`test_followup` 99) |
| `bash tests/run_setup_tests.sh` | 0 | 99 ok, 0 fallos |
| `claude plugin validate --strict .` | 0 | Validation passed |

ShellCheck no está instalado localmente; lo ejecuta la CI.

## 7. Pendiente

- CI sobre estos commits (requiere push autorizado).
- Sesión con modelo: la skill generando el esquema 2 y el uso de `classify`/revisión acotada en una sesión real.
- `classify` sigue siendo heurístico: herramientas desconocidas dan `unknown`; `mocha -u` (`--ui`) sale `writes-source` (falso positivo documentado en la skill).
