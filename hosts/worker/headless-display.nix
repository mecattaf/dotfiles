{ config, ... }:
# Headless display for the worker. wayvnc captures a wlr output, but with no monitor
# niri lights no connector — so synthesize one:
#
#   1. Generate a 1080p EDID from a modeline (built at eval time, nothing committed)
#      and force-enable a connector with it, so niri sees a real 1920x1080 output.
#   2. Autologin tom → niri via greetd, so the graphical session (and the wayvnc user
#      service) actually starts on a box nobody sits at.
#
# Connector name VERIFIED against the live box (2026-07-05, over TB ssh, amdgpu on
# Fedora): /sys/class/drm/ shows card1-DP-1 … DP-8 + HDMI-A-1, so DP-1 exists and one
# force-enabled connector is enough. wayvnc binds the lit output automatically
# (no --output pin; see home/remote.nix).
{
  hardware.display = {
    # Standard CEA 1080p60 timing → builds edid/1920x1080.bin.
    edid.modelines."1920x1080" = "148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";
    outputs."DP-1" = {
      edid = "1920x1080.bin";
      mode = "e"; # force-enable the connector
    };
  };

  # amdgpu probes connectors from the initrd (nixos-hardware enables early KMS);
  # without the EDID blob there, the first probe falls back to 1024x768 and only
  # heals if the kernel's firmware-load retry path cooperates. Ship it in stage 1.
  boot.initrd.extraFirmwarePaths = [ "edid/1920x1080.bin" ];

  # Autologin (initial_session) now lives fleet-wide in modules/common.nix.
}
