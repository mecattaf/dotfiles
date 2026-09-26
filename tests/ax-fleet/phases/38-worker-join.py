# Phase: the worker joins the cluster as the tainted inference agent
# (2026-09-25, Tom: "the amd strix halo worker SHOULD be available in the
# cluster (not just halogen inference)"). Track cluster. Runs after
# 35-lan-guard: until here the worker is the plain LAN host whose routed
# probes must fail, and once it is a node its host reaches pod IPs through
# flannel.1 legitimately. Switched last, as Tom will: the NAS admits it, the
# coordinator accepts its VXLAN (modules/ax-fleet/agent.nix).
#
# Asserted: Ready with the inference taint and both labels; nothing that runs
# today lands on it, even rescheduled; the WorkerPool stays on the
# coordinator; a pod that tolerates the taint runs there, reaches pods on
# both other nodes over VXLAN in both directions, and reaches neither the
# worker's sshd nor its other ports; non-root on the worker gets no
# ClusterIP; the Halogen stub keeps serving the NAS's egress, never
# restarted.
#
# Uses node_ready, kubectl, jsonpath, sysctls, kernel_keys_back,
# unit_invocation (prelude), and diag, AX_ON and `base` (10-cluster).

PROBE_WORKER = """
apiVersion: v1
kind: Pod
metadata:
  name: probe-worker
  namespace: default
  labels: {app: ax-fleet-probe}
spec:
  nodeSelector: {ax.mecattaf.dev/role: inference}
  tolerations:
    - {key: ax.mecattaf.dev/role, operator: Equal, value: inference, effect: NoSchedule}
  containers:
    - name: probe
      image: ax-fleet-probe:test
      imagePullPolicy: Never
      command: ["/bin/sh", "-c", "echo probe-started-probe-worker; mkdir -p /www; echo pod-ok > /www/index.html; exec httpd -f -p 8000 -h /www"]
      ports:
        - {containerPort: 8000, hostPort: 18087}
"""

PODS_BY_NODE = "get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.nodeName}{\"\\n\"}{end}'"


def pods_on(node):
    out = kubectl(PODS_BY_NODE).strip().splitlines()
    return sorted(l.split()[0] for l in out if len(l.split()) == 2 and l.split()[1] == node)


def stub_requests():
    lines = worker.succeed("cat /var/lib/halogen-stub/requests.jsonl 2>/dev/null || true").splitlines()
    return [json.loads(l) for l in lines if l.strip()]


with step("worker: baseline before the join"):
    worker.fail("systemctl cat k3s.service")
    worker.succeed("test -e /etc/ax-fleet/guard-declared")
    worker.succeed("grep -x inference /etc/ax-fleet/guard-declared")
    base["sysctl_worker"] = sysctls(worker)
    base["halogen_invocation"] = unit_invocation(worker, "halogen-stub.service")
    record("baseline_worker", {"sysctl": base["sysctl_worker"], "halogen_invocation": base["halogen_invocation"]})


with step("switch worker"):
    worker.succeed(f"{AX_ON} >&2")
    worker.succeed("systemctl is-active k3s.service")
    node_ready("worker")
    # The switch never restarted Halogen.
    assert unit_invocation(worker, "halogen-stub.service") == base["halogen_invocation"], "the Halogen stand-in restarted"
    worker.wait_for_open_port(8731)


with step("worker: Ready with the inference taint and labels"):
    taints = json.loads(kubectl("get node worker -o jsonpath='{.spec.taints}'"))
    record("worker_taints", taints)
    assert {"key": "ax.mecattaf.dev/role", "value": "inference", "effect": "NoSchedule"} in taints, taints
    labels = json.loads(kubectl("get node worker -o jsonpath='{.metadata.labels}'"))
    assert labels.get("ax.mecattaf.dev/role") == "inference", labels
    assert labels.get("ate.dev/substrate-version") == "none", labels
    ip = jsonpath("node worker", "{.status.addresses[?(@.type==\"InternalIP\")].address}")
    assert ip == "10.42.0.5", ip
    worker.wait_until_succeeds("ip -d link show flannel.1 | grep -q 'dev eth1'", timeout=180)
    record("worker_allocatable", json.loads(kubectl("get node worker -o jsonpath='{.status.allocatable}'")))
    record("sysctl_worker_after_switch", sysctls(worker))
    kernel_keys_back(worker, base["sysctl_worker"])
    worker.succeed("systemctl is-active ax-fleet-kernel-tunables.service")
    worker.succeed("test -s /var/lib/ax-fleet/sysctl-before.conf")


with step("worker: nothing that runs today lands there, even rescheduled"):
    # Discriminating: CoreDNS tolerates only the control-plane and
    # CriticalAddonsOnly keys, and the worker is the emptiest node, so an
    # untainted worker would take the rescheduled pod.
    kubectl("-n kube-system rollout restart deploy/coredns")
    kubectl("-n kube-system rollout status deploy/coredns --timeout=300s")
    placed = kubectl(PODS_BY_NODE).strip().splitlines()
    record("pod_placement_after_worker_join", placed)
    assert pods_on("worker") == [], pods_on("worker")
    coredns = kubectl("-n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[*].spec.nodeName}'").split()
    assert coredns and all(n == "nas" for n in coredns), coredns
    # The WorkerPool stays on the harness node.
    wp_nodes = kubectl(
        "-n ate-system get pods -l ax.mecattaf.dev/pool=ateom-gvisor -o jsonpath='{.items[*].spec.nodeName}'"
    ).split()
    record("workerpool_nodes_after_worker_join", wp_nodes)
    assert wp_nodes and all(n == "coordinator" for n in wp_nodes), wp_nodes
    atelet_nodes = kubectl(
        "-n ate-system get pods -o jsonpath='{range .items[*]}{.metadata.name} {.spec.nodeName}{\"\\n\"}{end}'"
    ).strip().splitlines()
    assert all(l.split()[1] == "coordinator" for l in atelet_nodes if l.startswith("atelet") and len(l.split()) == 2), atelet_nodes


with step("worker: a pod that tolerates the taint runs there"):
    nas.succeed(f"cat > /tmp/probe-worker.yaml <<'EOF'\n{PROBE_WORKER}\nEOF")
    kubectl("apply -f /tmp/probe-worker.yaml")
    kubectl("wait --for=condition=Ready pod/probe-worker --timeout=300s")
    assert jsonpath("pod probe-worker", "{.spec.nodeName}") == "worker"
    assert pods_on("worker") == ["default/probe-worker"], pods_on("worker")
    kubectl("logs probe-worker | grep -q probe-started-probe-worker")


with step("worker: pod to pod across all three nodes (flannel VXLAN, both directions)"):
    w_ip = jsonpath("pod probe-worker", "{.status.podIP}")
    c_ip = jsonpath("pod probe-coord", "{.status.podIP}")
    n_ip = jsonpath("pod probe-nas", "{.status.podIP}")
    record("vxlan_probe_ips", {"worker": w_ip, "coordinator": c_ip, "nas": n_ip})
    paths = {
        "worker->coordinator": ("probe-worker", c_ip),
        "coordinator->worker": ("probe-coord", w_ip),
        "worker->nas": ("probe-worker", n_ip),
        "nas->worker": ("probe-nas", w_ip),
    }
    for label, (src, dst) in paths.items():
        status, _ = nas.execute(f"k3s kubectl exec {src} -- curl -sf --max-time 10 http://{dst}:8000/")
        if status != 0:
            record(f"diag_vxlan_{label}", diag({
                "worker_fw": (worker, "iptables -S nixos-fw | grep -E '8472|pod-input'; iptables -t mangle -S ax-fleet-guard"),
                "coord_fw": (coordinator, "iptables -S nixos-fw | grep -E '8472|pod-input'"),
                "nas_input": (nas, "nft list chain inet nixos-fw input-allow"),
                "worker_fdb": (worker, "bridge fdb show dev flannel.1; ip route"),
            }))
        kubectl(f"exec {src} -- curl -sf --max-time 10 http://{dst}:8000/ | grep -x pod-ok")


with step("worker: hostPorts from the NAS host only"):
    nas.succeed("curl -sf --max-time 10 http://10.42.0.5:18087/ | grep -x pod-ok")
    coordinator.fail("curl -sf --max-time 5 http://10.42.0.5:18087/")


with step("worker: its pods never reach the worker host (sshd, 2222), the LAN, or anything but the NAS's API and registry"):
    # Discriminating: sshd and :2222 answer the worker itself and the NAS.
    worker.succeed("timeout 10 bash -c 'exec 3<>/dev/tcp/10.42.0.5/22; head -c 7 <&3' | grep -x SSH-2.0")
    nas.succeed("timeout 10 bash -c 'exec 3<>/dev/tcp/10.42.0.5/22; head -c 7 <&3' | grep -x SSH-2.0")
    nas.succeed("curl -sf --max-time 10 http://10.42.0.5:2222/ | grep -q worker-port-2222-reached")
    w_cni0 = worker.succeed("ip -4 -o addr show dev cni0 | awk '{print $4}' | cut -d/ -f1").strip()
    w_flannel = worker.succeed("ip -4 -o addr show dev flannel.1 | awk '{print $4}' | cut -d/ -f1").strip()
    record("worker_pod_input_targets", {"cni0": w_cni0, "flannel.1": w_flannel})
    for ip in ("10.42.0.5", w_cni0, w_flannel):
        kubectl(f"exec probe-worker -- sh -c '! (nc -w 5 {ip} 22 </dev/null 2>/dev/null | grep -q SSH)'")
        kubectl(f"exec probe-worker -- sh -c '! curl -s --max-time 5 -o /dev/null http://{ip}:2222/'")
    # Over VXLAN, from the NAS's pod, neither.
    kubectl(f"exec probe-nas -- sh -c '! (nc -w 5 {w_flannel} 22 </dev/null 2>/dev/null | grep -q SSH)'")
    refused = worker.succeed("iptables -S nixos-fw | grep -c ax-fleet-pod-input").strip()
    assert refused == "2", refused
    # Egress: the coordinator host's Caddy (the worker host reaches it) is a
    # private LAN address; the NAS's apiserver and registry are allowed.
    worker.succeed("curl -sf --max-time 10 http://10.42.0.2/ | grep -x caddy-ok")
    kubectl("exec probe-worker -- sh -c '! curl -s --max-time 5 -o /dev/null http://10.42.0.2/'")
    code = kubectl("exec probe-worker -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://10.42.0.1:5000/v2/").strip()
    assert code == "200", f"registry from a worker pod: {code}"
    code = kubectl("exec probe-worker -- curl -sk -o /dev/null -w '%{http_code}' --max-time 10 https://10.201.0.1/readyz").strip()
    assert code != "000", "a worker pod cannot reach the apiserver Service"
    # Recorded, not asserted (an open question for Tom): a worker pod reaching
    # the local Halogen port directly. The pod-input refusal covers it.
    rc, _ = nas.execute("k3s kubectl exec probe-worker -- curl -s --max-time 5 -o /dev/null http://10.42.0.5:8731/health")
    record("worker_pod_reaches_local_halogen", rc == 0)
    record("worker_guard_chain", worker.succeed("iptables -t mangle -S ax-fleet-guard").strip().splitlines())


with step("worker: the cluster ranges from the worker host, root and apiUsers only"):
    ax_ip = jsonpath("-n ax-system svc ax-server", "{.spec.clusterIP}")
    ax_pod = kubectl(
        "-n ax-system get pods -l app.kubernetes.io/name=ax-server -o jsonpath='{.items[0].status.podIP}'"
    ).strip()
    # Discriminating: kube-proxy runs here now, so root gets through.
    worker.succeed(f"curl -sf --max-time 10 http://{ax_ip}:8080/healthz")
    for url in (f"http://{ax_ip}:8080/healthz", f"http://{ax_pod}:8080/healthz"):
        worker.fail(f"runuser -u nobody -- curl -s --max-time 5 -o /dev/null {url}")
    worker.succeed("iptables -S OUTPUT 1 | grep -q ax-fleet-api")
    worker.fail("iptables -S ax-fleet-api | grep -q ax-server-proxy")
    record("worker_api_owner_chain", worker.succeed("iptables -S ax-fleet-api").strip().splitlines())


with step("worker: Halogen still serves the NAS's egress, and outweighs kubepods for CPU"):
    before = len(stub_requests())
    kubectl("exec probe-nas -- curl -sf --max-time 10 http://10.42.0.5:8731/health")
    new = stub_requests()[before:]
    record("halogen_stub_after_join", new)
    assert any(r.get("src") == "10.42.0.1" for r in new), new
    assert unit_invocation(worker, "halogen-stub.service") == base["halogen_invocation"], "the Halogen stand-in restarted"
    w = worker.succeed("systemctl show machine.slice -p CPUWeight --value").strip()
    assert w == "10000", w
    line = worker.succeed(
        "journalctl -u k3s --no-pager -o cat | grep -o 'HardEvictionThresholds.*' | tail -n1 | cut -c1-2000"
    )
    signals = sorted(set(re.findall(r'"Signal":"([a-z.A-Z]+)"', line)))
    record("worker_hard_eviction_signals", signals)
    for s in ("memory.available", "nodefs.available", "nodefs.inodesFree", "imagefs.available"):
        assert s in signals, (s, signals)
