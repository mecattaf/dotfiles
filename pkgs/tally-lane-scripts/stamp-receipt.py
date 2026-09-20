#!/usr/bin/env python3
"""stamp-receipt — measured identity for a factory receipt, from the harness's own records.

Sub-verbs (stdlib only):
  agent   --workflows DIR --marker TEXT   → JSON {agent_id, model, started_at, finished_at, seconds,
                                             tokens{in_uncached, cache_read, cache_write, out, reasoning, total}, messages, journal}
          Finds the workflow subagent whose first user message contains TEXT (the prompt marker
          "TALLY-UNIT <id> ROLE <role>"), under DIR (a session's subagents/workflows or one wf_* dir).
          Usage is summed per distinct message.id (streamed lines repeat usage), so nothing is double-counted.
  window  --seat cc|cc2|cc3                → JSON {seat, window_id, five_hour{utilization,resets_at}, seven_day{...}, observed_at}
          Reads the seat's OAuth credential file by path (authorised by the 2026-09-06 handoff; the value is never printed)
          and calls the same /api/oauth/usage endpoint Claude Code's /usage uses. A refused read is {grade: UNKNOWN, reason}.
  codex   --rollouts DIR --since ISO --until ISO → JSON tokens over the rollouts' last_token_usage events in the window.
  claude  --seat cc|cc2|cc3 --session ID [--run-json FILE] → JSON {seat, harness, session_id, model, started_at, finished_at,
          seconds, tokens{six cells}, context_window, context_window_source} from <seat home>/projects/**/<ID>.jsonl,
          usage summed per distinct message.id (the usage_of de-duplication). Exit 2 naming the id when no file matches.
  pi      --session ID [--sessions-dir ~/.pi/agent/sessions] [--models-json ~/.pi/agent/models.json] → the same cells
          from the pi session jsonl whose 'session' line carries ID (assistant usage: input→in_uncached, cacheRead,
          cacheWrite, output→out, reasoning, totalTokens→total), model/provider from model_change, context_window from
          models.json (exit 2 naming provider/model when absent), plus quota_error when an error line mentions
          quota/credit exhaustion.
  validate FILE [--schema build|replay|merge] → exit 0 when no required field is null/missing, else 1 naming each.

A null in a receipt is CRASH. This tool never writes a receipt; it prints what the receipt must carry.
"""
import argparse, glob, json, os, sys, urllib.request
from datetime import datetime, timezone

REQUIRED = {
    "build": ["id","kind","unit","repo","branch","commit_sha","seat","harness","model","thread_id","window_id",
              "started_at","finished_at","seconds","tokens","context_window","oracle_argv","oracle_rc",
              "mutation_hint","mutation_rc","evaluator","control_receipt_id","baseline","verdict","disposition",
              "receipt_path"],
    "merge": ["id","kind","unit","repo","branch","commit_sha","merge_commit","seat","harness","model","thread_id","window_id",
              "started_at","finished_at","seconds","tokens","context_window","oracle_argv","oracle_rc","evaluator",
              "control_receipt_id","baseline","verdict","disposition","receipt_path"],
    "replay": ["id","kind","unit","repo","branch","commit_sha","seat","harness","model","thread_id","window_id",
               "started_at","finished_at","seconds","tokens","context_window","oracle_argv","oracle_rc",
               "mutation","evaluator","control_receipt_id","baseline","verdict","disposition","receipt_path"],
}
TOKEN_CELLS = ["in_uncached","cache_read","cache_write","out","reasoning","total"]

def iso(ts): return ts

def find_agent(workflows_dir, marker):
    files = sorted(glob.glob(os.path.join(workflows_dir, "**", "agent-*.jsonl"), recursive=True), key=os.path.getmtime)
    hits = []
    for f in files:
        try:
            with open(f, encoding="utf-8") as fh:
                for line in fh:
                    o = json.loads(line)
                    if o.get("type") == "user":
                        c = o.get("message", {}).get("content")
                        text = c if isinstance(c, str) else json.dumps(c)
                        if marker in text: hits.append(f)
                        break
        except Exception:
            continue
    return hits


def usage_of(f):
    ids, first, last, model = {}, None, None, None
    with open(f, encoding="utf-8") as fh:
        for line in fh:
            try: o = json.loads(line)
            except Exception: continue
            ts = o.get("timestamp")
            if ts:
                first = first or ts; last = ts
            if o.get("type") == "assistant":
                m = o.get("message", {})
                if m.get("usage"): ids[m.get("id")] = m["usage"]; model = m.get("model") or model
    t = {k: 0 for k in TOKEN_CELLS}
    for u in ids.values():
        t["in_uncached"] += int(u.get("input_tokens", 0) or 0)
        t["cache_read"] += int(u.get("cache_read_input_tokens", 0) or 0)
        t["cache_write"] += int(u.get("cache_creation_input_tokens", 0) or 0)
        t["out"] += int(u.get("output_tokens", 0) or 0)
        t["reasoning"] += int(((u.get("output_tokens_details") or {}).get("thinking_tokens", 0)) or 0)
    t["total"] = t["in_uncached"] + t["cache_read"] + t["cache_write"] + t["out"]
    secs = None
    if first and last:
        a = datetime.fromisoformat(first.replace("Z", "+00:00")); b = datetime.fromisoformat(last.replace("Z", "+00:00"))
        secs = int((b - a).total_seconds())
    aid = os.path.basename(f)[len("agent-"):-len(".jsonl")]
    return {"agent_id": aid, "model": model, "started_at": first, "finished_at": last, "seconds": secs,
            "tokens": t, "messages": len(ids), "journal": f}

def cmd_agent(a):
    hits = find_agent(a.workflows, a.marker)
    if not hits:
        print(json.dumps({"error": "no agent journal carries the marker", "marker": a.marker})); sys.exit(1)
    print(json.dumps(usage_of(hits[-1]) if a.last else [usage_of(h) for h in hits]))

def cmd_window(a):
    home = {"cc": "~/.claude", "cc2": "~/.claude-work", "cc3": "~/.claude-3"}[a.seat]
    creds = os.path.expanduser(home + "/.credentials.json")
    now = datetime.now(timezone.utc).isoformat()
    try:
        with open(creds, encoding="utf-8") as fh:
            oauth = (json.load(fh) or {}).get("claudeAiOauth") or {}
        tok = oauth.get("accessToken")
        exp = oauth.get("expiresAt") or 0
        if not tok: raise RuntimeError("no access token in credential file")
        if exp and exp / 1000 < datetime.now(timezone.utc).timestamp(): raise RuntimeError("token expired; run `claude` on that seat to refresh")
        import time, random
        cache = os.path.expanduser(f"~/.local/state/tally-rewrite/meters/.window-cache-{a.seat}.json")
        u = None
        # D-B92: a reading under 45 s old is served from the cache before the API is called — the usage API
        # answers in whole percents and rate-limits (HTTP 429, six backoff retries ~60 s), and the pump reads
        # each seat several times per tick; re-measuring at 45 s resolution still satisfies D-B60.
        try:
            c = json.load(open(cache)); age = (datetime.now(timezone.utc) - datetime.fromisoformat(c["observed_at"])).total_seconds()
            if age < 45 and c.get("usage"):
                u = c["usage"]; out = {"seat": a.seat, "grade": "MEASURED", "observed_at": c["observed_at"], "from_cache_seconds": int(age)}
                for k in ("five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"):
                    v = u.get(k) or {}; out[k] = {"utilization": v.get("utilization"), "resets_at": v.get("resets_at")}
                out["window_id"] = (u.get("five_hour") or {}).get("resets_at") or "unknown"; print(json.dumps(out)); return
        except Exception:
            pass
        for attempt in range(6):
            try:
                req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers={
                    "Authorization": "Bearer " + tok, "Content-Type": "application/json", "anthropic-beta": "oauth-2025-04-20"})
                with urllib.request.urlopen(req, timeout=10) as resp: u = json.load(resp)
                break
            except urllib.error.HTTPError as e:
                if e.code != 429 or attempt == 5: raise
                time.sleep(2 ** attempt + random.random())
        try:
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            with open(cache, "w") as fh: json.dump({"observed_at": now, "usage": u}, fh)
        except Exception: pass
        out = {"seat": a.seat, "grade": "MEASURED", "observed_at": now}
        for k in ("five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"):
            v = u.get(k) or {}
            out[k] = {"utilization": v.get("utilization"), "resets_at": v.get("resets_at")}
        out["window_id"] = (u.get("five_hour") or {}).get("resets_at") or "unknown"
        print(json.dumps(out))
    except Exception as e:
        try:
            cache = os.path.expanduser(f"~/.local/state/tally-rewrite/meters/.window-cache-{a.seat}.json")
            c = json.load(open(cache)); age = (datetime.now(timezone.utc) - datetime.fromisoformat(c["observed_at"])).total_seconds()
            if age < 900 and c.get("usage"):  # D-B81: a 429 with a reading under 15 min old is MEASURED-cached, not UNKNOWN
                u = c["usage"]; out = {"seat": a.seat, "grade": "MEASURED", "observed_at": c["observed_at"], "from_cache_seconds": int(age)}
                for k in ("five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"):
                    v = u.get(k) or {}; out[k] = {"utilization": v.get("utilization"), "resets_at": v.get("resets_at")}
                out["window_id"] = (u.get("five_hour") or {}).get("resets_at") or "unknown"
                print(json.dumps(out)); return
        except Exception: pass
        print(json.dumps({"seat": a.seat, "grade": "UNKNOWN", "reason": f"{type(e).__name__}: {str(e)[:160]}", "observed_at": now, "window_id": "unknown"})); sys.exit(2)

def cmd_codex(a):
    t = {k: 0 for k in TOKEN_CELLS}; n = 0; model = None; opened = []; ctx = None; cwds = set()
    files = sorted(glob.glob(os.path.join(a.rollouts, "**", "rollout-*.jsonl"), recursive=True))
    if a.thread:
        files = [f for f in files if a.thread in os.path.basename(f)]
        if not files:
            print(json.dumps({"error": "no rollout carries that thread id", "thread": a.thread})); sys.exit(1)
    for f in files:
        opened.append(f)
        with open(f, encoding="utf-8") as fh:
            for line in fh:
                try: o = json.loads(line)
                except Exception: continue
                ts = o.get("timestamp") or ""
                if ts < a.since or ts > a.until: continue
                p = o.get("payload") or {}
                if o.get("type") == "event_msg" and p.get("type") == "token_count":
                    lu = ((p.get("info") or {}).get("last_token_usage")) or {}
                    inp = int(lu.get("input_tokens", 0) or 0); cached = int(lu.get("cached_input_tokens", 0) or 0)
                    t["in_uncached"] += inp - cached; t["cache_read"] += cached
                    t["cache_write"] += int(lu.get("cache_write_input_tokens", 0) or 0)
                    t["out"] += int(lu.get("output_tokens", 0) or 0); t["reasoning"] += int(lu.get("reasoning_output_tokens", 0) or 0)
                    n += 1
                if '"model"' in line and not model:
                    m = p.get("model") or ((p.get("state") or {}).get("collaboration_mode") or {}).get("model")
                    model = m or model
                if o.get("type") == "session_meta":
                    cwds.add(p.get("cwd"))
                if ctx is None:
                    c = p.get("model_context_window") or ((p.get("info") or {}).get("model_context_window"))
                    if c: ctx = c
    t["total"] = t["in_uncached"] + t["cache_read"] + t["cache_write"] + t["out"]
    print(json.dumps({"tokens": t, "events": n, "model": model, "context_window": ctx,
                      "thread": a.thread, "cwds": sorted(x for x in cwds if x),
                      "rollouts_matched": len(files), "paths_opened": opened}))

def cmd_claude(a):
    """A headless Claude Code session's cells, from the seat's own projects/**/<id>.jsonl journal.
    Usage is summed per distinct message.id exactly as usage_of does for workflow subagents."""
    home = {"cc": "~/.claude", "cc2": "~/.claude-work", "cc3": "~/.claude-3"}[a.seat]
    root = os.path.expanduser(home + "/projects")
    files = glob.glob(os.path.join(root, "**", a.session + ".jsonl"), recursive=True)
    if not files:
        print(json.dumps({"error": "no session file for that id on that seat", "seat": a.seat, "session": a.session,
                          "searched": os.path.join(root, "**", a.session + ".jsonl")})); sys.exit(2)
    f = sorted(files, key=os.path.getmtime)[-1]
    u = usage_of(f)
    cwds = set()
    with open(f, encoding="utf-8") as fh:
        for line in fh:
            try: o = json.loads(line)
            except Exception: continue
            if o.get("cwd"): cwds.add(o["cwd"])
    out = {"seat": a.seat, "harness": "claude-code-headless", "session_id": a.session, "model": u["model"],
           "started_at": u["started_at"], "finished_at": u["finished_at"], "seconds": u["seconds"],
           "tokens": u["tokens"], "messages": u["messages"], "cwds": sorted(cwds), "journal": f,
           "context_window": 200000,
           "context_window_source": "claude-code default for opus-class models; not read from the session"}
    if a.run_json:
        # the headless result JSON carries modelUsage[model].contextWindow — a measured value when present
        try:
            mu = (json.load(open(a.run_json)).get("modelUsage") or {})
            for m, v in mu.items():
                if isinstance(v, dict) and v.get("contextWindow"):
                    out["context_window"] = int(v["contextWindow"]); out["context_window_source"] = f"run.json modelUsage[{m}].contextWindow"
                    break
        except Exception as e:
            out["context_window_run_json_error"] = f"{type(e).__name__}: {str(e)[:120]}"
    print(json.dumps(out))

PI_QUOTA_MARKERS = ("quota", "credit", "insufficient", "rate limit", "rate_limit", "ratelimit", "too many requests", "429")

def pi_quota_hit(text):
    t = str(text).lower()
    return any(m in t for m in PI_QUOTA_MARKERS)

def cmd_pi(a):
    """A pi session's cells, from the session jsonl whose 'session' line carries that id (pi 0.84.4 shape:
    one 'session' line, 'model_change' lines with provider/modelId, 'message' lines whose message.role is
    assistant carry usage {input, output, cacheRead, cacheWrite, reasoning, totalTokens})."""
    root = os.path.expanduser(a.sessions_dir)
    cands = glob.glob(os.path.join(root, "*", f"*_{a.session}.jsonl")) + glob.glob(os.path.join(root, f"*_{a.session}.jsonl"))
    found = None
    for f in sorted(cands, key=os.path.getmtime):
        try:
            with open(f, encoding="utf-8") as fh:
                first = json.loads(fh.readline())
            if first.get("type") == "session" and first.get("id") == a.session: found = f
        except Exception:
            continue
    if not found:
        print(json.dumps({"error": "no pi session file whose session line carries that id", "session": a.session,
                          "searched": os.path.join(root, "*", f"*_{a.session}.jsonl")})); sys.exit(2)
    t = {k: 0 for k in TOKEN_CELLS}; n = 0; first = last = None; model = provider = None; cwd = None
    quota = False; quota_lines = []
    with open(found, encoding="utf-8") as fh:
        for line in fh:
            try: o = json.loads(line)
            except Exception: continue
            ts = o.get("timestamp")
            if ts: first = first or ts; last = ts
            typ = o.get("type")
            if typ == "session": cwd = o.get("cwd")
            if typ == "model_change":
                provider = o.get("provider") or provider; model = o.get("modelId") or model
            m = o.get("message") if typ == "message" else None
            if isinstance(m, dict):
                if m.get("errorMessage") or m.get("stopReason") == "error":
                    txt = str(m.get("errorMessage") or "")
                    if pi_quota_hit(txt): quota = True; quota_lines.append(txt[:200])
                if m.get("role") == "assistant" and isinstance(m.get("usage"), dict):
                    u = m["usage"]; n += 1
                    model = m.get("model") or model; provider = m.get("provider") or provider
                    t["in_uncached"] += int(u.get("input", 0) or 0); t["cache_read"] += int(u.get("cacheRead", 0) or 0)
                    t["cache_write"] += int(u.get("cacheWrite", 0) or 0); t["out"] += int(u.get("output", 0) or 0)
                    t["reasoning"] += int(u.get("reasoning", 0) or 0); t["total"] += int(u.get("totalTokens", 0) or 0)
            if typ in ("error",) or (isinstance(o.get("error"), (str, dict))):
                txt = json.dumps(o.get("error") or o)[:300]
                if pi_quota_hit(txt): quota = True; quota_lines.append(txt[:200])
    ctx = None; ctx_src = None
    try:
        mj = json.load(open(os.path.expanduser(a.models_json)))
        for mdl in ((mj.get("providers") or {}).get(provider) or {}).get("models") or []:
            if mdl.get("id") == model and mdl.get("contextWindow"):
                ctx = int(mdl["contextWindow"]); ctx_src = f"{a.models_json} providers[{provider}].models[id={model}].contextWindow"
    except Exception as e:
        ctx_src = f"{type(e).__name__}: {str(e)[:120]}"
    secs = None
    if first and last:
        aa = datetime.fromisoformat(first.replace("Z", "+00:00")); bb = datetime.fromisoformat(last.replace("Z", "+00:00"))
        secs = int((bb - aa).total_seconds())
    out = {"seat": "pi-qwencloud", "harness": "pi", "session_id": a.session, "model": model, "provider": provider,
           "started_at": first, "finished_at": last, "seconds": secs, "tokens": t, "messages": n, "cwd": cwd,
           "journal": found, "context_window": ctx, "context_window_source": ctx_src, "quota_error": quota,
           "quota_lines": quota_lines}
    if ctx is None:
        out["error"] = f"no contextWindow in {a.models_json} for provider {provider} model {model}"
        print(json.dumps(out)); sys.exit(2)
    print(json.dumps(out))

def cmd_validate(a):
    with open(a.file, encoding="utf-8") as fh: r = json.load(fh)
    kind = a.schema or r.get("kind") or "build"
    missing = []
    def walk(prefix, v):
        if v is None: missing.append(prefix)
        elif isinstance(v, dict):
            for k, x in v.items(): walk(f"{prefix}.{k}", x)
        elif isinstance(v, list):
            for i, x in enumerate(v): walk(f"{prefix}[{i}]", x)
    for k in REQUIRED.get(kind, REQUIRED["build"]):
        if k not in r: missing.append(k)
        else: walk(k, r[k])
    for who in ("tokens", "evaluator"):
        blk = r.get(who) if who == "tokens" else (r.get("evaluator") or {}).get("tokens")
        if isinstance(blk, dict):
            for c in TOKEN_CELLS:
                if not isinstance(blk.get(c), int): missing.append(f"{who}.tokens.{c}" if who != "tokens" else f"tokens.{c}")
    if missing:
        print("CRASH: null or missing fields: " + ", ".join(sorted(set(missing)))); sys.exit(1)
    print(f"ok: {a.file} kind={kind} every required field present and non-null"); sys.exit(0)

def main():
    p = argparse.ArgumentParser(); sub = p.add_subparsers(dest="verb", required=True)
    s = sub.add_parser("agent"); s.add_argument("--workflows", required=True); s.add_argument("--marker", required=True); s.add_argument("--last", action="store_true", default=True); s.set_defaults(fn=cmd_agent)
    s = sub.add_parser("window"); s.add_argument("--seat", required=True, choices=["cc","cc2","cc3"]); s.set_defaults(fn=cmd_window)
    s = sub.add_parser("codex"); s.add_argument("--rollouts", default=os.path.expanduser("~/.codex/sessions")); s.add_argument("--since", required=True); s.add_argument("--until", required=True); s.add_argument("--thread", help="rollout thread/session id; without it the sum covers EVERY concurrent worker in the window and is not one unit's cost"); s.set_defaults(fn=cmd_codex)
    s = sub.add_parser("claude"); s.add_argument("--seat", required=True, choices=["cc","cc2","cc3"]); s.add_argument("--session", required=True, help="the headless session id (claude -p --session-id / result JSON session_id)"); s.add_argument("--run-json", help="optional: the headless result JSON; its modelUsage contextWindow overrides the stated default"); s.set_defaults(fn=cmd_claude)
    s = sub.add_parser("pi"); s.add_argument("--session", required=True, help="the pi session id (launch.json session_id / the session line's id)"); s.add_argument("--sessions-dir", default="~/.pi/agent/sessions"); s.add_argument("--models-json", default="~/.pi/agent/models.json"); s.set_defaults(fn=cmd_pi)
    s = sub.add_parser("validate"); s.add_argument("file"); s.add_argument("--schema"); s.set_defaults(fn=cmd_validate)
    a = p.parse_args(); a.fn(a)

if __name__ == "__main__": main()
