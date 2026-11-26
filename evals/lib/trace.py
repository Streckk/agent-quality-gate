"""Extrae hechos verificables de una traza `claude -p --output-format stream-json --verbose`.

Uso: python3 -I trace.py <traza.jsonl> <directorio-de-salida>
Escribe en el directorio:
  facts.kv       session_id, has_result, result_subtype, is_error, api_error, model, cost_usd, duration_ms, num_turns
  commands.txt   un comando Bash ejecutado por línea (saltos de línea internos → " ⏎ ")
  commands_status.txt  alineado con commands.txt: ok (tool_result sin error), error o unknown
  skills.txt     una skill invocada por línea
  tools.txt      todas las herramientas usadas, en orden: "<herramienta>|<detalle>" (Bash → comando,
                 Edit/MultiEdit/Write/NotebookEdit → ruta editada, Skill → nombre; vacío en las demás)
  final.txt      el mensaje final (texto del evento result o, si falta, el último mensaje del asistente)
Solo biblioteca estándar. No ejecuta nada de la traza. Sale con 2 si la traza no existe o está vacía.
"""
import json
import os
import sys

EDIT_TOOLS = ("Edit", "MultiEdit", "Write", "NotebookEdit")


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 64
    path, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    facts = {"session_id": "", "has_result": "0", "result_subtype": "", "is_error": "0",
             "api_error": "0", "model": "", "cost_usd": "", "duration_ms": "", "num_turns": "", "parse_errors": "0"}
    commands, skills, tools, last_text = [], [], [], ""
    bash_ids, results = [], {}
    final = None
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        open(os.path.join(out, "facts.kv"), "w").write("missing_trace=1\n")
        return 2
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                facts["parse_errors"] = str(int(facts["parse_errors"]) + 1)
                continue
            if not isinstance(ev, dict):
                continue
            if ev.get("session_id") and not facts["session_id"]:
                facts["session_id"] = str(ev["session_id"])
            t = ev.get("type")
            if t == "system" and ev.get("subtype") == "init" and ev.get("model") and not facts["model"]:
                facts["model"] = str(ev["model"])
            if t == "assistant":
                mdl = (ev.get("message") or {}).get("model")
                if mdl and not facts["model"]:
                    facts["model"] = str(mdl)
                for c in (ev.get("message") or {}).get("content") or []:
                    if not isinstance(c, dict):
                        continue
                    if c.get("type") == "tool_use":
                        inp = c.get("input") or {}
                        if not isinstance(inp, dict):
                            inp = {}
                        name = str(c.get("name", ""))
                        if name == "Bash":
                            det = inp.get("command")
                        elif name in EDIT_TOOLS:
                            det = inp.get("file_path") or inp.get("notebook_path")
                        elif name == "Skill":
                            det = inp.get("skill")
                        else:
                            det = ""
                        tools.append((name, det if isinstance(det, str) else ""))
                        if c.get("name") == "Bash" and isinstance(inp.get("command"), str):
                            commands.append(inp["command"])
                            bash_ids.append(str(c.get("id", "")))
                        elif c.get("name") == "Skill":
                            skills.append(str(inp.get("skill", "")))
                    elif c.get("type") == "text" and isinstance(c.get("text"), str):
                        last_text = c["text"]
                if ev.get("error"):
                    facts["api_error"] = "1"
            elif t == "user":
                content = (ev.get("message") or {}).get("content")
                for c in content if isinstance(content, list) else []:
                    if isinstance(c, dict) and c.get("type") == "tool_result" and c.get("tool_use_id"):
                        results[str(c["tool_use_id"])] = "error" if c.get("is_error") else "ok"
            elif t == "result":
                final = ev
    if final is not None:
        facts["has_result"] = "1"
        facts["result_subtype"] = str(final.get("subtype", ""))
        facts["is_error"] = "1" if final.get("is_error") else "0"
        facts["cost_usd"] = str(final.get("total_cost_usd", ""))
        facts["duration_ms"] = str(final.get("duration_ms", ""))
        facts["num_turns"] = str(final.get("num_turns", ""))
        text = final.get("result") if isinstance(final.get("result"), str) else last_text
    else:
        text = last_text
    clean = lambda v: str(v).replace("\n", " ").replace("\r", " ")
    with open(os.path.join(out, "facts.kv"), "w", encoding="utf-8") as fh:
        for k, v in facts.items():
            fh.write(f"{k}={clean(v)}\n")
    with open(os.path.join(out, "commands.txt"), "w", encoding="utf-8") as fh:
        for c in commands:
            fh.write(c.replace("\r", "").replace("\n", " ⏎ ") + "\n")
    with open(os.path.join(out, "commands_status.txt"), "w", encoding="utf-8") as fh:
        for i in bash_ids:
            fh.write(results.get(i, "unknown") + "\n")
    with open(os.path.join(out, "skills.txt"), "w", encoding="utf-8") as fh:
        for s in skills:
            fh.write(clean(s) + "\n")
    with open(os.path.join(out, "tools.txt"), "w", encoding="utf-8") as fh:
        for n, d in tools:
            fh.write(clean(n).replace("|", "/") + "|" + d.replace("\r", "").replace("\n", " ⏎ ") + "\n")
    with open(os.path.join(out, "final.txt"), "w", encoding="utf-8") as fh:
        fh.write(text or "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
