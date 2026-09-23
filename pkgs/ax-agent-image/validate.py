#!/usr/bin/env python3
"""Minimal JSON Schema subset check (type, required, properties, enum, items,
additionalProperties:false) for the probe. Reads schema from $1 (JSON text) and
candidate text from stdin; extracts the first JSON object; prints a verdict JSON."""
import json, sys, re
schema = json.loads(sys.argv[1])
raw = sys.stdin.read()
T = {"object": dict, "array": list, "string": str, "integer": int, "number": (int, float), "boolean": bool, "null": type(None)}
def check(s, v, p="$"):
    errs = []
    t = s.get("type")
    if t and not isinstance(v, T[t]) or (t == "integer" and isinstance(v, bool)):
        return [f"{p}: expected {t}"]
    if "enum" in s and v not in s["enum"]:
        errs.append(f"{p}: not in enum")
    if isinstance(v, dict):
        for r in s.get("required", []):
            if r not in v: errs.append(f"{p}.{r}: missing")
        props = s.get("properties", {})
        for k, sub in props.items():
            if k in v: errs += check(sub, v[k], f"{p}.{k}")
        if s.get("additionalProperties") is False:
            errs += [f"{p}.{k}: extra" for k in v if k not in props]
    if isinstance(v, list) and "items" in s:
        for i, x in enumerate(v): errs += check(s["items"], x, f"{p}[{i}]")
    return errs
m = re.search(r"\{.*\}", raw, re.S)
if not m:
    print(json.dumps({"valid": False, "errors": ["no JSON object in output"], "value": None})); sys.exit(3)
try:
    val = json.loads(m.group(0))
except Exception as e:
    print(json.dumps({"valid": False, "errors": [f"parse: {e}"], "value": None})); sys.exit(3)
errs = check(schema, val)
print(json.dumps({"valid": not errs, "errors": errs, "value": val}))
sys.exit(0 if not errs else 4)
