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
# NB the pin lands as a kernel cmdline + initrd firmware change — live since
# the 2026-08-29 attended reboot (the 7.2 visit); the session no longer
# depends on the TV's own EDID.
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

  # Terminals for the session. kitty is what the binds spawn (2026-08-29,
  # Tom at the console: Mod+Return must open kitty, like everywhere else);
  # alacritty stays as the fallback niri's built-in defaults spawn if the
  # config below ever fails to parse.
  environment.systemPackages = [
    pkgs.kitty
    pkgs.alacritty
    pkgs.wayvnc
  ];

  # There is no dotfiles bootstrap / home-manager on the appliance, so the
  # session ran niri's built-in defaults (terminal on Mod+T → alacritty) —
  # unusable muscle-memory at the TV corner. niri falls back to
  # /etc/niri/config.kdl when ~/.config/niri/config.kdl is absent, which is
  # exactly the appliance shape: a deliberately small, self-contained bind
  # set (a `binds` section replaces ALL default binds, so everything needed
  # at the console is spelled out; desktop binds.kdl is NOT imported — it
  # spawns ~/.local/bin scripts this host does not have). Picked up at the
  # session's next start; the running compositor only watches the file it
  # loaded at startup.
  environment.etc."niri/config.kdl".text = ''
    binds {
        Mod+Shift+Slash { show-hotkey-overlay; }

        Mod+Return hotkey-overlay-title="Terminal" { spawn "kitty"; }
        Mod+T { spawn "kitty"; }

        Mod+Q { close-window; }

        Mod+Left  { focus-column-left; }
        Mod+Right { focus-column-right; }
        Mod+Up    { focus-window-up; }
        Mod+Down  { focus-window-down; }
        Mod+H { focus-column-left; }
        Mod+L { focus-column-right; }
        Mod+K { focus-window-up; }
        Mod+J { focus-window-down; }

        Mod+Shift+Left  { move-column-left; }
        Mod+Shift+Right { move-column-right; }
        Mod+Shift+H { move-column-left; }
        Mod+Shift+L { move-column-right; }

        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+Shift+1 { move-column-to-workspace 1; }
        Mod+Shift+2 { move-column-to-workspace 2; }
        Mod+Shift+3 { move-column-to-workspace 3; }

        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }
        Mod+R { switch-preset-column-width; }

        Mod+Shift+E { quit; }
    }
  '';

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

  # greetd installs as WantedBy=graphical.target, but this appliance never
  # reaches graphical.target (the desktop hosts get there via their display
  # manager plumbing; found dead-on-arrival at first deploy — greetd
  # inactive, getty autologin holding tty1). Want it from multi-user.target
  # so the TV session rises with the appliance's normal boot.
  systemd.services.greetd.wantedBy = [ "multi-user.target" ];
}
