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
        desc = inp.get("command", "")
    elif name in ("Edit", "Write", "Read"):
        desc = inp.get("file_path", "")
    elif name == "Skill":
        desc = f"{inp.get('skill')} {inp.get('args', '')}"
    else:
        desc = json.dumps(inp, ensure_ascii=False)[:160]
    flag = "ERR" if err else "ok "
    print(f"[{i:02}] {flag} {name}: {desc[:300]}")
    if name == "Bash" or full or err:
        tail = out.strip().splitlines()[-4:]
        for t in tail:
            print(f"        | {t[:200]}")

if final:
    print("\n=== RESULT ===")
    print(f"subtype={final.get('subtype')} turns={final.get('num_turns')} cost_usd={final.get('total_cost_usd')} denials={len(final.get('permission_denials', []))}")
    for d in final.get("permission_denials", []):
        print("  DENEGADO:", d.get("tool_name"), json.dumps(d.get("tool_input", {}), ensure_ascii=False)[:200])
    print(final.get("result", ""))
