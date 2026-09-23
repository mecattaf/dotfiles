# Phase 32: the bring-up's non-P1 cases on stock ax, in the floor-report shape.
#
# 25-harness-probe and 30-ax asserted P1 behaviour (a Task reaching
# Completed, `ax result`). Stock ax v0.3.0 keeps a finished Task Running, so
# every case here reports its own outcome to the stand-in floor (the worker's
# stub, as in 30-nop1) and the driver deletes the Task, as the link will. The
# checks themselves are the bring-up's: the harness probe (claude --version,
# Halogen through the Gateway, gVisor), T4 and T4b egress refusals, the API
# owner match (fix round 3), and the resilience cases with the LAN flap (fix
# round 1).
import base64
import json
import re
import time
from typing import Any

FLEET_REPORT_TAIL = r"""
rc=$?
b64=""
[ -f /tmp/result.json ] && b64="$(base64 -w0 /tmp/result.json)"
body="$(jq -nc --arg task "$FLOOR_TASK" --arg nonce "$(date +%s%N)-$$" --argjson rc "$rc" \
  --arg b64 "$b64" --arg kernel "$(cat /proc/version 2>/dev/null)" \
  '{task:$task, nonce:$nonce, rc:$rc, result_b64:$b64, result_sha256:"", kernel:$kernel}')"
for i in 1 2 3 4 5; do
  curl -sf --max-time 20 -H 'content-type: application/json' -d "$body" "$FLOOR_URL/floor/complete" >/dev/null && break
  sleep 2
done
exit "$rc"
"""


def fleet_task(name: str, body: str, gateway: Any = "halogen", image: Any = None) -> None:
    """Apply one Task whose BODY writes /tmp/result.json; the tail reports it."""
    script = "set -u\n(\n" + body + "\n)\n" + FLEET_REPORT_TAIL
    spec: dict[str, Any] = {
        "image": image or IMAGE,
        "command": ["bash", "-c", f"echo {base64.b64encode(script.encode()).decode()} | base64 -d | bash"],
        "env": [
            {"name": "HALOGEN_URL", "value": STUB},
            {"name": "FLOOR_URL", "value": STUB},
            {"name": "FLOOR_TASK", "value": name},
        ],
    }
    if gateway is not None:
        spec["gateway"] = {"name": gateway}
    task = {"apiVersion": "ax.io/v1alpha1", "kind": "Task", "metadata": {"name": name, "atespace": NS}, "spec": spec}
    b = base64.b64encode(json.dumps(task).encode()).decode()
    coordinator.succeed(f"echo {b} | base64 -d | {AX} apply -f -")


REAPPLY_RESUME = 3  # test parameter: re-applies of a Task whose resume failed transiently


def resume_failed_transient(st: Any) -> bool:
    """Failed with ActorResumeFailed for a reason other than a full pool."""
    msg = json.dumps(st)
    return (
        st.get("phase") == "Failed"
        and (st.get("ready") or {}).get("reason") == "ActorResumeFailed"
        and "ResourceExhausted" not in msg
        and "no free workers" not in msg
    )


def fleet_run(name: str, body: str, gateway: Any = "halogen", image: Any = None, attempts: int = MAX_ATTEMPTS) -> Any:
    """Attempts NAME-a1.. until the floor has a report; returns the decoded result."""
    tried: list[Any] = []
    for attempt in range(1, attempts + 1):
        n = f"{name}-a{attempt}"
        fleet_task(n, body, gateway, image)
        reps, before, secs = wait_report(n)
        reapplied: list[Any] = []
        # A resume that failed on a stale gRPC connection (ActorResumeFailed,
        # Unavailable) left the actor placed but never restored: atelet wrote
        # no sandbox record, and Substrate's Terminate then fails on every
        # delete (MEASURED r1 run 2, cmd/atelet/main.go:1281). Deleting that
        # attempt strands it in ACTOR_STATE_DELETING. Stock ax reconciles on
        # every save and re-runs ResumeActor with no phase guard, so the
        # recovery is to apply the same Task again, not to delete it.
        while not reps and len(reapplied) < REAPPLY_RESUME and resume_failed_transient(before):
            reapplied.append({"state": before, "after_s": secs})
            fleet_task(n, body, gateway, image)
            reps, before, secs = wait_report(n)
        entry: dict[str, Any] = {"task": n, "report_seconds": secs, "before_delete": before, "reapplied": reapplied}
        if reps:
            rep = reps[0]["report"]
            raw = base64.b64decode(rep["result_b64"]) if rep.get("result_b64") else b"{}"
            entry.update(rc=rep["rc"], kernel=rep.get("kernel", ""), result=json.loads(raw or b"{}"))
            assert "gvisor" in entry["kernel"], entry
        entry["delete"] = delete_task(n)
        tried.append(entry)
        if reps:
            break
    record(f"fleet_{name}", tried)
    assert "result" in tried[-1], f"{name}: no floor report after {len(tried)} attempt(s)"
    return tried[-1]


def curl_body(url: str) -> str:
    return (
        f"code=$(curl -s -o /dev/null -w '%{{http_code}}' --max-time 10 {url}); crc=$?\n"
        "jq -nc --arg code \"$code\" --argjson crc \"$crc\" '{http_code:$code, curl_rc:$crc}' >/tmp/result.json"
    )


with step("probe: a gVisor ax Task runs claude --version and reaches Halogen through the Gateway (floor report)"):
    digest = coordinator.succeed(f"cat {CLAUDE_PROBE_OCI}/digest").strip()
    assert digest.startswith("sha256:"), digest
    stub_before = len(worker.succeed("cat /var/lib/halogen-stub/requests.jsonl 2>/dev/null || true").splitlines())
    host_kernel = coordinator.succeed("cat /proc/version").strip()
    body = (
        "v=$(claude --version 2>&1); vrc=$?\n"
        "m=$(curl -s --max-time 20 \"$HALOGEN_URL/v1/models\"); mrc=$?\n"
        "jq -nc --arg v \"$v\" --argjson vrc \"$vrc\" --arg m \"$m\" --argjson mrc \"$mrc\" "
        "'{claude_version:$v, claude_rc:$vrc, models:$m, curl_rc:$mrc}' >/tmp/result.json"
    )
    p = fleet_run("probe-claude", body, image=f"localhost:5000/ax/ax-agent-claude-probe@{digest}")
    res = p["result"]
    assert res["claude_rc"] == 0 and re.search(r"\d+\.\d+\.\d+", res["claude_version"]), res
    assert res["curl_rc"] == 0 and "halogen-qwen3.8-flash-next" in res["models"], res
    assert p["kernel"] != host_kernel, (p["kernel"], host_kernel)
    new = worker.succeed("cat /var/lib/halogen-stub/requests.jsonl 2>/dev/null || true").splitlines()[stub_before:]
    assert any("/v1/models" in l for l in new), new
    nas.fail("pgrep -f '[r]unsc'")

with step("T4 egress-deny: a non-allowlisted target is refused by the Gateway"):
    worker.succeed("curl -s -o /dev/null --max-time 10 http://10.42.0.2/")
    t4 = fleet_run("t4-deny", curl_body("http://10.42.0.2/"))
    assert t4["result"]["http_code"] != "200", t4

with step("T4b egress-deny: the Gateway's host on another port is refused (the NAS enforces the port)"):
    nas.succeed("curl -sf --max-time 10 http://10.42.0.5:2222/ | grep -q worker-port-2222-reached")
    t4b = fleet_run("t4b-port", curl_body("http://10.42.0.5:2222/"))
    assert t4b["result"]["http_code"] != "200", t4b

with step("security: only root and apiUsers reach the ax API and the cluster ranges from the desk"):
    ax_pod = kubectl(
        "-n ax-system get pods -l app.kubernetes.io/name=ax-server -o jsonpath='{.items[0].status.podIP}'"
    ).strip()
    coordinator.succeed("runuser -u tom -- curl -sf --max-time 10 http://127.0.0.1:8099/healthz")
    coordinator.succeed("curl -sf --max-time 10 http://10.201.0.80:8080/healthz")
    for url in ("http://127.0.0.1:8099/healthz", "http://10.201.0.80:8080/healthz", f"http://{ax_pod}:8080/healthz"):
        coordinator.fail(f"runuser -u alice -- curl -s --max-time 5 -o /dev/null {url}")
    coordinator.fail("ss -ltn | grep -q '127.0.0.1:8080 '")
    record("api_owner_chain", coordinator.succeed("iptables -S ax-fleet-api").strip().splitlines())

with step("resilience: a restarted ax-redis keeps a held Task (AOF on the volume)"):
    fleet_task("held-a1", "sleep 600; echo '{}' >/tmp/result.json")
    coordinator.wait_until_succeeds(f"{AX} get task held-a1 >/dev/null", timeout=60)
    before = coordinator.succeed(f"{AX} get tasks | tail -n +2 | wc -l").strip()
    kubectl("-n ax-system delete pod -l app.kubernetes.io/name=ax-redis --wait=true")
    kubectl("-n ax-system rollout status deploy/ax-redis --timeout=300s")
    coordinator.wait_until_succeeds(f"{AX} get tasks >/dev/null", timeout=120)
    after = coordinator.succeed(f"{AX} get tasks | tail -n +2 | wc -l").strip()
    assert before == after and int(after) >= 1, f"tasks before={before} after={after}"
    record("resilience_redis_held_delete", delete_task("held-a1"))

with step("resilience: a restarted ax-controller, then a Task reports and is deleted"):
    kubectl("-n ax-system delete pod -l app.kubernetes.io/name=ax-controller --wait=true")
    kubectl("-n ax-system rollout status deploy/ax-controller --timeout=300s")
    r = fleet_run("after-ctl", curl_body(f"{STUB}/v1/models"))
    assert r["result"]["http_code"] == "200", r

with step("resilience: the LAN leg is down until the coordinator is NotReady; pods keep their names and uid, a new Task reports"):
    pods = lambda: kubectl(
        "-n ate-system get pods --field-selector spec.nodeName=coordinator -o name | grep ateom | sort"
    )
    before = pods()
    probe_uid = kubectl("get pod probe-coord -o jsonpath='{.metadata.uid}'").strip()
    flap_until_unreachable("ax")
    nas.wait_until_succeeds(
        "k3s kubectl get node coordinator -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -qx True",
        timeout=300,
    )
    nas.wait_until_succeeds(
        "! k3s kubectl get node coordinator -o jsonpath='{.spec.taints[*].key}' | grep -qw node.kubernetes.io/unreachable",
        timeout=300,
    )
    assert pods() == before, f"worker pods changed: {before!r}"
    kubectl("wait --for=condition=Ready pod/probe-coord --timeout=300s")
    assert kubectl("get pod probe-coord -o jsonpath='{.metadata.uid}'").strip() == probe_uid, "the probe pod was replaced by the flap"
    nas.wait_until_succeeds("curl -sf --max-time 5 http://10.42.0.2:18085/ | grep -x pod-ok", timeout=120)
    # Fix round 1 MEASURED that each stale gRPC connection left by an outage
    # costs one Task (ActorResumeFailed, Unavailable). The bound is a test
    # parameter: the fleet must recover within it without a restart.
    r = fleet_run("after-flap", curl_body(f"{STUB}/v1/models"), attempts=6)
    assert r["result"]["http_code"] == "200", r
