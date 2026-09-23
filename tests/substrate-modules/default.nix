{
  pkgs,
  self,
  lib,
}:
# substrate-modules: the rendered shape of modules/substrate.nix, proven at evaluation time.
#
# `nix flake check --no-build` evaluates this derivation's inputs, which forces the coordinator's
# services.substrate config twice: as declared (both gates OFF, no unit rendered, no secret declared) and
# armed through extendModules with fixtures (a stub puller, an empty file standing in for the age file), which
# renders both user units, the pusher.json and the runtimes.toml. `nix build .#checks.<system>.substrate-modules`
# then parses both files: the TOML decodes, every runtime table has a type the runners know, ssh:worker and the
# cc2 config dir are present, and no rendered file carries a token-shaped key.
let
  coord = self.nixosConfigurations.coordinator;
  declared = coord.config;
  armed =
    (coord.extendModules {
      modules = [
        {
          services.substrate = {
            pusher.enable = lib.mkForce true;
            puller.enable = lib.mkForce true;
            puller.package = pkgs.writeShellScriptBin "substrate-puller" "exit 78";
            tokenAgeFile = pkgs.writeText "substrate-floor-token.age" "eval fixture, not a secret";
          };
        }
      ];
    }).config;
  pusherUnit = armed.systemd.user.services.substrate-pusher;
  pullerUnit = armed.systemd.user.services.substrate-puller;
  hasInfix = lib.hasInfix;
in
# Declared OFF on the real host, and the import survived (the option exists).
assert declared.services ? substrate;
assert declared.services.substrate.pusher.enable == false;
assert declared.services.substrate.puller.enable == false;
assert declared.services.substrate.floorUrl == "https://substrate.mecattaf.dev";
assert !(declared.systemd.user.services ? substrate-pusher);
assert !(declared.systemd.user.services ? substrate-puller);
assert !(declared.age.secrets ? substrate-floor-token);
# Armed: both units exist, both take the bearer as a credential, never as a value.
assert armed.age.secrets.substrate-floor-token.owner == "tom";
assert
  pusherUnit.serviceConfig.LoadCredential == [ "floor-token:/run/agenix/substrate-floor-token" ];
assert
  pullerUnit.serviceConfig.LoadCredential == [ "floor-token:/run/agenix/substrate-floor-token" ];
assert hasInfix "--token-file %d/floor-token" pusherUnit.serviceConfig.ExecStart;
assert pusherUnit.unitConfig.ConditionUser == "tom";
assert pullerUnit.environment.CLAUDE_CONFIG_DIR == "/home/tom/.claude-work";
assert pullerUnit.environment.TALLY_SEAT == "cc2";
assert pullerUnit.serviceConfig.RuntimeDirectory == "substrate-puller";
pkgs.runCommand "substrate-modules"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    pusherJson = armed.services.substrate.pusher.configFile;
    runtimesToml = armed.services.substrate.puller.runtimesFile;
    pullerStart = pullerUnit.serviceConfig.ExecStart;
  }
  ''
    python3 - "$pusherJson" "$runtimesToml" "$pullerStart" <<'PY'
    import json, sys, tomllib
    pusher = json.load(open(sys.argv[1]))
    assert pusher["floorUrl"].startswith("https://"), pusher
    assert "tokenFile" not in pusher and not any("token" in k.lower() for k in pusher), list(pusher)
    assert pusher["seats"] == ["cc", "cc2", "codex", "pi-qwencloud", "halogen"], pusher["seats"]
    assert pusher["seatIds"] == {"gpu-worker": "halogen"}
    assert pusher["seatsBin"] == "/home/tom/.local/bin/seats"
    rt = tomllib.load(open(sys.argv[2], "rb"))
    known = {"host", "herdr", "gvisor", "microvm", "ssh", "workerd", "ax"}
    for name, table in rt["runtime"].items():
        assert table["type"] in known, (name, table)
    assert rt["default"] == "host"
    assert rt["runtime"]["ssh:worker"] == {"type": "ssh", "host": "worker", "harness": "pi", "seat": "halogen"}
    assert rt["runtime"]["gvisor"]["runsc"].endswith("/bin/runsc") and rt["runtime"]["gvisor"]["pasta"].endswith("/bin/pasta")
    assert rt["credentials"]["claude"] == "/home/tom/.claude-work"
    assert rt["seats"] == {"claude": "cc2", "pi": "halogen", "codex": "codex"}
    assert set(rt["allow"]) == {"host", "herdr", "gvisor", "ssh:worker"}
    start = open(sys.argv[3]).read()
    assert "@FLOOR_TOKEN_FILE@" in start and "CREDENTIALS_DIRECTORY" in start and "AX_CONWIP_RUNTIMES=" in start
    print("substrate-modules: pusher.json and runtimes.toml render as expected")
    PY
    touch "$out"
  ''
