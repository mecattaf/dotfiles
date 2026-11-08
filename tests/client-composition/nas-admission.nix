# A reviewable Home Manager admission payload, never an activation command.
# Build on compute only after the normal disk guard. Activation is a separate,
# deliberate step; suggest mode reloads unit definitions and prints lifecycle
# suggestions without starting/stopping/restarting existing user services.
{ source ? ../.. }:
let
  flake = builtins.getFlake "path:${toString source}";
  base = flake.nixosConfigurations.nas;
  pkgs = base.pkgs;
  helper = base.config.home-manager.users.tom.programs.agencyKitty.package;
  payload = pkgs.runCommand "agency-chat-native-catalogue" {
    nativeBuildInputs = [ pkgs.patch ];
  } ''
    cp -R ${source + "/modules/agency-web/chat-window"} "$out"
    chmod -R u+w "$out"
    cd "$out"
    patch --batch -p1 --input ${source + "/pkgs/agency-kitty/source/integration/agency-chat-window/catalogue-nas.patch"}
    substitute ${source + "/pkgs/agency-kitty/source/integration/agency-chat-window/native_catalogue.py"} "$out/native_catalogue.py" \
      --replace-fail '@AGENCY_KITTY_COMMAND@' '${helper}/bin/agency-kitty'
  '';
  admitted = base.extendModules {
    modules = [({ lib, ... }: {
      home-manager.users.tom = {
        systemd.user.startServices = lib.mkForce "suggest";
        home.file = {
          ".local/lib/agency-chat-window/catalogue_nas.py".source = "${payload}/catalogue_nas.py";
          ".local/lib/agency-chat-window/native_catalogue.py".source = "${payload}/native_catalogue.py";
        };
      };
    })];
  };
  home = admitted.config.home-manager.users.tom;
in {
  inherit payload;
  activationPackage = home.home.activationPackage;
  admission = {
    helper = toString helper;
    cataloguePayload = toString payload;
    catalogueEntry = toString home.home.file.".local/lib/agency-chat-window/catalogue_nas.py".source;
    unitLifecycleAutomatic = home.systemd.user.startServices;
    herdrSwitchMethod = home.systemd.user.services.herdr.Unit.X-SwitchMethod;
    primaryVi = home.programs.agencyEditor.viAlias;
    editorRole = home.home.sessionVariables.DSH_EDITOR_ROLE;
    neovim = toString home.programs.neovim.finalPackage;
    neovimPlugins = toString home.xdg.configFile."nvim/lua/plugins.lua".source;
    changesCurrentNas = false;
  };
}
