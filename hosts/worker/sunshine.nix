{
  config,
  pkgs,
  lib,
  ...
}:
# Sunshine (host) + Moonlight (client) on the HEADLESS worker, niri-compatible.
# Design + sources: ~/mecattaf/sunshine-moonlight-research.md.
#
# ⚠️ HARDWARE-DEPENDENT (only completable on the real worker — flagged, see runbook):
#   mainline niri has NO virtual/headless output, so niri lights no workspace without a
#   DRM connector presenting a mode. You must fake a connector. Two options:
#     (A) plug a ~$8 HDMI/DP EDID dummy dongle (zero config), OR
#     (B) the declarative kernelParams below — but they need the REAL connector name
#         (`niri msg outputs` on the box) and a REAL EDID blob (extract from a monitor
#         or use a generic one), neither of which can be known/shipped from here.
let
  user = "tom";
in
{
  # --- headless niri session via greetd autologin (so Sunshine's user service attaches) ---
  services.greetd.settings.initial_session = {
    command = "${config.programs.niri.package}/bin/niri-session";
    inherit user;
  };
  systemd.user.services.niri.enableDefaultPath = false; # documented niri+greetd PATH gotcha

  # --- (B) declarative faked connector — FILL connector name + ship the EDID blob on metal ---
  # boot.kernelParams = [
  #   "drm.edid_firmware=DP-1:edid/headless-1080p.bin" # <- real connector + blob in initrd
  #   "video=DP-1:e"                                    # force-enable even with nothing plugged
  # ];
  # hardware.firmware = [ (pkgs.runCommand "edid-fw" {} ''
  #   mkdir -p $out/lib/firmware/edid
  #   cp ${./edid/headless-1080p.bin} $out/lib/firmware/edid/headless-1080p.bin
  # '') ];

  # --- AMD VA-API encode stack (gfx1151 / RDNA3.5; radeonsi VAAPI ships in mesa) ---
  hardware.graphics.extraPackages = with pkgs; [
    libva
    libva-utils
  ];
  environment.systemPackages = with pkgs; [ libva-utils ]; # `vainfo` for debugging

  # --- input injection (uinput) ---
  hardware.uinput.enable = true;
  users.users.${user}.extraGroups = [
    "uinput"
    "input"
  ];

  # --- Sunshine host service (systemd USER unit) ---
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true; # required for Wayland/KMS capture
    openFirewall = true; # 47984/47989/47990/48010 TCP, 47998-48000 + 8000-8010 UDP
    settings = {
      capture = "wlr"; # niri implements wlr-screencopy; fall back to "kms" if garbled
      encoder = "vaapi"; # AMD HW encode; "software" as last resort
    };
  };

  # Client side: install `moonlight-qt` on the coordinator/laptop, pair via the PIN at
  # https://<worker>:47990. (Not configured here — that's the other machine.)
}
