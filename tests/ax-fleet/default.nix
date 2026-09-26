{
  pkgs,
  lib,
  inputs,
}:
# checks.x86_64-linux.ax-fleet: the 4-VM proof before any switch (DESIGN.md
# 12.1). The script mirrors the real motion: baseline, switch the NAS, switch
# the coordinator, Tasks, resilience, the LAN guard, then switch the worker
# (a tainted inference agent since 2026-09-25), rollback.
#
# The test script is phases/*.py concatenated in name order, after the
# prelude below: 10-cluster, 38-worker-join and 90-rollback (cluster track),
# 20-substrate (substrate track), 30-nop1 and 32-fleet (ax track). Every subtest a phase runs through
# `step(...)` is named in $out/receipt.json with the values it recorded.
let
  nodes = import ./nodes.nix { inherit pkgs lib inputs; };
  teardown = pkgs.callPackage ../../pkgs/ax-fleet-teardown {
    k3s = inputs.nixpkgs.legacyPackages.x86_64-linux.k3s_1_36;
  };
  phaseDir = ./phases;
  phaseFiles = lib.sort (a: b: a < b) (
    lib.filter (n: lib.hasSuffix ".py" n) (lib.attrNames (builtins.readDir phaseDir))
  );
  prelude = ''
    import json
    import os
    import re
    import time
    from contextlib import contextmanager

    # 90-rollback runs the teardown from the host's PATH, as documented; this
    # store path is only compared against it.
    TEARDOWN = "${teardown}/bin/ax-fleet-teardown"
    PROBE_IMAGE = "ax-fleet-probe:test"
    PROBE_TARBALL = "${nodes.probeImage}"
    # Test-only task image variant with claude-code (nodes.nix); its OCI layout
    # carries the manifest digest the Task names.
    CLAUDE_PROBE_OCI = "${nodes.claudeProbeImage}"
    LOCAL_PATH_ROOT = "/mnt/nas/services/ax-fleet/local-path"
    SYSCTLS = [
        "net.ipv4.ip_forward",
        "net.ipv6.conf.all.forwarding",
        "kernel.panic",
        "kernel.panic_on_oops",
        "vm.overcommit_memory",
        # kube-proxy's conntrack keys (fix round 2): the house router's NAT
        # table must keep the host's timeouts.
        "net.netfilter.nf_conntrack_max",
        "net.netfilter.nf_conntrack_tcp_timeout_established",
        "net.netfilter.nf_conntrack_tcp_timeout_close_wait",
    ]

    from typing import Any

    receipt_subtests: list[dict[str, Any]] = []
    receipt_values: dict[str, Any] = {}
    receipt: dict[str, Any] = {"test": "ax-fleet", "subtests": receipt_subtests, "values": receipt_values}


    def save_receipt():
        out = os.environ.get("out", ".")
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "receipt.json"), "w") as f:
            json.dump(receipt, f, indent=2, sort_keys=True)


    def record(key, value):
        receipt_values[key] = value
        # Also into the build log: a failed build keeps no $out.
        print(f"AXFLEET-RECORD {key} = {json.dumps(value, sort_keys=True)}")
        save_receipt()


    @contextmanager
    def step(name):
        t0 = time.monotonic()
        with subtest(name):
            yield
        receipt_subtests.append({"name": name, "result": "pass", "seconds": round(time.monotonic() - t0, 1)})
        save_receipt()


    def kubectl(args):
        """kubectl on the NAS, as root, with the k3s admin kubeconfig."""
        return nas.succeed(f"k3s kubectl {args}")


    def jsonpath(obj, path):
        return kubectl(f"get {obj} -o jsonpath='{path}'").strip()


    def sysctls(machine):
        return {k: machine.succeed(f"sysctl -n {k}").strip() for k in SYSCTLS}


    def node_ready(name):
        nas.wait_until_succeeds(
            f"k3s kubectl get node {name} -o jsonpath='{{.status.conditions[?(@.type==\"Ready\")].status}}' | grep -x True",
            timeout=600,
        )


    KERNEL_KEYS = ("kernel.panic", "kernel.panic_on_oops", "vm.overcommit_memory")


    def kernel_keys_back(machine, baseline):
        """myAxFleet.kubelet.keepHostKernelTunables: kubelet's values are put back."""
        for k in KERNEL_KEYS:
            machine.wait_until_succeeds(f"test \"$(sysctl -n {k})\" = '{baseline[k]}'", timeout=300)


    def flap_until_unreachable(tag):
        """Take the coordinator's LAN leg down until the control plane has
        reacted (Ready=Unknown and the unreachable taint), then bring it back.
        A test parameter, not an estimate: it waits for the transition."""
        t0 = time.monotonic()
        coordinator.succeed("ip link set eth1 down")
        try:
            nas.wait_until_succeeds(
                "k3s kubectl get node coordinator -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -qx Unknown",
                timeout=900,
            )
            nas.wait_until_succeeds(
                "k3s kubectl get node coordinator -o jsonpath='{.spec.taints[*].key}' | grep -qw node.kubernetes.io/unreachable",
                timeout=600,
            )
            record(f"flap_{tag}_taints_while_down", nas.succeed("k3s kubectl get node coordinator -o jsonpath='{.spec.taints}'").strip())
        finally:
            coordinator.succeed("ip link set eth1 up")
        outage = round(time.monotonic() - t0, 1)
        record(f"flap_{tag}_outage_seconds", outage)
        return outage


    def user_unit_pid(unit):
        return coordinator.succeed(
            "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/$(id -u alice) "
            f"systemctl --user show {unit} -p MainPID --value"
        ).strip()


    def nm_invocation():
        return coordinator.succeed("systemctl show NetworkManager -p InvocationID --value").strip()


    def unit_invocation(machine, unit):
        return machine.succeed(f"systemctl show {unit} -p InvocationID --value").strip()

  '';
in
pkgs.testers.runNixOSTest {
  name = "ax-fleet";
  node.specialArgs = { inherit inputs; };
  nodes = {
    inherit (nodes)
      nas
      coordinator
      worker
      peer
      ;
  };
  # Long waits are test parameters (k3s start, image import), not estimates.
  globalTimeout = 3 * 3600;
  testScript =
    prelude
    + lib.concatMapStrings (f: ''

      # ───────────── phases/${f} ─────────────
      ${builtins.readFile (phaseDir + "/${f}")}
    '') phaseFiles
    + ''

      save_receipt()
    '';
  passthru.axFleet = { inherit nodes teardown; };
}
