{
  config,
  inputs,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  enabled = osConfig.myDisplay.enable && osConfig.myDisplay.session == "sway";
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
        target = "sway-physical-session.target";
        environment.QT_QPA_PLATFORM = "wayland";
      };
      settings = {
        font.normal = {
          family = "Anthropic Sans";
          size = 11;
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

    services.mako = {
      enable = true;
      settings = {
        font = "Anthropic Sans 11";
        anchor = "top-right";
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
    xdg.desktopEntries = {
      herdr-picker =
        command "Herdr workspaces" "Find Herdr workspaces and agent status"
          "${config.home.homeDirectory}/.local/bin/herdr-picker";
      sway-workspace-new =
        command "New Herdr workspace" "Create an empty dedicated workspace"
          "${config.home.homeDirectory}/.local/bin/sway-workspace new";
      sway-workspace-rename =
        command "Rename workspace" "Rename the current Sway workspace"
          "${config.home.homeDirectory}/.local/bin/sway-workspace rename";
      notifications-dismiss =
        command "Dismiss notification" "Dismiss the newest Mako notification"
          "${pkgs.mako}/bin/makoctl dismiss";
      notifications-history =
        command "Restore notification" "Restore the most recently dismissed notification"
          "${pkgs.mako}/bin/makoctl restore";
      network-settings =
        command "Network settings" "Configure NetworkManager"
          "${pkgs.kitty}/bin/kitty --class network-settings ${pkgs.networkmanager}/bin/nmtui";
    };
  };
}
