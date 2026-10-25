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
  nativeShell = osConfig.myDisplay.session == "hyprland";
  sessionTarget = "sway-physical-session.target";
  sessionTargets = [ sessionTarget ];
  package = inputs.vicinae.packages.${pkgs.stdenv.hostPlatform.system}.default;
  cfgHome = config.xdg.configHome;
  command = name: title: exec: {
    inherit name exec;
    genericName = title;
    terminal = false;
    categories = [ "Utility" ];
    icon = "utilities-terminal";
  };
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
        target = sessionTarget;
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

    # Legacy services belong to the Sway recovery session. The Hyprland shell
    # owns notifications and clipboard history; never run both collectors.
    systemd.user.services.vicinae = {
      Unit.After = lib.mkForce sessionTargets;
      Unit.PartOf = lib.mkForce sessionTargets;
      Unit.ConditionEnvironment = lib.mkIf nativeShell "!HYPRLAND_INSTANCE_SIGNATURE";
      Install.WantedBy = lib.mkForce sessionTargets;
    };

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
        Description = "Physical desktop notifications";
        ConditionEnvironment = [ "WAYLAND_DISPLAY" ] ++ lib.optional nativeShell "!HYPRLAND_INSTANCE_SIGNATURE";
        After = sessionTargets;
        PartOf = lib.mkForce sessionTargets;
      };
      # HM installs the vendor unit but does not declare its Service section.
      # A unit here replaces that file, so it must include the executable.
      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = "${config.services.mako.package}/bin/mako";
        ExecReload = "${config.services.mako.package}/bin/makoctl reload";
      };
      Install.WantedBy = lib.mkForce sessionTargets;
    };

    home.packages = [ pkgs.libnotify ];
    # These commands appear in Vicinae's app search and share the same helpers
    # as Sway keybindings. No second extension runtime or bespoke desktop bar.
    xdg.desktopEntries = {
      herdr-picker =
        command "Herdr workspaces" "Find Herdr workspaces and agent status"
          "${config.home.homeDirectory}/.local/bin/herdr-picker";
      sway-workspace-new =
        command "New Herdr workspace" "Create an empty dedicated workspace"
          "${config.home.homeDirectory}/.local/bin/desktop-workspace new";
      sway-workspace-restore =
        command "Restore Herdr workspace" "Reopen the last closed workspace with its running session"
          "${config.home.homeDirectory}/.local/bin/desktop-workspace restore";
      sway-workspace-rename =
        command "Rename workspace" "Rename the current desktop workspace"
          "${config.home.homeDirectory}/.local/bin/desktop-workspace rename";
      notifications-dismiss =
        command "Dismiss notification" "Dismiss the newest Mako notification"
          "${config.home.homeDirectory}/.local/bin/desktop-notifications dismiss";
      notifications-history =
        command "Restore notification" "Restore the most recently dismissed notification"
          "${config.home.homeDirectory}/.local/bin/desktop-notifications history";
      network-settings =
        command "Network settings" "Configure NetworkManager"
          "${pkgs.kitty}/bin/kitty --class network-settings ${pkgs.networkmanager}/bin/nmtui";
    };
  };
}
