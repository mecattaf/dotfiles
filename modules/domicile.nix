{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Domicile is the client's physical desktop. greetd keeps the existing
# password-free initial login; leaving the desktop starts it again, guarded.
# Changes apply at the next greetd start, preserving the current desktop.
#
# Do not copy upstream's services.displayManager or gdm lines. greetd runs a
# command and reads no .desktop file, and gdm would be a second greeter.
#
# Upstream's Home Manager module stays off. It writes domicile.json whenever it
# is enabled, and a second config beside domicile.tsx is a hard stop at start.
let
  home = config.home-manager.users.tom;
  domicile = config.programs.domicile.package;
  keyTable = config.programs.domicilePhysical.configSource;
  # Keep the maintained package's relative imports together. Its reference
  # baseline, tests and proof fixtures are never part of the production source.
  imagineRoot = toString (builtins.toPath (toString inputs.imagine));
  imagineSource = lib.cleanSourceWith {
    name = "imagine-production";
    src = inputs.imagine;
    filter =
      path: _type:
      let
        relative = if path == imagineRoot then "" else lib.removePrefix "${imagineRoot}/" path;
        production = relative == "" || relative == "src" || lib.hasPrefix "src/" relative;
      in
      (
        production
        || builtins.elem relative [
          "package.json"
          "LICENSE"
        ]
      )
      && !(lib.hasSuffix ".test.ts" path || lib.hasSuffix ".test.tsx" path);
  };
  snapshot = import ./domicile-snapshot.nix {
    inherit pkgs domicile imagineSource;
    sdkSource = inputs.domicile.rev;
    source = inputs.dsh-domicile;
  };
  # A broken file at start means no desk, so it must not deploy. `check-config`
  # refuses a module, so run the builder as upstream's configDirectory does, then
  # `check-config` on the JSON it evaluates. The file deployed is the file checked.
  # Upstream watches config.parent recursively before starting the engine.
  # A top-level store file would make that parent all of /nix/store.
  checkedKeyTable = "${checkedKeyTableDirectory}/domicile.tsx";
  checkedKeyTableDirectory = pkgs.runCommand "domicile-config" { nativeBuildInputs = [ pkgs.jq ]; } ''
    set -o pipefail
    export HOME="$TMPDIR"
    mkdir config
    # The resolver hashes lexical imports but Vite follows the real entry's
    # symlink. Stamp dependency identity into the entry so an Imagine-only
    # generation change cannot reuse the old shell bundle.
    printf '%s\n' '// Imagine bundle: ${imagineSource}' > config/domicile.tsx
    cat ${keyTable} >> config/domicile.tsx
    cp -R ${imagineSource} config/imagine
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
    mkdir -p "$out"
    cp config/domicile.tsx "$out/domicile.tsx"
    cp -R config/imagine "$out/imagine"
  '';
  # Nix keeps these schemas outside the profile's share.
  schemaDirs = lib.concatMapStringsSep ":" (p: "${p}/share/gsettings-schemas/${p.name}") [
    pkgs.gsettings-desktop-schemas
    pkgs.nautilus-open-any-terminal
  ];
  # Import login variables before the launcher
  # sets those on the user manager itself, before any component starts.
  trialVars = [
    "DOMICILE_CONFIG_FILE"
    "DOMICILE_CONSOLE_TRIAL_PATH"
    "DOMICILE_DESKTOP_CLIENT_CONFIG"
  ];
  loginVars = lib.subtractLists trialVars (
    lib.unique (
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
    )
  );
  # These normally arrive through the installed login environment. A console
  # trial must also carry native-input flags from the candidate without activation.
  nativeVars = lib.filterAttrs (
    name: _: lib.hasPrefix "DOMICILE_" name
  ) config.environment.sessionVariables;
  helperDirectory = home.home.file.".local/bin".source;
  # Keep the paired compositor, engine and config builder untouched. Copy only
  # the small launcher so current_exe finds our external-open siblings on the
  # next physical login; a symlink would resolve back to upstream's hard-code.
  routedDomicile = pkgs.runCommand "domicile-external-open" { } ''
    mkdir -p "$out"
    cp -rs ${domicile}/. "$out/"
    chmod u+w "$out" "$out/bin"
    rm "$out/bin/domicile" "$out/bin/domicile-open-url" "$out/bin/domicile-xdg-open"
    cp --reflink=auto ${domicile}/bin/domicile "$out/bin/domicile-real"
    ln -s ${helperDirectory}/desktop-web "$out/bin/domicile-open-url"
    ln -s ${helperDirectory}/desktop-open "$out/bin/domicile-xdg-open"
    cat > "$out/bin/domicile" <<'SCRIPT'
    #!${pkgs.runtimeShell}
    if [ "$#" -eq 2 ] && [ "$1" = open ]; then
      case "$2" in --*) ;; *) exec ${helperDirectory}/desktop-open "$2" ;; esac
    fi
    exec "@out@/bin/domicile-real" "$@"
    SCRIPT
    substituteInPlace "$out/bin/domicile" --replace-fail '@out@' "$out"
    chmod +x "$out/bin/domicile"
  '';
  desktopClientConfig = home.xdg.configFile."herdr/desktop-client.toml".source;
  trialPath = "${helperDirectory}:${recovery}/bin:${domicile}/bin:${home.home.path}/bin:${pkgs.fish}/bin:/etc/profiles/per-user/tom/bin:/run/current-system/sw/bin";
  # A separately checked store file remains usable when the live config is broken.
  rescue = "${rescueDirectory}/domicile.tsx";
  rescueDirectory = pkgs.runCommand "domicile-rescue" { nativeBuildInputs = [ pkgs.jq ]; } ''
    set -o pipefail
    export HOME="$TMPDIR"
    ${domicile}/libexec/domicile/builder --evaluate ${./domicile-session/rescue.tsx} --cache "$TMPDIR/cache" > evaluated.log
    cat evaluated.log
    evaluated=$(jq -rR 'fromjson? | select(.step == "evaluated") | .config' evaluated.log)
    test -n "$evaluated"
    ${domicile}/bin/domicile check-config "$evaluated"
    ${domicile}/libexec/domicile/builder --entry ${./domicile-session/rescue.tsx} --cache "$TMPDIR/cache"
    mkdir -p "$out"
    cp ${./domicile-session/rescue.tsx} "$out/domicile.tsx"
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
  # greetd launches Domicile inside a real logind session with XDG_VTNR.
  # Upstream owns the graphical targets, restart behavior and teardown.
  session = pkgs.writeShellScriptBin "domicile-physical-session" ''
    set -Eeuo pipefail
    phase="loading the login environment"
    failed() {
      rc=$?
      echo "Domicile login failed while $phase (exit $rc)." >&2
      echo "Use Ctrl+Alt+F2 for a console; run domicile-recover check or domicile-recover status." >&2
      echo "Read: journalctl -t domicile-session -b; journalctl -u greetd -b" >&2
      echo "Fix the Domicile config before retrying, or use domicile-recover rescue." >&2
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
    if [ -n "''${SSH_CONNECTION:-}''${SSH_CLIENT:-}''${SSH_TTY:-}" ]; then
      echo "Start this from a fresh physical console login, outside SSH." >&2
      false
    fi
    if [[ ! "''${XDG_VTNR:-}" =~ ^[1-9][0-9]*$ ]] || [ -z "''${XDG_SESSION_ID:-}" ]; then
      echo "A physical console login with XDG_VTNR and XDG_SESSION_ID is required." >&2
      false
    fi
    [ -n "''${XDG_RUNTIME_DIR:-}" ]
    [ -d "$XDG_RUNTIME_DIR" ]
    ${pkgs.systemd}/bin/systemctl --user show-environment >/dev/null
    # An active target can outlive a killed launcher. login-check refuses live
    # sockets, leaves dead ones intact and lets upstream reclaim its own target.

    # Drop an inherited trial engine before applying this generation's declared
    # overrides. A console-started stock session must not pick a frozen engine.
    unset DOMICILE_ENGINE DOMICILE_ENGINE_ARGS
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") (
        lib.removeAttrs (nativeVars // home.home.sessionVariables) (
          [
            "HOME"
            "XDG_CONFIG_HOME"
          ]
          ++ trialVars
        )
      )
    )}
    # A login shell may prepend live ~/.local/bin. Reapply the candidate's
    # immutable helper directory only for the dedicated console trial.
    if [ -n "''${DOMICILE_CONSOLE_TRIAL_PATH:-}" ]; then
      export PATH="$DOMICILE_CONSOLE_TRIAL_PATH"
    fi
    export XDG_DATA_DIRS="${schemaDirs}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    if [ -n "''${DOMICILE_CONSOLE_TRIAL_PATH:-}" ]; then
      export XDG_DATA_DIRS="${domicile}/share:${home.home.path}/share:$XDG_DATA_DIRS"
    fi
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

    phase="starting the upstream launcher"
    # `exec` keeps the launcher in the session scope. No shell argument: the
    # config names it. No EXIT trap competes with upstream's session cleanup.
    configArgs=()
    if [ "''${DOMICILE_CONFIG_FILE+x}" = x ]; then
      configArgs=(--config "$DOMICILE_CONFIG_FILE")
    fi
    exec ${pkgs.systemd}/bin/systemd-cat --identifier=domicile-session \
      ${routedDomicile}/bin/domicile "''${configArgs[@]}"
  '';
  # greetd's default_session: Domicile again after a greetd restart or a
  # desktop exit, behind a restart-loop guard that falls back to a login shell.
  greetdGuard = pkgs.writeShellScriptBin "domicile-greetd-guard" (
    builtins.replaceStrings [ "@coreutils@" ] [ "${pkgs.coreutils}" ] (
      builtins.readFile ./domicile-session/greetd-guard.sh
    )
  );
  # Runs on the currently booted kernel from a real console login. No HOME or
  # XDG_CONFIG_HOME replacement: Chrome retains its ordinary personal profile.
  # The environment survives the login-shell re-exec without shell interpolation.
  trial = pkgs.writeShellScriptBin "domicile-console-trial" ''
    set -eu
    if [ "$#" -ne 0 ]; then
      echo "usage: domicile-console-trial (from a fresh physical console login)" >&2
      exit 2
    fi
    export DOMICILE_CONFIG_FILE=${lib.escapeShellArg (toString checkedKeyTable)}
    export DOMICILE_CONSOLE_TRIAL_PATH=${lib.escapeShellArg trialPath}
    export DOMICILE_DESKTOP_CLIENT_CONFIG=${lib.escapeShellArg (toString desktopClientConfig)}
    echo "Domicile console trial: config $DOMICILE_CONFIG_FILE"
    echo "No activation or kernel change. Logs: journalctl -t domicile-session -b"
    exec ${session}/bin/domicile-physical-session
  '';
in
{
  imports = [
    inputs.domicile.nixosModules.default
    ./domicile-apps.nix
    ./imagine-helpers.nix
  ];

  options.programs.domicilePhysical = {
    checkedConfigPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = checkedKeyTableDirectory;
      description = "The checked desktop entry and its production import graph.";
    };
    configSource = lib.mkOption {
      type = lib.types.path;
      default = ../home/dot_config/domicile/domicile.tsx;
      description = "The one checked TSX config; native candidates select their explicit composed source.";
    };
    sessionPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = session;
      description = "Physical Domicile session launcher for greetd and console logins.";
    };
    trialPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = trial;
      description = "Store-backed console trial on the running kernel, without activation.";
    };
    snapshotClientPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = snapshot.package;
      description = "Bounded read-only Imagine snapshot helper; no desktop listener or DSH Host.";
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
      trial
      snapshot.package
    ];

    services.dbus.packages = [ pkgs.nautilus ];

    programs.domicile = {
      enable = true;
      # The default opens TCP 7236 on every interface. This host serves nothing.
      miracast = false;
    };

    # The group carries upstream's nice and rtprio limits, from the next login.
    users.users.tom.extraGroups = [ "domicile" ];

    # Keep the user directory real: the launcher's recursive watcher sees this
    # file link replaced by Home Manager and reloads the new stamped bundle.
    # Relative imports resolve beside its checked store target, including Imagine.
    # The explicit console-trial route remains immutable for recovery.
    home-manager.users.tom.xdg.configFile."domicile/domicile.tsx".source = checkedKeyTable;
    # The stock import graph resolves beside the user link, while Vite resolves
    # beside its real target. Both locations need the same bundled dependencies;
    # the entry stamp above prevents stale-cache reuse during link replacement.
    home-manager.users.tom.xdg.configFile."domicile/imagine".source =
      "${checkedKeyTableDirectory}/imagine";
    # The optional hook reads config once per mount. Complete its owner-only
    # atomic config write before linkGeneration can trigger the watched TSX.
    home-manager.users.tom.home.activation.stageImagineSnapshotConfig = {
      before = [ "linkGeneration" ];
      after = [ "writeBoundary" ];
      data = "run ${snapshot.stage} ${lib.escapeShellArg "${home.home.homeDirectory}/.config/dsh-domicile"}";
    };

    # Bash is the TTY login shell. Functions take precedence over the temporary
    # ~/bin first-pass launchers; arguments still reach the real CLI binaries.
    home-manager.users.tom.home.file.".bashrc.d/desktop-sessions.bash".text = ''
      domicile() {
        if [ "$#" -eq 0 ]; then
          unset DOMICILE_CONFIG_FILE DOMICILE_CONSOLE_TRIAL_PATH DOMICILE_DESKTOP_CLIENT_CONFIG
          unset DOMICILE_ENGINE DOMICILE_ENGINE_ARGS
          exec ${session}/bin/domicile-physical-session
        fi
        command ${domicile}/bin/domicile "$@"
      }
    '';

    # Override each complete freeform TOML block, as in modules/common.nix.
    # greetd starts the desktop once per boot without authentication. After a
    # greetd restart or a desktop exit it runs default_session, which starts
    # Domicile again through a loop guard (#734): three starts within 120 s
    # this boot open Tom's login shell on VT1 instead of another attempt.
    # VT2-6 also retain their existing password-free getty recovery sessions.
    services.greetd.settings = {
      initial_session = lib.mkForce {
        command = "${session}/bin/domicile-physical-session";
        user = "tom";
      };
      default_session = lib.mkForce {
        command = "${greetdGuard}/bin/domicile-greetd-guard ${session}/bin/domicile-physical-session ${pkgs.bash}/bin/bash -l";
        user = "tom";
      };
    };
    # Switching configuration must leave the current greetd and independently
    # launched console Domicile session running.
    systemd.services.greetd.restartIfChanged = false;
  };
}
