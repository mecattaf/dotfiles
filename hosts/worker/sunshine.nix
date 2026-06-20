{ config, pkgs, lib, ... }:
# ░░ DEFERRED STUB — NOT imported (rolled back 2026-06-20). "I'll use that later." ░░
# Activate by uncommenting `./sunshine.nix` in hosts/worker/default.nix.
#
# Sunshine (host) + Moonlight (client) on the HEADLESS worker, niri-compatible.
# Full design + sources + the headless-display analysis: ~/mecattaf/sunshine-moonlight-research.md.
#
# This file holds THREE stubs to pick up later:
#   (1) sunshine/moonlight — the stable service config below (ready; uses stock niri).
#   (2) niri PR #3800 — dynamic virtual outputs (the clean headless path). Pinned build
#       hashes kept in the commented block below. NOT used until the PR merges (its build
#       proved flaky on rebuild).
#   (3) the corresponding "Sunlight" PR/project — pairs with #3800 on the streaming side.
#       TODO(me): fill the exact repo/PR ref when activating.
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

  # ── STUB (2): headless display ────────────────────────────────────────────────────
  # INTERIM (works now): EDID dummy dongle, OR kernel EDID —
  #   boot.kernelParams = [ "drm.edid_firmware=DP-1:edid/headless-1080p.bin" "video=DP-1:e" ];
  #   hardware.firmware = [ (pkgs.runCommand "edid-fw" {} '' … cp ${./edid/headless-1080p.bin} … '') ];
  #
  # CLEAN (when niri PR #3800 merges): build the PR niri + Sunshine virtual-output prep-cmd.
  # Pinned hashes (prefetched 2026-06-20, ready to drop in):
  #   niriSrc = pkgs.fetchFromGitHub {
  #     owner = "niri-wm"; repo = "niri";
  #     rev = "38e760e6daf64f9223f197800d6069262cbc4374";   # pull/3800/head
  #     hash = "sha256-tcjX4u+lc90IE8HFVsYgVLLOLo/9DugHUizv3dh3tHQ=";
  #   };
  #   niriVirtualOutput = pkgs.niri.overrideAttrs (_: {
  #     src = niriSrc;
  #     cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
  #       src = niriSrc; name = "niri-pr3800-cargo-vendor";
  #       hash = "sha256-gfnalA3qI3a9h3PvsxgQLCrzapfjLLkxhTMJpwRh+ro=";
  #     };
  #   });
  #   # then: programs.niri.package = niriVirtualOutput;
  #   #       services.sunshine.settings.output_name = "sunshine";
  #   #       services.sunshine.applications.apps = [ { name = "Desktop (niri VD)";
  #   #         "prep-cmd" = [ { do = "${lib.getExe niriVirtualOutput} msg create-virtual-output
  #   #           --name sunshine --width \${SUNSHINE_CLIENT_WIDTH} --height \${SUNSHINE_CLIENT_HEIGHT}
  #   #           --refresh-rate \${SUNSHINE_CLIENT_FPS}";
  #   #           undo = "${lib.getExe niriVirtualOutput} msg remove-virtual-output sunshine"; } ]; } ];
  #
  # ── STUB (3): the corresponding "Sunlight" PR/project ─────────────────────────────
  #   TODO(me): record the exact repo/PR that pairs with niri #3800 on the streaming side.
  #
  # Client: install `moonlight-qt` on the coordinator/laptop; pair at https://<worker>:47990.
}
