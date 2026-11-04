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
  # A separately checked store file remains usable when the live config is broken.
  rescue = pkgs.runCommand "domicile-rescue.tsx" { nativeBuildInputs = [ pkgs.jq ]; } ''
    set -o pipefail
    export HOME="$TMPDIR"
    ${domicile}/libexec/domicile/builder --evaluate ${./domicile-session/rescue.tsx} --cache "$TMPDIR/cache" > evaluated.log
    cat evaluated.log
    evaluated=$(jq -rR 'fromjson? | select(.step == "evaluated") | .config' evaluated.log)
    test -n "$evaluated"
    ${domicile}/bin/domicile check-config "$evaluated"
    ${domicile}/libexec/domicile/builder --entry ${./domicile-session/rescue.tsx} --cache "$TMPDIR/cache"
    cp ${./domicile-session/rescue.tsx} "$out"
  '';
  recovery = pkgs.writeTextFile {
    name = "domicile-recover";
    destination = "/bin/domicile-recover";
    executable = true;
    text =
      "#!${pkgs.python3}/bin/python3\n"
      + builtins.replaceStrings [ "@domicile@" "@rescue@" ] [ (toString domicile) (toString rescue) ] (
        builtins.readFile ./domicile-session/recover.py
      );
  };
  # The environment half of sway-physical-session. The launcher must stay greetd's
  # own child: its drm path needs a logind session and XDG_VTNR, and a user
  # service has neither, so Sway's `systemctl --user --wait start` shape cannot
  # be copied. Preflight failures say how to recover; after exec, upstream
  # owns restarts, its graphical targets and teardown. greetd offers Sway.
  session = pkgs.writeShellScriptBin "domicile-physical-session" ''
    set -Eeuo pipefail
    phase="loading the login environment"
    failed() {
      rc=$?
      echo "Domicile login failed while $phase (exit $rc)." >&2
      echo "Use Ctrl+Alt+F2 for a console; run domicile-recover check or domicile-recover status." >&2
      echo "Read: journalctl -t domicile-session -b; journalctl -u greetd -b" >&2
      echo "greetd's default desktop is Sway. Fix the config before trying Domicile again." >&2
      exit "$rc"
    }
    trap failed ERR
    if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != -l ]; }; then
      echo "usage: domicile-physical-session (from a physical console login)" >&2
      exit 2
    fi
    # Load Home Manager's login PATH, exactly once.
    if [ -n "''${SHELL:-}" ] && [ "''${1:-}" != -l ] \
      && ${pkgs.gnugrep}/bin/grep -qx "$SHELL" /etc/shells \
      && ! printf %s "$SHELL" | ${pkgs.gnugrep}/bin/grep -q 'nologin\|false'; then
      exec "$SHELL" -l -c "exec \"$0\" -l"
    fi

    phase="checking the physical login and user bus"
    # Refuse an SSH/nested invocation before touching the user's environment.
    if [[ ! "''${XDG_VTNR:-}" =~ ^[1-9][0-9]*$ ]] || [ -z "''${XDG_SESSION_ID:-}" ]; then
      echo "A physical console login with XDG_VTNR and XDG_SESSION_ID is required." >&2
      false
    fi
    [ -n "''${XDG_RUNTIME_DIR:-}" ]
    [ -d "$XDG_RUNTIME_DIR" ]
    ${pkgs.systemd}/bin/systemctl --user show-environment >/dev/null
    if ${pkgs.systemd}/bin/systemctl --user -q is-active sway-physical.service; then
      echo "A physical desktop is already running (sway-physical.service). Log out before starting Domicile." >&2
      false
    fi
    # An active target can outlive a killed launcher. login-check refuses live
    # sockets, leaves dead ones intact and lets upstream reclaim its own target.

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: value: "export ${name}=${lib.escapeShellArg value}"
      ) home.home.sessionVariables
    )}
    export XDG_DATA_DIRS="${schemaDirs}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    # XDG_VTNR alone must choose the drm platform, and a stale desktop name would
    # route the portal frontend wrongly.
    unset SWAYSOCK I3SOCK WAYLAND_DISPLAY DISPLAY OZONE DOMICILE_SOCK DOMICILE_PAGE
    unset XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
    # Validate the actual login config before mutating the user manager.
    phase="validating the startup config"
    ${recovery}/bin/domicile-recover login-check

    phase="exporting the login environment"
    ${pkgs.systemd}/bin/systemctl --user unset-environment SWAYSOCK I3SOCK WAYLAND_DISPLAY DISPLAY DOMICILE_SOCK XDG_SESSION_DESKTOP
    # The launcher sets four variables on the user manager and imports nothing
    # else, so portals and keyring units need these from here.
    present=()
    for name in ${lib.concatStringsSep " " loginVars}; do
      if [ -v "$name" ]; then present+=("$name"); fi
    done
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd "''${present[@]}"

    echo "Domicile login: validated config; starting the upstream launcher on VT $XDG_VTNR."
    echo "Recovery: Ctrl+Alt+F2, then domicile-recover status. Logs: journalctl -t domicile-session -b"
    phase="starting the upstream launcher"
    # `exec` keeps the launcher in the session scope. No shell argument: the
    # config names it. No EXIT trap competes with upstream's session cleanup.
    exec ${pkgs.systemd}/bin/systemd-cat --identifier=domicile-session \
      ${domicile}/bin/domicile
  '';
in
{
  imports = [ inputs.domicile.nixosModules.default ];

  options.programs.domicilePhysical = {
    sessionPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = session;
      description = "greetd child launcher for the physical Domicile trial.";
    };
    recoveryPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = recovery;
      description = "Console config validation, shell rescue and graceful desktop exit.";
    };
  };

  config = {
    environment.systemPackages = [
      session
      recovery
    ];

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
  };
}
