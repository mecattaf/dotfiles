#!/usr/bin/env bash
# tests/util-01/test-halogen-token-window.sh — UTIL-01's Halogen token window,
# end to end on fixtures (dotfiles#312).
#
#   1. the sampler's LINE_RE reads every request-line shape Halogen 0.7.0 logs
#      (with and without `(K cached)`, `rounds, commit` and the pld tail), skips
#      access lines, and COUNTS a request line it cannot read instead of guessing;
#   2. read_token_window() chains by cursor, marks a cursor-less window
#      incomplete, starts a chain over a quiet minute, and turns every journalctl
#      failure into `error` with no counts — never a zero;
#   3. util-row sums the windows: tokens_in = prompt - cached, prefill rate
#      (prompt - cached) / prefill_s (halogen-flash-server#48), grades MEASURED /
#      PARTIAL / UNKNOWN, and never nulls-to-zero.
#
# Hermetic: the sampler is imported as a module from its path, `journalctl` is a
# fake earlier on PATH, util-row runs in --replay-mode into a scratch meters
# root. python3 and coreutils only.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLER="${UTIL_SAMPLER:-$HERE/home/dot_local/bin/util-sampler}"
ROW="${UTIL_ROW:-$HERE/home/dot_local/bin/util-row}"
test -r "$SAMPLER" && test -r "$ROW" || { echo "missing util-sampler or util-row" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# Fake journalctl. FAKE_MODE: lines (fixture lines + cursor), empty-since (no
# output for --since, a cursor for -n 1), fail (exit 1), nocursor (lines, no
# cursor). It records its argv so the test can check --after-cursor chaining.
BASH_ABS="$(command -v bash)"
printf '#!%s\n' "$BASH_ABS" > "$tmp/bin/journalctl"
cat >> "$tmp/bin/journalctl" <<'FAKE'
printf '%s\n' "$*" >> "$FAKE_ARGV"
case "$FAKE_MODE" in
  fail) echo "Failed to seek to cursor: Invalid argument" >&2; exit 1 ;;
  empty-since)
    case " $* " in *" -n 1 "*) echo "-- cursor: s=last" ;; esac
    exit 0 ;;
  lines|nocursor)
    cat "$FAKE_LINES"
    [ "$FAKE_MODE" = lines ] && echo "-- cursor: s=next"
    exit 0 ;;
esac
FAKE
chmod +x "$tmp/bin/journalctl"

# Real shapes (worker journal, 2026-09-13), a synthetic concurrency line with no
# `rounds, commit` and no `(N cached)`, an access line, and a garbled request line.
cat > "$tmp/lines" <<'L'
serve_api: mtp 448 tok in 9.59s = 46.71 t/s | 249 rounds, commit 1.80/round | prompt 2070 (349 cached), prefill 2.29s | detok 14us/tok
serve_api: mtp 160 tok in 3.43s = 46.64 t/s | 88 rounds, commit 1.82/round | prompt 330, prefill 1.07s | detok 14us/tok | pld 6 rounds, 2.33 acc/round
serve_api: mtp 160 tok in 3.14s = 50.89 t/s | 88 rounds, commit 1.82/round | prompt 330 (325 cached), prefill 0.05s | detok 11us/tok | pld 6 rounds, 2.33 acc/round
serve_api: mtp 406 tok in 8.83s = 45.97 t/s | 230 rounds, commit 1.76/round | prompt 1836, prefill 3.24s
serve_api: mtp 50 tok in 1.00s = 50.00 t/s | prompt 100, prefill 0.50s | detok 12us/tok
INFO:     10.42.0.5:50820 - "GET /health HTTP/1.1" 200 OK
serve_api: mtp 7 tok in garbled | prompt ??
L

export PATH="$tmp/bin:$PATH" FAKE_ARGV="$tmp/argv" FAKE_LINES="$tmp/lines" TMPD="$tmp"

out="$(python3 - "$SAMPLER" <<'PY'
import importlib.machinery, importlib.util, json, os, sys
loader = importlib.machinery.SourceFileLoader("util_sampler", sys.argv[1])
spec = importlib.util.spec_from_loader("util_sampler", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
fails = []
def check(label, cond):
    print(("PASS  " if cond else "FAIL  ") + label)
    if not cond:
        fails.append(label)

lines = open(os.environ["FAKE_LINES"]).read().splitlines()
shapes = [m.LINE_RE.search(l) for l in lines[:5]]
check("1a all five request shapes parse", all(shapes))
check("1b (prompt, cached, out) per line",
      [(int(x.group("prompt")), int(x.group("cached") or 0), int(x.group("out"))) for x in shapes]
      == [(2070, 349, 448), (330, 0, 160), (330, 325, 160), (1836, 0, 406), (100, 0, 50)])
acc = m.parse_serve_lines(lines)
check("1c sums: 5 requests, 1 unparsed, access line skipped",
      acc["requests"] == 5 and acc["unparsed"] == 1)
check("1d prompt/cached/completion totals",
      (acc["prompt_tokens"], acc["cached_tokens"], acc["completion_tokens"]) == (4666, 674, 1224))

spec_ = m.SERVE_PROBES["worker"][0]
clock = m.Clock()
os.environ["FAKE_MODE"] = "lines"
w = m.read_token_window(spec_, "s=prev", clock)
argv = open(os.environ["FAKE_ARGV"]).read().splitlines()[-1]
check("2a chained window: cursor, complete, --after-cursor passed",
      w.get("cursor") == "s=next" and w.get("window_complete") is True
      and w.get("since_cursor") == "s=prev" and "--after-cursor=s=prev" in argv
      and "error" not in w and w["completion_tokens"] == 1224)
w = m.read_token_window(spec_, None, clock)
check("2b first window: --since, incomplete", w.get("window_complete") is False
      and "--since=-60s" in open(os.environ["FAKE_ARGV"]).read().splitlines()[-1])
os.environ["FAKE_MODE"] = "empty-since"
w = m.read_token_window(spec_, None, clock)
check("2c quiet minute starts the chain from the last entry, measured zero",
      w.get("cursor") == "s=last" and w.get("requests") == 0 and "error" not in w)
for mode, label in (("fail", "non-zero exit"), ("nocursor", "no cursor printed")):
    os.environ["FAKE_MODE"] = mode
    w = m.read_token_window(spec_, "s=prev", clock)
    check("2d %s -> error, no counts" % label,
          isinstance(w.get("error"), str) and w.get("cursor") is None
          and "completion_tokens" not in w)
spent = m.Clock(budget=0)
w = m.read_token_window(spec_, "s=prev", spent)
check("2e exhausted budget -> error, journalctl not run", "error" in w)

# previous_cursor walks back past an errored window to the last good cursor
meters = os.path.join(os.environ["TMPD"], "meters")
os.makedirs(os.path.join(meters, "util-sampler"))
import datetime
now = datetime.datetime.now().astimezone()
day = now.strftime("%Y-%m-%d")
with open(os.path.join(meters, "util-sampler", "worker-%s.jsonl" % day), "w") as fh:
    for ts, tok in ((now.timestamp() - 120, {"cursor": "s=good"}),
                    (now.timestamp() - 60, {"error": "x", "cursor": None})):
        fh.write(json.dumps({"ts_epoch": ts, "probes": [{"name": "halogen", "tokens": tok}]}) + "\n")
cur, age = m.previous_cursor(meters, "worker", "halogen", now.timestamp())
check("2f previous_cursor skips an errored window", cur == "s=good" and 100 < age < 140)
print("SAMPLER_FAILS=%d" % len(fails))
PY
)" || true
echo "$out"
case "$out" in *"SAMPLER_FAILS=0"*) sampler_ok=1 ;; *) sampler_ok=0 ;; esac

# ── 3. util-row sums the windows ───────────────────────────────────────────
# A worker day of four samples at noon UTC. Windows: w1 the calibration pair
# (330 prompt, 325 cached), w2 the 2070/349 line, w3 an idle measured zero, w4
# depends on the case.
mkrow() { # $1 = case name, $2 = the fourth window's JSON
  local b="$tmp/bundle-$1"
  mkdir -p "$b"
  python3 - "$b/worker.jsonl" "$2" <<'PY'
import datetime, json, sys
path, fourth = sys.argv[1], json.loads(sys.argv[2])
arm = ["halogen-qwen3.8-flash-next"]
def win(**kw):
    base = {"source": "journal", "cursor": "c", "window_complete": True, "requests": 0,
            "prompt_tokens": 0, "cached_tokens": 0, "completion_tokens": 0,
            "prefill_s": 0.0, "decode_s": 0.0, "unparsed": 0}
    base.update(kw)
    return base
wins = [win(requests=2, prompt_tokens=660, cached_tokens=325, completion_tokens=320,
            prefill_s=1.12, decode_s=6.57),
        win(requests=1, prompt_tokens=2070, cached_tokens=349, completion_tokens=448,
            prefill_s=2.29, decode_s=9.59),
        win(), fourth]
with open(path, "w") as fh:
    for i, w in enumerate(wins):
        t = 1789214400 + 60 * i
        probe = {"name": "halogen", "alive": True, "arms": arm, "metrics": None}
        if w is not None:
            probe["tokens"] = w
        fh.write(json.dumps({"schema": "util-sample/3", "box": "worker", "ts_epoch": t,
                             "ts": datetime.datetime.fromtimestamp(t).astimezone().isoformat(),
                             "sysfs": {}, "pools": None, "probes": [probe], "ledger": {}}) + "\n")
PY
  printf '{"box":"worker","date":"2026-09-12","sampler_log":{"path":"worker.jsonl","file":"worker.jsonl"},"ledger":null,"lease_slice":null,"lease_source_log":null,"evidence_files":[]}\n' > "$b/INPUTS.json"
  python3 "$ROW" --replay-mode "$b" --meters "$tmp/m-$1" >/dev/null
  cat "$tmp/m-$1/util-worker-2026-09-12.json"
}
full='{"source":"journal","cursor":"c","window_complete":true,"requests":0,"prompt_tokens":0,"cached_tokens":0,"completion_tokens":0,"prefill_s":0.0,"decode_s":0.0,"unparsed":0}'
row_ok="$(mkrow measured "$full")"
row_err="$(mkrow partial '{"source":"journal","cursor":null,"error":"journalctl exit 1"}')"
row_gap="$(mkrow gap null)"

row_out="$(ROW_OK="$row_ok" ROW_ERR="$row_err" python3 - <<'PY'
import json, os
fails = []
def check(label, cond):
    print(("PASS  " if cond else "FAIL  ") + label)
    if not cond:
        fails.append(label)
A = "halogen-qwen3.8-flash-next"
ok = json.loads(os.environ["ROW_OK"])
check("3a schema util-row/2", ok["schema"] == "util-row/2")
check("3b tokens_in = prompt - cached = 2056", ok["tokens_in"] == {A: (660 - 325) + (2070 - 349)})
check("3c tokens_in_cached 674, tokens_out 768, requests 3",
      ok["tokens_in_cached"] == {A: 674} and ok["tokens_out"] == {A: 768}
      and ok["tokens_requests"] == {A: 3})
check("3d prefill rate (prompt-cached)/prefill_s", ok["prefill_tokens_per_s"] == {A: round(2056 / 3.41, 6)})
check("3e decode rate out/decode_s", ok["decode_tokens_per_s"] == {A: round(768 / 16.16, 6)})
check("3f grade MEASURED, 4 counted windows",
      ok["tokens_grade"] == "MEASURED" and ok["tokens_windows"]["counted"] == 4
      and ok["tokens_windows"]["missing"] == 0)
err = json.loads(os.environ["ROW_ERR"])
check("3g an errored window -> PARTIAL, missing 1, the counted sums unchanged",
      err["tokens_grade"] == "PARTIAL" and err["tokens_windows"]["missing"] == 1
      and err["tokens_out"] == {A: 768})
# 2070/349 prefill 2.29 alone: 751.5 t/s — the issue's worked number
check("3h one-line prefill rate 1721/2.29 = 751.5", round((2070 - 349) / 2.29, 1) == 751.5)
print("ROW_FAILS=%d" % len(fails))
PY
)" || true
echo "$row_out"

# A day where no sample carries a window (a util-sample/2 day): UNKNOWN, null, never 0.
nowin="$tmp/bundle-nowin"; mkdir -p "$nowin"
python3 - "$nowin/worker.jsonl" <<'PY'
import datetime, json, sys
with open(sys.argv[1], "w") as fh:
    for i in range(3):
        t = 1789214400 + 60 * i
        fh.write(json.dumps({"schema": "util-sample/2", "box": "worker", "ts_epoch": t,
                             "ts": datetime.datetime.fromtimestamp(t).astimezone().isoformat(),
                             "probes": [{"name": "halogen", "alive": True,
                                         "arms": ["halogen-qwen3.8-flash-next"], "metrics": None}]}) + "\n")
PY
printf '{"box":"worker","date":"2026-09-12","sampler_log":{"path":"worker.jsonl","file":"worker.jsonl"},"ledger":null,"lease_slice":null,"lease_source_log":null,"evidence_files":[]}\n' > "$nowin/INPUTS.json"
python3 "$ROW" --replay-mode "$nowin" --meters "$tmp/m-nowin" >/dev/null
unk="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["tokens_grade"], r["tokens_out"])' "$tmp/m-nowin/util-worker-2026-09-12.json")"
if [ "$unk" = "UNKNOWN {'halogen-qwen3.8-flash-next': None}" ]; then
  echo "PASS  3i no window all day -> UNKNOWN, tokens_out null (never 0)"; unk_ok=1
else
  echo "FAIL  3i no window all day -> got: $unk"; unk_ok=0
fi

case "$row_out" in *"ROW_FAILS=0"*) row_ok_flag=1 ;; *) row_ok_flag=0 ;; esac
if [ "$sampler_ok" = 1 ] && [ "$row_ok_flag" = 1 ] && [ "$unk_ok" = 1 ]; then
  echo "test-halogen-token-window: all green"
  exit 0
fi
echo "test-halogen-token-window: FAILED"
exit 1
