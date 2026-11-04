{
  dotfilesCheckout,
  dotfilesRevision,
  domicileCheckout,
  domicileRevision,
  engineTarball,
}:
let
  dotfiles = builtins.getFlake "git+file://${dotfilesCheckout}?rev=${dotfilesRevision}";
  domicile = builtins.getFlake "git+file://${domicileCheckout}?rev=${domicileRevision}";
  lib = dotfiles.inputs.nixpkgs.lib;
  pkgs = domicile.inputs.nixpkgs.legacyPackages.x86_64-linux;
  packages = domicile.packages.x86_64-linux;
  engine = packages.engine.overrideAttrs (old: {
    src = builtins.path {
      path = engineTarball;
      name = "domicile-engine-local.tar.zst";
    };
    version = "autonomous-checked";
    postFixup = (old.postFixup or "") + ''
      ${pkgs.binutils}/bin/nm -D "$out/libdomicile_engine.so" \
        | ${pkgs.gnugrep}/bin/grep -E '[[:space:]][TW][[:space:]]+domicile_displays_set_white_points$'
    '';
  });
  originalLink = ''ln -s ${packages.engine} "$out/libexec/domicile/engine"'';
  package = packages.domicile.overrideAttrs (old: {
    buildCommand =
      assert lib.hasInfix originalLink old.buildCommand;
      builtins.replaceStrings [ originalLink ] [ ''ln -s ${engine} "$out/libexec/domicile/engine"'' ]
        old.buildCommand;
  });
  candidate = dotfiles.nixosConfigurations.client.extendModules {
    modules = [
      ({ lib, ... }: {
        programs.domicile.package = lib.mkForce package;
        programs.domicilePhysical.configSource = lib.mkForce (
          pkgs.writeText "domicile-native.tsx" (
            builtins.readFile "${dotfiles}/home/dot_config/domicile/domicile.tsx"
            + "\n"
            + builtins.readFile "${dotfiles}/tests/domicile-candidate/native-output.ts"
          )
        );
        environment.sessionVariables.DOMICILE_ENGINE_ARGS = "--domicile-touchpad-natural-scroll --domicile-mouse-flat-acceleration";
      })
    ];
  };
  config = candidate.config;
in
{
  inherit package engine;
  system = config.system.build.toplevel;
  session = config.programs.domicilePhysical.sessionPackage;
  recovery = config.programs.domicilePhysical.recoveryPackage;
  keyTable = config.home-manager.users.tom.xdg.configFile."domicile/domicile.tsx".source;
  metadata = {
    inherit dotfilesRevision domicileRevision;
    engineSource = toString engine.src;
    nativeEngine = engine.outPath;
    compositor = package.outPath;
    system = config.system.build.toplevel.outPath;
    trialSpecialisation = config.system.build.toplevel.outPath + "/specialisation/domicile";
    consoleTrial = config.programs.domicilePhysical.trialPackage or null;
    homeProfile = config.home-manager.users.tom.home.path.outPath;
    helperDirectory = toString config.home-manager.users.tom.home.file.".local/bin".source;
    applicationBinaries = {
      kitty = "${candidate.pkgs.kitty}/bin/kitty";
      chrome = "${candidate.pkgs.google-chrome}/bin/google-chrome-stable";
      nautilus = "${candidate.pkgs.nautilus}/bin/nautilus";
      fish = "${candidate.pkgs.fish}/bin/fish";
    };
    kernel = config.boot.kernelPackages.kernel.version;
    greetd = config.services.greetd.settings;
    trialGreetd = config.specialisation.domicile.configuration.services.greetd.settings;
    failedAssertions = map (x: x.message) (builtins.filter (x: !x.assertion) config.assertions);
  };
}
