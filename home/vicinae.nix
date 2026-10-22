# vicinae.nix: the launcher and command palette (Vicinae) plus Mako.
# What it is: Vicinae settings, theme pointer, Mako, and the palette's root
# items. Changed 2026-10-22 (lane 16): the seven hand written desktop entries
# are now generated from dot_config/vicinae/commands.toml, the declarative
# palette catalog; every other setting is unchanged.
# Deliberately absent: a bar (Vicinae is the command surface, Mako owns
# notifications), Vicinae's input server, and any second palette (R3).
{
  config,
  inputs,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  enabled = osConfig.myDisplay.enable;
  package = inputs.vicinae.packages.${pkgs.stdenv.hostPlatform.system}.default;
  cfgHome = config.xdg.configHome;
  # The command palette catalog (lane 16, 2026-10-22). Rows with scope
  # "launcher" become Vicinae root items below; every row is runnable by id
  # through dot_config/vicinae/palette. Ruling R3: Vicinae is the only palette.
  catalogFile = ./dot_config/vicinae/commands.toml;
  catalog = (builtins.fromTOML (builtins.readFile catalogFile)).command;
  # Exec tokens: {home} and {pkg:NAME}. Only the packages named here may
  # appear; an unknown token fails evaluation instead of shipping a broken
  # desktop entry.
  pkgTokens = {
    inherit (pkgs) mako kitty networkmanager;
  };
  expandExec =
    exec:
    let
      names = builtins.attrNames pkgTokens;
      out =
        builtins.replaceStrings
          ([ "{home}" ] ++ map (n: "{pkg:${n}}") names)
          ([ config.home.homeDirectory ] ++ map (n: "${pkgTokens.${n}}") names)
          exec;
    in
    if lib.hasInfix "{" out then
      throw "home/dot_config/vicinae/commands.toml: unexpanded token in exec '${exec}'"
    else
      out;
  command = row: {
    name = row.name;
    genericName = row.description;
    exec = expandExec row.exec;
    terminal = false;
    categories = [ "Utility" ];
    icon = "utilities-terminal";
  };
  launcherRows = builtins.filter (row: row.scope == "launcher") catalog;
in
{
  imports = [ inputs.vicinae.homeManagerModules.default ];

  config = lib.mkIf enabled {
    programs.vicinae = {
      enable = true;
      enableChromeIntegration = false; # Chrome is installed outside HM's browser module.
      enableFirefoxIntegration = false;
      systemd = {
        enable = true;
        target = "sway-physical-session.target";
        environment.QT_QPA_PLATFORM = "wayland";
      };
      settings = {
        font.normal = {
          family = "Anthropic Sans";
          size = 12; # Tom, 2026-10-12: "make the font larger than 11 (12 or 14, need to decide, start at 12)"
        };
        telemetry.system_info = false;
        tray.enabled = false; # Search Tray still hosts other applications' tray menus.
        input_server.enabled = false; # Copy works; no privileged input injection.
        pop_to_root_on_close = true;
        favicon_service = "none";
        theme = {
          dark.name = "dotfiles-current";
          light.name = "dotfiles-current";
        };
        launcher_window = {
          opacity = 1;
          material = "none";
          rounding = 0;
          client_side_decorations = {
            border_width = 1;
            shadow_size = 0;
          };
          layer_shell = {
            enabled = true;
            layer = "overlay";
            keyboard_interactivity = "exclusive";
          };
        };
        providers = {
          # Vicinae's own "Report Vicinae Bug" and "Donate to Vicinae" root
          # items, hidden (Tom, 2026-10-12). Ids from the pinned source:
          # provider "core", entrypoints "report-bug" and "sponsor".
          core.entrypoints = {
            report-bug.enabled = false;
            sponsor.enabled = false;
          };
          clipboard.preferences = {
            monitoring = true;
            ignorePasswords = true;
            evictionThreshold = "86400";
            preserveTagged = true;
          };
          files.preferences = {
            autoIndexing = true;
            indexingPaths = [
              "${config.home.homeDirectory}/Downloads"
              "${config.home.homeDirectory}/Documents"
            ];
          };
        };
        favorites = [
          "applications:herdr-picker"
          "clipboard:history"
          "browser-extension:browse-tabs"
          "media:now-playing"
          "core:search-tray"
        ];
      };
    };

    # A stable theme ID follows the same active palette pointer as Kitty/Herdr.
    # `theme apply` rescans and reloads it without restarting Vicinae.
    xdg.dataFile."vicinae/themes/dotfiles-current.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${cfgHome}/theme/vicinae.toml";
    xdg.configFile."google-chrome/NativeMessagingHosts/com.vicinae.vicinae.json".source =
      "${package}/etc/chromium/native-messaging-hosts/com.vicinae.vicinae.json";
    xdg.configFile."xdg-terminals.list".text = "kitty.desktop\n";
    # asusd stays (it holds the Zenbook's Quiet profile and charge limit); only
    # its ROG Control Center launcher entry is hidden (Tom, 2026-10-12).
    xdg.dataFile."applications/rog-control-center.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=ROG Control Center
      NoDisplay=true
      Hidden=true
    '';

    services.mako = {
      enable = true;
      settings = {
        font = "Anthropic Sans 11";
        anchor = "top-center"; # Tom, 2026-10-11: "top and center not top right"
        width = 390;
        margin = 12;
        padding = 14;
        border-size = 1;
        border-radius = 0;
        default-timeout = 5000;
        max-visible = 4;
        layer = "overlay";
        include = "${cfgHome}/theme/mako.conf";
      };
    };
    systemd.user.services.mako = {
      Unit = {
        Description = "Physical Sway notifications";
        ConditionEnvironment = "WAYLAND_DISPLAY";
        After = [ "sway-physical-session.target" ];
        PartOf = lib.mkForce [ "sway-physical-session.target" ];
      };
      # HM installs the vendor unit but does not declare its Service section.
      # A unit here replaces that file, so it must include the executable.
      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = "${config.services.mako.package}/bin/mako";
        ExecReload = "${config.services.mako.package}/bin/makoctl reload";
      };
      Install.WantedBy = lib.mkForce [ "sway-physical-session.target" ];
    };

    home.packages = [ pkgs.libnotify ];
    # These commands appear in Vicinae's app search and share the same helpers
    # as Sway keybindings. No second extension runtime or bespoke desktop bar.
    # Generated from the catalog: each scope "launcher" row keeps its id as the
    # desktop entry id, so favorites such as "applications:herdr-picker" hold.
    xdg.desktopEntries = builtins.listToAttrs (
      map (row: {
        name = row.id;
        value = command row;
      }) launcherRows
    );
    # The catalog itself, for the palette script (store copy on purpose: the
    # desktop entries above are built from this same revision).
    xdg.configFile."vicinae/commands.toml".source = catalogFile;
  };
}
