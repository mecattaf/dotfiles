{
  config,
  lib,
  pkgs,
  ...
}:
# The physical Sway seat is distinct from browser-desktop's headless compositor.
# Stock Sway supplies tiling and IPC; this module only owns session lifetime.
let
  cfg = config.programs.swayPhysical;
  schemaDirs = lib.concatMapStringsSep ":" (p: "${p}/share/gsettings-schemas/${p.name}") [
    pkgs.gsettings-desktop-schemas
    pkgs.nautilus-open-any-terminal
  ];
  sessionVars = [
    "WAYLAND_DISPLAY"
    "DISPLAY"
    "SWAYSOCK"
    "I3SOCK"
    "XDG_CURRENT_DESKTOP"
    "XDG_SESSION_TYPE"
    "XDG_SESSION_DESKTOP"
  ];
  loginVars = lib.unique (
    [
      "PATH"
      "SHELL"
      "XDG_DATA_DIRS"
      "XDG_CONFIG_DIRS"
      # A compositor restart in a lingering manager must use this login,
      # not the session ID left over from the previous physical desktop.
      "XDG_SESSION_ID"
      "XDG_SEAT"
      "XDG_VTNR"
      "XDG_CURRENT_DESKTOP"
      "XDG_SESSION_DESKTOP"
      "XDG_SESSION_TYPE"
    ]
    ++ builtins.attrNames config.environment.sessionVariables
    ++ builtins.attrNames (config.home-manager.users.tom.home.sessionVariables or { })
  );
  session = pkgs.writeShellScriptBin "sway-physical-session" ''
    set -eu
    # Load Home Manager's login PATH, exactly once.
    if [ -n "''${SHELL:-}" ] && [ "''${1:-}" != -l ] \
      && ${pkgs.gnugrep}/bin/grep -qx "$SHELL" /etc/shells \
      && ! printf %s "$SHELL" | ${pkgs.gnugrep}/bin/grep -q 'nologin\|false'; then
      exec "$SHELL" -l -c "exec $0 -l"
    fi

    for unit in sway-physical.service scroll.service niri.service; do
      if ${pkgs.systemd}/bin/systemctl --user -q is-active "$unit"; then
        echo "A physical desktop is already running ($unit). Log out before starting Sway." >&2
        exit 1
      fi
    done

    # Raw fish config does not source HM's POSIX session fragment. Set the
    # declared values here so compositor children and activation agree.
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (name: value: "export ${name}=${lib.escapeShellArg value}")
      config.home-manager.users.tom.home.sessionVariables)}
    export XDG_CURRENT_DESKTOP=sway-physical
    export XDG_SESSION_DESKTOP=sway XDG_SESSION_TYPE=wayland
    # Nix keeps these schemas outside the ordinary profile share directory.
    # Plain gsettings, GTK clients and manager-launched apps need the same path.
    export XDG_DATA_DIRS="${schemaDirs}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    unset SWAYSOCK I3SOCK SCROLLSOCK NIRI_SOCKET WAYLAND_DISPLAY DISPLAY
    # Physical seats own the user's ordinary portals. The optional headless
    # browser compositor keeps its private display environment in its service.
    # Never clear failures globally or restart the manager / Herdr here.
    ${pkgs.systemd}/bin/systemctl --user unset-environment SWAYSOCK I3SOCK SCROLLSOCK NIRI_SOCKET WAYLAND_DISPLAY DISPLAY
    # Import declared session settings (Qt, Chrome, Home Manager), without
    # copying arbitrary shell secrets or stale compositor variables.
    present=()
    for name in ${lib.concatStringsSep " " loginVars}; do
      if [ -v "$name" ]; then present+=("$name"); fi
    done
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd "''${present[@]}"

    cleanup() {
      ${pkgs.systemd}/bin/systemctl --user start sway-physical-shutdown.target
      ${pkgs.systemd}/bin/systemctl --user unset-environment ${lib.concatStringsSep " " sessionVars}
    }
    trap cleanup EXIT
    ${pkgs.systemd}/bin/systemctl --user --wait start sway-physical.service
  '';
in
{
  options.programs.swayPhysical = {
    enable = lib.mkEnableOption "the fleet's physical Sway session";
    sessionPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = session;
      description = "Physical Sway launcher, independent of the headless browser desktop.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Google Chrome policy and the signed upstream launcher cache on both seats.
    programs.chromium = {
      enable = true;
      extensions = [
        "kcmipingpfbohfjckomimmahknoddnke;https://clients2.google.com/service/update2/crx"
      ];
    };
    nix.settings = {
      extra-substituters = [ "https://vicinae.cachix.org" ];
      extra-trusted-public-keys = [
        "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
      ];
    };

    programs.sway = {
      enable = true;
      # The service already has a bus and a deliberate desktop identity.
      wrapperFeatures.base = false;
      extraPackages = [ ];
    };
    environment.systemPackages = [ session ];
    environment.etc."sway/physical-session.conf".text = ''
      # Only the physical seat includes this file. Do not include config.d/*:
      # NixOS's stock sway-session hooks would duplicate this session lifetime.
      exec ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd ${lib.concatStringsSep " " sessionVars} && ${pkgs.systemd}/bin/systemctl --user start sway-physical-session.target
    '';

    systemd.user.services.sway-physical = {
      description = "Physical Sway desktop";
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
      restartIfChanged = false;
      enableDefaultPath = false;
      serviceConfig = {
        Type = "simple";
        Slice = "session.slice";
        ExecStart = "${config.programs.sway.package}/bin/sway";
        Restart = "no";
      };
    };
    systemd.user.targets.sway-physical-session = {
      description = "Physical Sway graphical session";
      bindsTo = [ "graphical-session.target" ];
      wants = [
        "graphical-session-pre.target"
        "xdg-desktop-autostart.target"
      ];
      after = [ "graphical-session-pre.target" ];
      before = [ "xdg-desktop-autostart.target" ];
    };
    systemd.user.targets.sway-physical-shutdown = {
      description = "End the physical Sway graphical session";
      conflicts = [
        "graphical-session.target"
        "graphical-session-pre.target"
        "sway-physical-session.target"
      ];
      after = [
        "graphical-session.target"
        "graphical-session-pre.target"
        "sway-physical-session.target"
      ];
      unitConfig = {
        DefaultDependencies = false;
        StopWhenUnneeded = true;
      };
    };

    services.dbus.packages = [ pkgs.nautilus ];
    xdg.portal = {
      config.sway-physical = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.FileChooser" = "gnome";
        "org.freedesktop.impl.portal.ScreenCast" = "wlr";
        "org.freedesktop.impl.portal.Screenshot" = "wlr";
        "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
        "org.freedesktop.impl.portal.Inhibit" = "none";
      };
      extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
      wlr.settings.screencast = {
        chooser_type = "simple";
        chooser_cmd = "${pkgs.slurp}/bin/slurp -f %o -or";
      };
    };
  };
}
