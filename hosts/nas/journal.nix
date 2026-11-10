{ config, lib, ... }:
# Fleet journald substrate, receiver side (issue #135, workstream 1). The NAS
# holds the fleet's remote journal on the NVMe pool (@fast/journal-remote,
# bound at /var/log/journal/remote — journal-remote's default output). SplitMode = "host"
# below keeps each sender in its own file set, so the strix and the worker
# (admitted since 2026-08-21, #229) never interleave. Continuous
# writeback is why this lives on the SSD: it would be wear on the eMMC and
# spin-up poison for the HDD. The weekly NVMe→HDD archive job and its
# liveness dead-man's switch are deliberately NOT here — they depend on the
# HDD and land with it.
#
# Ungated by design: the substrate is not user-facing, costs nothing while
# idle, and has no device-ID dependency beyond the pool ./home-disk.nix asserts.
{
  # /mnt/fast is the 1TB pool's @fast since the 2026-10-25 home cutover
  # (./home-disk.nix); journal-remote keeps its default output path via this
  # bind. systemd's fstab generator orders the bind after mnt-fast.mount on its own.
  fileSystems."/var/log/journal/remote" = {
    device = "/mnt/fast/journal-remote";
    fsType = "none";
    options = [
      "bind"
      "nofail"
    ];
  };

  # The local system journal has no size cap. Tom, 2026-11-10: "there should
  # be no size cap on journal or other such crucial directories. otherwise we
  # lost information." journald's implicit limits are 10% of the filesystem
  # with a 4G ceiling, and at most 100 archived files. On the 57G eMMC root
  # the 4G ceiling was reached by 2026-11-08 ("System Journal ... is 3.9G, max
  # 3.9G, 0B free"), and journald had begun deleting the oldest entries: the
  # earliest line left on 2026-11-10 is from 2026-08-26. journald accepts no
  # "infinity", so both limits are set beyond any disk in the fleet.
  #
  # The one bound left is journald's SystemKeepFree default, the smaller of 15%
  # of the filesystem and 4G. It vacuums only when the disk would otherwise
  # fill. The storage alerts (./storage-alerts.nix) fire long before that: the
  # eMMC root at 75%. At the measured ~50MB/day the eMMC holds years of
  # journal, and after the /var move (./system-off-emmc.nix) the 1TB pool
  # holds it. Raising a limit deletes nothing on a switch.
  services.journald.extraConfig = ''
    SystemMaxUse=16T
    SystemMaxFiles=1000000
  '';

  services.journald.remote = {
    enable = true;
    # Plaintext HTTP is a settled #135 decision: nixpkgs systemd is built
    # without GnuTLS (the module asserts if cert options are set) and the
    # transport is the same point-to-point /30 that already carries NFSv4.
    listen = "http";
    settings.Remote = {
      # No size cap, for the same reason as the local journal above (Tom,
      # 2026-11-10). This was 100G, with journal-remote's default of at most
      # 100 archived files; 48 files were in use on 2026-11-10 (41 from the
      # strix). Both are now set beyond any disk. journal-remote's KeepFree
      # default still keeps the 1TB pool from filling, and the pool alert
      # fires first. Rotated files move to the HDD by hand (journal-archive,
      # ../../modules/journal-upload.nix).
      MaxUse = "16T";
      MaxFiles = 1000000;
      SplitMode = "host";
    };
  };

  # Same admit pattern as SSH, and deliberately per-ADDRESS rather than
  # per-interface: only named senders may write into the fleet's journal.
  #
  # The sender set is the two Strix Halo boxes (Tom's 2026-08-21 ruling): they
  # live in the same room as this appliance, on this LAN, and never leave it.
  # The rule was written to exclude the de-facto mobile zenbook-duo — a roaming
  # laptop streaming its journal home over arbitrary networks is the wrong trade.
  #
  # That laptop is BACK, as `client` (10.42.0.16 on this LAN, 100.64.0.4 on the
  # tailnet when it is not), and it is deliberately NOT admitted here: the
  # reason the rule excluded it has not changed — it is the one fleet member
  # that roams. See DEFERRED.md DF-CLIENT-6; the plan's Q-8 closed with that
  # default and I-7 records it. So this is NOT "every member there is": it is
  # exactly the two stationary Strix boxes, and the allowlist stays explicit
  # rather than a subnet precisely so admitting a mobile member is a ruling
  # somebody has to make, not a lease somebody happens to get.
  #
  # Both sender addresses are STATIC on their own side
  # (hosts/strix/uplink-nas.nix, hosts/worker/default.nix) with dhcp-host
  # pins in ./router.nix as the pool guard, so this ACL cannot be defeated by a
  # lease shuffle.
  #
  # This renders because the NAS runs the nftables backend (see network.nix).
  # A dormant worker (modules/mesh-registry.nix) is not admitted.
  networking.firewall.extraInputRules =
    lib.optionalString (config.myFleet.active "strix-worker") ''
      ip saddr 10.42.0.5 tcp dport 19532 accept comment "journald-remote upload from strix-worker"
    ''
    + ''
      ip saddr 10.42.0.2 tcp dport 19532 accept comment "journald-remote upload from strix (LAN; /30 retired 2026-08-21)"
    '';
}
