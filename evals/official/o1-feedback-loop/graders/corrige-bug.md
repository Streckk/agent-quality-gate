---
type: regex
target: { source: file, path: src/sum.js }
pattern: "return a \\+ b"
arm: both
---
El defecto se corrigió en el código, no en las pruebas.
