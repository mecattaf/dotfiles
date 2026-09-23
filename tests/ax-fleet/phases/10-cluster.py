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
    # The house router's forwarding is what the snapshot says (fix round 2).
    nas.succeed("grep -x 'net.ipv4.ip_forward = 1' /var/lib/ax-fleet/sysctl-before.conf")


with step("nas: node Ready, untainted, control labels"):
    node_ready("nas")
    # k3s's own transient taints (uninitialized, not-ready) clear on their own.
    nas.wait_until_succeeds("test -z \"$(k3s kubectl get node nas -o jsonpath='{.spec.taints}')\"", timeout=300)
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
    nas.succeed("nft list chain inet ax-fleet-guard prerouting | grep -q 'ax-fleet: cluster ranges'")
    record("sysctl_nas_after_switch", sysctls(nas))
    kernel_keys_back(nas, base["sysctl_nas"])


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
    # flannel.1 appears shortly after the node registers; wait for it.
    coordinator.wait_until_succeeds("ip -d link show flannel.1 | grep -q 'dev eth1'", timeout=180)
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
    # kubelet's panic tunables are put back: an oops does not reboot the desk.
    kernel_keys_back(coordinator, base["sysctl_coordinator"])
    record("sysctl_coordinator_after_restore", sysctls(coordinator))


with step("coordinator: kubelet's tunables are put back whenever they appear, not only after a k3s start"):
    # Fix round 2. kubelet applies them when its container manager starts,
    # which on an agent is when the server first answers, possibly long after
    # k3s.service started (MEASURED by the review). Write kubelet's values with
    # no k3s restart, well after the switch: the watcher must restore them.
    nrestarts = coordinator.succeed("systemctl show k3s.service -p NRestarts --value").strip()
    coordinator.succeed("sysctl -w kernel.panic=10 kernel.panic_on_oops=1 vm.overcommit_memory=1")
    kernel_keys_back(coordinator, base["sysctl_coordinator"])
    assert coordinator.succeed("systemctl show k3s.service -p NRestarts --value").strip() == nrestarts
    coordinator.succeed("systemctl is-active ax-fleet-kernel-tunables.service")


with step("coordinator: the desk outweighs kubepods for CPU"):
    w = {s: int(coordinator.succeed(f"cat /sys/fs/cgroup/{s}/cpu.weight").strip()) for s in ("user.slice", "system.slice", "kubepods.slice")}
    record("cpu_weights", w)
    assert w["user.slice"] > w["kubepods.slice"] and w["system.slice"] > w["kubepods.slice"], w


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


with step("coordinator: pods never reach the coordinator host (sshd accepts passwords)"):
    # Fix round 2. Discriminating: sshd answers the worker on the LAN, and
    # port 22 is open on every interface (openFirewall), so only the pod-input
    # refusal stops a pod.
    worker.succeed("timeout 10 bash -c 'exec 3<>/dev/tcp/10.42.0.2/22; head -c 7 <&3' | grep -x SSH-2.0")
    gw = coordinator.succeed("ip -4 -o addr show dev cni0 | awk '{print $4}' | cut -d/ -f1").strip()
    fl = coordinator.succeed("ip -4 -o addr show dev flannel.1 | awk '{print $4}' | cut -d/ -f1").strip()
    record("pod_input_targets", {"cni0": gw, "flannel.1": fl})
    for ip in ("10.42.0.2", gw, fl, "100.105.121.73"):
        kubectl(f"exec probe-coord -- sh -c '! (nc -w 5 {ip} 22 </dev/null 2>/dev/null | grep -q SSH)'")
    # The NAS's pods, over VXLAN, neither.
    kubectl(f"exec probe-nas -- sh -c '! (nc -w 5 {fl} 22 </dev/null 2>/dev/null | grep -q SSH)'")
    # Pod reachability of the host's own hostPort and of Services is unchanged.
    code = kubectl("exec probe-coord -- curl -sk -o /dev/null -w '%{http_code}' --max-time 10 https://10.201.0.1/readyz").strip()
    assert code != "000", "a coordinator pod lost the apiserver Service"
    refused = coordinator.succeed("iptables -S nixos-fw | grep -c ax-fleet-pod-input").strip()
    assert refused == "2", refused
    coordinator.succeed("ip6tables -S nixos-fw | grep -q 'cni0.*ax-fleet-pod-input'")


with step("coordinator: pods reach no private range on the LAN leg (the Freebox fallback case)"):
    # A private subnet this module does not know, on the same leg, as when
    # NetworkManager falls back to the Freebox profile. Discriminating: the
    # coordinator host reaches it; a pod must not.
    worker.succeed("ip addr add 192.168.77.5/24 dev eth1")
    coordinator.succeed("ip route replace 192.168.77.0/24 dev eth1")
    try:
        coordinator.succeed("curl -sf --max-time 10 http://192.168.77.5:8731/health")
        kubectl("exec probe-coord -- sh -c '! curl -s --max-time 5 -o /dev/null http://192.168.77.5:8731/health'")
    finally:
        coordinator.succeed("ip route del 192.168.77.0/24 dev eth1")
        worker.succeed("ip addr del 192.168.77.5/24 dev eth1")


with step("coordinator: a second LAN leg (the desk's wired port) is guarded and never takes the routes"):
    # Fix round 3. eth3 stands in for enp191s0: NetworkManager-managed, DHCP
    # from the worker's second leg (vlan 3). Round 2's guard named only eth1,
    # so pod egress and inbound hostPorts over eth3 matched no DROP.
    rc, _ = coordinator.execute("timeout 120 sh -c 'until ip -4 -o addr show dev eth3 | grep -q \"inet 192.168.43.\"; do sleep 2; done'")
    if rc != 0:
        record("eth3_profile_added", True)
        coordinator.succeed("nmcli con add type ethernet ifname eth3 con-name wired-eth3 ipv4.method auto ipv6.method ignore")
    record("eth3_routes_before_reactivation", coordinator.succeed("ip -4 route show dev eth3").strip().splitlines())
    # The drop-in's metric applies at the next activation, as on the desk,
    # where the wired port is down today.
    coordinator.succeed("nmcli device disconnect eth3 && nmcli device connect eth3")
    coordinator.wait_until_succeeds("ip -4 -o addr show dev eth3 | grep -q 'inet 192.168.43.'", timeout=120)
    routes = coordinator.succeed("ip -4 route show dev eth3").strip().splitlines()
    record("eth3_routes", routes)
    assert routes and all("metric 700" in r for r in routes), routes
    addr3 = coordinator.succeed("ip -4 -o addr show dev eth3 | awk '{print $4}' | cut -d/ -f1").strip()
    pod_ip = jsonpath("pod probe-coord", "{.status.podIP}")
    # Out: the host reaches the worker's second leg; a pod does not.
    coordinator.succeed("curl -sf --max-time 10 http://192.168.43.5:8731/health")
    kubectl("exec probe-coord -- sh -c '! curl -s --max-time 5 -o /dev/null http://192.168.43.5:8731/health'")
    # In: Caddy answers on the second leg; the pod hostPort and a routed
    # path into the pod network do not.
    worker.succeed(f"curl -sf --max-time 10 http://{addr3}/ | grep -x caddy-ok")
    worker.fail(f"curl -s --max-time 5 -o /dev/null http://{addr3}:18085/")
    worker.succeed(f"ip route replace 10.200.0.0/16 via {addr3}")
    try:
        worker.fail(f"curl -s --max-time 5 -o /dev/null http://{pod_ip}:8000/")
    finally:
        worker.succeed(f"ip route del 10.200.0.0/16 via {addr3}")


with step("coordinator: proxy ARP on the pod interfaces only, never on a LAN leg or a NIC that appears later"):
    # Fix round 3. Round 2 set conf.default, which every later NIC copies
    # (the desk's NICs appear after systemd-sysctl at boot).
    veth = coordinator.succeed("ip -o link show type veth | awk -F': ' '{print $2}' | cut -d@ -f1 | head -1").strip()
    coordinator.succeed("ip link add axprobe0 type dummy && udevadm settle")
    try:
        parp = {
            i: coordinator.succeed(f"cat /proc/sys/net/ipv4/conf/{i}/proxy_arp").strip()
            for i in ("default", "all", "eth1", "eth2", "eth3", "axprobe0", "cni0", "flannel.1", veth)
        }
    finally:
        coordinator.succeed("ip link del axprobe0")
    record("proxy_arp", parp)
    assert parp["cni0"] == "1" and parp["flannel.1"] == "1" and parp[veth] == "1", parp
    assert all(parp[i] == "0" for i in ("default", "all", "eth1", "eth2", "eth3", "axprobe0")), parp


with step("coordinator: LAN traffic routed through the NAS never reaches a harness pod"):
    # The house default gateway is the NAS. Before fix round 1 this path
    # (worker -> nas -> flannel.1 -> harness pod) answered (MEASURED).
    pod_ip = jsonpath("pod probe-coord", "{.status.podIP}")
    nas.succeed(f"curl -sf --max-time 10 http://{pod_ip}:8000/ | grep -x pod-ok")  # the path itself works
    worker.succeed("ip route replace 10.200.0.0/16 via 10.42.0.1")
    try:
        worker.fail(f"curl -s --max-time 5 -o /dev/null http://{pod_ip}:8000/")
    finally:
        worker.succeed("ip route del 10.200.0.0/16 via 10.42.0.1")


def diag(cmds):
    out = {}
    for name, (machine, cmd) in cmds.items():
        _, text = machine.execute(cmd + " 2>&1")
        out[name] = text[-3000:]
    return out


with step("cluster plumbing: pod to pod across nodes (flannel VXLAN)"):
    nas_pod_ip = jsonpath("pod probe-nas", "{.status.podIP}")
    status, _ = nas.execute(f"k3s kubectl exec probe-coord -- curl -sf --max-time 10 http://{nas_pod_ip}:8000/")
    if status != 0:
        record("diag_flannel", diag({
            "coord_routes": (coordinator, "ip route; ip -d link show flannel.1"),
            "nas_routes": (nas, "ip route; ip -d link show flannel.1"),
            "coord_fw": (coordinator, "iptables -S nixos-fw; iptables -t mangle -S ax-fleet-guard"),
            "nas_nft_input": (nas, "nft list chain inet nixos-fw input-allow"),
        }))
    nas.succeed(f"k3s kubectl exec probe-coord -- curl -sf --max-time 10 http://{nas_pod_ip}:8000/ | grep -x pod-ok")


with step("cluster plumbing: DNS through the NAS stand-in"):
    # A records only: the stand-in has no upstream, so AAAA answers REFUSED.
    status, _ = nas.execute("k3s kubectl exec probe-coord -- nslookup -type=a only-nas.test 2>&1 | grep -q 10.42.0.77")
    if status != 0:
        record("diag_dns", diag({
            "coord_nslookup": (nas, "k3s kubectl exec probe-coord -- nslookup only-nas.test"),
            "coord_nslookup_svc": (nas, "k3s kubectl exec probe-coord -- nslookup kubernetes.default.svc.cluster.local"),
            "nas_pod_direct": (nas, "k3s kubectl exec probe-nas -- nslookup only-nas.test 10.42.0.1"),
            "nas_pod_coredns": (nas, "k3s kubectl exec probe-nas -- nslookup only-nas.test"),
            "coredns_logs": (nas, "k3s kubectl -n kube-system logs deploy/coredns --tail=50"),
            "coredns_pod_resolv": (nas, "k3s kubectl -n kube-system exec deploy/coredns -- cat /etc/resolv.conf"),
            "dnsmasq": (nas, "journalctl -u dnsmasq --no-pager | tail -30; ss -lunp | grep :53"),
            "nas_nft": (nas, "nft list table inet nixos-fw"),
        }))
    kubectl("exec probe-coord -- nslookup -type=a only-nas.test | grep -q 10.42.0.77")
    kubectl("exec probe-nas -- nslookup -type=a only-nas.test | grep -q 10.42.0.77")


# The coordinator link flap runs at the END of 30-ax (fix round 1), together
# with the Substrate/ax flap: a flap long enough to take the node NotReady
# can leave connections to the NAS stale (INFERRED), and the Task phases before it
# must run on a cluster that has not seen an outage. probe-coord stays up
# until then; that subtest asserts its uid survives.
