"""Extrae y valida el bloque estructurado del reporte de /quality-gate (esquemas 1 y 2).

Uso: python3 -I report.py <final.txt> <salida.kv>

El bloque es un fence ```json cuyo objeto lleva "kind": "quality-gate-report". Si hay varios, se
usa el último y se anota cuántos había. Este script NO decide si el reporte es verdadero: solo
comprueba la forma. evaluate.sh contrasta las afirmaciones con qg, los registros y la traza.

Esquema 1: un repositorio, objeto "evidence" en la raíz. Esquema 2 (obligatorio con varios
repositorios): sin "evidence" en la raíz; "repos" = [{"id", "evidence"}] (1-16, ids únicos, el id es
una etiqueta y no una ruta) y "approvals" = {"pending_required", "pending_optional"} obligatorio.
Ambos admiten "review.followup" (done|pending|not_required) y "review.critical_fixed" (booleano: se
corrigió un hallazgo confirmado de categoría crítica); el esquema 1 admite "approvals" opcional.
En el esquema 2 ningún texto del bloque puede contener una ruta absoluta.

Salida (clave=valor):
  block=absent|present   blocks=<n>   valid=1|0   error=<motivo>   schema=1|2
  verdict, risk, review_status, review_kind, review_reason, review_followup,
  review_critical_fixed (true|false, vacío si no se declara),
  approvals_pending_required, approvals_pending_optional (vacíos si no se declaran)
  repos=<n> y, por repo (i desde 1), repo.<i>.id (vacío en el esquema 1) y
  repo.<i>.evidence_provider|evidence_run_id|evidence_status|evidence_fingerprint|evidence_reason
  evidence_* = los del único repo (esquema 1, o esquema 2 con un solo repo); vacíos si hay varios.
Códigos de salida: 0 = analizado (aunque el bloque sea inválido); 64 = uso; 70 = error interno.
Solo biblioteca estándar. No ejecuta nada del reporte.
"""
import json
import re
import sys

KIND = "quality-gate-report"
SUPPORTED_SCHEMAS = (1, 2)
VERDICTS = ("PASS", "PASS WITH LIMITATIONS", "FAIL", "BLOCKED", "NOT VERIFIED")
RISKS = ("low", "medium", "high")
QG_STATUSES = ("valid", "failed", "blocked", "incomplete", "stale", "missing")
REVIEW_STATUSES = ("done", "skipped", "not_required")
REVIEW_KINDS = ("review", "adversarial")
FOLLOWUPS = ("done", "pending", "not_required")
REPO_ID = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")
MAX_REPOS = 16
# Ruta absoluta dentro de un texto: /a/b (dos segmentos o más), ~/… o C:\…
ABS_PATH = re.compile(r"(^|[\s\"'(=:,;])(/[^\s/]+/[^\s]|~/|[A-Za-z]:[\\/])")
EV_KEYS = ("provider", "run_id", "status", "fingerprint", "reason")
RUN_ID = re.compile(r"^(cc|qg)-[A-Za-z0-9][A-Za-z0-9-]{5,120}$")
FINGERPRINT = re.compile(r"^sha(1|256):[0-9a-f]{40,64}$")
MAX_TEXT = 200
FENCE = re.compile(r"```json[^\n]*\n(.*?)\n```", re.S)


class Invalid(Exception):
    pass


def text(obj, key, required, maxlen=MAX_TEXT):
    if key not in obj:
        if required:
            raise Invalid(f"falta el campo {key}")
        return ""
    v = obj[key]
    if not isinstance(v, str) or not v.strip():
        raise Invalid(f"{key} debe ser un texto no vacío")
    if len(v) > maxlen or "\n" in v:
        raise Invalid(f"{key} demasiado largo o con saltos de línea")
    return v


def enum(obj, key, allowed, required=True):
    v = text(obj, key, required)
    if v and v not in allowed:
        raise Invalid(f"{key} desconocido: {v}")
    return v


def evidence(ev, where):
    if not isinstance(ev, dict):
        raise Invalid(f"falta el objeto {where}")
    out = {k: "" for k in EV_KEYS}
    prov = enum(ev, "provider", ("qg", "none"))
    out["provider"] = prov
    if prov == "qg":
        rid = text(ev, "run_id", True)
        if not RUN_ID.match(rid):
            raise Invalid(f"{where}.run_id con formato inválido")
        out["run_id"] = rid
        out["status"] = enum(ev, "status", QG_STATUSES)
        fp = text(ev, "fingerprint", False)
        if fp and not FINGERPRINT.match(fp):
            raise Invalid(f"{where}.fingerprint con formato inválido")
        out["fingerprint"] = fp
    else:
        out["reason"] = text(ev, "reason", True)
        for k in ("run_id", "status", "fingerprint"):
            if k in ev:
                raise Invalid(f"{where}.{k} no admitido con provider=none")
    return out


def count(obj, key):
    v = obj.get(key)
    if isinstance(v, bool) or not isinstance(v, int) or v < 0:
        raise Invalid(f"approvals.{key} debe ser un entero ≥ 0")
    return str(v)


def strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for k, v in node.items():
            yield k
            yield from strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from strings(v)


def validate(doc):
    out = {}
    if not isinstance(doc, dict):
        raise Invalid("el bloque no es un objeto JSON")
    schema = doc.get("schema")
    if isinstance(schema, bool) or not isinstance(schema, int):
        raise Invalid("schema ausente o no entero")
    if schema not in SUPPORTED_SCHEMAS:
        raise Invalid(f"schema no soportado: {schema}")
    out["schema"] = str(schema)
    out["verdict"] = enum(doc, "verdict", VERDICTS)
    out["risk"] = enum(doc, "risk", RISKS)
    repos = []
    if schema == 1:
        if "repos" in doc:
            raise Invalid("repos solo se admite en el esquema 2")
        repos.append(("", evidence(doc.get("evidence"), "evidence")))
    else:
        if "evidence" in doc:
            raise Invalid("evidence en la raíz no se admite en el esquema 2 (va en repos[].evidence)")
        rl = doc.get("repos")
        if not isinstance(rl, list) or not 1 <= len(rl) <= MAX_REPOS:
            raise Invalid(f"repos debe ser una lista de 1 a {MAX_REPOS} repositorios")
        seen = set()
        for i, r in enumerate(rl):
            if not isinstance(r, dict):
                raise Invalid(f"repos[{i}] no es un objeto")
            rid = r.get("id")
            if not isinstance(rid, str) or not REPO_ID.match(rid):
                raise Invalid(f"repos[{i}].id inválido (una etiqueta corta, no una ruta)")
            if rid in seen:
                raise Invalid(f"repos: id duplicado {rid}")
            seen.add(rid)
            repos.append((rid, evidence(r.get("evidence"), f"repos[{i}].evidence")))
        for t in strings(doc):
            if ABS_PATH.search(t):
                raise Invalid("ruta absoluta en el bloque de esquema 2 (los repositorios se identifican por id)")
    out["repos"] = str(len(repos))
    for i, (rid, ev) in enumerate(repos, 1):
        out[f"repo.{i}.id"] = rid
        for k in EV_KEYS:
            out[f"repo.{i}.evidence_{k}"] = ev[k]
    for k in EV_KEYS:
        out[f"evidence_{k}"] = repos[0][1][k] if len(repos) == 1 else ""
    ap = doc.get("approvals")
    out["approvals_pending_required"] = out["approvals_pending_optional"] = ""
    if ap is not None or schema == 2:
        if not isinstance(ap, dict):
            raise Invalid("falta el objeto approvals (pending_required, pending_optional)")
        out["approvals_pending_required"] = count(ap, "pending_required")
        out["approvals_pending_optional"] = count(ap, "pending_optional")
    rv = doc.get("review")
    if not isinstance(rv, dict):
        raise Invalid("falta el objeto review")
    st = enum(rv, "status", REVIEW_STATUSES)
    out["review_status"] = st
    out["review_kind"] = enum(rv, "kind", REVIEW_KINDS, required=(st == "done"))
    out["review_reason"] = text(rv, "reason", st == "skipped")
    out["review_followup"] = enum(rv, "followup", FOLLOWUPS, required=False)
    cf = rv.get("critical_fixed")
    if cf is not None and not isinstance(cf, bool):
        raise Invalid("review.critical_fixed debe ser booleano")
    out["review_critical_fixed"] = "" if cf is None else ("true" if cf else "false")
    return out


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 64
    try:
        with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
            body = fh.read()
    except OSError:
        body = ""
    res = {"block": "absent", "blocks": "0", "valid": "", "error": ""}
    blocks = []
    for m in FENCE.finditer(body):
        raw = m.group(1)
        if '"kind"' in raw and KIND in raw:
            blocks.append(raw)
    if blocks:
        res["block"] = "present"
        res["blocks"] = str(len(blocks))
        try:
            try:
                doc = json.loads(blocks[-1])
            except ValueError as e:
                raise Invalid(f"JSON malformado ({e.msg})")
            if not isinstance(doc, dict) or doc.get("kind") != KIND:
                raise Invalid("kind distinto de quality-gate-report")
            res.update(validate(doc))
            res["valid"] = "1"
        except Invalid as e:
            res["valid"] = "0"
            res["error"] = str(e)
    with open(sys.argv[2], "w", encoding="utf-8") as fh:
        for k, v in res.items():
            fh.write(f"{k}={str(v).replace(chr(10), ' ')}\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # cualquier otro fallo es un error del evaluador, no del agente
        print(f"report.py: error interno: {e}", file=sys.stderr)
        sys.exit(70)
