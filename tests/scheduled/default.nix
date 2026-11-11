{ pkgs, configurations }:
let
  inherit (pkgs) lib;
  nas = configurations.nas.config;
  hm = nas.home-manager.users.tom;
  units = hm.systemd.user;
  timer = units.timers.scheduled-heartbeat;
  tick = units.services.scheduled-heartbeat;
  tunnel = units.services.scheduled-panel-tunnel;
  scheduled = configurations.nas.pkgs.scheduled;
  timersOf =
    name:
    let
      users = configurations.${name}.config.home-manager.users;
    in
    builtins.attrNames (users.tom.systemd.user.timers or { });
  storeFree = unit: !(lib.hasInfix "/nix/store/" (builtins.toJSON unit));
  targets = map (f: f.target) (builtins.attrValues hm.home.file);
in
assert timer.Timer == {
  OnCalendar = "hourly";
  OnStartupSec = "2min";
  Persistent = true;
};
assert timer.Install.WantedBy == [ "timers.target" ];
assert storeFree timer && storeFree tunnel;
assert tick.Service.Type == "oneshot";
assert tick.Unit.X-RestartIfChanged == false;
assert tick.Unit.StartLimitIntervalSec == 0;
assert lib.toList tick.Service.ExecStart == [ "${lib.getExe scheduled} tick" ];
assert !(tick ? Install);
assert builtins.elem scheduled hm.home.packages;
assert !(lib.any (t: lib.hasPrefix ".agency" t) targets);
assert timersOf "nas" == [
  "paper-daemon-flush"
  "scheduled-heartbeat"
  "speech-queue"
];
assert lib.all (h: !(builtins.elem "scheduled-heartbeat" (timersOf h))) [
  "client"
  "strix-coordinator"
  "strix-worker"
];
assert builtins.elem "CLAUDECODE" nas.dshd.releases.nas.unsetEnvironment;
assert !(builtins.elem "CLAUDE_CONFIG_DIR"
  nas.dshd.releases.nas.unsetEnvironment);
# The tests run on a writable copy: the stub dshd's `#!/usr/bin/env node` needs patchShebangs (the build sandbox has no
# /usr/bin/env), and the if.idle gate spawns python3.
pkgs.runCommand "scheduled" { nativeBuildInputs = [ scheduled.node pkgs.python3 ]; } ''
  export HOME=$TMPDIR
  export SCHEDULED_PYTHON=${lib.getExe pkgs.python3}
  # Commands get the host's exact PATH (DESIGN 5.2), which the sandbox lacks.
  export SCHEDULED_PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.bash pkgs.python3 ]}
  cp -r ${scheduled}/share/scheduled $TMPDIR/scheduled
  chmod -R u+w $TMPDIR/scheduled
  cd $TMPDIR/scheduled
  patchShebangs test
  node --test 'test/*.test.mjs'
  ${lib.getExe scheduled} --version
  touch $out
''
