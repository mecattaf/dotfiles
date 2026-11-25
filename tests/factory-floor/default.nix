{ pkgs, configurations }:
# factory-floor.service (home/factory-floor.nix): eval asserts on the real NAS
# config, then the launcher against a fake checkout. docs/factory-floor.md.
let
  inherit (pkgs) lib;
  nas = configurations.nas.config;
  hm = nas.home-manager.users.tom;
  cfg = hm.services.factory-floor;
  services = hm.systemd.user.services;
  svc = services.factory-floor;
  comms = services.communications;
  tunnel = services.scheduled-panel-tunnel;
  heartbeat = services.scheduled-heartbeat;
  rendered = hm.xdg.configFile."systemd/user/factory-floor.service".source;
  environment = svc.Service.Environment;
  launcher = lib.head svc.Service.ExecStart;
  herdrCore = configurations.nas.pkgs.llm-agents.herdr-core;
  # The installed heartbeat command (home/scheduled.nix) and the floor unit it
  # would wake.
  cli = lib.findFirst (p: p ? floorUnit && p ? unwrapped) null hm.home.packages;
  servicesOf = name: configurations.${name}.config.home-manager.users.tom.systemd.user.services;
  timersOf =
    name:
    builtins.attrNames (
      configurations.${name}.config.home-manager.users.tom.systemd.user.timers or { }
    );
  home = "/home/tom";
  # The NAS has both flips on (hosts/nas/default.nix). The way back is the
  # module's defaults, evaluated here so a revert is never a first
  # evaluation.
  unflipped =
    (configurations.nas.extendModules {
      modules = [
        {
          home-manager.users.tom.services.factory-floor = {
            autostart = lib.mkForce false;
            heartbeatWake = lib.mkForce false;
          };
        }
      ];
    }).config.home-manager.users.tom;
in
assert cfg.enable;
# The unit keeps communications.service's shape: the same restart, stop and
# start-limit policy, and a private umask.
assert svc.Service.Type == comms.Service.Type && svc.Service.Type == "exec";
assert svc.Service.Restart == comms.Service.Restart;
assert svc.Service.RestartSec == comms.Service.RestartSec;
assert svc.Service.KillSignal == comms.Service.KillSignal;
assert svc.Service.TimeoutStopSec == comms.Service.TimeoutStopSec;
assert svc.Service.UMask == comms.Service.UMask;
assert svc.Unit.StartLimitIntervalSec == comms.Unit.StartLimitIntervalSec;
assert svc.Unit.StartLimitBurst == comms.Unit.StartLimitBurst;
assert svc.Service.RestartPreventExitStatus == 78;
assert svc.Unit.X-SwitchMethod == "keep-old";
# Ordered behind the declared hc core, which it never starts itself.
assert builtins.elem "hc-core.service" svc.Unit.After;
assert builtins.elem "network-online.target" svc.Unit.After;
assert svc.Unit.Wants == [ "hc-core.service" ];
# Autostart (hosts/nas/default.nix): wanted by default.target, so up at boot.
assert cfg.autostart && svc.Install.WantedBy == [ "default.target" ];
# Local-checkout mode: a store launcher runs the built entry of the checkout.
assert cfg.package == null;
assert cfg.checkout == "${home}/mecattaf/factory-floor";
assert cfg.entry == "${home}/mecattaf/factory-floor/bin/agency-service";
assert svc.Unit.ConditionPathExists == cfg.entry;
assert
  lib.hasPrefix builtins.storeDir launcher && lib.hasSuffix "/bin/factory-floor-service" launcher;
# The environment the floor's defaults must equal (docs/factory-floor.md).
assert
  environment == [
    "FACTORY_FLOOR_CHECKOUT=${home}/mecattaf/factory-floor"
    "FACTORY_FLOOR_ENTRY=${home}/mecattaf/factory-floor/bin/agency-service"
    "FACTORY_FLOOR_STATE_DIR=${home}/.agency/state/master/factory-floor"
    "FACTORY_FLOOR_WORK_DIR=${home}/.local/state/factory-floor"
    "FACTORY_FLOOR_CONFIG_DIR=${home}/.config/agency/factory-floor"
    "FACTORY_FLOOR_HOST=127.0.0.1"
    "FACTORY_FLOOR_PORT=3082"
    "HC_BIN=${lib.getExe' herdrCore "herdr-core"}"
  ];
# The per-launch names dropped from the user manager's environment; the same
# list as the hc core's, while both units exist.
assert builtins.elem "CLAUDECODE" svc.Service.UnsetEnvironment;
assert builtins.elem "HC_SESSION" svc.Service.UnsetEnvironment;
assert
  services ? hc-core -> svc.Service.UnsetEnvironment == services.hc-core.Service.UnsetEnvironment;
# A fresh state directory under the master agency, never the agency's state
# directory itself (the retired floor's orchestrator.sqlite sits there).
assert cfg.stateDir != "${home}/.agency/state/master";
assert lib.hasPrefix "${home}/.agency/state/master/" cfg.stateDir;
# Loopback on the port the panel tunnel already forwards to the seat.
assert cfg.host == "127.0.0.1";
assert cfg.port == 3082;
assert lib.hasInfix "-R 127.0.0.1:${toString cfg.port}:127.0.0.1:${toString cfg.port} " (
  toString tunnel.Service.ExecStart
);
# The heartbeat wake (hosts/nas/default.nix): the heartbeat and the installed
# command name this unit. The floor's own scheduled inbox is still not the
# live one: the floor reads the live inbox only when floor.jsonc says so.
assert cfg.heartbeatWake && cfg.floorUnit == "factory-floor.service";
assert cli != null && cli.floorUnit == "factory-floor.service";
assert
  lib.filter (e: lib.hasPrefix "SCHEDULED_FLOOR" e) (lib.toList heartbeat.Service.Environment) == [
    "SCHEDULED_FLOOR_UNIT=factory-floor.service"
  ];
assert "${cfg.stateDir}/inbox/scheduled" != cli.inbox;
# The floor adds no clock: the NAS timer list is unchanged.
assert
  timersOf "nas" == [
    "paper-daemon-flush"
    "scheduled-heartbeat"
    "speech-queue"
  ];
# Only the brain host has the unit.
assert lib.all (h: !((servicesOf h) ? factory-floor)) [
  "client"
  "strix-coordinator"
  "strix-worker"
];
# Both flips off again: wanted by no target, and the heartbeat wakes nothing.
assert !(unflipped.systemd.user.services.factory-floor ? Install);
assert unflipped.services.factory-floor.floorUnit == null;
assert
  !(lib.any (e: lib.hasPrefix "SCHEDULED_FLOOR" e) (
    lib.toList unflipped.systemd.user.services.scheduled-heartbeat.Service.Environment
  ));
pkgs.runCommand "factory-floor" { } ''
  set -eu
  unit=${rendered}
  grep -qxF 'Type=exec' "$unit"
  grep -qxF 'X-SwitchMethod=keep-old' "$unit"
  grep -qxF 'RestartPreventExitStatus=78' "$unit"
  grep -qxF 'ConditionPathExists=${cfg.entry}' "$unit"
  grep -qxF 'ExecStart=${launcher}' "$unit"
  grep -qxF '[Install]' "$unit"
  grep -qxF 'WantedBy=default.target' "$unit"

  # The unit's own environment, with the checkout moved to a fake one whose
  # entry reports what the contract promises it: node 24 and herdr-core on
  # PATH, HC_BIN and the port, and no arguments.
  fake=$TMPDIR/checkout
  mkdir -p "$fake/bin"
  cat > "$fake/bin/agency-service" <<'EOF'
  #!${pkgs.runtimeShell}
  node --version
  command -v herdr-core
  printf 'HC_BIN=%s\n' "$HC_BIN"
  printf 'PORT=%s\n' "$FACTORY_FLOOR_PORT"
  printf 'ARGC=%s\n' "$#"
  EOF
  chmod +x "$fake/bin/agency-service"
  run() {
    env -i ${lib.escapeShellArgs environment} PATH=/var/empty/bin "$@" ${launcher}
  }
  run FACTORY_FLOOR_CHECKOUT="$fake" FACTORY_FLOOR_ENTRY="$fake/bin/agency-service" > out
  cat out
  grep -qE '^v24\.' out
  grep -qxF '${lib.getExe' herdrCore "herdr-core"}' out
  grep -qxF 'HC_BIN=${lib.getExe' herdrCore "herdr-core"}' out
  grep -qxF 'PORT=3082' out
  grep -qxF 'ARGC=0' out
  # A relative entry is resolved against the checkout.
  run FACTORY_FLOOR_CHECKOUT="$fake" FACTORY_FLOOR_ENTRY=bin/agency-service > out-relative
  cmp out out-relative

  # A missing checkout and an entry that is not executable both exit 78
  # (RestartPreventExitStatus) and say what to do.
  rc=0
  run FACTORY_FLOOR_CHECKOUT="$TMPDIR/missing" FACTORY_FLOOR_ENTRY="$TMPDIR/missing/bin/agency-service" 2> err || rc=$?
  test "$rc" = 78
  grep -qF 'build the checkout first (pnpm install && pnpm build)' err
  chmod -x "$fake/bin/agency-service"
  rc=0
  run FACTORY_FLOOR_CHECKOUT="$fake" FACTORY_FLOOR_ENTRY="$fake/bin/agency-service" 2> err || rc=$?
  test "$rc" = 78
  touch $out
''
