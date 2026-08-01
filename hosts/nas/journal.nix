{ ... }:
# Fleet journald substrate, receiver side (issue #135, workstream 1). The NAS
# holds the fleet's remote journal on the dedicated NVMe (disko mounts it at
# /var/log/journal/remote — journal-remote's default output). Continuous
# writeback is why this lives on the SSD: it would be wear on the eMMC and
# spin-up poison for the HDD. The weekly NVMe→HDD archive job and its
# liveness dead-man's switch are deliberately NOT here — they depend on the
# HDD and land with it.
#
# Ungated by design: the substrate is not user-facing, costs nothing while
# idle, and has no device-ID dependency beyond the NVMe disko already asserts.
{
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

  # Same admit pattern as SSH: the coordinator is the only sender. This
  # renders because the NAS runs the nftables backend (see network.nix).
  networking.firewall.extraInputRules = ''
    ip saddr 10.77.0.1 tcp dport 19532 accept comment "journald-remote upload from coordinator"
  '';
}
