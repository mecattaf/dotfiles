{ pkgs, ... }:
# Local-network media + printing plane for the desktop (coordinator only).
#
# The Freebox wifi carries two appliances this box should "just work" with:
#   - a JBL Authentics 200  — AirPlay 2 + Chromecast, 192.168.1.40
#   - a Brother printer     — driverless IPP (currently powered off, see below)
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
  # the older mono-laser models as a fallback. The printer was NOT on the wifi
  # when this landed (a full subnet sweep found only the JBL, the Freebox, a
  # phone and the worker); power it on and it should appear at http://localhost:631.
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };
}
