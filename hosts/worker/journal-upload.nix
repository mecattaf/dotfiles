{ ... }:
# Fleet journald substrate, sender side (issue #135, workstream 1) — the worker
# half, landed 2026-08-21 with the reintegration (#229).
#
# The star topology's senders are the STRIX HALO BOXES ONLY (Tom's ruling
# 2026-08-21): coordinator + worker live in the same room as the NAS, on the same
# LAN, and never leave it; the zenbook is de-facto mobile and never uploads,
# because a roaming laptop streaming its journal home over arbitrary networks is
# the wrong trade. hosts/coordinator/journal-upload.nix said "when hosts/worker
# lands, it gets this same sender module" — this is that module.
#
# It is deliberately the SENDER HALF ONLY. The weekly NVMe→HDD archive job and
# its liveness dead-man's switch stay coordinator-side: they are a single
# fleet-wide janitor over the NAS's whole remote-journal tree, they need
# credentials and the tally daemon that only the coordinator has, and running a
# second copy here would race the first over the same files. Nothing about the
# archive is per-sender.
#
# Plaintext over the LAN is a settled #135 decision: nixpkgs systemd is built
# without GnuTLS (the module asserts if cert options are set), and this is the
# same trust domain and the same segment that already carries NFSv4.
{
  services.journald.upload = {
    enable = true;
    # The NAS's LAN identity. Stated as an ADDRESS, not the `nas` name, for the
    # same reason the coordinator states it: this must not depend on name
    # resolution, and it is the address the NAS's own firewall admits on
    # (hosts/nas/journal.nix now admits 10.42.0.5 alongside the coordinator).
    settings.Upload.URL = "http://10.42.0.1:19532";
  };

  # journald-remote drops the upload connection every time it rotates its
  # receiving journal file (NAS side logs "microhttpd: Application reported
  # internal error"); the uploader exits 1 and reconnects seconds later. That
  # ~daily blip is not a signal — sustained upload loss is, and the coordinator's
  # archive liveness dead-man's switch is the detection for it — so keep the blip
  # off this box's failure markers exactly as the coordinator does.
  myFailureSurfacing.excludeUnits = [
    "systemd-journal-upload.service"
  ];

  # Persistent, bounded local journal. Volatile storage would lose the final
  # pre-lockup window in an mt7925e-class hard freeze — and this box runs the
  # same mt7925e RZ717 on the same 6GHz SSID as the coordinator, so it carries
  # exactly the forensic case the whole substrate exists for. 4G at the
  # coordinator's measured ~50MB/day is ~80 days.
  services.journald.storage = "persistent";
  services.journald.extraConfig = ''
    SystemMaxUse=4G
  '';
}
