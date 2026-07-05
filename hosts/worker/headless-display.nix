{ config, ... }:
# Headless display for the worker. wayvnc captures a wlr output, but with no monitor
# niri lights no connector — so synthesize one:
#
#   1. Generate a 1080p EDID from a modeline (built at eval time, nothing committed)
#      and force-enable a connector with it, so niri sees a real 1920x1080 output.
#   2. Autologin tom → niri via greetd, so the graphical session (and the wayvnc user
#      service) actually starts on a box nobody sits at.
#
# The real connector name has never been observed on this box, so several candidates
# are force-enabled with the same EDID — the kernel silently ignores names that don't
# exist, so whichever connector amdgpu actually exposes lights up. wayvnc binds the
# lit output automatically (no --output pin; see home/remote.nix).
#
# ⚠️ AFTER FIRST BOOT: `niri msg outputs` / `ls /sys/class/drm/` shows which name was
# real — optionally trim the list back to that one connector.
let
  forceEnabled = {
    edid = "1920x1080.bin";
    mode = "e"; # force-enable the connector
  };
in
{
  hardware.display = {
    # Standard CEA 1080p60 timing → builds edid/1920x1080.bin.
    edid.modelines."1920x1080" = "148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";
    outputs = {
      "DP-1" = forceEnabled;
      "DP-2" = forceEnabled;
      "DP-3" = forceEnabled;
      "DP-4" = forceEnabled;
      "HDMI-A-1" = forceEnabled;
      "HDMI-A-2" = forceEnabled;
    };
  };

  # amdgpu probes connectors from the initrd (nixos-hardware enables early KMS);
  # without the EDID blob there, the first probe falls back to 1024x768 and only
  # heals if the kernel's firmware-load retry path cooperates. Ship it in stage 1.
  boot.initrd.extraFirmwarePaths = [ "edid/1920x1080.bin" ];

  services.greetd.settings.initial_session = {
    command = "${config.programs.niri.package}/bin/niri-session";
    user = "tom";
  };
}
