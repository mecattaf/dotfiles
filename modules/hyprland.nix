{
  config,
  lib,
  pkgs,
  ...
}:
# The physical Hyprland seat is distinct from browser-desktop's headless Sway.
# Stock Hyprland owns composition, input and layout; this module owns session lifetime.
let
  cfg = config.programs.hyprlandPhysical;
  schemaDirs = lib.concatMapStringsSep ":" (p: "${p}/share/gsettings-schemas/${p.name}") [
    pkgs.gsettings-desktop-schemas
    pkgs.nautilus-open-any-terminal
  ];
  sessionVars = [
    "WAYLAND_DISPLAY"
    "DISPLAY"
    "HYPRLAND_INSTANCE_SIGNATURE"
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
  session = pkgs.writeShellScriptBin "hyprland-physical-session" ''
    set -eu
    # Load Home Manager's login PATH, exactly once.
    if [ -n "''${SHELL:-}" ] && [ "''${1:-}" != -l ] \
      && ${pkgs.gnugrep}/bin/grep -qx "$SHELL" /etc/shells \
      && ! printf %s "$SHELL" | ${pkgs.gnugrep}/bin/grep -q 'nologin\|false'; then
      exec "$SHELL" -l -c "exec $0 -l"
    fi

    if ${pkgs.systemd}/bin/systemctl --user -q is-active hyprland-physical.service sway-physical.service; then
      echo "A physical desktop is already running. Log out before starting Hyprland." >&2
      exit 1
    fi

    # Raw fish config does not source HM's POSIX session fragment. Set the
    # declared values here so compositor children and activation agree.
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: value: "export ${name}=${lib.escapeShellArg value}"
      ) config.home-manager.users.tom.home.sessionVariables
    )}
    export XDG_CURRENT_DESKTOP=Hyprland
    export XDG_SESSION_DESKTOP=Hyprland XDG_SESSION_TYPE=wayland
    # Nix keeps these schemas outside the ordinary profile share directory.
    # Plain gsettings, GTK clients and manager-launched apps need the same path.
    export XDG_DATA_DIRS="${schemaDirs}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    unset SWAYSOCK I3SOCK HYPRLAND_INSTANCE_SIGNATURE HYPRLAND_CMD WAYLAND_DISPLAY DISPLAY
    # Physical seats own the user's ordinary portals. The optional headless
    # browser compositor keeps its private display environment in its service.
    # Never clear failures globally or restart the manager / Herdr here.
    ${pkgs.systemd}/bin/systemctl --user unset-environment SWAYSOCK I3SOCK HYPRLAND_INSTANCE_SIGNATURE HYPRLAND_CMD WAYLAND_DISPLAY DISPLAY
    # Import declared session settings (Qt, Chrome, Home Manager), without
    # copying arbitrary shell secrets or stale compositor variables.
    present=()
    for name in ${lib.concatStringsSep " " loginVars}; do
      if [ -v "$name" ]; then present+=("$name"); fi
    done
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd "''${present[@]}"

    cleanup() {
      ${pkgs.systemd}/bin/systemctl --user start hyprland-physical-shutdown.target
      ${pkgs.systemd}/bin/systemctl --user unset-environment ${lib.concatStringsSep " " sessionVars}
    }
    trap cleanup EXIT
    ${pkgs.systemd}/bin/systemctl --user --wait start hyprland-physical.service
  '';
in
{
  options.programs.hyprlandPhysical = {
    enable = lib.mkEnableOption "the fleet's physical Hyprland session";
    sessionPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = session;
      description = "Physical Hyprland launcher, independent of the headless browser desktop.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.hyprland = {
      enable = true;
      # This module owns session targets and environment, as the Sway fallback does.
      withUWSM = false;
    };
    environment.systemPackages = [ session ];
    environment.etc."hypr/physical-session.conf".text = ''
      # Import only compositor-owned variables once the Wayland socket exists.
      exec-once = ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd ${lib.concatStringsSep " " sessionVars} && ${pkgs.systemd}/bin/systemctl --user start hyprland-physical-session.target
    '';

    systemd.user.services.hyprland-physical = {
      description = "Physical Hyprland desktop";
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
      restartIfChanged = false;
      enableDefaultPath = false;
      serviceConfig = {
        Type = "simple";
        Slice = "session.slice";
        ExecStart = "/run/wrappers/bin/Hyprland --config %h/.config/hypr/hyprland.conf";
        Environment = [ "HYPRLAND_NO_SD_VARS=1" ];
        Restart = "no";
      };
    };
    systemd.user.targets.hyprland-physical-session = {
      description = "Physical Hyprland graphical session";
      bindsTo = [ "graphical-session.target" ];
      wants = [
        "graphical-session-pre.target"
        "xdg-desktop-autostart.target"
      ];
      after = [ "graphical-session-pre.target" ];
      before = [ "xdg-desktop-autostart.target" ];
    };
    systemd.user.targets.hyprland-physical-shutdown = {
      description = "End the physical Hyprland graphical session";
      conflicts = [
        "graphical-session.target"
        "graphical-session-pre.target"
        "hyprland-physical-session.target"
      ];
      after = [
        "graphical-session.target"
        "graphical-session-pre.target"
        "hyprland-physical-session.target"
      ];
      unitConfig = {
        DefaultDependencies = false;
        StopWhenUnneeded = true;
      };
    };

    xdg.portal.config.hyprland = {
      default = [ "hyprland" "gtk" ];
      "org.freedesktop.impl.portal.FileChooser" = "gnome";
      "org.freedesktop.impl.portal.ScreenCast" = "hyprland";
      "org.freedesktop.impl.portal.Screenshot" = "hyprland";
      "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
      "org.freedesktop.impl.portal.Inhibit" = "none";
    };
  };
}
