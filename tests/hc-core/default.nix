{ pkgs, configurations }:
# hc on the brain host (home/herdr-core.nix, modules/herdr-core.nix): eval
# asserts on the real NAS config, then the rendered unit and the config link
# are read back. The live behaviour (config, start, 7501 status, stop,
# hc-restart-clean) is tests/hc-core/smoke.sh, run under runtime-test.
let
  inherit (pkgs) lib;
  nas = configurations.nas.config;
  hm = nas.home-manager.users.tom;
  svc = hm.systemd.user.services.hc-core;
  herdr-core = configurations.nas.pkgs.llm-agents.herdr-core;
  terminfo = configurations.nas.pkgs.kitty.terminfo;
  exec = lib.toList svc.Service.ExecStart;
  unsetEnvironment = lib.toList svc.Service.UnsetEnvironment;
  homeOf = name: configurations.${name}.config.home-manager.users.tom;
  timersOf = name: builtins.attrNames ((homeOf name).systemd.user.timers or { });
  # The repo's config, as hc reads it; hc 0.1.22 has exactly these 11 keys
  # (crates/herdr-core/src/config.rs) and ignores unknown ones silently.
  toml = builtins.fromTOML (builtins.readFile ../../home/dot_config/herdr-core/config.toml);
  knownKeys = [
    "shell"
    "detach_key"
    "wait_timeout"
    "notes"
    "notes_quiet"
    "draft_wait"
    "headless"
    "history_mb"
    "restore_screen"
    "socket"
    "machine_timeout"
  ];
  configLink = hm.xdg.configFile."herdr-core/config.toml".source;
  unit = hm.xdg.configFile."systemd/user/hc-core.service".source;
  # Agent templates: the repo's files and the links Home Manager makes.
  templateDir = ../../home/dot_config/herdr-core/templates;
  templateFiles = builtins.attrNames (builtins.readDir templateDir);
  templateLinksOf =
    name: lib.filter (lib.hasPrefix "herdr-core/templates/") (builtins.attrNames (homeOf name).xdg.configFile);
in
assert svc.Unit.Description == "hc core for this machine (default session)";
assert svc.Unit.X-SwitchMethod == "keep-old";
assert svc.Service.Type == "oneshot";
assert svc.Service.RemainAfterExit == true;
assert svc.Service.KillMode == "process";
assert svc.Service.OOMPolicy == "continue";
assert svc.Service.WorkingDirectory == "%h";
# hc's own transient units supervise; a unit that restarts, stops or wraps the
# core fights them (home/herdr-core.nix).
assert !(svc.Service ? Restart);
assert !(svc.Service ? ExecStop);
# Home Manager fills Environment with [ ] by default: no value may be set.
assert (svc.Service.Environment or [ ]) == [ ];
assert !(svc.Service ? ManagedOOMPreference);
assert !(svc.Service ? MemoryMax) && !(svc.Service ? MemoryHigh);
assert exec == [ "${herdr-core}/bin/herdr-core server start" ];
assert lib.hasPrefix "${herdr-core}/" (builtins.head exec);
assert lib.hasSuffix "/bin/herdr-core server start" (builtins.head exec);
assert lib.all (name: builtins.elem name unsetEnvironment) [
  "CLOUDFLARE_API_TOKEN"
  "CLAUDECODE"
  "CLAUDE_CODE_SESSION_ID"
  "CLAUDE_CODE_MESSAGING_TOKEN"
  "CODEX_THREAD_ID"
  "DSH_SESSION_ID"
  "HC_SESSION"
  "HC_SOCKET"
];
assert svc.Install.WantedBy == [ "default.target" ];
# The brain carries kitty's terminfo system-wide (modules/herdr-core.nix).
assert lib.any (p: (p.outPath or null) == terminfo.outPath) nas.environment.systemPackages;
# The config file and the unit exist on the brain only.
assert hm.xdg.configFile ? "herdr-core/config.toml";
assert lib.all
  (
    name:
    !((homeOf name).systemd.user.services ? hc-core)
    && !((homeOf name).xdg.configFile ? "herdr-core/config.toml")
  )
  [
    "client"
    "strix-coordinator"
    "strix-worker"
  ];
# The repo's config.toml: notes on, the contract values (P1 §5.9), no socket,
# and nothing hc would silently ignore.
assert toml.notes == true;
assert toml.draft_wait == 60;
assert toml.headless == "120x40";
assert
  toml.shell == [
    "/run/current-system/sw/bin/fish"
    "--login"
  ];
assert !(toml ? socket);
assert lib.all (k: builtins.elem k knownKeys) (builtins.attrNames toml);
# No new clock: the NAS keeps its three timers, and hc adds none.
assert
  timersOf "nas" == [
    "paper-daemon-flush"
    "scheduled-heartbeat"
    "speech-queue"
  ];
assert !(hm.systemd.user.timers ? hc-core);
# Templates: named worker-*, never like a binary (it would shadow that binary
# for every caller); each file has a header with a command; every repo file is
# linked on the brain and none anywhere else.
assert lib.all (f: builtins.match "worker-[a-z0-9-]+\\.md" f != null) templateFiles;
assert lib.all (
  f:
  let
    text = builtins.readFile (templateDir + "/${f}");
  in
  lib.hasPrefix "---\n" text && lib.hasInfix "\ncommand: " text
) templateFiles;
assert builtins.elem "worker-claude.md" templateFiles && builtins.elem "worker-codex.md" templateFiles;
assert templateLinksOf "nas" == map (f: "herdr-core/templates/${f}") templateFiles;
assert lib.all (
  name: builtins.match "herdr-core/templates/worker-[a-z0-9-]+\\.md" name != null
) (templateLinksOf "nas");
assert lib.all (name: templateLinksOf name == [ ]) [
  "client"
  "strix-coordinator"
  "strix-worker"
];
pkgs.runCommand "hc-core" { nativeBuildInputs = [ pkgs.dash ]; } ''
  set -eu
  unit=${unit}
  for line in Type=oneshot RemainAfterExit=true KillMode=process OOMPolicy=continue \
              X-SwitchMethod=keep-old WorkingDirectory=%h WantedBy=default.target \
              'ExecStart=${herdr-core}/bin/herdr-core server start'; do
    grep -qxF "$line" "$unit" || { echo "hc-core.service lacks: $line"; cat "$unit"; exit 1; }
  done
  for key in Restart ExecStop Environment ManagedOOMPreference; do
    if grep -q "^$key=" "$unit"; then echo "hc-core.service must not set $key"; cat "$unit"; exit 1; fi
  done
  grep -Eq '^UnsetEnvironment=(.* )?CLAUDECODE( .*)?$' "$unit" \
    || { echo "hc-core.service does not unset CLAUDECODE"; cat "$unit"; exit 1; }
  # A single-file raw link into the checkout, never a store copy (hot edit).
  test "$(readlink ${configLink})" = /home/tom/mecattaf/dotfiles/home/dot_config/herdr-core/config.toml
  ${lib.concatMapStrings (f: ''
    test "$(readlink ${
      hm.xdg.configFile."herdr-core/templates/${f}".source
    })" = /home/tom/mecattaf/dotfiles/home/dot_config/herdr-core/templates/${f}
  '') templateFiles}
  dash -n ${../../home/dot_local/bin/hc-restart-clean}
  touch $out
''
