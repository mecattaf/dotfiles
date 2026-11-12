{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
# The Master configuration (docs/scheduled.md): one source for the DSH profile
# folders of the master agency's superagent, rendered by pkgs/dsh-master as
#
#   master          web app, superagent engine on: the floor instance
#   master-<pair>   headless, engine off: the workers of one provider-harness pair
#
# Activation copies the rendered files into ~/.dsh/profiles/master* with
# `dsh-master render --quiet`, which needs no network and never runs pnpm.
# Installing the plugins is a hand step (`dsh-master install`, then
# `dsh-master check`). No other profile folder and no ~/.dsh/cordis.patch.yml
# is written: that home layer would change every profile of the home.
let
  cfg = config.programs.dsh.master;
  home = config.home.homeDirectory;
  localModel = import ../lib/local-model.nix;
  inherit (lib) mkOption types;

  pair = types.submodule {
    options = {
      provider = mkOption {
        type = types.str;
        description = "agent-default-model provider of this pair's workers.";
      };
      model = mkOption {
        type = types.str;
        description = "agent-default-model model id.";
      };
      reasoningEffort = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Reasoning effort; null for a model that declares none.";
      };
      env = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Environment of this pair's units. Recorded in each unit's recipe: public values only.";
      };
      maxWorkers = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = "At most this many units of this pair at once.";
      };
    };
  };

  # Profile folders that exist beside Master and are never written.
  otherProfiles = pkgs.dsh.profiles ++ [
    "web"
    "floor"
    "floor-worker"
  ];
  workerNames = map (name: "master-${name}") (builtins.attrNames cfg.pairs);
in
{
  options.programs.dsh.master = {
    enable = mkOption {
      type = types.bool;
      # The superagent runs where dsh and dshd run.
      default = osConfig.myFleet.has "brain";
      description = "Render the Master DSH profile folders.";
    };
    superagent = mkOption {
      type = types.str;
      # Release tag of the fork; the integrator moves it to each new floor-v2.<n>.
      default = "github:mecattaf/dsh-superagent-prototype#floor-v2.0";
      description = "package.json spec of the dsh-superagent fork (a tag whose tarball holds the built lib/).";
    };
    claude = mkOption {
      type = types.str;
      default = "github:mecattaf/dsh-claude#floor-v2.0";
      description = "package.json spec of dsh-claude (a tag whose tarball holds the built lib/).";
    };
    stateDir = mkOption {
      type = types.str;
      default = "${home}/.agency/state/master";
      description = "The superagent's stateDir: orchestrator.sqlite and its lock.";
    };
    claudeConfigDir = mkOption {
      type = types.str;
      # cc2, the seat of the superagent and its Claude workers.
      default = "${home}/.claude-work";
      description = "CLAUDE_CONFIG_DIR of every Claude process the Master profiles start.";
    };
    workerCwd = mkOption {
      type = types.str;
      default = home;
      description = "Directory of a worker whose Trigger names none (dshd.cwd).";
    };
    webPort = mkOption {
      type = types.port;
      # scheduled-panel-tunnel forwards this port (home/scheduled.nix).
      default = 3082;
      description = "Loopback port of the master web profile.";
    };
    dshdCommand = mkOption {
      type = types.str;
      default = "/run/current-system/sw/bin/dshd";
      description = "The dshd CLI the superagent launches workers with.";
    };
    dshCommand = mkOption {
      type = types.str;
      # The dsh dshd runs (modules/dshd.nix), not the fleet wrapper.
      default = "/etc/dshd/releases/default/bin/dsh";
      description = "The dsh that dsh-master install and check run.";
    };
    defaultPair = mkOption {
      type = types.str;
      default = "opus";
      description = "The pair a Ticket runs on when its Trigger names none.";
    };
    pairs = mkOption {
      type = types.attrsOf pair;
      default = {
        # "opus" is a seed id of dsh-claude's catalog, so it is never rewritten.
        opus = {
          provider = "claude";
          model = "opus";
          reasoningEffort = "medium";
        };
        # Gufo serves one generation at a time. The bearer is the public dummy
        # the keyless server takes (pkgs/dsh), never a secret.
        gufo = {
          provider = "gufo";
          model = localModel.modelId;
          env.GUFO_API_KEY = "local-no-auth";
          maxWorkers = 1;
        };
      };
      description = "Provider-harness pairs; each renders one headless folder master-<name>.";
    };
    claudeConfig = {
      master = mkOption {
        type = types.attrs;
        default = { };
        description = "Keys merged last into the llm-claude row of master.";
      };
      worker = mkOption {
        type = types.attrs;
        default = { };
        description = "Keys merged last into the llm-claude row of every master-<pair>.";
      };
    };
    superagentConfig = mkOption {
      type = types.attrs;
      default = { };
      description = "Further dsh-superagent Schema keys, merged into the row of every folder (`engine` stays per folder).";
    };
    superagentRows = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "Rows of the fork bundle's other plugins, the same in every folder (a worker never applies them: they inject the orchestrator service).";
    };
    package = mkOption {
      type = types.package;
      readOnly = true;
      description = "The rendered profiles and the dsh-master CLI.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.dsh.master.package = pkgs.callPackage ../pkgs/dsh-master { settings = cfg; };

    assertions = [
      {
        assertion = cfg.pairs ? ${cfg.defaultPair};
        message = "programs.dsh.master.defaultPair (${cfg.defaultPair}) is not one of the pairs.";
      }
      {
        assertion = lib.all (name: builtins.match "[a-z0-9][a-z0-9-]*" name != null) (builtins.attrNames cfg.pairs);
        message = "programs.dsh.master.pairs: a name must match ^[a-z0-9][a-z0-9-]*$.";
      }
      {
        assertion = !(cfg.pairs ? web || cfg.pairs ? master);
        message = "programs.dsh.master.pairs: `web` and `master` are not pair names.";
      }
      {
        assertion = !(lib.any (name: builtins.elem name otherProfiles) ([ "master" ] ++ workerNames));
        message = "programs.dsh.master: a Master profile name collides with an existing profile.";
      }
      {
        assertion = !(cfg.superagentConfig ? engine);
        message = "programs.dsh.master.superagentConfig: `engine` is set per folder by the renderer.";
      }
    ];

    home.packages = [ cfg.package ];

    # After writeBoundary: the profile folders are dsh's state, never Home
    # Manager links. A failed render must not fail the generation; it says
    # so and `dsh-master render` repeats it by hand.
    home.activation.dshMasterProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe cfg.package} render --quiet \
        || echo "dsh-master: render failed; run dsh-master render" >&2
    '';
  };
}
