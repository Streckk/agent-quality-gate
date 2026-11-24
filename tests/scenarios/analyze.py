"""Resume una traza stream-json de `claude -p`: skill cargada, herramientas usadas, comandos Bash con
resultado, ediciones y el reporte final. Uso: python3 -I analyze.py <log.jsonl> [--full]"""
import json, sys

path = sys.argv[1]
full = "--full" in sys.argv
calls, results, final = {}, {}, None
order = []
for line in open(path, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    if ev.get("type") == "assistant":
        for c in ev["message"].get("content", []):
            if c.get("type") == "tool_use":
                calls[c["id"]] = (c["name"], c.get("input", {}))
                order.append(c["id"])
    elif ev.get("type") == "user":
        content = ev.get("message", {}).get("content", [])
        if isinstance(content, list):
            for c in content:
                if c.get("type") == "tool_result":
                    txt = c.get("content")
                    if isinstance(txt, list):
                        txt = "\n".join(x.get("text", "") for x in txt if isinstance(x, dict))
                    results[c["tool_use_id"]] = (bool(c.get("is_error")), str(txt or ""))
    elif ev.get("type") == "result":
        final = ev

for i, cid in enumerate(order, 1):
    name, inp = calls[cid]
    err, out = results.get(cid, (None, "<sin resultado>"))
    if name == "Bash":
        desc = " ⏎ ".join(inp.get("command", "").splitlines())   # comandos multilínea completos
    elif name in ("Edit", "Write", "Read"):
        desc = inp.get("file_path", "")
    elif name == "Skill":
        desc = f"{inp.get('skill')} {inp.get('args', '')}"
    else:
        desc = json.dumps(inp, ensure_ascii=False)[:160]
    flag = "ERR" if err else "ok "
    print(f"[{i:02}] {flag} {name}: {desc if name == 'Bash' else desc[:300]}")
    if name == "Bash" or full or err:
        tail = out.strip().splitlines()[-4:]
        for t in tail:
            print(f"        | {t[:200]}")

# Invocaciones de qg y run-ids, para contrastar el reporte con `qg status --run-id <id> --json`.
import re
qg_calls = [calls[c][1].get("command", "") for c in order if calls[c][0] == "Bash"]
qg_calls = [c for c in qg_calls if re.search(r"(^|[/\s\"'])qg(-run)?(\s|\"|$)|\$\{?Q[A-Z_]*\b", c)]
subs = {}
for c in qg_calls:
    for m in re.finditer(r"(?:qg|\$\{?Q[A-Z_]*\}?)\"?\s+(?:-C\s+\S+\s+)?(fingerprint|run|require|status|reject|version|show|gc)\b", c):
        subs[m.group(1)] = subs.get(m.group(1), 0) + 1
all_bash = " ".join(calls[c][1].get("command", "") for c in order if calls[c][0] == "Bash")
run_ids = sorted(set(re.findall(r"\bqg-\d{8}T\d{6}Z-\d+\b", all_bash)))
print("\n=== QG ===")
print(f"comandos Bash con qg: {len(qg_calls)}  subcomandos: {subs}")
print(f"run-ids: {run_ids}")

if final:
    print("\n=== RESULT ===")
    print(f"subtype={final.get('subtype')} turns={final.get('num_turns')} cost_usd={final.get('total_cost_usd')} denials={len(final.get('permission_denials', []))}")
    for d in final.get("permission_denials", []):
        print("  DENEGADO:", d.get("tool_name"), json.dumps(d.get("tool_input", {}), ensure_ascii=False)[:200])
    print(final.get("result", ""))
