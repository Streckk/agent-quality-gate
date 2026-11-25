"""Extrae y valida el bloque estructurado del reporte de /quality-gate (esquema 1).

Uso: python3 -I report.py <final.txt> <salida.kv>

El bloque es un fence ```json cuyo objeto lleva "kind": "quality-gate-report". Si hay varios, se
usa el último y se anota cuántos había. Este script NO decide si el reporte es verdadero: solo
comprueba la forma. evaluate.sh contrasta las afirmaciones con qg, los registros y la traza.

Salida (clave=valor):
  block=absent|present   blocks=<n>   valid=1|0   error=<motivo>
  verdict, risk, evidence_provider, evidence_run_id, evidence_status, evidence_fingerprint,
  evidence_reason, review_status, review_kind, review_reason
Códigos de salida: 0 = analizado (aunque el bloque sea inválido); 64 = uso; 70 = error interno.
Solo biblioteca estándar. No ejecuta nada del reporte.
"""
import json
import re
import sys

KIND = "quality-gate-report"
SUPPORTED_SCHEMAS = (1,)
VERDICTS = ("PASS", "PASS WITH LIMITATIONS", "FAIL", "BLOCKED", "NOT VERIFIED")
RISKS = ("low", "medium", "high")
QG_STATUSES = ("valid", "failed", "blocked", "incomplete", "stale", "missing")
REVIEW_STATUSES = ("done", "skipped", "not_required")
REVIEW_KINDS = ("review", "adversarial")
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


def validate(doc):
    out = {}
    if not isinstance(doc, dict):
        raise Invalid("el bloque no es un objeto JSON")
    schema = doc.get("schema")
    if isinstance(schema, bool) or not isinstance(schema, int):
        raise Invalid("schema ausente o no entero")
    if schema not in SUPPORTED_SCHEMAS:
        raise Invalid(f"schema no soportado: {schema}")
    out["verdict"] = enum(doc, "verdict", VERDICTS)
    out["risk"] = enum(doc, "risk", RISKS)
    ev = doc.get("evidence")
    if not isinstance(ev, dict):
        raise Invalid("falta el objeto evidence")
    prov = enum(ev, "provider", ("qg", "none"))
    out["evidence_provider"] = prov
    if prov == "qg":
        rid = text(ev, "run_id", True)
        if not RUN_ID.match(rid):
            raise Invalid("evidence.run_id con formato inválido")
        out["evidence_run_id"] = rid
        out["evidence_status"] = enum(ev, "status", QG_STATUSES)
        fp = text(ev, "fingerprint", False)
        if fp and not FINGERPRINT.match(fp):
            raise Invalid("evidence.fingerprint con formato inválido")
        out["evidence_fingerprint"] = fp
    else:
        out["evidence_reason"] = text(ev, "reason", True)
        for k in ("run_id", "status", "fingerprint"):
            if k in ev:
                raise Invalid(f"evidence.{k} no admitido con provider=none")
    rv = doc.get("review")
    if not isinstance(rv, dict):
        raise Invalid("falta el objeto review")
    st = enum(rv, "status", REVIEW_STATUSES)
    out["review_status"] = st
    out["review_kind"] = enum(rv, "kind", REVIEW_KINDS, required=(st == "done"))
    out["review_reason"] = text(rv, "reason", st == "skipped")
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
