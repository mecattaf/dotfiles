# Read-only admission. This expression does not build, activate, start or stop.
{ source ? ../.. }:
let
  flake = builtins.getFlake "path:${toString source}";
  client = flake.nixosConfigurations.client;
  nas = flake.nixosConfigurations.nas;
  c = client.config;
  n = nas.config;
  ch = c.home-manager.users.tom;
  nh = n.home-manager.users.tom;
  failed = rows: map (row: row.message) (builtins.filter (row: !row.assertion) rows);
in {
  client = {
    baseNixpkgs = flake.inputs.nixpkgs.rev;
    domicileSource = flake.inputs.domicile.rev;
    domicileEngine = toString flake.inputs.domicile.packages.x86_64-linux.engine;
    systemDerivation = c.system.build.toplevel.drvPath;
    activationDerivation = ch.home.activationPackage.drvPath;
    imagineSource = flake.inputs.imagine.rev;
    sdkPackage = toString c.programs.domicile.package;
    configuredEntry = toString c.programs.domicilePhysical.configSource;
    sourceEntry = toString ch.xdg.configFile."domicile/domicile.tsx".source;
    companionSource = toString ch.xdg.configFile."domicile/imagine".source;
    greetd = c.services.greetd.settings;
    greetdRestartIfChanged = c.systemd.services.greetd.restartIfChanged;
    swayManualFallback = c.programs.sway.enable;
    kitty = { version = client.pkgs.kitty.version; path = toString client.pkgs.kitty; };
    helper = toString ch.programs.agencyKitty.package;
    editor = { viAlias = ch.programs.agencyEditor.viAlias; role = ch.home.sessionVariables.DSH_EDITOR_ROLE; };
    kernel = toString c.boot.kernelPackages.kernel;
    mesa = toString c.hardware.graphics.package;
    failedAssertions = failed c.assertions ++ failed ch.assertions;
  };
  nas = {
    helper = toString nh.programs.agencyKitty.package;
    editor = { viAlias = nh.programs.agencyEditor.viAlias; role = nh.home.sessionVariables.DSH_EDITOR_ROLE; };
    herdrSwitchMethod = nh.systemd.user.services.herdr.Unit.X-SwitchMethod;
    systemDerivation = n.system.build.toplevel.drvPath;
    neovim = toString nh.programs.neovim.finalPackage;
    neovimPlugins = toString nh.xdg.configFile."nvim/lua/plugins.lua".source;
    failedAssertions = failed n.assertions ++ failed nh.assertions;
  };
  activates = false;
}
