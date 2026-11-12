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
  # The installed command: the package wrapped with the inbox and floor as
  # defaults (home/scheduled.nix), since no NAS shell reads session variables.
  cli = lib.findFirst (p: p ? floorInstance && p ? unwrapped) null hm.home.packages;
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
assert cli != null && cli.unwrapped == scheduled;
assert cli.inbox == inbox && cli.floorInstance == "floor";
assert !(hm.home.sessionVariables ? SCHEDULED_INBOX);
assert !(hm.home.sessionVariables ? SCHEDULED_FLOOR_INSTANCE);
assert tick.Service.Nice == 10;
# Its own state is systemd's StateDirectory, never inside .agency/state.
assert tick.Service.StateDirectory == "scheduled";
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
assert builtins.elem "CLAUDECODE" nas.dshd.releases.nas.unsetEnvironment;
assert !(builtins.elem "CLAUDE_CONFIG_DIR"
  nas.dshd.releases.nas.unsetEnvironment);
# The tests run on a writable copy: the stub dshd's `#!/usr/bin/env node` needs patchShebangs (the build sandbox has no
# /usr/bin/env). Node 24 refuses `node --test test/`, so the glob names the files.
pkgs.runCommand "scheduled" { nativeBuildInputs = [ scheduled.node ]; } ''
  export HOME=$TMPDIR
  cp -r ${scheduled}/share/scheduled $TMPDIR/scheduled
  chmod -R u+w $TMPDIR/scheduled
  cd $TMPDIR/scheduled
  patchShebangs test
  node --test 'test/*.test.mjs'
  ${lib.getExe scheduled} --version
  # The installed command carries the defaults, and a variable set by hand
  # still wins (makeWrapper --set-default).
  grep -qxF "export SCHEDULED_INBOX=\''${SCHEDULED_INBOX-'${inbox}'}" ${lib.getExe cli}
  grep -qxF "export SCHEDULED_FLOOR_INSTANCE=\''${SCHEDULED_FLOOR_INSTANCE-'floor'}" ${lib.getExe cli}
  ${lib.getExe cli} --version
  touch $out
''
