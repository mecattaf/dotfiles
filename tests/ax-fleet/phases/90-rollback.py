# Phase 6: rollback, the kill switch proven (DESIGN.md 12.1, 13). Track
# cluster. Reverse order: coordinator, then nas. Each host goes back to its
# base toplevel (ax off) and then ax-fleet-teardown runs, as Tom would.

BASE = "/run/booted-system/bin/switch-to-configuration test"
LEFTOVER_RULES = "iptables-save 2>/dev/null | grep -E 'KUBE-|FLANNEL|CNI-'"


def pod_netns_pid(machine):
    # A pod sandbox's pause process in a network namespace other than the host's.
    return machine.succeed(
        "host=$(readlink /proc/1/ns/net); for p in $(pgrep -x pause); do "
        "[ \"$(readlink /proc/$p/ns/net)\" != \"$host\" ] && { echo $p; break; }; done"
    ).strip()


with step("rollback coordinator"):
    coordinator.succeed(f"{BASE} >&2")
    coordinator.fail("systemctl is-active k3s.service")
    # Fix round 3: between the kill switch and the teardown the pods still
    # run (KillMode=process). The role-scoped guards keep them off the host.
    pid = pod_netns_pid(coordinator)
    assert pid, "no pod network namespace survived the kill switch"
    coordinator.succeed("timeout 10 bash -c 'exec 3<>/dev/tcp/10.42.0.2/22'")  # sshd is up
    coordinator.fail(f"nsenter -t {pid} -n timeout 5 bash -c 'exec 3<>/dev/tcp/10.42.0.2/22'")
    coordinator.fail(f"nsenter -t {pid} -n timeout 5 bash -c 'exec 3<>/dev/tcp/100.105.121.73/22'")
    coordinator.fail(f"nsenter -t {pid} -n timeout 5 bash -c 'exec 3<>/dev/tcp/10.42.0.5/8731'")
    assert coordinator.succeed("iptables -S nixos-fw | grep -c ax-fleet-pod-input").strip() == "2"
    coordinator.succeed("iptables -t mangle -S FORWARD 1 | grep -q ax-fleet-guard")
    # As documented (fix round 2): the teardown from the rolled-back host's
    # own PATH, no checkout, no injected store path.
    coordinator.succeed("test -x /run/current-system/sw/bin/ax-fleet-teardown")
    coordinator.succeed("ax-fleet-teardown >&2")
    coordinator.fail("ip link show cni0")
    coordinator.fail("ip link show flannel.1")
    coordinator.fail(LEFTOVER_RULES)
    coordinator.fail("pgrep -f containerd-shim")
    # The guards belong to the harness role's every generation (fix round 3);
    # the teardown leaves them, inert without cni0 and flannel.1.
    coordinator.succeed("iptables -t mangle -S ax-fleet-guard | grep -q DROP")
    coordinator.succeed("iptables -S OUTPUT 1 | grep -q ax-fleet-api")
    after = sysctls(coordinator)
    record("sysctl_coordinator_after_rollback", after)
    assert after == base["sysctl_coordinator"], (after, base["sysctl_coordinator"])
    assert user_unit_pid("herdr-standin") == base["herdr_pid"], "herdr stand-in restarted"
    assert nm_invocation() == base["nm_invocation"], "NetworkManager restarted"
    coordinator.fail("test -e /etc/NetworkManager/conf.d/90-ax-fleet.conf")
    worker.succeed("curl -sf --max-time 10 http://10.42.0.2/ | grep -x caddy-ok")
    peer.succeed("curl -sf --max-time 10 http://100.105.121.73/ | grep -x caddy-ok")


with step("rollback nas"):
    # Diagnostic only: which processes hold the kubelet bind before the switch.
    _, holders = nas.execute("ls -l /proc/[0-9]*/cwd /proc/[0-9]*/root 2>/dev/null | grep -c /var/lib/kubelet")
    record("nas_kubelet_holders_before_rollback", holders.strip())
    nas.succeed(f"{BASE} >&2")
    nas.fail("systemctl is-active k3s.service")
    nas.fail("systemctl is-active docker-registry.service")
    nas.succeed("command -v tailscale")  # the stub is reachable from a root shell
    nas.succeed("test -x /run/current-system/sw/bin/ax-fleet-teardown")
    nas.succeed("ax-fleet-teardown >&2")
    # The teardown's pinned PATH keeps k3s-killall.sh away from tailscale.
    nas.fail("test -e /var/log/tailscale-stub.log")
    nas.fail("ip link show cni0")
    nas.fail("ip link show flannel.1")
    nas.fail("pgrep -f containerd-shim")
    ruleset = nas.succeed("nft -s list ruleset")
    for marker in ("KUBE-", "FLANNEL", "CNI-"):
        assert marker not in ruleset, f"{marker} left in the NAS ruleset"
    # The control role's guard table stays in every generation (fix round 3).
    nas.succeed("nft list chain inet ax-fleet-guard forward | grep -q 'tcp dport 8731'")
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
