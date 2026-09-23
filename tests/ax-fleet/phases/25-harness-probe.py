# Phase 25: the integration's harness probe (ax-fleet INTEGRATE.md). It runs
# after 10-cluster (both switches) and 20-substrate, before the T-cases of
# 30-ax, so its result is in the log even if a later case fails.
#
# One ax Task with spec.sandboxClass gvisor, run by `ax-fleet-smoke probe`
# (the script Tom runs on the real coordinator) in a test-only variant of the
# fleet task image that also carries claude-code. No credential exists in the
# image, the Task or the cluster. The Task runs `claude --version` and one GET
# of the worker's Halogen stand-in, must reach Completed with exit 0, and must
# stay Completed for PROBE_HOLD seconds, sampled every PROBE_EVERY seconds
# (four and more of P1's 15 s resync periods).
#
# There is no containerd RuntimeClass on this path: Substrate's ateom-gvisor
# worker pods run runsc themselves (DESIGN.md D2, 6.2). "gVisor" is proven from
# inside the Task: its /proc/version is not the coordinator VM's kernel.
import json
import re

PROBE_HOLD = 60
PROBE_EVERY = 5
PROBE_AX = "AX_SERVER=http://127.0.0.1:8099 ax -a fleet"
PROBE_STUB_LOG = "/var/lib/halogen-stub/requests.jsonl"


def probe_task_phase(name):
    # `ax get task NAME` prints YAML; status.phase is its only `phase:` key.
    out = coordinator.succeed(f"{PROBE_AX} get task {name}")
    m = re.search(r"^\s+phase:\s*(\S+)", out, re.M)
    assert m, f"no phase for {name}: {out!r}"
    return m.group(1).strip("\"'")


def probe_stub_lines():
    return worker.succeed(f"cat {PROBE_STUB_LOG} 2>/dev/null || true").splitlines()


with step("probe: k3s nodes Ready, Substrate healthy, ax-server and ax-controller up"):
    node_ready("nas")
    node_ready("coordinator")
    kubectl("-n ate-system wait --for=condition=Available deploy --all --timeout=600s")
    kubectl("-n ate-system rollout status statefulset/postgres --timeout=600s")
    nas.wait_until_succeeds(
        "test \"$(k3s kubectl -n ate-system get workerpool ateom-gvisor -o jsonpath='{.status.readyReplicas}')\" = 2",
        timeout=900,
    )
    for d in ("ax-redis", "ax-server", "ax-controller"):
        kubectl(f"-n ax-system rollout status deploy/{d} --timeout=600s")
    coordinator.wait_until_succeeds("curl -sf http://127.0.0.1:8099/healthz", timeout=300)
    record("probe_nodes", kubectl("get nodes -o wide").strip().splitlines())
    record("probe_ax_pods", kubectl("-n ax-system get pods -o wide").strip().splitlines())
    workers_wide = kubectl("-n ate-system get pods -l ax.mecattaf.dev/pool=ateom-gvisor -o wide")
    record("probe_worker_pods", workers_wide.strip().splitlines())
    worker_nodes = kubectl(
        "-n ate-system get pods -l ax.mecattaf.dev/pool=ateom-gvisor "
        "-o jsonpath='{range .items[*]}{.spec.nodeName}{\"\\n\"}{end}'"
    ).split()
    assert worker_nodes and all(n == "coordinator" for n in worker_nodes), worker_nodes


with step("probe: a gVisor ax Task on the coordinator runs claude --version and reaches Halogen, Completed and still Completed 60 s later"):
    digest = coordinator.succeed(f"cat {CLAUDE_PROBE_OCI}/digest").strip()
    assert digest.startswith("sha256:"), digest
    image = f"localhost:5000/ax/ax-agent-claude-probe@{digest}"
    stub_before = len(probe_stub_lines())
    host_kernel = coordinator.succeed("cat /proc/version").strip()

    rc, out = coordinator.execute(
        f"ax-fleet-smoke probe --image {image} --keep --timeout 1500 2>/tmp/probe-smoke.stderr",
        timeout=1800,
    )
    lines = [l for l in out.strip().splitlines() if l.startswith("{")]
    if not lines or rc != 0:
        _, err = coordinator.execute("tail -c 4000 /tmp/probe-smoke.stderr")
        _, tasks = coordinator.execute(f"{PROBE_AX} get tasks 2>&1 | tail -20")
        _, atelet = nas.execute("k3s kubectl -n ate-system logs -l app=atelet --all-containers --tail=80 2>&1")
        _, wp = nas.execute("k3s kubectl -n ate-system logs -l ax.mecattaf.dev/pool=ateom-gvisor --all-containers --tail=60 2>&1")
        _, ctl = nas.execute("k3s kubectl -n ax-system logs deploy/ax-controller --tail=80 2>&1")
        record("probe_diag", {"stderr": err[-4000:], "tasks": tasks[-3000:], "atelet": atelet[-6000:],
                              "workers": wp[-6000:], "controller": ctl[-6000:]})
    assert lines, f"ax-fleet-smoke probe printed no receipt (rc={rc}): {out!r}"
    r = json.loads(lines[-1])
    record("probe_receipt", r)
    assert rc == 0 and r.get("pass") is True, r
    name = r["task"]

    # Completed, and STAYS Completed: sample for PROBE_HOLD seconds.
    samples = []
    t_end = time.monotonic() + PROBE_HOLD
    while True:
        samples.append(probe_task_phase(name))
        if time.monotonic() >= t_end:
            break
        time.sleep(PROBE_EVERY)
    record("probe_phase_samples", {"hold_seconds": PROBE_HOLD, "every_seconds": PROBE_EVERY, "phases": samples})
    assert len(samples) >= PROBE_HOLD // PROBE_EVERY and all(p == "Completed" for p in samples), samples
    record("probe_task_yaml", coordinator.succeed(f"{PROBE_AX} get task {name}").strip().splitlines())

    res = r["result"]
    # claude-code answered inside the sandbox, with no credential anywhere.
    assert res["claude_rc"] == 0 and re.search(r"\d+\.\d+\.\d+", res["claude_version"]), res
    # The Halogen stand-in on the worker VM answered through the Gateway.
    assert res["curl_rc"] == 0 and res["http_code"] == "200", res
    assert res["model"] == "halogen-qwen3.8-flash-next", res
    # gVisor, not runc: a runc container would report the VM's own kernel.
    record("probe_kernels", {"sandbox": res["proc_version"], "coordinator_vm": host_kernel})
    assert res["proc_version"] and res["proc_version"] != host_kernel, (res["proc_version"], host_kernel)

    new = [json.loads(l) for l in probe_stub_lines()[stub_before:] if l.strip()]
    models = [q for q in new if q.get("path", "").rstrip("/") == "/v1/models"]
    record("probe_stub_requests", models)
    assert models, f"the Halogen stand-in logged no /v1/models request: {new!r}"

    # The image was pulled by atelet, which runs on the coordinator only.
    atelet_logs = kubectl("-n ate-system logs -l app=atelet --all-containers --tail=-1")
    hits = [
        l for l in atelet_logs.splitlines() if "ax-agent-claude-probe" in l or digest.split(":", 1)[1][:16] in l
    ]
    # Recorded, not asserted: the placement proof is the pool (every worker pod
    # on the coordinator, asserted in the first step) and the sandbox kernel above.
    record("probe_atelet_image_lines", hits[-5:])
    # '[r]unsc' so the pattern does not match the shell that runs pgrep.
    record("probe_runsc_processes", {
        "coordinator": coordinator.succeed("pgrep -c -f '[r]unsc' || true").strip(),
        "nas": nas.succeed("pgrep -c -f '[r]unsc' || true").strip(),
    })
    nas.fail("pgrep -f '[r]unsc'")

    coordinator.succeed(f"{PROBE_AX} delete task {name}")
