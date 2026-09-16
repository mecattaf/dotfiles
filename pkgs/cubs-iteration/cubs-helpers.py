#!/usr/bin/env python3
"""cubs-iteration's two pure helpers. No network, no git, no state.

  cubs-helpers.py events <pi-events.jsonl>
      Summarise one `pi --mode json` event stream (pi docs/json.md): usage
      summed over message_end events, tool-call and isError counts from
      tool_execution_end, repeated identical calls (same toolName + same
      canonical args seen before), the last assistant stopReason. Prints one
      JSON object. Never fails on a truncated or empty stream: a partial run
      still gets a summary, with `truncated` true.

  cubs-helpers.py guard <repo> <allowed_paths.json> [upstream-dir]   < touched-files
      The built-in diff guard (the campaign's tools/spec-diff-guard.sh rules):
      every touched file must match allowed_paths + new_files, no spec.md,
      no constitution, a setup copy identical to the upstream checkout is not
      a change, an empty allowed diff fails. Prints {ok, violations, files,
      changed}; exit 1 on a violation.
"""
import hashlib
import json
import os
import re
import sys


# ----------------------------------------------------------------- events
def _num(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


def _usage_of(message):
    usage = message.get("usage") if isinstance(message, dict) else None
    if not isinstance(usage, dict):
        return None
    # pi's Usage is {input, output, cacheRead, cacheWrite, totalTokens, cost};
    # an OpenAI-shaped provider may leave prompt_tokens/completion_tokens and a
    # reasoning count. Both spellings are read; the receipt keeps one.
    prompt = _num(usage.get("input")) + _num(usage.get("cacheRead")) + _num(usage.get("cacheWrite"))
    if prompt == 0:
        prompt = _num(usage.get("prompt_tokens"))
    completion = _num(usage.get("output")) or _num(usage.get("completion_tokens"))
    reasoning = None
    for key in ("reasoning", "reasoning_tokens", "reasoningTokens"):
        if isinstance(usage.get(key), (int, float)):
            reasoning = _num(usage.get(key))
            break
    details = usage.get("completion_tokens_details")
    if reasoning is None and isinstance(details, dict) and isinstance(details.get("reasoning_tokens"), (int, float)):
        reasoning = _num(details.get("reasoning_tokens"))
    return prompt, completion, reasoning


def events(path):
    out = {
        "events": 0,
        "message_ends": 0,
        "tool_calls": 0,
        "tool_errors": 0,
        "repeated_identical_calls": 0,
        "tools_by_name": {},
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "reasoning_tokens": None},
        "stop_reason": None,
        "error_message": None,
        "agent_end": False,
        "truncated": False,
        "compactions": 0,
    }
    seen = set()
    try:
        fh = open(path, "r", encoding="utf-8", errors="replace")
    except OSError as error:
        out["truncated"] = True
        out["error_message"] = f"cannot read {path}: {error}"
        print(json.dumps(out))
        return 0
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                out["truncated"] = True
                continue
            if not isinstance(event, dict):
                continue
            out["events"] += 1
            kind = event.get("type")
            if kind == "tool_execution_start":
                out["tool_calls"] += 1
                name = str(event.get("toolName"))
                out["tools_by_name"][name] = out["tools_by_name"].get(name, 0) + 1
                key = name + "\0" + json.dumps(event.get("args"), sort_keys=True, separators=(",", ":"))
                if key in seen:
                    out["repeated_identical_calls"] += 1
                seen.add(key)
            elif kind == "tool_execution_end":
                if event.get("isError") is True:
                    out["tool_errors"] += 1
            elif kind == "message_end":
                message = event.get("message") or {}
                if message.get("role") == "assistant":
                    out["message_ends"] += 1
                    usage = _usage_of(message)
                    if usage is not None:
                        prompt, completion, reasoning = usage
                        out["usage"]["prompt_tokens"] += prompt
                        out["usage"]["completion_tokens"] += completion
                        if reasoning is not None:
                            out["usage"]["reasoning_tokens"] = (out["usage"]["reasoning_tokens"] or 0) + reasoning
                    if message.get("stopReason") is not None:
                        out["stop_reason"] = message.get("stopReason")
                    if message.get("errorMessage"):
                        out["error_message"] = str(message.get("errorMessage"))[:500]
            elif kind == "compaction_end":
                out["compactions"] += 1
            elif kind == "agent_end":
                out["agent_end"] = True
    if not out["agent_end"]:
        out["truncated"] = True
    print(json.dumps(out))
    return 0


# ----------------------------------------------------------------- guard
# The same rules as the campaign's tools/spec-diff-guard.sh, so the built-in
# fallback and the campaign's grader agree on what a touched file may be:
# any file whose basename is spec.md is frozen (spec/**/spec.md relative to
# ~/agency, and the same rule inside every repo), so is the speckit
# constitution; a touched file outside allowed_paths + new_files is a
# violation unless it is byte-identical to the same path under the upstream
# checkout (a setup copy is not a change); an empty diff inside the allowed
# set fails.
FROZEN_BASENAME = "spec.md"
FROZEN_PATHS = {".specify/memory/constitution.md"}


def _glob_to_regex(pattern):
    # `**/` crosses directories, `**` matches anything, `*` and `?` stay inside
    # one path segment, everything else is literal (the campaign guard's
    # grammar, verbatim).
    out = ""
    i = 0
    while i < len(pattern):
        ch = pattern[i]
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
            continue
        if pattern.startswith("**", i):
            out += ".*"
            i += 2
            continue
        if ch == "*":
            out += "[^/]*"
        elif ch == "?":
            out += "[^/]"
        else:
            out += re.escape(ch)
        i += 1
    return re.compile("^" + out + "$")


def _same_as_upstream(upstream, path):
    if not upstream:
        return False
    up = os.path.join(upstream, path)
    if not os.path.isfile(up) or not os.path.isfile(path):
        return False
    with open(up, "rb") as a, open(path, "rb") as b:
        return hashlib.sha256(a.read()).hexdigest() == hashlib.sha256(b.read()).hexdigest()


def guard(repo, allowed_json, upstream=""):
    try:
        allowed = json.loads(allowed_json)
    except json.JSONDecodeError as error:
        print(json.dumps({"ok": False, "violations": [f"allowed_paths is not JSON: {error}"], "files": [], "changed": []}))
        return 1
    if not isinstance(allowed, list) or not all(isinstance(p, str) for p in allowed):
        print(json.dumps({"ok": False, "violations": ["allowed_paths is not a list of strings"], "files": [], "changed": []}))
        return 1
    patterns = [_glob_to_regex(p.strip()) for p in allowed if p.strip()]
    files = [line.rstrip("\n") for line in sys.stdin if line.strip()]
    violations = []
    changed = []
    for path in files:
        full = f"{repo}/{path}"
        if os.path.basename(path) == FROZEN_BASENAME:
            violations.append(f"{path}: spec/**/spec.md is never modified ({full})")
            continue
        if path in FROZEN_PATHS:
            violations.append(f"{path}: the constitution is frozen")
            continue
        if any(rx.match(path) for rx in patterns):
            changed.append(path)
            continue
        if _same_as_upstream(upstream, path):
            continue
        violations.append(f"{path}: outside allowed_paths")
    if not violations and not changed:
        violations.append("empty diff: no changed or new file inside allowed_paths")
    result = {"ok": not violations, "violations": violations, "files": files, "changed": changed}
    print(json.dumps(result))
    return 0 if not violations else 1


def main(argv):
    if len(argv) >= 3 and argv[1] == "events":
        return events(argv[2])
    if len(argv) >= 4 and argv[1] == "guard":
        return guard(argv[2], argv[3], argv[4] if len(argv) > 4 else "")
    sys.stderr.write(__doc__)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
