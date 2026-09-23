# Phase: the house LAN cannot reach the cluster ranges through the NAS, and
# the credential and RBAC surface is what fix round 1 left (2026-09-23). Runs
# after 30-ax, so ax-server, ax-redis and RustFS all exist. The worker is a
# plain LAN host; the NAS is its default gateway on the real LAN.


def tcp_open(ip, port):
    return f"timeout 5 bash -c 'exec 3<>/dev/tcp/{ip}/{port}'"


with step("lan: routed LAN traffic never reaches a ClusterIP or pod IP"):
    def svc_ip(ns, name):
        return jsonpath(f"-n {ns} svc {name}", "{.spec.clusterIP}")

    ax_ip = svc_ip("ax-system", "ax-server")
    redis_ip = svc_ip("ax-system", "ax-redis")
    rustfs_ip = svc_ip("ate-system", "rustfs")
    ax_pod = kubectl(
        "-n ax-system get pods -l app.kubernetes.io/name=ax-server -o jsonpath='{.items[0].status.podIP}'"
    ).strip()
    record("lan_probe_targets", {"ax": ax_ip, "redis": redis_ip, "rustfs": rustfs_ip, "ax_pod": ax_pod})

    # Positive controls from the NAS host (OUTPUT path, not prerouting): the
    # endpoints are up, so a failure from the worker is the guard.
    nas.succeed(f"curl -sf --max-time 10 http://{ax_ip}:8080/healthz")
    nas.succeed(tcp_open(redis_ip, 6379))
    nas.succeed(f"curl -s --max-time 10 -o /dev/null http://{rustfs_ip}:9000/")

    worker.succeed("ip route replace 10.200.0.0/16 via 10.42.0.1")
    worker.succeed("ip route replace 10.201.0.0/16 via 10.42.0.1")
    try:
        # curl without -f: rc 0 on ANY HTTP answer, so fail() means no answer.
        worker.fail(f"curl -s --max-time 5 -o /dev/null http://{ax_ip}:8080/healthz")
        worker.fail(f"curl -s --max-time 5 -o /dev/null http://{ax_pod}:8080/healthz")
        worker.fail(f"curl -s --max-time 5 -o /dev/null http://{rustfs_ip}:9000/")
        worker.fail(tcp_open(redis_ip, 6379))
        worker.fail("dig +time=2 +tries=1 @10.201.0.10 ax-server.ax-system.svc.cluster.local")
    finally:
        worker.succeed("ip route del 10.200.0.0/16 via 10.42.0.1")
        worker.succeed("ip route del 10.201.0.0/16 via 10.42.0.1")
    record("nas_range_guard", nas.succeed("nft list chain inet ax-fleet-guard prerouting").strip().splitlines())


with step("nas: pods reach Halogen on its port and no other private address"):
    # Fix round 3. The round-3 review MEASURED postgres-0 reaching worker:2222;
    # the NAS had no pod egress guard. Discriminating: the NAS host reaches
    # both targets.
    nas.succeed("curl -sf --max-time 10 http://10.42.0.5:2222/ | grep -q worker-port-2222-reached")
    nas.succeed("curl -sf --max-time 10 http://10.42.0.2/ | grep -x caddy-ok")
    kubectl("exec probe-nas -- curl -sf --max-time 10 http://10.42.0.5:8731/health")
    kubectl("exec probe-nas -- sh -c '! curl -s --max-time 5 -o /dev/null http://10.42.0.5:2222/'")
    kubectl("exec probe-nas -- sh -c '! curl -s --max-time 5 -o /dev/null http://10.42.0.2/'")
    record("nas_pod_egress", nas.succeed("nft list chain inet ax-fleet-guard forward").strip().splitlines())


with step("security: the registry is read-only to the coordinator; the seed wrote everything"):
    # Fix round 2. The round-2 review MEASURED 202 for an upload and 201 for a
    # tag overwrite from an unprivileged coordinator user.
    reg = "http://10.42.0.1:5000"
    alice = "runuser -u alice -- curl -s -o /dev/null -w '%{http_code}' --max-time 10"
    assert coordinator.succeed(f"{alice} {reg}/v2/_catalog").strip() == "200"
    codes = {
        "upload": coordinator.succeed(f"{alice} -X POST {reg}/v2/secprobe/blobs/uploads/").strip(),
        "mount": coordinator.succeed(f"{alice} -X POST '{reg}/v2/secprobe/blobs/uploads/?mount=sha256:0000000000000000000000000000000000000000000000000000000000000000&from=ax/ax-redis'").strip(),
        "delete": coordinator.succeed(f"{alice} -X DELETE {reg}/v2/ax/ax-redis/manifests/sha256:0000000000000000000000000000000000000000000000000000000000000000").strip(),
    }
    record("registry_write_codes", codes)
    assert all(c not in ("201", "202") for c in codes.values()), codes
    nas.fail("ss -ltn | grep -q '127.0.0.1:5001'")  # the seed's writer is gone
    nas.succeed("ss -ltn | grep -q '10.42.0.1:5000'")


with step("security: ax-controller holds no Secret grant and no API token"):
    nas.fail("k3s kubectl get clusterrole ax-controller")
    nas.fail("k3s kubectl get clusterrolebinding ax-controller")
    auto = jsonpath("-n ax-system deploy ax-controller", "{.spec.template.spec.automountServiceAccountToken}")
    assert auto == "false", auto
    vols = kubectl(
        "-n ax-system get pods -l app.kubernetes.io/name=ax-controller -o jsonpath='{.items[0].spec.volumes[*].name}'"
    ).split()
    record("ax_controller_volumes", vols)
    assert not any(v.startswith("kube-api-access") for v in vols), vols
    can = nas.succeed(
        "k3s kubectl auth can-i list secrets --all-namespaces --as=system:serviceaccount:ax-system:ax-controller || true"
    ).strip()
    assert can == "no", can


with step("security: RustFS and its clients read a generated credential, not the kind default"):
    nas.succeed("stat -c '%a %U' /var/lib/ax-fleet/rustfs.env | grep -x '600 root'")
    nas.succeed("k3s kubectl -n ate-system get secret ax-fleet-rustfs -o name")
    wanted = {"RUSTFS_ACCESS_KEY", "RUSTFS_SECRET_KEY", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"}
    seen = []
    # The bucket-init Job uses the credential too; fix round 1 first missed it
    # and it crash-looped (MEASURED), so it must complete here.
    kubectl("-n ate-system wait --for=condition=complete job/rustfs-bucket-init --timeout=300s")
    for obj in ("deploy rustfs", "deploy ate-api-server", "ds atelet", "job rustfs-bucket-init"):
        kind, name = obj.split()
        names = kubectl(f"-n ate-system get {kind} -o name").split()
        target = [n for n in names if n.split("/")[-1].startswith(name)]
        for t in target:
            doc = json.loads(kubectl(f"-n ate-system get {t} -o json"))
            for c in doc["spec"]["template"]["spec"]["containers"]:
                for e in c.get("env", []):
                    if e["name"] in wanted:
                        assert "value" not in e, f"{t} {e['name']} carries a literal value"
                        assert e["valueFrom"]["secretKeyRef"]["name"] == "ax-fleet-rustfs", (t, e["name"])
                        seen.append(f"{t}:{e['name']}")
    record("rustfs_credential_refs", sorted(seen))
    assert any(s.endswith("RUSTFS_SECRET_KEY") for s in seen), seen
    assert any(s.endswith("AWS_SECRET_ACCESS_KEY") for s in seen), seen
    assert any(s.startswith("job") and s.endswith("AWS_SECRET_ACCESS_KEY") for s in seen), seen
