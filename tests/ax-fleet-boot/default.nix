{
  pkgs,
  lib,
  inputs,
}:
# checks.x86_64-linux.ax-fleet-boot (DESIGN.md 12.2): a NAS node with ax ON
# FROM BOOT. The 4-VM test proves the live-switch ordering; this proves the
# boot ordering: the bind mounts come up before k3s, the tmpfiles links land
# on the /mnt/fast side, the registry seed and the bootstrap succeed, and the
# node is Ready and untainted. The substrate track adds its Available checks
# here through the same bootstrap.
#
# Built from nixpkgs-STABLE, as the real NAS is (fix round 2): the round-2
# review MEASURED that every other ax-fleet VM runs NixOS 26.11 and systemd
# 261 while the NAS runs 26.05 and systemd 260, so the NAS's own module set
# (k3s, docker-registry, nftables, systemd) had never run. The NAS boots with
# the systemd initrd, as the real one does (boot.initrd.systemd.enable is
# true on it, MEASURED nix eval), because that is where the boot-time
# activation runs.
let
  stablePkgs = inputs.nixpkgs-stable.legacyPackages.x86_64-linux;
  nodes = import ../ax-fleet/nodes.nix {
    pkgs = stablePkgs;
    inherit lib inputs;
  };
in
stablePkgs.testers.runNixOSTest {
  name = "ax-fleet-boot";
  node.specialArgs = { inherit inputs; };
  nodes.nas = {
    # The pre-ax NAS plus its fleet module, ON from boot (fix round 4: the
    # ax-fleet test's base no longer imports the module).
    imports = [
      nodes.nasBase
      nodes.nasFleet
    ];
    myAxFleet.enable = true;
    boot.initrd.systemd.enable = true;
    # The NAS's kernel (hosts/nas/kernel.nix: freshPkgs.linuxPackages_7_2);
    # ax-fleet-topology asserts it is the same derivation.
    boot.kernelPackages =
      (import inputs.nixpkgs-fresh {
        system = "x86_64-linux";
        config.allowUnfree = true;
      }).linuxPackages_7_2;
    myAxFleet.kubelet.systemReserved = "cpu=1,memory=1Gi";
    # The real NAS gets 10.42.0.1 from NetworkManager seconds AFTER
    # network(-online).target (MEASURED 2026-09-23: target at 11.78 s, address
    # at 20.15 s). Reproduce that: no static address, then a unit nothing
    # waits for adds it late. The delay is a test parameter longer than the
    # units' 30 s address wait, so both the wait and Restart= are exercised.
    networking.interfaces.eth1.ipv4.addresses = lib.mkOverride 10 [ ];
    systemd.services.late-lan-addr = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [
        pkgs.iproute2
        pkgs.coreutils
      ];
      script = ''
        sleep 40
        ip link set eth1 up
        ip addr add 10.42.0.1/24 dev eth1
        date +%s > /run/late-lan-addr.done
      '';
    };
  };
  globalTimeout = 3600;
  testScript = ''
    nas.start()
    nas.wait_for_file("/run/late-lan-addr.done", timeout=600)
    nas.wait_for_unit("k3s.service", timeout=900)
    nas.wait_for_unit("ax-fleet-bootstrap.service", timeout=1800)
    for p in ("/var/lib/rancher/k3s", "/var/lib/kubelet", "/var/log/pods"):
        src = nas.succeed(f"findmnt -n -o SOURCE -T {p}").strip()
        assert src.startswith("/dev/vdb"), f"{p} is on {src}, not /mnt/fast"
    nas.succeed("ls /mnt/fast/k3s/rancher/k3s/agent/images/ | grep -q airgap")
    nas.succeed("systemctl show ax-fleet-registry-seed.service -p Result --value | grep -x success")
    # The registry came up on the late address and stays up.
    nas.succeed("systemctl is-active docker-registry.service")
    nas.succeed("curl -sf --max-time 10 http://10.42.0.1:5000/v2/")
    addr_at = int(nas.succeed("cat /run/late-lan-addr.done").strip())
    reg_at = int(nas.succeed(
        "date -d \"$(systemctl show docker-registry.service -p ActiveEnterTimestamp --value)\" +%s"
    ).strip())
    assert reg_at >= addr_at, f"registry active at {reg_at}, before the address at {addr_at}"
    print("AXFLEET-BOOT registry NRestarts=" + nas.succeed("systemctl show docker-registry.service -p NRestarts --value").strip())
    nas.succeed("systemctl show ax-fleet-bootstrap.service -p Result --value | grep -x success")
    nas.wait_until_succeeds(
        "k3s kubectl get node nas -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -x True",
        timeout=600,
    )
    # k3s's own transient taints (uninitialized, not-ready) clear on their own;
    # the NAS carries no taint of ours.
    nas.wait_until_succeeds("test -z \"$(k3s kubectl get node nas -o jsonpath='{.spec.taints}')\"", timeout=300)
    nas.succeed("k3s kubectl -n kube-system wait --for=condition=Available deploy/coredns deploy/local-path-provisioner --timeout=600s")
    nas.succeed("test -s /etc/ax-fleet/admin.kubeconfig")
    # The snapshot was taken at first activation, before k3s ever ran, and at
    # boot it carries the host's declared values, not the kernel defaults the
    # boot activation sees (fix round 2: it had recorded ip_forward = 0 on
    # the router, which the teardown would have applied).
    print("AXFLEET-BOOT snapshot:\n" + nas.succeed("cat /var/lib/ax-fleet/sysctl-before.conf"))
    print("AXFLEET-BOOT release=" + nas.succeed("nixos-version").strip() + " systemd=" + nas.succeed("systemctl --version | head -1").strip())
    nas.succeed("test \"$(sysctl -n net.ipv4.ip_forward)\" = 1")
    nas.succeed("grep -x 'net.ipv4.ip_forward = 1' /var/lib/ax-fleet/sysctl-before.conf")
    nas.succeed("grep -q '^kernel.panic = ' /var/lib/ax-fleet/sysctl-before.conf")
    # kubelet ran; its panic values are not what the host is left with.
    snap_panic = nas.succeed("sed -n 's/^kernel.panic = //p' /var/lib/ax-fleet/sysctl-before.conf").strip()
    nas.wait_until_succeeds(f"test \"$(sysctl -n kernel.panic)\" = '{snap_panic}'", timeout=300)
    nas.fail("findmnt -n -T /var/lib/rancher/k3s -o SOURCE | grep -q vda")
  '';
}
