---
# El defecto se corrigió en el código (ambos brazos).
type: regex
target: { source: file, path: src/sum.js }
match: contains
arm: both
---
return a \+ b
