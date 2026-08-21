{ pkgs, ... }:
# Fleet journald substrate, sender side (issue #135, workstream 1). Star
# topology; senders are the STRIX HALO BOXES ONLY (Tom's ruling 2026-08-21:
# coordinator + worker live in the same room as the NAS; the zenbook is
# de-facto mobile and never uploads — a roaming laptop streaming its journal
# home over arbitrary networks is the wrong trade). When hosts/worker lands,
# it gets this same sender module; zenbook/bridge stay thin clients.
# Plaintext over the LAN (settled decision — nixpkgs systemd has no GnuTLS;
# same trust domain as NFSv4 on the same segment).
let
  # Weekly NVMe→HDD archive on the NAS (#135 workstream 1, final checkbox).
  # Runs coordinator-side because only the coordinator holds credentials and
  # tally; the argv is SSH to the NAS. Rotated remote-*@*.journal files are
  # immutable once renamed, so the move is safe; the active file stays on the
  # NVMe so the HDD keeps spinning down between bursts.
  #
  # Liveness dead-man's switch: the run FAILS if the newest mtime under the
  # remote journal tree has not advanced since the previous run — "uploads
  # quietly stop" is the likeliest failure mode of journald-remote and this
  # is the design's only absence-detection. State lives next to the journal
  # tree on the NAS NVMe.
  journalArchive = pkgs.writeShellApplication {
    name = "journal-archive";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      exec ssh -i /run/agenix/ssh-user-key root@nas /bin/sh -s <<'REMOTE'
      set -eu
      SRC=/var/log/journal/remote
      DST=/mnt/nas/services/journal-archive
      STATE=/var/log/journal/.archive-state
      newest=$(find "$SRC" -maxdepth 1 -name '*.journal' -printf '%T@\n' | sort -n | tail -1)
      prev=$(cat "$STATE" 2>/dev/null || echo 0)
      if ! awk -v a="''${newest:-0}" -v b="$prev" 'BEGIN{exit !(a>b)}'; then
        echo "LIVENESS FAIL: no new journal bytes since previous archive (newest=''${newest:-none} prev=$prev)" >&2
        exit 1
      fi
      moved=0
      for f in "$SRC"/*@*.journal; do
        [ -e "$f" ] || continue
        mv "$f" "$DST"/
        moved=$((moved+1))
      done
      echo "$newest" > "$STATE"
      echo "archived $moved rotated file(s); newest source mtime $newest"
      REMOTE
    '';
  };
in
{
  services.journald.upload = {
    enable = true;
    # The NAS's LAN identity (2026-08-20 rewire); reachable over the legacy
    # /30 cable AND the BE550 LAN during the transition — same address on
    # both wires, so the physical move never touches this line.
    settings.Upload.URL = "http://10.42.0.1:19532";
  };

  # journald-remote drops the upload connection whenever it rotates its
  # receiving journal file (NAS side: "microhttpd: Application reported
  # internal error"); the uploader exits 1 and reconnects seconds later. That
  # ~daily blip is not a signal — sustained upload loss is what matters, and
  # the archive liveness dead-man's switch above is the detection for it — so
  # keep the blip off the failure markers.
  myFailureSurfacing.excludeUnits = [
    "systemd-journal-upload.service"
  ];

  # The local journal stays persistent and bounded (#135, closing #133 item
  # 4 for journald): volatile storage would lose the final pre-lockup window
  # in an mt7925e-class hard freeze — the exact forensic case that motivates
  # the whole substrate. 4G ≈ 80 days at the measured ~50MB/day.
  services.journald.storage = "persistent";
  services.journald.extraConfig = ''
    SystemMaxUse=4G
  '';

  # Started exclusively by the tally weekly producer (home/tally.nix), which
  # holds the nas-hdd pool lease so archives never race a future borg backup
  # or scrub against the same spindle.
  systemd.services.journal-archive = {
    description = "Move rotated remote journal files from NAS NVMe to HDD";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${journalArchive}/bin/journal-archive";
    };
  };
}
