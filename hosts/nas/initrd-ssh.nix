{ pkgs, ... }:
let
  registry = import ../../modules/mesh-registry.nix;
in
# Remote access in stage 1 (2026-10-27). The NAS boots headless, and the 1TB
# swap left it dark with no way to see where it stopped. With this, a stage-1
# hang (a missing pool device, an fsck, emergency mode) still answers on
# 10.42.0.1:2222 as root, key-only, so the failing unit can be read over SSH.
#
# The host key is NOT in the store: boot.initrd.secrets appends it to the
# initrd on the ESP when the bootloader is installed, from the path below on
# the eMMC root. The file must exist before `switch-to-configuration boot`, or
# the install of this generation fails ("failed to create initrd secrets!").
# It is a separate key from the stage-2 host key because the ESP is plain vfat.
{
  # AQC113 10GbE (ec:1a:c3:04:9d:54) uses the atlantic driver; without it in
  # the initrd the NIC is not brought up before stage 2.
  boot.initrd.availableKernelModules = [ "atlantic" ];

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = [ registry.strix-coordinator.userKey ];
      hostKeys = [ "/etc/ssh/initrd_ssh_host_ed25519_key" ];
    };
  };

  # Matched by MAC rather than name. The stage-2 10-lan.link (which renames
  # the NIC to enp1s0) is copied into the initrd too, so either name works.
  boot.initrd.systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "ec:1a:c3:04:9d:54";
    address = [ "10.42.0.1/24" ];
    gateway = [ "10.42.0.3" ];
  };

  # Hand the NIC to stage 2 bare, as gen 89 did. networkd leaves static
  # addresses in place when it stops at switch-root, even with
  # flushBeforeStage2 (KeepConfiguration=no); NetworkManager then finds a
  # configured NIC and marks it "connected (externally)" instead of activating
  # coordinator-fast-lane (seen in a VM test, 2026-10-27). Runs only on the way
  # to stage 2, after networkd has stopped; an emergency stop keeps the network.
  boot.initrd.systemd.initrdBin = [ pkgs.iproute2 ];
  boot.initrd.systemd.services.lan-handover = {
    description = "Unconfigure the LAN NIC before stage 2";
    wantedBy = [ "initrd-switch-root.target" ];
    before = [ "initrd-switch-root.target" ];
    after = [ "systemd-networkd.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    # Best effort: if a step fails the NIC stays configured, which still works.
    script = ''
      set +e
      for dev in /sys/class/net/*; do
        if [ "$(cat "$dev/address" 2>/dev/null)" = "ec:1a:c3:04:9d:54" ]; then
          ip route flush dev "''${dev##*/}"
          ip address flush dev "''${dev##*/}"
          ip link set dev "''${dev##*/}" down
        fi
      done
      exit 0
    '';
  };

  # Passwordless root shell on the console in stage-1 emergency mode (the
  # 2026-10-25 gen 86 hang showed "root account is locked"). Same as client.
  boot.initrd.systemd.emergencyAccess = true;
}
