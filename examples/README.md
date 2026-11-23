# Ejemplos

> **Solo ejemplos.** Nada de esta carpeta es una dependencia de la skill. La skill funciona sin `.agent/verification.yaml`; estos archivos muestran cómo un proyecto *puede* declarar sus verificaciones si quiere hacerlas explícitas.

| Carpeta | Stack | Qué muestra |
|---|---|---|
| [nodejs](nodejs/) | Node.js (pnpm / Nx opcional) | checks obligatorios y opcionales, rutas de alto riesgo, comandos prohibidos |
| [python](python/) | Python (ruff + mypy + pytest) | checks mínimos y umbral de revisión |

Para usarlos, copia el archivo a `.agent/verification.yaml` en la raíz de tu proyecto y **ajusta los comandos a los que realmente existan** en él.
