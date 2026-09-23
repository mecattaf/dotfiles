# probe/ax-fleet-nop1: is ax P1 (the completion write-back patch) necessary?
#
# This branch builds ax v0.3.0 with sandbox-class.patch only (P1 removed, the
# controller runs without --running-resync). Instead of the controller learning
# that a command exited, each Task's command reports its own completion to a
# stand-in floor (POST /floor/complete on the worker's stub, the one allowlisted
# egress target), and this driver, standing in for the link, reads the floor
# and then DELETES the Task through the stock ax client. Measured here:
#   - the Task's phase just before the delete (stock ax: expected Running);
#   - T5 shape without P1: 6 Tasks in a row, then 2 rounds of 2 at once, on the
#     2-worker pool; none ResourceExhausted, every result intact;
#   - the delete frees the worker (the next Task gets one) and is idempotent;
#   - leaks after delete: ax Tasks, Substrate actors and templates, PVs, the
#     RustFS volume;
#   - control: without the delete the 3rd Task is refused (the P1 failure);
#   - side: SuspendTask instead of delete also frees a worker.
# Everything is recorded with record(); assertions are only the acceptance
# items above.
import base64
import hashlib
import json
import re
from typing import Any

AX = "AX_SERVER=http://127.0.0.1:8080 ax -a fleet"
ATE = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl-ate"
STUB = "http://10.42.0.5:8731"
NS = "fleet"
TASK_TIMEOUT = 900  # test parameter: per-Task wait for a floor report

TASK_SCRIPT = r"""
set -u
nonce="$(date +%s%N)-$$-$RANDOM"
started="$(date +%s.%N)"
ax-agent halogen-smoke >/tmp/agent.out 2>&1
rc=$?
out="${AX_RESULT_PATH:-.ax/result.json}"
b64=""
sha=""
if [ -f "$out" ]; then
  b64="$(base64 -w0 "$out")"
  sha="$(sha256sum "$out" | cut -d' ' -f1)"
fi
body="$(jq -nc --arg task "$FLOOR_TASK" --arg nonce "$nonce" --arg started "$started" \
  --arg pwd "$PWD" --argjson rc "$rc" --arg b64 "$b64" --arg sha "$sha" \
  --arg kernel "$(cat /proc/version 2>/dev/null)" \
  '{task:$task, nonce:$nonce, started:$started, pwd:$pwd, rc:$rc, result_b64:$b64, result_sha256:$sha, kernel:$kernel}')"
for i in 1 2 3 4 5; do
  curl -sf --max-time 20 -H 'content-type: application/json' -d "$body" "$FLOOR_URL/floor/complete" >/dev/null && break
  sleep 2
done
exit "$rc"
"""


def ax(args: str) -> tuple[int, str]:
    rc, out = coordinator.execute(f"{AX} {args} 2>&1")
    return rc, out.strip()


def apply_task(name: str) -> None:
    task: dict[str, Any] = {
        "apiVersion": "ax.io/v1alpha1",
        "kind": "Task",
        "metadata": {"name": name, "atespace": NS},
        "spec": {
            "image": IMAGE,
            "command": ["bash", "-c", TASK_SCRIPT],
            "env": [
                {"name": "HALOGEN_URL", "value": STUB},
                {"name": "FLOOR_URL", "value": STUB},
                {"name": "FLOOR_TASK", "value": name},
            ],
            "gateway": {"name": "halogen"},
        },
    }
    b = base64.b64encode(json.dumps(task).encode()).decode()
    coordinator.succeed(f"echo {b} | base64 -d | {AX} apply -f -")


def task_state(name: str) -> Any:
    """(exists, phase, ready_reason, ready_message, raw) from `ax get task`."""
    rc, out = ax(f"get task {name}")
    if rc != 0:
        return {"exists": False, "rc": rc, "out": out[-300:]}
    m = re.search(r"^\s+phase:\s*(\S+)", out, re.M)
    phase = m.group(1).strip("\"'") if m else None
    ready: Any = None
    for block in re.split(r"\n\s*- ", out):
        if re.search(r"type:\s*\"?Ready\"?", block):
            r = re.search(r"reason:\s*(.+)", block)
            msg = re.search(r"message:\s*(.+)", block)
            ready = {
                "reason": r.group(1).strip().strip("\"'") if r else None,
                "message": msg.group(1).strip().strip("\"'")[:300] if msg else None,
            }
    return {"exists": True, "phase": phase, "ready": ready}


def floor_reports(name: Any = None) -> Any:
    out = worker.succeed("curl -sf http://127.0.0.1:8731/floor/results")
    reps = json.loads(out)["reports"]
    if name is None:
        return reps
    return [r for r in reps if r["report"].get("task") == name]


def ate_json(args: str) -> Any:
    rc, out = nas.execute(f"{ATE} {args} -o json 2>&1")
    if rc != 0:
        return {"rc": rc, "error": out.strip()[-400:]}
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return {"rc": rc, "unparsed": out.strip()[-400:]}


def actors() -> Any:
    """Actors in the fleet atespace: [{name, state, worker}], or the error."""
    j = ate_json(f"get actors --atespace {NS}")
    if isinstance(j, dict) and ("error" in j or "unparsed" in j):
        return j
    items = j if isinstance(j, list) else (j.get("actors") or j.get("items") or [])
    res: list[Any] = []
    for a in items:
        st = a.get("status") or {}
        res.append(
            {
                "name": (a.get("metadata") or {}).get("name"),
                "state": st.get("state") or st.get("phase"),
                "worker": ((st.get("workerAssignment") or {}).get("worker") or {}).get("name"),
            }
        )
    return res


def templates() -> Any:
    j = ate_json(f"get actor-template --atespace {NS}")
    if isinstance(j, dict) and ("error" in j or "unparsed" in j):
        return j
    items = j if isinstance(j, list) else (j.get("actorTemplates") or j.get("items") or [])
    return sorted((t.get("metadata") or {}).get("name") for t in items)


def rustfs_volume() -> Any:
    pvs = json.loads(kubectl("get pv -o json"))["items"]
    paths: list[str] = []
    for pv in pvs:
        claim = (pv["spec"].get("claimRef") or {}).get("name", "")
        path = (pv["spec"].get("local") or {}).get("path") or (pv["spec"].get("hostPath") or {}).get("path")
        if "rustfs" in claim and path:
            paths.append(path)
    res: dict[str, Any] = {"pv_count": len(pvs), "rustfs_paths": paths}
    for p in paths:
        res[p] = nas.succeed(f"echo $(find {p} -type f | wc -l) $(du -sb {p} | cut -f1)").strip()
    return res


def leak_snapshot(tag: str) -> Any:
    snap: dict[str, Any] = {
        "ax_tasks": ax("get tasks")[1],
        "actors": actors(),
        "templates": templates(),
        "volumes": rustfs_volume(),
    }
    record(f"nop1_leaks_{tag}", snap)
    return snap


def wait_report(name: str) -> Any:
    """Poll the floor for NAME's report; stop early if the Task fails."""
    t0 = time.monotonic()
    while time.monotonic() - t0 < TASK_TIMEOUT:
        reps = floor_reports(name)
        if reps:
            return reps, task_state(name), round(time.monotonic() - t0, 1)
        st = task_state(name)
        if st.get("phase") == "Failed":
            return [], st, round(time.monotonic() - t0, 1)
        time.sleep(2)
    return [], task_state(name), round(time.monotonic() - t0, 1)


def check_report(name: str, reps: Any) -> Any:
    rep = reps[0]["report"]
    raw = base64.b64decode(rep["result_b64"]) if rep.get("result_b64") else b""
    try:
        result: Any = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        result = {}
    intact = (
        rep.get("rc") == 0
        and raw != b""
        and hashlib.sha256(raw).hexdigest() == rep.get("result_sha256")
        and result.get("ok") is True
        and result.get("content") == "halogen-stub-ok"
    )
    return {
        "reports": len(reps),
        "distinct_nonces": len({r["report"]["nonce"] for r in reps}),
        "rc": rep["rc"],
        "sha256": rep["result_sha256"],
        "intact": intact,
        "src": reps[0]["src"],
        "gvisor": "gvisor" in rep.get("kernel", ""),
    }


def delete_task(name: str) -> Any:
    """Delete as the link would; measure idempotence and the Task's removal."""
    t0 = time.monotonic()
    first = ax(f"delete task {name}")
    again = ax(f"delete task {name}")  # while Terminating
    coordinator.wait_until_succeeds(f"! {AX} get task {name} >/dev/null 2>&1", timeout=300)
    gone_s = round(time.monotonic() - t0, 1)
    after = ax(f"delete task {name}")  # once gone
    return {
        "first": {"rc": first[0], "out": first[1][-200:]},
        "while_terminating": {"rc": again[0], "out": again[1][-200:]},
        "after_gone": {"rc": after[0], "out": after[1][-200:]},
        "gone_seconds": gone_s,
    }


def run_one(name: str) -> Any:
    apply_task(name)
    reps, before, secs = wait_report(name)
    entry: dict[str, Any] = {"task": name, "report_seconds": secs, "before_delete": before}
    if reps:
        entry["floor"] = check_report(name, reps)
    entry["actors_before_delete"] = actors()
    entry["delete"] = delete_task(name)
    entry["actors_after_delete"] = actors()
    return entry


def resource_exhausted(entry: Any) -> bool:
    msg = json.dumps(entry.get("before_delete", {}))
    return "ResourceExhausted" in msg or "no free workers" in msg


with step("nop1: stock ax control plane up (no P1, no --running-resync)"):
    for d in ["ax-redis", "ax-server", "ax-controller"]:
        kubectl(f"-n ax-system rollout status deploy/{d} --timeout=600s")
    coordinator.wait_until_succeeds("curl -sf http://127.0.0.1:8080/healthz", timeout=300)
    args = kubectl("-n ax-system get deploy ax-controller -o jsonpath='{.spec.template.spec.containers[0].args}'")
    record("nop1_controller_args", args)
    assert "running-resync" not in args, args
    rc, out = ax("result task nothing")
    record("nop1_ax_result_verb", {"rc": rc, "out": out[-200:]})
    IMAGE = coordinator.succeed("ax-fleet-image-ref").strip()
    record("nop1_image", IMAGE)
    gw: dict[str, Any] = {
        "apiVersion": "ax.io/v1alpha1",
        "kind": "Gateway",
        "metadata": {"name": "halogen", "atespace": NS},
        "spec": {"egress": {"allowlist": {"hosts": [{"host": "10.42.0.5/32", "port": 8731}]}}},
    }
    coordinator.succeed(f"echo {base64.b64encode(json.dumps(gw).encode()).decode()} | base64 -d | {AX} apply -f -")
    worker.succeed("curl -sf http://127.0.0.1:8731/floor/results")
    record("nop1_workers_baseline", ate_json("get workers"))
    leak_snapshot("baseline")

with step("nop1 T5 sequential: 6 Tasks in a row on the 2-worker pool, reported to the floor, deleted by the driver"):
    seq: list[Any] = []
    for i in range(1, 7):
        e = run_one(f"nop1-seq-{i}")
        record(f"nop1_seq_{i}", e)
        seq.append(e)
    for e in seq:
        assert not resource_exhausted(e), e
        assert e.get("floor", {}).get("intact") is True, e
        assert e["before_delete"].get("exists") is True, e
        assert e["delete"]["first"]["rc"] == 0, e
    record("nop1_seq_phase_before_delete", [e["before_delete"].get("phase") for e in seq])

with step("nop1 T5 concurrent: 2 rounds of 2 Tasks at once"):
    conc: list[Any] = []
    for rnd in (1, 2):
        names = [f"nop1-conc-{rnd}-{j}" for j in (1, 2)]
        for n in names:
            apply_task(n)
        entries: list[Any] = []
        for n in names:
            reps, before, secs = wait_report(n)
            e: dict[str, Any] = {"task": n, "report_seconds": secs, "before_delete": before}
            if reps:
                e["floor"] = check_report(n, reps)
            entries.append(e)
        acts = actors()
        for e in entries:
            e["actors_before_delete"] = acts
            e["delete"] = delete_task(e["task"])
        record(f"nop1_conc_round_{rnd}", entries)
        conc.extend(entries)
    for e in conc:
        assert not resource_exhausted(e), e
        assert e.get("floor", {}).get("intact") is True, e
    leak_snapshot("after_t5")

with step("nop1 control: without the delete, the 3rd Task on 2 workers"):
    ctl: dict[str, Any] = {}
    for n in ("nop1-ctl-1", "nop1-ctl-2"):
        apply_task(n)
    for n in ("nop1-ctl-1", "nop1-ctl-2"):
        reps, before, secs = wait_report(n)
        ctl[n] = {"reported": bool(reps), "state": before, "seconds": secs}
    # Both commands have exited and reported; stock ax still holds their workers.
    time.sleep(30)
    ctl["held_after_30s"] = {n: task_state(n) for n in ("nop1-ctl-1", "nop1-ctl-2")}
    ctl["actors_held"] = actors()
    apply_task("nop1-ctl-3")
    reps, st, secs = wait_report("nop1-ctl-3")
    ctl["nop1-ctl-3"] = {"reported": bool(reps), "state": st, "seconds": secs}
    record("nop1_control", ctl)
    for n in ("nop1-ctl-1", "nop1-ctl-2", "nop1-ctl-3"):
        ctl[f"delete_{n}"] = delete_task(n)
    # After deleting the holders, the pool serves again.
    ctl["after"] = run_one("nop1-ctl-after")
    record("nop1_control", ctl)
    assert ctl["after"].get("floor", {}).get("intact") is True, ctl["after"]

with step("nop1 side: SuspendTask instead of delete frees a worker"):
    side: dict[str, Any] = {}
    for n in ("nop1-sus-1", "nop1-sus-2"):
        apply_task(n)
    for n in ("nop1-sus-1", "nop1-sus-2"):
        reps, before, secs = wait_report(n)
        side[n] = {"reported": bool(reps), "state": before}
    side["suspend"] = ax("suspend task nop1-sus-1")
    t0 = time.monotonic()
    while time.monotonic() - t0 < 300 and task_state("nop1-sus-1").get("phase") != "Suspended":
        time.sleep(2)
    side["suspended_state"] = task_state("nop1-sus-1")
    side["suspended_seconds"] = round(time.monotonic() - t0, 1)
    side["actors_after_suspend"] = actors()
    apply_task("nop1-sus-3")
    reps, st, secs = wait_report("nop1-sus-3")
    side["nop1-sus-3"] = {"floor": check_report("nop1-sus-3", reps) if reps else None, "state": st, "seconds": secs}
    side["sus1_after_60s"] = task_state("nop1-sus-1")
    side["reports_sus1"] = len(floor_reports("nop1-sus-1"))
    record("nop1_suspend", side)
    leak_snapshot("suspend_before_delete")
    for n in ("nop1-sus-1", "nop1-sus-2", "nop1-sus-3"):
        side[f"delete_{n}"] = delete_task(n)
    record("nop1_suspend", side)

with step("nop1: leaks after every Task is deleted"):
    time.sleep(30)
    final = leak_snapshot("final")
    all_reports = floor_reports()
    per_task: dict[str, list[Any]] = {}
    for r in all_reports:
        per_task.setdefault(r["report"]["task"], []).append(r["report"]["nonce"])
    record("nop1_reports_per_task", {k: len(v) for k, v in sorted(per_task.items())})
    record("nop1_workers_final", ate_json("get workers"))
    rc, out = ax("get tasks")
    assert "nop1-" not in out, out
