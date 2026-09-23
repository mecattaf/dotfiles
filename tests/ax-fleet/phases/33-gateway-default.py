# Phase 33: egress without a gateway lands behind the atespace's default
# Gateway (modules/ax-fleet/gateways.nix). Stock ax v0.3.0 gives such a Task
# allow-all; the fleet closes it without an ax patch: the bootstrap declared a
# default Gateway (Halogen and the floor only) and ax-fleet-gateway-default
# points the Task at it. Discriminating: the NAS host reaches the public
# stand-in (TEST-NET-2 on the worker, fix round 4), and a Gateway that
# allowlists it gets its 200 through the same egress path.
import re

PUBLIC = "http://198.51.100.5:8000/"


def task_gateway(name: str) -> Any:
    rc, out = ax(f"get task {name}")
    if rc != 0:
        return None
    m = re.search(r"gateway:\s*\n\s+name:\s*(\S+)", out)
    return m.group(1).strip("\"'") if m else ""


def late_curl_body(url: str, wait: int) -> str:
    # Waits WAIT seconds first: the repoint is asynchronous by design.
    return f"sleep {wait}\n" + curl_body(url)


with step("gateways: the bootstrap declared a default Gateway in every declared atespace"):
    for ns in ("fleet", "default"):
        coordinator.succeed(f"AX_SERVER=http://127.0.0.1:8099 ax -a {ns} get gateway default")
    nas.succeed("systemctl is-active ax-fleet-gateway-default.service")
    record("gateway_default_unit", nas.succeed("systemctl show ax-fleet-gateway-default -p ExecStart --value").strip())

with step("gateways: a Task without a gateway, or naming a missing one, is pointed at the default and cannot reach the public stand-in"):
    worker.wait_for_unit("public-8000.service")
    nas.wait_until_succeeds(f"curl -sf --max-time 10 {PUBLIC} | grep -q public-reached", timeout=120)
    results = {}
    for label, gw in (("none", None), ("missing", "no-such-gateway")):
        name = f"gwdef-{label}"
        n = f"{name}-a1"
        t0 = time.monotonic()
        fleet_task(n, late_curl_body(PUBLIC, 30), gateway=gw)
        coordinator.wait_until_succeeds(
            f"{AX} get task {n} | grep -A1 -E '^\\s+gateway:' | grep -qE 'name:\\s*\"?default\"?'", timeout=120
        )
        repoint_s = round(time.monotonic() - t0, 1)
        reps, before, secs = wait_report(n)
        assert reps, f"{n}: no floor report (the default Gateway allows the floor): {before}"
        rep = reps[0]["report"]
        res = json.loads(base64.b64decode(rep["result_b64"]) or b"{}")
        results[label] = {"repoint_seconds": repoint_s, "report_seconds": secs, "result": res, "state": before}
        record("gateway_default_repoint", results)
        assert task_gateway(n) == "default", n
        assert res.get("http_code") != "200", (label, res)
        delete_task(n)

with step("gateways: positive control, a Gateway allowlisting the public stand-in reaches it"):
    coordinator.succeed(
        "AX_SERVER=http://127.0.0.1:8099 ax -a fleet apply -f - <<'EOF'\n"
        "apiVersion: ax.io/v1alpha1\nkind: Gateway\nmetadata:\n  name: public-test\n  atespace: fleet\n"
        "spec:\n  egress:\n    allowlist:\n      hosts:\n"
        "        - host: \"198.51.100.5/32\"\n          port: 8000\n"
        "        - host: \"10.42.0.5/32\"\n          port: 8731\n"
        "EOF"
    )
    ok = fleet_run("gw-public", curl_body(PUBLIC), gateway="public-test")
    record("gateway_public_positive_control", ok["result"])
    assert ok["result"]["http_code"] == "200", ok
    assert task_gateway("gw-public-a1") in (None, "public-test")
    coordinator.execute("AX_SERVER=http://127.0.0.1:8099 ax -a fleet delete gateway public-test")
