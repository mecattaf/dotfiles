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
  # The one shared value (docs/scheduled.md): the Master profile's
  # dsh-superagent stateDir, whose <stateDir>/inbox/scheduled the floor's
  # scheduled Source reads.
  inbox = "${hm.programs.dsh.master.stateDir}/inbox/scheduled";
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
# The heartbeat links records into the Master profile's inbox and wakes the
# instance the Master floor recipe names.
assert builtins.elem "SCHEDULED_INBOX=${inbox}" environment;
assert builtins.elem "SCHEDULED_FLOOR_INSTANCE=floor" environment;
assert hm.home.sessionVariables.SCHEDULED_INBOX == inbox;
assert hm.home.sessionVariables.SCHEDULED_FLOOR_INSTANCE == "floor";
# Its own state is systemd's StateDirectory, never inside .agency/state.
assert tick.Service.StateDirectory == "scheduled";
assert tick.Service.StateDirectoryMode == "0700";
# The tunnel forwards the Master web profile's port, from its one option.
assert lib.hasInfix
  "-R 127.0.0.1:${toString hm.programs.dsh.master.webPort}:127.0.0.1:${toString hm.programs.dsh.master.webPort} "
  tunnel.Service.ExecStart;
assert !(lib.any (e: lib.hasPrefix "SCHEDULED_STATE_DIR=" e) environment);
assert !(lib.hasInfix "--state-dir" (toString tick.Service.ExecStart));
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
# The tests run on a writable copy of the package plus the suite from the
# source tree: the stub dshd's `#!/usr/bin/env node` needs patchShebangs (the build sandbox has no
# /usr/bin/env). Node 24 refuses `node --test test/`, so the glob names the files.
pkgs.runCommand "scheduled" { nativeBuildInputs = [ scheduled.node ]; } ''
  export HOME=$TMPDIR
  cp -r ${scheduled}/share/scheduled $TMPDIR/scheduled
  chmod -R u+w $TMPDIR/scheduled
  # The suite and the stub dshd stay out of the installed package.
  test ! -e $TMPDIR/scheduled/test
  cp -r ${../../pkgs/scheduled/test} $TMPDIR/scheduled/test
  chmod -R u+w $TMPDIR/scheduled/test
  cd $TMPDIR/scheduled
  patchShebangs test
  node --test 'test/*.test.mjs'
  ${lib.getExe scheduled} --version
  touch $out
''
