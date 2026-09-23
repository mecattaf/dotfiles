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
let
  nodes = import ../ax-fleet/nodes.nix { inherit pkgs lib inputs; };
in
pkgs.testers.runNixOSTest {
  name = "ax-fleet-boot";
  node.specialArgs = { inherit inputs; };
  nodes.nas = {
    imports = [ nodes.nas ];
    myAxFleet.enable = true;
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
    # The snapshot was taken at first activation, before k3s ever ran.
    nas.succeed("grep -q '^kernel.panic = ' /var/lib/ax-fleet/sysctl-before.conf")
    nas.fail("findmnt -n -T /var/lib/rancher/k3s -o SOURCE | grep -q vda")
  '';
}
