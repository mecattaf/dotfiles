{
  pkgs,
  self,
  lib,
}:
# substrate-modules: the rendered shape of modules/substrate.nix, proven at evaluation time.
#
# `nix flake check --no-build` evaluates this derivation's inputs, which forces the coordinator's
# services.substrate config twice: as declared (both gates OFF, no unit rendered, no secret declared) and
# armed through extendModules with fixtures (a stub puller, empty files standing in for the age files), which
# renders both user units, the pusher.json, the runtimes.toml and the puller's config.toml.
# `nix build .#checks.<system>.substrate-modules` then parses the three files: the TOML decodes, every runtime
# table has a type the runners know, ssh:worker and the cc2 config dir are present, the [puller] table carries the
# credential placeholders, and no rendered file carries a token-shaped key or a credential path.
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
            # A stub, so building this check does not build the puller's node_modules tree; the real
            # package is asserted on the declared host below (evaluated, not built).
            puller.package = pkgs.writeShellScriptBin "substrate-puller" "exit 78";
            tokenAgeFile = pkgs.writeText "substrate-floor-token.age" "eval fixture, not a secret";
            puller.linkTokenAgeFile = pkgs.writeText "substrate-link-token-coordinator.age" "eval fixture, not a secret";
          };
        }
      ];
    }).config;
  pusherUnit = armed.systemd.user.services.substrate-pusher;
  pullerUnit = armed.systemd.user.services.substrate-puller;
  inherit (lib) hasInfix;
in
# Declared OFF on the real host, and the import survived (the option exists).
assert declared.services ? substrate;
assert declared.services.substrate.pusher.enable == false;
assert declared.services.substrate.puller.enable == false;
assert declared.services.substrate.floorUrl == "https://substrate.mecattaf.dev";
assert !(declared.systemd.user.services ? substrate-pusher);
assert !(declared.systemd.user.services ? substrate-puller);
assert !(declared.age.secrets ? substrate-floor-token);
assert !(declared.age.secrets ? substrate-link-token-coordinator);
# The real packages are the defaults (evaluated here, not built).
assert declared.services.substrate.puller.package.pname == "substrate-puller";
assert declared.services.substrate.pusher.package.pname == "substrate-pusher";
# Armed: both units exist, both take their bearers as credentials, never as values.
assert armed.age.secrets.substrate-floor-token.owner == "tom";
assert armed.age.secrets.substrate-link-token-coordinator.owner == "tom";
assert
  pusherUnit.serviceConfig.LoadCredential == [ "floor-token:/run/agenix/substrate-floor-token" ];
assert
  pullerUnit.serviceConfig.LoadCredential == [
    "floor-token:/run/agenix/substrate-floor-token"
    "link-token:/run/agenix/substrate-link-token-coordinator"
  ];
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
    clientToml = armed.services.substrate.puller.clientConfigFile;
    pullerStart = pullerUnit.serviceConfig.ExecStart;
  }
  ''
    python3 - "$pusherJson" "$runtimesToml" "$pullerStart" "$clientToml" <<'PY'
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
    assert "@FLOOR_TOKEN_FILE@" in start and "@LINK_TOKEN_FILE@" in start and "CREDENTIALS_DIRECTORY" in start
    assert "AX_CONWIP_RUNTIMES=" in start and "SUBSTRATE_CLIENT_CONFIG=" in start and "SUBSTRATE_CONFIG=" in start
    client = tomllib.load(open(sys.argv[4], "rb"))
    assert client["floor_url"].startswith("https://") and client["token_file"] == "@FLOOR_TOKEN_FILE@", client
    p = client["puller"]
    assert p["holder"] == "coordinator" and p["link_token_file"] == "@LINK_TOKEN_FILE@" and p["seat"] == "cc2", p
    assert p["node_dispatch"] == "local" and p["runtimes"].endswith("substrate-runtimes.toml") and p["max_runs"] == 1, p
    assert p["state_dir"] == "/home/tom/.local/state/substrate/puller"
    for f in (sys.argv[1], sys.argv[2], sys.argv[4]):
        text = open(f).read()
        assert "/run/agenix" not in text and "/run/user" not in text, f
    print("substrate-modules: pusher.json, runtimes.toml and config.toml render as expected")
    PY
    touch "$out"
  ''
