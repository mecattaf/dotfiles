{ pkgs, configurations }:
let
  inherit (pkgs) lib;
  nas = configurations.nas.config;
  release = nas.dshd.releases.nas;
  handRun = nas.home-manager.users.tom.home.packages;
  nativeDsh = configurations.nas.pkgs.llm-agents.dsh;
  unit = nas.systemd.user.units."dshd@.service".text;
  disabled = name: !configurations.${name}.config.dshd.enable;
in
assert nas.dshd.enable;
assert builtins.attrNames nas.dshd.releases == [ "nas" ];
assert nas.dshd.defaultRelease == null;
assert release.dsh.drvPath == nativeDsh.drvPath;
assert release.environment == { };
assert release.unsetEnvironment == [ "CLOUDFLARE_API_TOKEN" ];
assert !(builtins.elem nativeDsh handRun);
assert builtins.any (package: lib.getName package == "dsh") handRun;
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
