{ config, ... }:
# Headless display for the worker. wayvnc captures a wlr output, but with no monitor
# niri lights no connector — so synthesize one:
#
#   1. Generate a 1080p EDID from a modeline (built at eval time, nothing committed)
#      and force-enable a connector with it, so niri sees a real 1920x1080 output.
#   2. Autologin tom → niri via greetd, so the graphical session (and the wayvnc user
#      service) actually starts on a box nobody sits at.
#
# wayvnc is pointed at this connector by name in home/remote.nix (--output DP-1).
#
# ⚠️ VERIFY ON FIRST BOOT: the connector name. `ls /sys/class/drm/` (e.g. card1-DP-1)
# or `niri msg outputs` gives the real name; if it isn't DP-1, change it in BOTH the
# `outputs` key below and `vncOutput` in home/remote.nix.
{
  hardware.display = {
    # Standard CEA 1080p60 timing → builds edid/1920x1080.bin.
    edid.modelines."1920x1080" = "148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";
    outputs."DP-1" = {
      edid = "1920x1080.bin";
      mode = "e"; # force-enable the connector
    };
  };

  services.greetd.settings.initial_session = {
    command = "${config.programs.niri.package}/bin/niri-session";
    user = "tom";
  };
}
