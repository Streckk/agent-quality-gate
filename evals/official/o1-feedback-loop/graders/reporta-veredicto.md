---
# Entrega un veredicto explícito y verificable (ambos brazos; la instrucción es la misma).
type: regex
target: last_message
flags: i
arm: both
---
Veredicto:\W*(PASS WITH LIMITATIONS|PASS|FAIL|BLOCKED|NOT VERIFIED)
