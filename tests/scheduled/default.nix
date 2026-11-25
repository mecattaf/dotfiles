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
  # The installed command: the package wrapped with the inbox (and a floor
  # unit, once one is named) as defaults (home/scheduled.nix), since no NAS
  # shell reads session variables.
  cli = lib.findFirst (p: p ? floorUnit && p ? unwrapped) null hm.home.packages;
  timersOf =
    name:
    let
      users = configurations.${name}.config.home-manager.users;
    in
    builtins.attrNames (users.tom.systemd.user.timers or { });
  storeFree = unit: !(lib.hasInfix "/nix/store/" (builtins.toJSON unit));
  targets = map (f: f.target) (builtins.attrValues hm.home.file);
  # The one shared value (docs/scheduled.md): the inbox the retired Master
  # profile's stateDir held, kept at its path on 2026-11-26 so its records
  # stay where the new floor's scheduled Source can be pointed.
  inbox = "/home/tom/.agency/state/master/inbox/scheduled";
  environment = lib.toList tick.Service.Environment;
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
# The heartbeat links records into the inbox and wakes nothing: no floor
# unit is named (R-9, the supported no-floor mode), so the unit's whole
# environment is PATH and the inbox.
assert tick.Unit.ConditionPathIsDirectory == "%h/.agency";
assert builtins.elem "SCHEDULED_INBOX=${inbox}" environment;
assert !(lib.any (e: lib.hasPrefix "SCHEDULED_FLOOR" e) environment);
assert environment == [
  "PATH=/run/current-system/sw/bin"
  "SCHEDULED_INBOX=${inbox}"
];
assert cli != null && cli.unwrapped == scheduled;
assert cli.inbox == inbox && cli.floorUnit == null;
assert !(hm.home.sessionVariables ? SCHEDULED_INBOX);
assert !(hm.home.sessionVariables ? SCHEDULED_FLOOR_UNIT);
assert tick.Service.Nice == 10;
# Its own state is systemd's StateDirectory, never inside .agency/state.
assert tick.Service.StateDirectory == "scheduled";
assert tick.Service.StateDirectoryMode == "0700";
# The tunnel forwards the factory floor's loopback panel port, a literal
# since the Master web profile that owned it was retired (R-10).
assert lib.hasInfix "-R 127.0.0.1:3082:127.0.0.1:3082 " (toString tunnel.Service.ExecStart);
assert !(lib.any (e: lib.hasPrefix "SCHEDULED_STATE_DIR=" e) environment);
assert !(lib.hasInfix "--state-dir" (toString tick.Service.ExecStart));
assert !(tick ? Install);
assert !(builtins.elem scheduled hm.home.packages);
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
# The tests run on a writable copy of the package plus the suite from the
# source tree: the test stubs' `#!/usr/bin/env node` needs patchShebangs (the build sandbox has no
# /usr/bin/env). Node 24 refuses `node --test test/`, so the glob names the files.
pkgs.runCommand "scheduled" { nativeBuildInputs = [ scheduled.node ]; } ''
  export HOME=$TMPDIR
  cp -r ${scheduled}/share/scheduled $TMPDIR/scheduled
  chmod -R u+w $TMPDIR/scheduled
  # The suite and its stubs stay out of the installed package.
  test ! -e $TMPDIR/scheduled/test
  cp -r ${../../pkgs/scheduled/test} $TMPDIR/scheduled/test
  chmod -R u+w $TMPDIR/scheduled/test
  cd $TMPDIR/scheduled
  patchShebangs test
  node --test 'test/*.test.mjs'
  ${lib.getExe scheduled} --version
  # The installed command carries the inbox default, and a variable set by
  # hand still wins (makeWrapper --set-default). No floor unit default while
  # none is named.
  grep -qxF "export SCHEDULED_INBOX=\''${SCHEDULED_INBOX-'${inbox}'}" ${lib.getExe cli}
  if grep -q SCHEDULED_FLOOR ${lib.getExe cli}; then exit 1; fi
  ${lib.getExe cli} --version
  touch $out
''
