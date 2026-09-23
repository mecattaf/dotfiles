# Phase 6: rollback, the kill switch and the generation rollback proven
# (DESIGN.md 12.1, 13). Track cluster. Fix round 4: the base is "today"
# (pre-ax, no modules/ax-fleet), so every path below lands where Tom would.
#   coordinator (a) ax-fleet-teardown inside the ax-on generation: the guards
#               are re-applied after k3s-killall.sh strips every flannel rule,
#               and a k3s that starts again runs behind them;
#               (b) the kill switch (ax-off: role declared, enable false), then
#               the teardown from the host's PATH;
#               (c) the generation rollback to the pre-ax base, then the
#               flake's teardown (the pre-ax PATH has none).
#   nas         the generation rollback straight from ax-on, pods still
#               running, then the flake's teardown.

AX_OFF = "/run/booted-system/specialisation/ax-off/bin/switch-to-configuration test"
PRE_AX = "/run/booted-system/bin/switch-to-configuration test"
LEFTOVER_RULES = "iptables-save 2>/dev/null | grep -E 'KUBE-|FLANNEL|CNI-'"
POD_NETNS_PID = (
    "host=$(readlink /proc/1/ns/net); for p in $(pgrep -x pause); do "
    "[ \"$(readlink /proc/$p/ns/net)\" != \"$host\" ] && { echo $p; break; }; done"
)
EXPECTED_GUARDS = {"pod_input": 2, "pod_input_flannel_v4": 1, "pod_input_flannel_v6": 1, "vxlan_source": 1, "guard_flannel": 5}


def pod_netns_pid(machine):
    # A pod sandbox's pause process in a network namespace other than the host's.
    return machine.succeed(POD_NETNS_PID).strip()


def rule_count(machine, cmd):
    return int(machine.succeed(f"{cmd} || true").strip() or "0")


def guards(machine):
    return {
        "pod_input": rule_count(machine, "iptables -S nixos-fw | grep -c ax-fleet-pod-input"),
        "pod_input_flannel_v4": rule_count(machine, "iptables -S nixos-fw | grep -c 'flannel.1.*ax-fleet-pod-input'"),
        "pod_input_flannel_v6": rule_count(machine, "ip6tables -S nixos-fw | grep -c 'flannel.1.*ax-fleet-pod-input'"),
        # iptables -S prints the source before the interface (MEASURED run 2).
        "vxlan_source": rule_count(machine, "iptables -t mangle -S ax-fleet-guard | grep -cE -- '! -s [0-9./]+ -i flannel.1 -j DROP'"),
        "guard_flannel": rule_count(machine, "iptables -t mangle -S ax-fleet-guard | grep -c flannel.1"),
    }


with step("rollback coordinator (a): the teardown inside ax-on re-applies the guards; k3s restarts behind them"):
    # Fix round 4. k3s-killall.sh runs `iptables-save | grep -iv flannel |
    # iptables-restore`, which deleted every guard rule naming flannel.1 while
    # the teardown reported them "left in place" (MEASURED by the review).
    coordinator.succeed("ax-fleet-teardown >&2")
    coordinator.fail("ip link show flannel.1")
    g = guards(coordinator)
    record("guards_after_teardown_in_ax_on", g)
    assert g == EXPECTED_GUARDS, g
    # "It starts again at the next boot or switch": no firewall reload first.
    coordinator.succeed("systemctl start k3s.service")
    node_ready("coordinator")
    coordinator.wait_until_succeeds("ip link show flannel.1", timeout=300)
    kubectl("wait --for=condition=Ready pod/probe-coord --timeout=600s")
    g = guards(coordinator)
    record("guards_after_k3s_restart", g)
    assert g == EXPECTED_GUARDS, g  # re-applied once, never duplicated
    # Discriminating: the NAS's pod reaches a coordinator pod over VXLAN, and
    # the coordinator's sshd listens on its flannel.1 address, yet the pod
    # gets no SSH banner from it.
    coord_pod = jsonpath("pod probe-coord", "{.status.podIP}")
    nas.wait_until_succeeds(f"k3s kubectl exec probe-nas -- curl -sf --max-time 5 http://{coord_pod}:8000/ | grep -x pod-ok", timeout=300)
    fl = coordinator.succeed("ip -4 -o addr show dev flannel.1 | awk '{print $4}' | cut -d/ -f1").strip()
    coordinator.succeed(f"timeout 10 bash -c 'exec 3<>/dev/tcp/{fl}/22'")
    kubectl(f"exec probe-nas -- sh -c '! (nc -w 5 {fl} 22 </dev/null 2>/dev/null | grep -q SSH)'")
    record("ip_forward_after_k3s_restart", coordinator.succeed("sysctl -n net.ipv4.ip_forward").strip())


with step("rollback coordinator (b): the kill switch, then the teardown from PATH"):
    coordinator.succeed(f"{AX_OFF} >&2")
    coordinator.fail("systemctl is-active k3s.service")
    # Fix round 3: between the kill switch and the teardown the pods still
    # run (KillMode=process). The role-scoped guards keep them off the host.
    pid = pod_netns_pid(coordinator)
    assert pid, "no pod network namespace survived the kill switch"
    coordinator.succeed("timeout 10 bash -c 'exec 3<>/dev/tcp/10.42.0.2/22'")  # sshd is up
    coordinator.fail(f"nsenter -t {pid} -n timeout 5 bash -c 'exec 3<>/dev/tcp/10.42.0.2/22'")
    coordinator.fail(f"nsenter -t {pid} -n timeout 5 bash -c 'exec 3<>/dev/tcp/100.105.121.73/22'")
    coordinator.fail(f"nsenter -t {pid} -n timeout 5 bash -c 'exec 3<>/dev/tcp/10.42.0.5/8731'")
    assert guards(coordinator) == EXPECTED_GUARDS, guards(coordinator)
    coordinator.succeed("iptables -t mangle -S FORWARD 1 | grep -q ax-fleet-guard")
    # As documented (fix round 2): the teardown from the host's own PATH.
    coordinator.succeed("test -x /run/current-system/sw/bin/ax-fleet-teardown")
    coordinator.succeed("ax-fleet-teardown >&2")
    coordinator.fail("ip link show cni0")
    coordinator.fail("ip link show flannel.1")
    coordinator.fail(LEFTOVER_RULES)
    coordinator.fail("pgrep -f containerd-shim")
    # The guards belong to the harness role's every generation (fix round 3),
    # re-applied whole after the killall (fix round 4).
    g = guards(coordinator)
    record("guards_after_kill_switch_teardown", g)
    assert g == EXPECTED_GUARDS, g
    coordinator.succeed("iptables -S OUTPUT 1 | grep -q ax-fleet-api")


with step("rollback coordinator (c): the generation rollback to the pre-ax base, then the flake's teardown"):
    coordinator.succeed(f"{PRE_AX} >&2")
    coordinator.fail("test -e /etc/ax-fleet/guard-declared")
    # The pre-ax PATH has no teardown; Tom runs the flake's (DESIGN 13).
    coordinator.fail("command -v ax-fleet-teardown")
    record("coordinator_pre_ax_stale", {
        "mangle_guard": rule_count(coordinator, "iptables -t mangle -S | grep -c ax-fleet-guard"),
        "api_chain": rule_count(coordinator, "iptables -S | grep -c ax-fleet-api"),
        "pod_input": rule_count(coordinator, "iptables -S nixos-fw | grep -c ax-fleet-pod-input"),
    })
    coordinator.succeed(f"{TEARDOWN} >&2")
    coordinator.fail("iptables -t mangle -S ax-fleet-guard")
    coordinator.fail("iptables -S ax-fleet-api")
    coordinator.fail("iptables-save | grep -q ax-fleet")
    coordinator.fail("ip6tables-save | grep -q ax-fleet")
    after = sysctls(coordinator)
    record("sysctl_coordinator_after_rollback", after)
    assert after == base["sysctl_coordinator"], (after, base["sysctl_coordinator"])
    assert user_unit_pid("herdr-standin") == base["herdr_pid"], "herdr stand-in restarted"
    assert nm_invocation() == base["nm_invocation"], "NetworkManager restarted"
    coordinator.fail("test -e /etc/NetworkManager/conf.d/90-ax-fleet.conf")
    worker.succeed("curl -sf --max-time 10 http://10.42.0.2/ | grep -x caddy-ok")
    peer.succeed("curl -sf --max-time 10 http://100.105.121.73/ | grep -x caddy-ok")


with step("rollback nas: the generation rollback straight from ax-on, then the flake's teardown"):
    # Diagnostic only: which processes hold the kubelet bind before the switch.
    _, holders = nas.execute("ls -l /proc/[0-9]*/cwd /proc/[0-9]*/root 2>/dev/null | grep -c /var/lib/kubelet")
    record("nas_kubelet_holders_before_rollback", holders.strip())
    nas.succeed(f"{PRE_AX} >&2")
    nas.fail("systemctl is-active k3s.service")
    nas.fail("systemctl is-active docker-registry.service")
    nas.fail("test -e /etc/ax-fleet/guard-declared")
    nas.fail("command -v ax-fleet-teardown")
    # The window DESIGN 13 documents: pods outlive the switch until the
    # teardown. Recorded, not asserted: which guard (if any) still holds them.
    pid = pod_netns_pid(nas)
    window = {"pod_survived": bool(pid)}
    if pid:
        rc, _ = nas.execute(f"nsenter -t {pid} -n timeout 5 bash -c 'exec 3<>/dev/tcp/10.42.0.5/2222'")
        window["pod_reaches_worker_2222"] = rc == 0
    window["guard_table_present"] = nas.execute("nft list table inet ax-fleet-guard")[0] == 0
    record("nas_generation_rollback_window", window)
    nas.succeed("command -v tailscale")  # the stub is reachable from a root shell
    nas.succeed(f"{TEARDOWN} >&2")
    # The teardown's pinned PATH keeps k3s-killall.sh away from tailscale.
    nas.fail("test -e /var/log/tailscale-stub.log")
    nas.fail("ip link show cni0")
    nas.fail("ip link show flannel.1")
    nas.fail("pgrep -f containerd-shim")
    ruleset = nas.succeed("nft -s list ruleset")
    for marker in ("KUBE-", "FLANNEL", "CNI-", "ax-fleet"):
        assert marker not in ruleset, f"{marker} left in the NAS ruleset"
    nixos_fw = nas.succeed("nft -s list table inet nixos-fw")
    assert nixos_fw == base["nas_nixos_fw"], "the NAS firewall table differs from the baseline"
    record("nas_ruleset_equal_baseline", ruleset == base["nas_nft"])
    if ruleset != base["nas_nft"]:
        record("nas_ruleset_after_rollback", ruleset)
    after = sysctls(nas)
    record("sysctl_nas_after_rollback", after)
    assert after == base["sysctl_nas"], (after, base["sysctl_nas"])
    assert unit_invocation(nas, "postgresql.service") == base["postgres_invocation"], "the shared PostgreSQL restarted"
    dbs = sorted(nas.succeed("runuser -u postgres -- psql -Atc 'select datname from pg_database'").split())
    assert dbs == base["nas_databases"], dbs
    # Left on disk on purpose; deleting it is Tom's call.
    nas.succeed("test -d /mnt/fast/k3s/rancher/k3s")
    nas.fail("findmnt /var/lib/rancher")
