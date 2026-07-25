{ pkgs, ... }:
# Local-network media + printing plane for the desktop (coordinator only).
#
# The Freebox wifi carries two appliances this box should "just work" with:
#   - a JBL Authentics 200  — AirPlay 2 + Chromecast, 192.168.1.40
#   - a Brother HL-L2445DW  — driverless IPP, 192.168.1.38
# Both are found over mDNS / DNS-SD: a multicast query to 224.0.0.251:5353.
#
# Why nothing worked before this module (diagnosed 2026-07-24):
#   1. No mDNS at all. avahi was not installed, and common.nix's firewall
#      (enable = true, no LAN holes) dropped inbound UDP 5353. A multicast probe
#      for _googlecast/_raop/_ipp got ZERO responders even though the JBL pings
#      fine and its cast/airplay ports are open — Chrome's Cast picker, PipeWire's
#      AirPlay discovery, and CUPS printer discovery all saw an empty network.
#   2. PipeWire had no RAOP (AirPlay) sender module, so a discovered JBL could
#      not be selected as an output sink.
#   3. No CUPS, so there was nothing to print to.
#
# AirPlay is the chosen path for the JBL, not Chromecast. Chromecast has no
# native PipeWire sink — routing system audio to it needs a separate bridge
# daemon (mkchromecast/pulseaudio-dlna) and still can't be a system default.
# RAOP exposes the JBL as an ordinary PipeWire sink, so it sits in the normal
# audio menu next to the USB INZONE headset and WirePlumber remembers it as the
# default when present, falling back to the headset when it's gone. Chrome can
# still cast a tab over the same open :5353 if ever wanted.
{
  # --- mDNS / DNS-SD discovery (the shared root cause) ---
  # avahi owns :5353 and browses the wifi; openFirewall punches UDP 5353 so
  # multicast replies reach us. Chrome does its own mDNS and only needs the port
  # open; PipeWire + CUPS talk to the avahi daemon over D-Bus.
  services.avahi = {
    enable = true;
    nssmdns4 = true; # resolve <device>.local (e.g. the printer's web UI)
    openFirewall = true; # UDP 5353
  };
  # systemd-resolved also wants :5353 for its own mDNS stub; hand mDNS to avahi so
  # the daemon binds cleanly. This only disables resolved's MULTICAST DNS — it
  # merges with the AdGuard module's [Resolve] block (DNS/Domains) and leaves the
  # unicast app → resolved → AdGuard → DoH path in modules/adguardhome.nix intact.
  services.resolved.settings.Resolve.MulticastDNS = false;

  # --- AirPlay output for the JBL ---
  # RAOP discover turns AirPlay speakers into native PipeWire sinks. ~1-2s latency
  # (fine for the lofi/piano listening this speaker is for; not lip-sync for video).
  services.pipewire.extraConfig.pipewire."10-airplay" = {
    "context.modules" = [
      { name = "libpipewire-module-raop-discover"; }
    ];
  };

  # --- printing (Brother) ---
  # Modern Brother printers speak driverless IPP Everywhere, which CUPS
  # auto-configures once avahi is up — no per-model driver needed. brlaser covers
  # the older mono-laser models as a fallback.
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };

  # The printer came online after the 2026-07-24 module landed: a Brother
  # HL-L2445DW at 192.168.1.38, advertising _ipp._tcp with rp=ipp/print and
  # URF/PWG raster, i.e. fully driverless. Discovery is NOT the problem any more —
  # avahi sees it and cups-browsed is running.
  #
  # But Chrome's print dialog was still empty (2026-07-25), because discovery only
  # produced a CUPS *temporary* queue — the on-demand kind CUPS materialises per
  # job and tears down again. The split is visible in CUPS itself: `lpstat -e`
  # listed Brother_HL_L2445DW while `lpstat -t` answered "No destinations added".
  # Chrome enumerates permanent destinations, so it had nothing to show.
  #
  # ensurePrinters runs lpadmin to create a real, persistent queue, so the printer
  # is there at dialog-open instead of depending on discovery timing.
  # model = "everywhere" is driverless IPP: CUPS pulls capabilities off the
  # printer itself, so no PPD or vendor driver is pinned. Addressed by its mDNS
  # hostname rather than the current DHCP lease so a new address cannot silently
  # break the queue (nssmdns4 above is what resolves it).
  hardware.printers = {
    ensureDefaultPrinter = "Brother_HL_L2445DW";
    ensurePrinters = [
      {
        name = "Brother_HL_L2445DW";
        description = "Brother HL-L2445DW";
        location = "Home";
        deviceUri = "ipp://BRW08F97E55F396.local:631/ipp/print";
        model = "everywhere";
        ppdOptions.PageSize = "A4";
      }
    ];
  };

  # `lpadmin -m everywhere` has to TALK to the printer to fetch its capabilities,
  # so nixpkgs' ensure-printers oneshot fails whenever the printer is powered off —
  # which for a household printer is most of the time, including during the nightly
  # fleet deploy. Retry on a slow cadence instead of leaving a failed unit behind
  # (the 2026-07-15 auto-upgrade breakage was exactly this shape: one unrelated
  # non-zero exit poisoning the whole fleet update).
  systemd.services.ensure-printers = {
    startLimitIntervalSec = 0; # never latch into start-limit-hit
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5min";
    };
  };
}
