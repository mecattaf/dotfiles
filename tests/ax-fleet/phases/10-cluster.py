# Phase 1 (baseline), 2 and 3 (switch nas, then coordinator): the cluster
# assertions. Track cluster. DESIGN.md 12.1 and 6.6. The substrate and ax
# phases (20, 30) run after this one, on the cluster it leaves behind.

AX_ON = "/run/current-system/specialisation/ax-on/bin/switch-to-configuration test"

PROBE_POD = """
apiVersion: v1
kind: Pod
metadata:
  name: {name}
  namespace: default
  labels: {{app: ax-fleet-probe}}
spec:
  nodeSelector: {{ax.mecattaf.dev/role: {role}}}
  tolerations:
    - {{key: ate.dev/sandboxClass, operator: Exists, effect: NoSchedule}}
  containers:
    - name: probe
      image: ax-fleet-probe:test
      imagePullPolicy: Never
      command: ["/bin/sh", "-c", "echo probe-started-{name}; mkdir -p /www; echo pod-ok > /www/index.html; exec httpd -f -p 8000 -h /www"]
      ports:
        - {{containerPort: 8000, hostPort: {host_port}}}
      {volume_mounts}
  {volumes}
"""


def apply_probe(name, role, host_port, pvc=None):
    vm = "volumeMounts: [{name: data, mountPath: /data}]" if pvc else ""
    vols = f"volumes: [{{name: data, persistentVolumeClaim: {{claimName: {pvc}}}}}]" if pvc else ""
    doc = PROBE_POD.format(name=name, role=role, host_port=host_port, volume_mounts=vm, volumes=vols)
    nas.succeed(f"cat > /tmp/{name}.yaml <<'EOF'\n{doc}\nEOF")
    kubectl(f"apply -f /tmp/{name}.yaml")
    kubectl(f"wait --for=condition=Ready pod/{name} --timeout=300s")


with step("baseline"):
    start_all()
    for m in (nas, coordinator, worker, peer):
        m.wait_for_unit("multi-user.target")
    coordinator.wait_for_unit("caddy.service")
    coordinator.wait_for_unit("NetworkManager.service")
    nas.wait_for_unit("postgresql.service")
    nas.wait_for_unit("dnsmasq.service")
    worker.wait_for_unit("halogen-stub.service")
    worker.wait_for_open_port(8731)
    coordinator.wait_until_succeeds(
        "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/$(id -u alice) systemctl --user is-active herdr-standin"
    )
    worker.succeed("curl -sf --max-time 10 http://10.42.0.2/ | grep -x caddy-ok")
    peer.succeed("curl -sf --max-time 10 http://100.105.121.73/ | grep -x caddy-ok")
    # Not a k3s node, never switched: nothing from the fleet module runs here.
    worker.fail("systemctl cat k3s.service")
    nas.fail("systemctl cat k3s.service")
    coordinator.fail("systemctl cat k3s.service")

    base = {
        "herdr_pid": user_unit_pid("herdr-standin"),
        "nm_invocation": nm_invocation(),
        "postgres_invocation": unit_invocation(nas, "postgresql.service"),
        "nas_databases": sorted(nas.succeed("runuser -u postgres -- psql -Atc 'select datname from pg_database'").split()),
        "nas_nft": nas.succeed("nft -s list ruleset"),
        "nas_nixos_fw": nas.succeed("nft -s list table inet nixos-fw"),
        "sysctl_nas": sysctls(nas),
        "sysctl_coordinator": sysctls(coordinator),
    }
    record("baseline", {k: v for k, v in base.items() if k not in ("nas_nft", "nas_nixos_fw")})


with step("switch nas"):
    nas.succeed(f"{AX_ON} >&2")
    nas.succeed("systemctl is-active k3s.service docker-registry.service")
    for u in ("ax-fleet-registry-seed.service", "ax-fleet-bootstrap.service"):
        nas.succeed(f"systemctl is-active {u}")
        nas.succeed(f"systemctl show {u} -p Result --value | grep -x success")


with step("nas: k3s state on the fast tier, links on that disk"):
    src = nas.succeed("findmnt -n -o SOURCE -T /var/lib/rancher/k3s").strip()
    record("nas_rancher_source", src)
    assert src.startswith("/dev/vdb"), f"/var/lib/rancher/k3s is on {src}, not the /mnt/fast disk"
    for p in ("/var/lib/kubelet", "/var/log/pods"):
        s = nas.succeed(f"findmnt -n -o SOURCE -T {p}").strip()
        assert s.startswith("/dev/vdb"), f"{p} is on {s}"
    # The airgap images link lives under the bind mount, i.e. on /mnt/fast.
    nas.succeed("ls -l /var/lib/rancher/k3s/agent/images/ | grep -q airgap")
    nas.succeed("ls -l /mnt/fast/k3s/rancher/k3s/agent/images/ | grep -q airgap")
    nas.succeed("test -s /etc/ax-fleet/admin.kubeconfig")
    nas.succeed("stat -c '%a %U %G' /etc/ax-fleet/admin.kubeconfig | grep -x '640 root wheel'")
    nas.succeed("grep -q 'server: https://10.42.0.1:6443' /etc/ax-fleet/admin.kubeconfig")
    nas.succeed("test -s /var/lib/ax-fleet/sysctl-before.conf")


with step("nas: node Ready, untainted, control labels"):
    node_ready("nas")
    assert jsonpath("node nas", "{.spec.taints}") == "", "the NAS must be untainted"
    labels = json.loads(kubectl("get node nas -o jsonpath='{.metadata.labels}'"))
    assert labels.get("ax.mecattaf.dev/role") == "control", labels
    assert labels.get("ate.dev/substrate-version") == "none", labels
    ip = jsonpath("node nas", "{.status.addresses[?(@.type==\"InternalIP\")].address}")
    assert ip == "10.42.0.1", ip
    kubectl("-n kube-system wait --for=condition=Available deploy/coredns deploy/local-path-provisioner --timeout=600s")


with step("nas: certificates.k8s.io/v1beta1 serves the Substrate resources"):
    res = json.loads(kubectl("get --raw /apis/certificates.k8s.io/v1beta1"))
    names = sorted(r["name"] for r in res["resources"])
    record("certificates_v1beta1", names)
    assert "clustertrustbundles" in names and "podcertificaterequests" in names, names


with step("nas: PersistentVolumes land on the data pool"):
    nas.succeed(
        "cat > /tmp/pvc.yaml <<'EOF'\n"
        "apiVersion: v1\nkind: PersistentVolumeClaim\nmetadata: {name: ax-fleet-probe-pvc, namespace: default}\n"
        "spec: {accessModes: [ReadWriteOnce], storageClassName: local-path, resources: {requests: {storage: 16Mi}}}\n"
        "EOF"
    )
    kubectl("apply -f /tmp/pvc.yaml")
    apply_probe("probe-nas", "control", 18086, pvc="ax-fleet-probe-pvc")
    kubectl("exec probe-nas -- sh -c 'echo data-pool > /data/marker'")
    paths = kubectl(
        "get pv -o jsonpath='{range .items[*]}{.spec.hostPath.path}{.spec.local.path}{\"\\n\"}{end}'"
    ).split()
    record("pv_paths", paths)
    assert paths and all(p.startswith(LOCAL_PATH_ROOT) for p in paths), paths
    nas.succeed(f"grep -rqx data-pool {LOCAL_PATH_ROOT}")
    src = nas.succeed(f"findmnt -n -o SOURCE -T {LOCAL_PATH_ROOT}").strip()
    assert src.startswith("/dev/vdc"), f"local-path root is on {src}, not the data pool"


with step("nas: bystanders untouched"):
    assert unit_invocation(nas, "postgresql.service") == base["postgres_invocation"], "the shared PostgreSQL restarted"
    dbs = sorted(nas.succeed("runuser -u postgres -- psql -Atc 'select datname from pg_database'").split())
    assert dbs == base["nas_databases"], (dbs, base["nas_databases"])
    nas.succeed("dig +short @10.42.0.1 only-nas.test | grep -x 10.42.0.77")
    ruleset = nas.succeed("nft list ruleset")
    record("nas_kube_services_in_nft", "KUBE-SERVICES" in ruleset)
    record("sysctl_nas_after_switch", sysctls(nas))


with step("switch coordinator"):
    coordinator.succeed(f"{AX_ON} >&2")
    coordinator.succeed("systemctl is-active k3s.service ax-fleet-nm-unmanaged.service ax-server-proxy.socket")
    node_ready("coordinator")


with step("coordinator: Ready with the harness taint and labels"):
    taints = json.loads(kubectl("get node coordinator -o jsonpath='{.spec.taints}'"))
    assert {"key": "ate.dev/sandboxClass", "value": "gvisor", "effect": "NoSchedule"} in taints, taints
    labels = json.loads(kubectl("get node coordinator -o jsonpath='{.metadata.labels}'"))
    assert labels.get("ax.mecattaf.dev/role") == "harness", labels
    assert labels.get("ate.dev/substrate-version") == "d277088b", labels
    ip = jsonpath("node coordinator", "{.status.addresses[?(@.type==\"InternalIP\")].address}")
    assert ip == "10.42.0.2", ip
    coordinator.succeed("ip -d link show flannel.1 | grep -q 'dev eth1'")
    record("sysctl_coordinator_after_switch", sysctls(coordinator))


with step("coordinator: only tolerating pods land here; control stays on the NAS"):
    apply_probe("probe-coord", "harness", 18085)
    placed = kubectl(
        "get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.nodeName}{\"\\n\"}{end}'"
    )
    record("pod_placement", placed.strip().splitlines())
    for line in placed.strip().splitlines():
        name, node = line.split()
        if node == "coordinator":
            assert (
                name == "default/probe-coord" or "/atelet" in name or "/ateom-gvisor" in name
            ), f"{name} landed on the coordinator"
    # kubectl logs of a coordinator pod rides the agent tunnel (egress-selector agent).
    kubectl("logs probe-coord | grep -q probe-started-probe-coord")


with step("coordinator: nothing changed for Tom"):
    assert user_unit_pid("herdr-standin") == base["herdr_pid"], "herdr stand-in restarted"
    assert nm_invocation() == base["nm_invocation"], "NetworkManager restarted"
    coordinator.wait_until_succeeds("nmcli -t -f DEVICE,STATE d | grep -x 'cni0:unmanaged'", timeout=60)
    coordinator.succeed("nmcli -t -f DEVICE,STATE d | grep -x 'flannel.1:unmanaged'")
    record("nmcli_devices", coordinator.succeed("nmcli -t -f DEVICE,STATE d").strip().splitlines())
    worker.succeed("curl -sf --max-time 10 http://10.42.0.2/ | grep -x caddy-ok")
    peer.succeed("curl -sf --max-time 10 http://100.105.121.73/ | grep -x caddy-ok")
    # A podman container on the default bridge still reaches the host's Caddy
    # (br_netfilter is loaded now, rpfilter is strict).
    loaded = coordinator.succeed(f"podman load -i {PROBE_TARBALL}")
    ref = [l.split("Loaded image:")[1].strip() for l in loaded.splitlines() if "Loaded image" in l][0]
    coordinator.succeed(f"podman run --rm --network bridge {ref} curl -sf --max-time 10 http://10.88.0.1/ | grep -x caddy-ok")
    coordinator.succeed("lsmod | grep -q br_netfilter")


with step("coordinator: the guards hold"):
    pod_ip = jsonpath("pod probe-coord", "{.status.podIP}")
    record("probe_coord_ip", pod_ip)
    # Make the negative tests discriminating: the peer routes the LAN and the
    # pod network through the coordinator, and the worker routes the tailnet
    # back through it. Without the guard chain, ip_forward=1 would carry these.
    peer.succeed("ip route replace 10.42.0.0/24 via 100.105.121.73")
    peer.succeed("ip route replace 10.200.0.0/16 via 100.105.121.73")
    worker.succeed("ip route replace 100.64.0.0/10 via 10.42.0.2")
    peer.fail("curl -sf --max-time 5 http://10.42.0.5:8731/health")
    peer.fail(f"curl -sf --max-time 5 http://{pod_ip}:8000/")
    for port in (8085, 9090, 10250, 6443, 18085):
        peer.fail(f"curl -sk --max-time 5 -o /dev/null https://100.105.121.73:{port}/")
        peer.fail(f"curl -s --max-time 5 -o /dev/null http://100.105.121.73:{port}/")
    # hostPorts: from the NAS yes (atelet's peers), from the worker no.
    nas.succeed("curl -sf --max-time 10 http://10.42.0.2:18085/ | grep -x pod-ok")
    worker.fail("curl -sf --max-time 5 http://10.42.0.2:18085/")
    # Pods never reach the tailnet; the coordinator host itself still does.
    coordinator.succeed("curl -sf --max-time 5 http://100.64.0.9:8000/hostname")
    kubectl("exec probe-coord -- sh -c '! curl -sf --max-time 5 http://100.64.0.9:8000/hostname'")
    # Pods reach the apiserver Service (any HTTP answer is reachability).
    code = kubectl("exec probe-coord -- curl -sk -o /dev/null -w '%{http_code}' --max-time 10 https://10.201.0.1/readyz").strip()
    assert code != "000", "a coordinator pod cannot reach the apiserver Service"
    # Pods never reach the LAN except the NAS's apiserver and registry.
    kubectl("exec probe-coord -- sh -c '! curl -sf --max-time 5 http://10.42.0.5:8731/health'")
    worker.succeed("ip route del 100.64.0.0/10 via 10.42.0.2")
    assert coordinator.succeed("sysctl -n net.ipv6.conf.all.forwarding").strip() == "0"
    coordinator.succeed("iptables -t mangle -S nixos-fw-rpfilter | grep -q rpfilter")
    coordinator.succeed("iptables -t mangle -S FORWARD 1 | grep -q ax-fleet-guard")
    coordinator.fail("ip -br link | grep -qi cilium")
    record("guard_chain", coordinator.succeed("iptables -t mangle -S ax-fleet-guard").strip().splitlines())


with step("cluster plumbing: DNS through the NAS stand-in"):
    kubectl("exec probe-coord -- nslookup only-nas.test | grep -q 10.42.0.77")
    kubectl("exec probe-nas -- nslookup only-nas.test | grep -q 10.42.0.77")


with step("resilience: coordinator link flap"):
    uid = jsonpath("pod probe-coord", "{.metadata.uid}")
    coordinator.succeed("ip link set eth1 down")
    time.sleep(20)
    coordinator.succeed("ip link set eth1 up")
    node_ready("coordinator")
    kubectl("wait --for=condition=Ready pod/probe-coord --timeout=300s")
    assert jsonpath("pod probe-coord", "{.metadata.uid}") == uid, "the probe pod was replaced by the flap"
    nas.wait_until_succeeds("curl -sf --max-time 5 http://10.42.0.2:18085/ | grep -x pod-ok", timeout=120)
