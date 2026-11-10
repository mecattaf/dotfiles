{ pkgs, configurations }:
let
  inherit (pkgs) lib;
  nas = configurations.nas.config;
  handRun = nas.home-manager.users.tom.programs.dsh.package;
  release = nas.services.dshd.releases.nas;
  permissive = handRun.override { permissive = true; };
  unit = nas.systemd.user.units."dshd@.service".text;
  disabled = name: !configurations.${name}.config.services.dshd.enable;
in
assert nas.services.dshd.enable;
assert builtins.attrNames nas.services.dshd.releases == [ "nas" ];
assert nas.services.dshd.defaultRelease == null;
assert release.dsh.drvPath == permissive.drvPath;
assert release.environment == { };
assert release.unsetEnvironment == handRun.unsetEnvironment;
assert builtins.elem "CLOUDFLARE_API_TOKEN" release.unsetEnvironment;
assert builtins.elem "DEEPSEEK_API_KEY" release.unsetEnvironment;
assert handRun.drvPath == (handRun.override { permissive = false; }).drvPath;
assert handRun.drvPath != permissive.drvPath;
assert builtins.elem handRun nas.home-manager.users.tom.home.packages;
assert !(builtins.elem permissive nas.home-manager.users.tom.home.packages);
assert nas.users.users.tom.linger;
assert builtins.all disabled [
  "client"
  "strix-coordinator"
  "strix-worker"
];
assert lib.hasInfix "X-RestartIfChanged=false" unit;
assert lib.hasInfix "X-StopOnRemoval=false" unit;
assert !(lib.hasInfix "/nix/store/" unit);
assert !(lib.hasInfix "Environment=" unit);
assert
  nas.environment.etc."dshd/releases/default".source
  == nas.environment.etc."dshd/releases/nas".source;
assert !(lib.any (name: lib.hasPrefix "dshd" name) (builtins.attrNames nas.systemd.user.timers));
assert
  !(lib.any (name: lib.hasPrefix "dshd@" name && name != "dshd@") (
    builtins.attrNames nas.systemd.user.services
  ));
pkgs.runCommand "dshd-nas" { } ''
  touch "$out"
''
