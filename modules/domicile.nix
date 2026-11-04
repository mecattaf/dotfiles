{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Domicile under trial on the client, beside Sway. Sway stays the base config
# and the boot default; nothing here starts Domicile on an ordinary boot. This
# adds upstream's NixOS module, the key table and one boot entry,
# specialisation.domicile, that differs from the base only in greetd's first
# session. `bootctl set-oneshot` picks it for one boot, so the next boot, or a
# held power button, is Sway again. The rest sits in the base because a deploy
# activates the base: under a running Domicile, its PAM file and units stay.
#
# Do not copy upstream's services.displayManager or gdm lines. greetd runs a
# command and reads no .desktop file, and gdm would be a second greeter.
#
# Upstream's Home Manager module stays off. It writes domicile.json whenever it
# is enabled, and a second config beside domicile.tsx is a hard stop at start.
let
  home = config.home-manager.users.tom;
  domicile = config.programs.domicile.package;
  keyTable = ../home/dot_config/domicile/domicile.tsx;
  # A broken file at start means no desk, so it must not deploy. `check-config`
  # refuses a module, so run the builder as upstream's configDirectory does, then
  # `check-config` on the JSON it evaluates. The file deployed is the file checked.
  checkedKeyTable = pkgs.runCommand "domicile.tsx" { nativeBuildInputs = [ pkgs.jq ]; } ''
    set -o pipefail
    export HOME="$TMPDIR"
    mkdir config
    cp ${keyTable} config/domicile.tsx
    chmod -R u+w config
    # Runs the builder and prints `field` of its `step` line.
    run() { # step field builder-arguments...
      ${domicile}/libexec/domicile/builder "''${@:3}" --cache "$TMPDIR/cache" \
        | tee /dev/stderr \
        | jq -rR "fromjson? | select(.step == \"$1\") | $2"
    }
    evaluated=$(run evaluated .config --evaluate config/domicile.tsx)
    ${domicile}/bin/domicile check-config "$evaluated"
    run built .root --entry config/domicile.tsx
    cp ${keyTable} "$out"
  '';
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
      ${domicile}/bin/domicile
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

  # The key table, as one file link and not a whole-folder link. It sets no idle
  # section, so blanking does not lock.
  home-manager.users.tom.xdg.configFile."domicile/domicile.tsx".source = checkedKeyTable;

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
