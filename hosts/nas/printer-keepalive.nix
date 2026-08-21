{ pkgs, ... }:
# ─── Brother Deep Sleep prevention (2026-08-21 hardening ruling) ────────────
#
# "printing is really central to my working setup!!!" — Tom, after Deep Sleep
# bit him for the second time. The HL-L2445DW's Deep Sleep mutes its mDNS
# responder entirely (avahi-resolve times out while the IP still pings) and
# stranded a CUPS job on cutover day. Two independent fixes:
#
#   1. modules/printing.nix dials the pinned IP (10.42.0.4), not the mDNS
#      name — resolution can no longer fail.
#   2. THIS unit: the NAS touches the printer's IPP port every 4 minutes.
#      Any network connection resets the printer's idle countdown, so it
#      settles in light sleep at worst — a state that answers mDNS and
#      prints instantly — and can never reach Deep Sleep. The NAS is the
#      one machine that never sleeps, making it the natural metronome.
#
# Cost: one TCP handshake per 4 min, a few printer-side watts vs Deep Sleep.
# Failure is silent by design (printer off / out of range is not an error
# worth waking anyone for — the '-' prefix and || true swallow it), and
# LogLevelMax keeps the 4-minute tick out of the journal noise budget
# (same doctrine as tally-drain on the coordinator).
{
  systemd.services.printer-keepalive = {
    description = "Keep the Brother out of Deep Sleep with a periodic IPP touch";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "-${pkgs.curl}/bin/curl -s -m 5 -o /dev/null http://10.42.0.4:631/";
      LogLevelMax = "notice";
    };
  };
  systemd.timers.printer-keepalive = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "4min";
      AccuracySec = "30s";
    };
  };
}
