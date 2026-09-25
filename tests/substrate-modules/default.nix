{
  pkgs,
  self,
  lib,
}:
# substrate-modules: the rendered shape of modules/substrate.nix, proven at evaluation time.
#
# `nix flake check --no-build` evaluates this derivation's inputs, which forces the coordinator's
# services.substrate config twice: as declared (both gates ON since 2026-09-24, both units rendered, both
# secrets declared from the two named age files) and armed through extendModules with fixtures (a stub puller,
# files standing in for the age files), which renders both user units, the pusher.json, the runtimes.toml and the
# puller's config.toml without a token on disk. `nix build .#checks.<system>.substrate-modules` then parses the
# three files against the 2026-09-24 proven deployment plus the 2026-09-25 ssh runtime: runtimes
# opus/halogen/codex/codex-rw and ssh:worker (type ssh, host worker, harness pi, seat halogen: lane B's pi runs on
# the worker through the ssh runner, merged in from puller.sshRuntimes; still no herdr or gvisor), [credentials.seats]
# with cc2 = ~/.claude-work, pusher.json with peerCacheDir and no tokenFile, the [puller] table with the two
# credential placeholders, and no rendered file carrying a token-shaped key or a credential path. It also pins the
# academic drain's standing submit (modules/academic-drain.nix, ON on the coordinator since 2026-09-25): the user
# service and timer, the timer's OnCalendar, the floor token as a credential, and a rendered script with no
# token-shaped literal.
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
  standing = declared.systemd.user.services.academic-drain-standing;
  standingTimer = declared.systemd.user.timers.academic-drain-standing;
  pusherUnit = armed.systemd.user.services.substrate-pusher;
  pullerUnit = armed.systemd.user.services.substrate-puller;
  inherit (lib) hasInfix;
in
# Declared ON on the real host (2026-09-24), from the two named age files, and the import survived.
assert declared.services ? substrate;
assert declared.services.substrate.pusher.enable == true;
assert declared.services.substrate.puller.enable == true;
assert declared.services.substrate.floorUrl == "https://substrate.mecattaf.dev";
assert declared.services.substrate.puller.runtimeTestWrapper == null;
assert declared.systemd.user.services ? substrate-pusher;
assert declared.systemd.user.services ? substrate-puller;
assert baseNameOf declared.age.secrets.substrate-floor-token.file == "substrate-floor-token.age";
assert
  baseNameOf declared.age.secrets.substrate-link-token-coordinator.file
  == "substrate-link-token-coordinator.age";
assert declared.age.secrets.substrate-floor-token.owner == "tom";
assert declared.age.secrets.substrate-floor-token.mode == "0400";
assert declared.age.secrets.substrate-link-token-coordinator.owner == "tom";
assert declared.age.secrets.substrate-link-token-coordinator.mode == "0400";
# secrets.nix names both, coordinator-only (read as data, never imported into the host eval).
assert (import ../../secrets.nix) ? "secrets/substrate-floor-token.age";
assert (import ../../secrets.nix) ? "secrets/substrate-link-token-coordinator.age";
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
# Environment=PATH replaces the manager's PATH: both units must name the user's profile themselves, or the
# runners' bare claude/pi/codex and seats' bare codex fail with ENOENT.
assert hasInfix "/etc/profiles/per-user/tom/bin" pullerUnit.environment.PATH;
assert hasInfix "/home/tom/.local/bin" pullerUnit.environment.PATH;
assert hasInfix "/etc/profiles/per-user/tom/bin" pusherUnit.environment.PATH;
assert hasInfix "/home/tom/.local/bin" pusherUnit.environment.PATH;
assert hasInfix "/etc/profiles/per-user/tom/bin"
  declared.systemd.user.services.substrate-puller.environment.PATH;
assert pullerUnit.serviceConfig.RuntimeDirectory == "substrate-puller";
# The standing lane B submit: a oneshot user service on a Persistent=false timer, the bearer by LoadCredential.
assert declared.services.academicDrain.standing.enable;
assert standing.serviceConfig.Type == "oneshot";
assert standing.unitConfig.ConditionUser == "tom";
assert standing.serviceConfig.LoadCredential == [ "floor-token:/run/agenix/substrate-floor-token" ];
assert !(standing ? wantedBy) || standing.wantedBy == [ ];
assert standingTimer.timerConfig.OnCalendar == "*-*-* 01:30:00";
assert standingTimer.timerConfig.Persistent == false;
assert standingTimer.wantedBy == [ "timers.target" ];
assert declared.services.academicDrain.standing.args.runtime == "ssh:worker";
# puller.sshRuntimes MERGES into the default runtimes (a hand-set runtimes.runtime."ssh:worker" would replace it).
assert declared.services.substrate.puller.sshRuntimes ? "ssh:worker";
assert
  builtins.attrNames declared.services.substrate.puller.runtimes.runtime == [
    "codex"
    "codex-rw"
    "halogen"
    "opus"
    "ssh:worker"
  ];
# The pidfile is in the RuntimeDirectory, so a hold is transient: 3 must be retried, not terminal.
assert !(builtins.elem 3 pullerUnit.serviceConfig.RestartPreventExitStatus);
assert builtins.elem 75 pullerUnit.serviceConfig.RestartPreventExitStatus;
pkgs.runCommand "substrate-modules"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    pusherJson = armed.services.substrate.pusher.configFile;
    runtimesToml = armed.services.substrate.puller.runtimesFile;
    clientToml = armed.services.substrate.puller.clientConfigFile;
    pullerStart = pullerUnit.serviceConfig.ExecStart;
    standingScript = standing.serviceConfig.ExecStart;
  }
  ''
    python3 - "$pusherJson" "$runtimesToml" "$pullerStart" "$clientToml" "$standingScript" <<'PY'
    import json, re, sys, tomllib
    pusher = json.load(open(sys.argv[1]))
    assert pusher["floorUrl"].startswith("https://"), pusher
    assert "tokenFile" not in pusher and not any("token" in k.lower() for k in pusher), list(pusher)
    assert pusher["seats"] == ["cc", "cc2", "codex", "pi-qwencloud", "halogen"], pusher["seats"]
    assert pusher["seatIds"] == {"gpu-worker": "halogen"}
    assert pusher["seatsBin"] == "/home/tom/.local/bin/seats"
    rt = tomllib.load(open(sys.argv[2], "rb"))
    known = {"host", "runtime-test", "herdr", "gvisor", "microvm", "ssh", "workerd", "ax"}
    for name, table in rt["runtime"].items():
        assert table["type"] in known, (name, table)
    assert rt["default"] == "opus", rt["default"]
    assert rt["allow"] == ["opus", "halogen", "codex", "codex-rw", "ssh:worker"], rt["allow"]
    assert set(rt["runtime"]) == {"opus", "halogen", "codex", "codex-rw", "ssh:worker"}, list(rt["runtime"])
    assert not {"herdr", "gvisor"} & set(rt["runtime"]), list(rt["runtime"])
    for name in ("opus", "halogen", "codex", "codex-rw", "ssh:worker"):
        assert isinstance(rt["runtime"][name].get("timeoutMs"), int) and rt["runtime"][name]["timeoutMs"] >= 900000, (name, rt["runtime"][name])
    strip = lambda t: {k: v for k, v in t.items() if k != "timeoutMs"}
    assert strip(rt["runtime"]["opus"]) == {"type": "host", "harness": "claude", "seat": "cc2"}
    assert strip(rt["runtime"]["halogen"]) == {"type": "host", "harness": "pi", "seat": "halogen"}
    assert strip(rt["runtime"]["codex"]) == {"type": "host", "harness": "codex", "seat": "codex", "codexSandbox": "read-only"}
    assert strip(rt["runtime"]["codex-rw"]) == {"type": "host", "harness": "codex", "seat": "codex", "codexSandbox": "workspace-write"}
    # SshRuntime (packages/runners/src/config.ts:116-121): type, host, and the common harness, seat, timeoutMs.
    assert rt["runtime"]["ssh:worker"] == {"type": "ssh", "host": "worker", "harness": "pi", "seat": "halogen", "timeoutMs": 1800000}, rt["runtime"]["ssh:worker"]
    # The loader's guardrail (packages/runners/src/config.ts): codexSandbox only on the codex harness.
    for name, table in rt["runtime"].items():
        assert "codexSandbox" not in table or table.get("harness") == "codex", name
    assert rt["seats"] == {"claude": "cc2", "pi": "halogen", "codex": "codex"}
    cred = rt["credentials"]
    assert cred["claude"] == "/home/tom/.claude-work" and cred["mode"] == "rw" and cred["scope"] == "credential", cred
    assert cred["seats"] == {"cc": "/home/tom/.claude", "cc2": "/home/tom/.claude-work"}, cred
    assert all(d.startswith("/") for d in cred["seats"].values())
    assert len(set(cred["seats"].values())) == len(cred["seats"]), "one config dir is one seat"
    assert pusher["peerCacheDir"] == "inherit", pusher
    assert pusher["not_dispatchable"] == {"cc3": "evicted", "gpu-coordinator": "halogen is declared but not resident on the coordinator"}
    assert pusher["owners"] == {"codex": "tom"}
    start = open(sys.argv[3]).read()
    assert "@FLOOR_TOKEN_FILE@" in start and "@LINK_TOKEN_FILE@" in start and "CREDENTIALS_DIRECTORY" in start
    assert "AX_CONWIP_RUNTIMES=" in start and "SUBSTRATE_CLIENT_CONFIG=" in start and "SUBSTRATE_CONFIG=" in start
    client = tomllib.load(open(sys.argv[4], "rb"))
    assert client["floor_url"].startswith("https://") and client["token_file"] == "@FLOOR_TOKEN_FILE@", client
    p = client["puller"]
    assert p["holder"] == "coordinator" and p["link_token_file"] == "@LINK_TOKEN_FILE@" and p["seat"] == "cc2", p
    assert p["node_dispatch"] == "local" and p["runtimes"].endswith("substrate-runtimes.toml") and isinstance(p["max_runs"], int) and p["max_runs"] >= 1, p
    assert p["state_dir"] == "/home/tom/.local/state/substrate/puller"
    assert p["pidfile"] == "@RUNTIME_DIRECTORY@/puller.pid" and isinstance(p["cap"], int) and p["cap"] >= 1, p
    assert "s|@RUNTIME_DIRECTORY@|$RUNTIME_DIRECTORY|" in start, "the start script must fill the pidfile placeholder"
    assert p["default_model"] == "claude-opus-5-5", p
    assert p["demand_dir"] == "/home/tom/.local/state/substrate/demand", p
    assert p["drain_timeout_s"] == 60 and p["capacity_wait_s"] == 600, p
    assert "health_addr" not in p and "ax_server" not in p, p
    assert client["token_file"] == "@FLOOR_TOKEN_FILE@" and client["puller"]["link_token_file"] == "@LINK_TOKEN_FILE@"
    token_shaped = re.compile(r"(sk-ant-|sk-[A-Za-z0-9]{20,}|ghp_|eyJ[A-Za-z0-9_-]{10,}\.|[A-Fa-f0-9]{40,}|[A-Za-z0-9+/_-]{48,})")
    for f in (sys.argv[1], sys.argv[2], sys.argv[4]):
        text = open(f).read()
        assert "/run/agenix" not in text and "/run/user" not in text and "/.local/state/substrate/floor-token" not in text, f
        # No token-shaped value anywhere; store paths are masked first (their hashes are 32 base32 chars).
        masked = re.sub(r"/nix/store/[a-z0-9]{32}-", "/nix/store/HASH-", text)
        assert not token_shaped.search(masked), (f, token_shaped.search(masked).group(0))
    standing = open(sys.argv[5]).read()
    assert "CREDENTIALS_DIRECTORY" in standing and "/floor-token" in standing, "the standing submit reads the bearer from its credential"
    assert "authorization: Bearer %s" in standing and "@<(auth)" in standing, "the bearer goes to curl as a header file, never argv"
    assert "acadlb" in standing and "academic-drain-lane-b" in standing and "/runs" in standing
    assert "/run/agenix" not in standing and "/.local/state/substrate/floor-token" not in standing
    masked = re.sub(r"/nix/store/[a-z0-9]{32}-", "/nix/store/HASH-", standing)
    assert not token_shaped.search(masked), ("standing submit", token_shaped.search(masked).group(0))
    print("substrate-modules: pusher.json, runtimes.toml and config.toml render the 2026-09-24 proven shape plus ssh:worker; the standing submit carries no token")
    PY
    touch "$out"
  ''
