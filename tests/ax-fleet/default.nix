{
  pkgs,
  lib,
  inputs,
}:
# checks.x86_64-linux.ax-fleet: the 4-VM proof before any switch (DESIGN.md
# 12.1). The script mirrors the real motion: baseline, switch the NAS, switch
# the coordinator (the worker is not switched), Tasks, resilience, rollback.
#
# The test script is phases/*.py concatenated in name order, after the
# prelude below: 10-cluster and 90-rollback (cluster track), 20-substrate
# (substrate track), 30-ax (ax track). Every subtest a phase runs through
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
    import time
    from contextlib import contextmanager

    TEARDOWN = "${teardown}/bin/ax-fleet-teardown"
    PROBE_IMAGE = "ax-fleet-probe:test"
    PROBE_TARBALL = "${nodes.probeImage}"
    LOCAL_PATH_ROOT = "/mnt/nas/services/ax-fleet/local-path"
    SYSCTLS = [
        "net.ipv4.ip_forward",
        "net.ipv6.conf.all.forwarding",
        "kernel.panic",
        "kernel.panic_on_oops",
        "vm.overcommit_memory",
    ]

    receipt = {"test": "ax-fleet", "subtests": [], "values": {}}


    def save_receipt():
        out = os.environ.get("out", ".")
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "receipt.json"), "w") as f:
            json.dump(receipt, f, indent=2, sort_keys=True)


    def record(key, value):
        receipt["values"][key] = value
        save_receipt()


    @contextmanager
    def step(name):
        t0 = time.monotonic()
        with subtest(name):
            yield
        receipt["subtests"].append({"name": name, "result": "pass", "seconds": round(time.monotonic() - t0, 1)})
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
