# Phase 6: rollback, the kill switch proven (DESIGN.md 12.1, 13). Track
# cluster. Reverse order: coordinator, then nas. Each host goes back to its
# base toplevel (ax off) and then ax-fleet-teardown runs, as Tom would.

BASE = "/run/booted-system/bin/switch-to-configuration test"
LEFTOVER_RULES = "iptables-save 2>/dev/null | grep -E 'KUBE-|FLANNEL|CNI-'"


with step("rollback coordinator"):
    coordinator.succeed(f"{BASE} >&2")
    coordinator.fail("systemctl is-active k3s.service")
    coordinator.succeed(f"{TEARDOWN} >&2")
    coordinator.fail("ip link show cni0")
    coordinator.fail("ip link show flannel.1")
    coordinator.fail(LEFTOVER_RULES)
    coordinator.fail("pgrep -f containerd-shim")
    coordinator.fail("iptables -t mangle -S ax-fleet-guard")
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
