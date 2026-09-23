# Phase 4 (Tasks) and phase 5 (resilience) of checks.x86_64-linux.ax-fleet.
# Track ax; DESIGN.md section 12.1. Concatenated after 10-cluster and
# 20-substrate by tests/ax-fleet/default.nix, so `nas`, `coordinator` and
# `worker` are the test nodes and the cluster, Substrate and the WorkerPool are
# already up. Every Task runs through ax-fleet-smoke, the script Tom runs on the
# real coordinator after the switch.
import json
import re


def ax_smoke(case, *args, expect_pass=True):
    cmd = "ax-fleet-smoke " + " ".join([case, *map(str, args)])
    rc, out = coordinator.execute(cmd + " 2>/dev/null")
    lines = [l for l in out.strip().splitlines() if l.startswith("{")]
    assert lines, f"{cmd}: no receipt (rc={rc}): {out!r}"
    receipt = json.loads(lines[-1])
    print(f"RECEIPT {cmd}: {json.dumps(receipt)}")
    if expect_pass:
        assert rc == 0 and receipt.get("pass") is True, f"{cmd} failed: {receipt}"
    return receipt


def kubectl(args):
    return nas.succeed(f"k3s kubectl {args}")


AX = "AX_SERVER=http://127.0.0.1:8080 ax -a fleet"


def task_phase(name):
    # `ax get task NAME` prints the Task as YAML; status.phase is its only
    # `phase:` key.
    out = coordinator.succeed(f"{AX} get task {name}")
    m = re.search(r"^\s+phase:\s*(\S+)", out, re.M)
    assert m, f"no phase for {name}: {out!r}"
    return m.group(1).strip("\"'")


with subtest("ax control plane is Available on the NAS, nowhere else"):
    for d in ["ax-redis", "ax-server", "ax-controller"]:
        kubectl(f"-n ax-system rollout status deploy/{d} --timeout=600s")
        node = kubectl(
            f"-n ax-system get pods -l app.kubernetes.io/name={d} -o jsonpath='{{.items[0].spec.nodeName}}'"
        ).strip()
        assert node == "nas", f"{d} runs on {node}"
    pv = kubectl(
        "get pv -o jsonpath='{range .items[?(@.spec.claimRef.name==\"ax-redis-data\")]}{.spec.local.path}{.spec.hostPath.path}{end}'"
    )
    assert pv.startswith("/mnt/nas/services/ax-fleet/local-path"), f"ax-redis volume at {pv!r}"
    coordinator.wait_until_succeeds("curl -sf http://127.0.0.1:8080/healthz", timeout=300)
    # No Claude credential, and no secret, in any ax object.
    kubectl("-n ax-system get secrets -o name | (! grep -q .)")

with subtest("T1 halogen: Completed, and still Completed after the hold"):
    t1 = ax_smoke("halogen", "--hold", 90, "--keep")
    assert t1["exit_code"] == 0 and t1["phase_after_hold"] == "Completed", t1
    # The golden-snapshot double execution judge 2 inferred: record, do not fail.
    rc, count = worker.execute("curl -sf http://127.0.0.1:8731/stub/requests")
    print(f"RECEIPT halogen stub requests after T1: rc={rc} {count.strip()!r}")

with subtest("T2 pi: Completed with a schema-valid result read back through P1"):
    t2 = ax_smoke("pi", "--hold", 30)
    assert t2["result"]["valid"] is True, t2
    assert t2["result_bytes"] and t2["result_sha256"], t2

with subtest("T3 exit 3: Failed with ExitCode=3"):
    t3 = ax_smoke("exit", 3, "--hold", 30)
    assert t3["phase"] == "Failed" and t3["ready"]["message"].startswith("ExitCode=3"), t3

with subtest("T4 egress-deny: a non-allowlisted target is refused by the Gateway"):
    # The coordinator's LAN address answers the worker in this run (checked
    # first), so a failure inside the sandbox is the Gateway's refusal.
    worker.succeed("curl -s -o /dev/null --max-time 10 http://10.42.0.2/")
    t4 = ax_smoke("egress-deny", "http://10.42.0.2/")
    assert t4["phase"] == "Failed", t4

with subtest("T5 floor 4: four Tasks in a row on the 2-worker pool, none ResourceExhausted"):
    t5 = ax_smoke("floor", 4)
    for t in t5["tasks"]:
        assert t["phase"] == "Completed", t
        occupancy = kubectl(
            "-n ate-system get pods --field-selector spec.nodeName=coordinator -o name | grep -c ateom || true"
        ).strip()
        print(f"RECEIPT worker pods on coordinator after {t['task']}: {occupancy}")

t1_name = t1["task"]

with subtest("resilience: a restarted ax-controller leaves a finished Task Completed"):
    kubectl("-n ax-system delete pod -l app.kubernetes.io/name=ax-controller --wait=true")
    kubectl("-n ax-system rollout status deploy/ax-controller --timeout=300s")
    coordinator.sleep(45)  # three resync periods
    assert task_phase(t1_name) == "Completed"

with subtest("resilience: a restarted ax-redis keeps every Task (AOF on the volume)"):
    before = coordinator.succeed(f"{AX} get tasks | tail -n +2 | wc -l").strip()
    kubectl("-n ax-system delete pod -l app.kubernetes.io/name=ax-redis --wait=true")
    kubectl("-n ax-system rollout status deploy/ax-redis --timeout=300s")
    coordinator.wait_until_succeeds(f"{AX} get tasks >/dev/null", timeout=120)
    after = coordinator.succeed(f"{AX} get tasks | tail -n +2 | wc -l").strip()
    assert before == after and int(after) >= 1, f"tasks before={before} after={after}"
    assert task_phase(t1_name) == "Completed"

with subtest("resilience: the LAN leg flaps, worker pods keep their names, a new T1 completes"):
    pods = lambda: kubectl(
        "-n ate-system get pods --field-selector spec.nodeName=coordinator -o name | grep ateom | sort"
    )
    before = pods()
    coordinator.succeed("ip link set eth1 down")
    coordinator.sleep(20)
    coordinator.succeed("ip link set eth1 up")
    nas.wait_until_succeeds(
        "k3s kubectl get node coordinator -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -qx True",
        timeout=300,
    )
    assert pods() == before, f"worker pods changed: {before!r}"
    ax_smoke("halogen")

coordinator.succeed(f"{AX} delete task {t1_name}")
