{ pkgs, ... }:
# ─── The TV endpoint: a niri session on the NAS's HDMI, viewable over VNC ────
#
# 2026-08-21 (Tom: "since it now has hdmi, i'm thinking it would be good to
# have vnc with it as well. might as well do it now"). The NAS sits at the TV
# corner with card1-HDMI-A-1 wired to the TV (verified connected, live). This
# module + the myHeadless.tv carve-out (modules/headless.nix) give it a
# graphical session without surrendering the appliance profile: greetd
# autologins tom → niri on VT1 (both from common.nix, un-forced by the
# carve-out), wayvnc mirrors the output, pipewire carries HDMI audio.
#
# EDID pinned to synthesized 1080p — the worker's headless-display.nix trick,
# used here for two REAL reasons even though a physical TV is attached:
#   1. A TV that is off/standby often drops its EDID and reads disconnected;
#      without the pin, niri would lose its only output and the VNC session
#      would die whenever the TV sleeps. The pin keeps the session immortal.
#   2. It caps the output at 1080p even on a 4K panel — the TV upscales, and
#      VNC moves a quarter of the pixels.
# NB the pin lands as a kernel cmdline + initrd firmware change, so it takes
# effect at the NEXT REBOOT (fold it into the pending NAS reboot test — never
# reboot while the LaCie dump runs). Until then the session simply rides the
# TV's own EDID, which works as long as the TV stays attached.
#
# wayvnc runs as a systemd USER service defined system-side (this appliance
# has no home-manager), tied to the graphical session. No VNC auth — access
# is gated at the network layer exactly like the rest of the fleet
# (home/remote.nix doctrine): admitted on the LAN (trusted, same ruling as
# SMB "widen the whole lan") and the tailnet, never the WAN uplink.
{
  myHeadless.tv.enable = true;

  hardware.display = {
    # Standard CEA 1080p60 timing → builds edid/1920x1080.bin.
    edid.modelines."1920x1080" = "148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";
    outputs."HDMI-A-1" = {
      edid = "1920x1080.bin";
      mode = "e"; # force-enabled: survives TV power-off (see header)
    };
  };
  # Early KMS probes connectors from the initrd; ship the blob there or the
  # first probe falls back to 1024x768 (worker lore, headless-display.nix).
  boot.initrd.extraFirmwarePaths = [ "edid/1920x1080.bin" ];

  # A terminal for the session — niri's default config spawns alacritty; there
  # is no dotfiles bootstrap on the appliance, so defaults are the config.
  environment.systemPackages = [
    pkgs.alacritty
    pkgs.wayvnc
  ];

  systemd.user.services.wayvnc = {
    description = "wayvnc — VNC mirror of the TV session";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc --config /etc/wayvnc/config";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  environment.etc."wayvnc/config".text = ''
    address=0.0.0.0
    port=5900
  '';

  # LAN + tailnet only. The WAN uplink (wan0) admits nothing, as ever.
  networking.firewall.interfaces = {
    enp1s0.allowedTCPPorts = [ 5900 ];
    tailscale0.allowedTCPPorts = [ 5900 ];
  };
}
