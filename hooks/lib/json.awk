# Parser JSON mínimo y estricto (descenso recursivo) para los hooks de agent-quality-gate.
# Compatible con awk POSIX (gawk, BWK awk de macOS, mawk). Ejecutar con LC_ALL=C (bytes).
#
# Uso:  LC_ALL=C awk -v outdir=DIR -v want="a,b.c" -f json.awk < entrada.json
#   - Valida que la entrada sea UN objeto JSON completo (nada después, profundidad <= 64, <= 4 MiB).
#   - Para cada ruta pedida (claves separadas por ".") que exista, escribe:
#       DIR/<ruta con [^A-Za-z0-9_] → _>       el valor (cadenas decodificadas; resto, el literal)
#       DIR/<…>.type                            string | number | true | false | null | object | array
#   - Cadenas: decodifica \" \\ \/ \b \f \n \r \t y \uXXXX (pares sustitutos → UTF-8). Rechaza \u0000
#     y caracteres de control sin escapar.
#   - Código de salida: 0 válido; 2 inválido (motivo en stderr). Nunca ejecuta nada de la entrada.

function fail(msg) { printf "json: %s (posición %d)\n", msg, P > "/dev/stderr"; FAILED = 1; exit 2 }
function ch() { return substr(S, P, 1) }
function skipws(   c) {
  while (P <= L) { c = substr(S, P, 1); if (c == " " || c == "\t" || c == "\n" || c == "\r") P++; else break }
}
function store(path, type, val) {
  if (path in WANT) { TYPE[path] = type; VAL[path] = val; FOUND[path] = 1 }
}
function hexval(h,   i, c, v, d) {
  v = 0
  for (i = 1; i <= 4; i++) {
    c = tolower(substr(h, i, 1)); d = index("0123456789abcdef", c)
    if (d == 0) fail("escape \\u inválido")
    v = v * 16 + (d - 1)
  }
  return v
}
function utf8(cp) {
  if (cp < 128) return sprintf("%c", cp)
  if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
  if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
  return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
}
# Lee una cadena empezando en P (que apunta a la comilla). Si collect=1 devuelve el valor decodificado.
function pstring(collect,   out, start, c, e, cp, lo) {
  P++; out = ""; start = P
  while (1) {
    if (P > L) fail("cadena sin terminar")
    c = substr(S, P, 1)
    if (c == "\"") { if (collect) out = out substr(S, start, P - start); P++; return out }
    if (c < " ") fail("carácter de control sin escapar en una cadena")
    if (c != "\\") { P++; continue }
    if (collect) out = out substr(S, start, P - start)
    e = substr(S, P + 1, 1)
    if (e == "u") {
      cp = hexval(substr(S, P + 2, 4)); P += 6
      if (cp >= 55296 && cp <= 56319) {                       # sustituto alto: requiere el bajo
        if (substr(S, P, 2) == "\\u") {
          lo = hexval(substr(S, P + 2, 4))
          if (lo >= 56320 && lo <= 57343) { cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); P += 6 }
          else cp = 65533
        } else cp = 65533
      } else if (cp >= 56320 && cp <= 57343) cp = 65533      # sustituto bajo aislado
      if (cp == 0) fail("\\u0000 no admitido")
      if (collect) out = out utf8(cp)
    } else {
      if      (e == "\"") c = "\""
      else if (e == "\\") c = "\\"
      else if (e == "/")  c = "/"
      else if (e == "b")  c = "\b"
      else if (e == "f")  c = "\f"
      else if (e == "n")  c = "\n"
      else if (e == "r")  c = "\r"
      else if (e == "t")  c = "\t"
      else fail("escape inválido")
      if (collect) out = out c
      P += 2
    }
    start = P
  }
}
function pnumber(path,   start, tok) {
  start = P
  while (P <= L && index("+-0123456789.eE", substr(S, P, 1)) > 0) P++
  tok = substr(S, start, P - start)
  if (tok !~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/) fail("número inválido")
  store(path, "number", tok)
}
function pliteral(path, word) {
  if (substr(S, P, length(word)) != word) fail("literal inválido")
  P += length(word); store(path, word, word)
}
function pvalue(path,   c) {
  skipws(); c = ch()
  if (c == "{") pobject(path)
  else if (c == "[") parray(path)
  else if (c == "\"") store(path, "string", pstring(path in WANT))
  else if (c == "t") pliteral(path, "true")
  else if (c == "f") pliteral(path, "false")
  else if (c == "n") pliteral(path, "null")
  else if (c == "-" || (c >= "0" && c <= "9")) pnumber(path)
  else fail("valor inesperado")
}
function pobject(path,   key, child) {
  if (++DEPTH > 64) fail("anidamiento excesivo")
  store(path, "object", ""); P++; skipws()
  if (ch() == "}") { P++; DEPTH--; return }
  while (1) {
    skipws(); if (ch() != "\"") fail("se esperaba una clave")
    key = pstring(1); skipws()
    if (ch() != ":") fail("se esperaba ':'")
    P++
    child = (path == "") ? key : path "." key
    pvalue(child); skipws()
    if (ch() == ",") { P++; continue }
    if (ch() == "}") { P++; break }
    fail("se esperaba ',' o '}'")
  }
  DEPTH--
}
function parray(path) {
  if (++DEPTH > 64) fail("anidamiento excesivo")
  store(path, "array", ""); P++; skipws()
  if (ch() == "]") { P++; DEPTH--; return }
  while (1) {
    pvalue(path "[]"); skipws()
    if (ch() == ",") { P++; continue }
    if (ch() == "]") { P++; break }
    fail("se esperaba ',' o ']'")
  }
  DEPTH--
}
{ S = (NR == 1) ? $0 : S "\n" $0; if (length(S) > 4194304) { P = 0; fail("entrada demasiado grande") } }
END {
  if (FAILED) exit 2
  n = split(want, W, ",")
  for (i = 1; i <= n; i++) if (W[i] != "") WANT[W[i]] = 1
  L = length(S); P = 1; DEPTH = 0
  skipws()
  if (ch() != "{") fail("la entrada no es un objeto JSON")
  pobject("")
  skipws()
  if (P <= L) fail("datos después del objeto")
  for (k in FOUND) {
    f = k; gsub(/[^A-Za-z0-9_]/, "_", f); f = outdir "/" f
    printf "%s", VAL[k] > f; close(f)
    print TYPE[k] > (f ".type"); close(f ".type")
  }
  exit 0
}
