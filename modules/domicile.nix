{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Domicile under trial on the client, beside Sway. Sway stays the base config
# and the boot default; nothing here starts Domicile on an ordinary boot. This
# adds both of upstream's modules and one boot entry, specialisation.domicile,
# that differs from the base only in greetd's first session. `bootctl
# set-oneshot` picks it for one boot, so the next boot, or a held power button,
# is Sway again. A deploy activates the base, and the entry differs only in that
# one command, so a deploy under a running Domicile takes nothing away from it.
#
# Do not copy upstream's services.displayManager or gdm lines. greetd runs a
# command and reads no .desktop file, and gdm would be a second greeter.
let
  home = config.home-manager.users.tom;
  # As modules/sway.nix: Nix keeps these schemas outside the profile's share.
  schemaDirs = lib.concatMapStringsSep ":" (p: "${p}/share/gsettings-schemas/${p.name}") [
    pkgs.gsettings-desktop-schemas
    pkgs.nautilus-open-any-terminal
  ];
  # As modules/sway.nix, without the variables that name a desktop. The launcher
  # sets those on the user manager itself, before any component starts.
  loginVars = lib.unique (
    [
      "PATH"
      "SHELL"
      "XDG_DATA_DIRS"
      "XDG_CONFIG_DIRS"
      "XDG_SESSION_ID"
      "XDG_SEAT"
      "XDG_VTNR"
    ]
    ++ builtins.attrNames config.environment.sessionVariables
    ++ builtins.attrNames home.home.sessionVariables
  );
  # The environment half of sway-physical-session. The launcher must stay greetd's
  # own child: its drm path needs a logind session and XDG_VTNR, and a user
  # service has neither, so Sway's `systemctl --user --wait start` shape cannot
  # be copied. It exits on any failure and greetd falls to agreety, which offers
  # Sway.
  session = pkgs.writeShellScriptBin "domicile-physical-session" ''
    set -eu
    # Load Home Manager's login PATH, exactly once.
    if [ -n "''${SHELL:-}" ] && [ "''${1:-}" != -l ] \
      && ${pkgs.gnugrep}/bin/grep -qx "$SHELL" /etc/shells \
      && ! printf %s "$SHELL" | ${pkgs.gnugrep}/bin/grep -q 'nologin\|false'; then
      exec "$SHELL" -l -c "exec $0 -l"
    fi

    if ${pkgs.systemd}/bin/systemctl --user -q is-active sway-physical.service; then
      echo "A physical desktop is already running (sway-physical.service). Log out before starting Domicile." >&2
      exit 1
    fi

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: value: "export ${name}=${lib.escapeShellArg value}"
      ) home.home.sessionVariables
    )}
    export XDG_DATA_DIRS="${schemaDirs}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    # XDG_VTNR alone must choose the drm platform, and a stale desktop name would
    # route the portal frontend wrongly.
    unset SWAYSOCK I3SOCK WAYLAND_DISPLAY DISPLAY OZONE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP
    ${pkgs.systemd}/bin/systemctl --user unset-environment SWAYSOCK I3SOCK WAYLAND_DISPLAY DISPLAY
    # The launcher sets four variables on the user manager and imports nothing
    # else, so portals and keyring units need these from here.
    present=()
    for name in ${lib.concatStringsSep " " loginVars}; do
      if [ -v "$name" ]; then present+=("$name"); fi
    done
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd "''${present[@]}"

    # `exec` keeps the launcher in the session scope. No shell argument: the
    # config names it.
    exec ${pkgs.systemd}/bin/systemd-cat --identifier=domicile-session \
      ${home.programs.domicile.finalPackage}/bin/domicile
  '';
in
{
  imports = [ inputs.domicile.nixosModules.default ];

  programs.domicile = {
    enable = true;
    # The default opens TCP 7236 on every interface. This host serves nothing.
    miracast = false;
  };

  # The group carries upstream's nice and rtprio limits, from the next login.
  users.users.tom.extraGroups = [ "domicile" ];

  home-manager.users.tom = {
    imports = [ inputs.domicile.homeManagerModules.default ];

    programs.domicile = {
      enable = true;
      # The key table. Its built Shell becomes the shell, so set neither `shell`
      # nor `settings.shell` beside it.
      configDirectory = ../home/domicile;
      # Leave settings.idle.lock_after_seconds unset. Blanking does not lock
      # without it.
    };
  };

  # Only greetd's first session changes. default_session stays agreety with
  # Sway's command, so a Domicile that exits lands on a login that offers Sway.
  # The whole block, because greetd's TOML settings replace rather than merge
  # (modules/common.nix). The seat assertions read the base config, so they stay
  # as they are.
  specialisation.domicile.configuration.services.greetd.settings.initial_session = lib.mkForce {
    command = "${session}/bin/domicile-physical-session";
    user = "tom";
  };
}
