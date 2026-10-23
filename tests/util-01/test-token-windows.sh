#!/usr/bin/env bash
# Gufo's uncalibrated telemetry stays UNKNOWN; recorded token windows still
# aggregate correctly in offline replay, including missing and partial data.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLER="${UTIL_SAMPLER:-$HERE/home/dot_local/bin/util-sampler}"
ROW="${UTIL_ROW:-$HERE/home/dot_local/bin/util-row}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 - "$SAMPLER" <<'PYTEST'
import importlib.machinery, importlib.util, sys
from unittest.mock import patch
loader = importlib.machinery.SourceFileLoader("util_sampler", sys.argv[1])
spec = importlib.util.spec_from_loader("util_sampler", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
with patch.object(m, "http_get", side_effect=[
    (200, '{"status":"ok"}', 1, None),
    (200, '{"data":[{"id":"qwen3.8-flash-next"}]}', 1, None),
]), patch.object(m, "read_sysfs", return_value={}), patch.object(m, "read_pools", return_value=None), patch.object(m, "read_ledger", return_value={}):
    sample = m.build_sample("strix")
probe = sample["probes"][0]
assert probe["alive"] and probe["name"] == "gufo"
assert probe["arms"] == ["qwen3.8-flash-next"]
assert probe["tokens"]["source"] == "unavailable" and "error" in probe["tokens"]
assert "completion_tokens" not in probe["tokens"]
assert "requests" not in probe["tokens"]
print("PASS  Gufo probe reports unavailable token counts, never zero")
PYTEST
sampler_ok=1

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
arm = ["qwen3.8-flash-next"]
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
        probe = {"name": "gufo", "alive": True, "arms": arm, "metrics": None}
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
A = "qwen3.8-flash-next"
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
                             "probes": [{"name": "gufo", "alive": True,
                                         "arms": ["qwen3.8-flash-next"], "metrics": None}]}) + "\n")
PY
printf '{"box":"worker","date":"2026-09-12","sampler_log":{"path":"worker.jsonl","file":"worker.jsonl"},"ledger":null,"lease_slice":null,"lease_source_log":null,"evidence_files":[]}\n' > "$nowin/INPUTS.json"
python3 "$ROW" --replay-mode "$nowin" --meters "$tmp/m-nowin" >/dev/null
unk="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["tokens_grade"], r["tokens_out"])' "$tmp/m-nowin/util-worker-2026-09-12.json")"
if [ "$unk" = "UNKNOWN {'qwen3.8-flash-next': None}" ]; then
  echo "PASS  3i no window all day -> UNKNOWN, tokens_out null (never 0)"; unk_ok=1
else
  echo "FAIL  3i no window all day -> got: $unk"; unk_ok=0
fi

case "$row_out" in *"ROW_FAILS=0"*) row_ok_flag=1 ;; *) row_ok_flag=0 ;; esac
if [ "$sampler_ok" = 1 ] && [ "$row_ok_flag" = 1 ] && [ "$unk_ok" = 1 ]; then
  echo "test-token-windows: all green"
  exit 0
fi
echo "test-token-windows: FAILED"
exit 1
