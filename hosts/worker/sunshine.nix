{ config, pkgs, lib, ... }:
# Sunshine (host) + Moonlight (client) on the HEADLESS worker, niri-compatible.
# Design + sources: ~/mecattaf/sunshine-moonlight-research.md.
#
# APPROACH (revised): niri PR #3800 (willybarret) adds DYNAMIC virtual outputs
# (`niri msg create-virtual-output`). Sunshine creates a VD on stream-start and removes
# it on stream-end via per-app prep-commands, sized to the Moonlight client. No EDID
# dongle, no static connector. We build niri from the PR and run it on the worker.
let
  user = "tom";

  # niri built from PR #3800 head (pinned). Override nixpkgs niri's src + cargo vendor.
  niriSrc = pkgs.fetchFromGitHub {
    owner = "niri-wm";
    repo = "niri";
    rev = "38e760e6daf64f9223f197800d6069262cbc4374"; # pull/3800/head @ 2026-06-20
    hash = "sha256-tcjX4u+lc90IE8HFVsYgVLLOLo/9DugHUizv3dh3tHQ=";
  };
  niriVirtualOutput = pkgs.niri.overrideAttrs (_old: {
    version = "26.04-unstable-pr3800-virtual-output";
    src = niriSrc;
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      src = niriSrc;
      name = "niri-pr3800-cargo-vendor";
      hash = "sha256-gfnalA3qI3a9h3PvsxgQLCrzapfjLLkxhTMJpwRh+ro=";
    };
  });
  niri = lib.getExe niriVirtualOutput;
in
{
  # the worker runs the PR niri (has create-virtual-output); the rest of the fleet keeps stock
  programs.niri.package = niriVirtualOutput;

  # --- headless niri session via greetd autologin (so Sunshine's user service attaches) ---
  services.greetd.settings.initial_session = {
    command = "${niriVirtualOutput}/bin/niri-session";
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
      output_name = "sunshine"; # capture the dynamically-created virtual output (see prep-cmd)
    };
    # The streamed "app" creates the virtual output sized to the Moonlight client, then
    # removes it on disconnect. SUNSHINE_CLIENT_{WIDTH,HEIGHT,FPS} are set by Sunshine.
    applications = {
      env = { };
      apps = [
        {
          name = "Desktop (niri virtual output)";
          "prep-cmd" = [
            {
              do = ''${niri} msg create-virtual-output --name sunshine --width ''${SUNSHINE_CLIENT_WIDTH} --height ''${SUNSHINE_CLIENT_HEIGHT} --refresh-rate ''${SUNSHINE_CLIENT_FPS}'';
              undo = "${niri} msg remove-virtual-output sunshine";
            }
          ];
        }
      ];
    };
  };

  # Client side: install `moonlight-qt` on the coordinator/laptop, pair via the PIN at
  # https://<worker>:47990, then launch the "Desktop (niri virtual output)" app.
}
