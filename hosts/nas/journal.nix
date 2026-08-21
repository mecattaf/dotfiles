{ ... }:
# Fleet journald substrate, receiver side (issue #135, workstream 1). The NAS
# holds the fleet's remote journal on the dedicated NVMe (disko mounts it at
# /var/log/journal/remote — journal-remote's default output). SplitMode = "host"
# below keeps each sender in its own file set, so the coordinator and the worker
# (admitted since 2026-08-21, #229) never interleave. Continuous
# writeback is why this lives on the SSD: it would be wear on the eMMC and
# spin-up poison for the HDD. The weekly NVMe→HDD archive job and its
# liveness dead-man's switch are deliberately NOT here — they depend on the
# HDD and land with it.
#
# Ungated by design: the substrate is not user-facing, costs nothing while
# idle, and has no device-ID dependency beyond the NVMe disko already asserts.
{
  # The NVMe mounts at /mnt/fast since the 2026-08-02 role widening
  # (disko.nix); journal-remote keeps its default output path via this bind.
  # systemd's fstab generator orders the bind after mnt-fast.mount on its own.
  fileSystems."/var/log/journal/remote" = {
    device = "/mnt/fast/journal-remote";
    fsType = "none";
    options = [
      "bind"
      "nofail"
    ];
  };

  services.journald.remote = {
    enable = true;
    # Plaintext HTTP is a settled #135 decision: nixpkgs systemd is built
    # without GnuTLS (the module asserts if cert options are set) and the
    # transport is the same point-to-point /30 that already carries NFSv4.
    listen = "http";
    settings.Remote = {
      # ~40% of the NVMe; coordinator keeps 80 days locally and weekly
      # archives will land on the HDD, so NVMe loss loses almost nothing.
      MaxUse = "100G";
      SplitMode = "host";
    };
  };

  # Same admit pattern as SSH, and deliberately per-ADDRESS rather than
  # per-interface: only named senders may write into the fleet's journal.
  #
  # The sender set is the two Strix Halo boxes (Tom's 2026-08-21 ruling): they
  # live in the same room as this appliance, on this LAN, and never leave it.
  # The zenbook is de-facto mobile and is deliberately NOT admitted — a roaming
  # laptop streaming its journal home over arbitrary networks is the wrong trade.
  #
  # Both sender addresses are STATIC on their own side
  # (hosts/coordinator/uplink-nas.nix, hosts/worker/default.nix) with dhcp-host
  # pins in ./router.nix as the pool guard, so this ACL cannot be defeated by a
  # lease shuffle.
  #
  # This renders because the NAS runs the nftables backend (see network.nix).
  networking.firewall.extraInputRules = ''
    ip saddr 10.42.0.2 tcp dport 19532 accept comment "journald-remote upload from coordinator (LAN; /30 retired 2026-08-21)"
    ip saddr 10.42.0.5 tcp dport 19532 accept comment "journald-remote upload from worker (LAN; reintegrated 2026-08-21, refs #229)"
  '';
}
