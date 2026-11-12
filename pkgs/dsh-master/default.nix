{
  lib,
  runCommand,
  formats,
  writeText,
  writeShellScriptBin,
  makeWrapper,
  python3,
  coreutils,
  git,
  pnpm,
  dsh,
  llm-agents,
  # programs.dsh.master (home/dsh-master.nix): one Master configuration.
  settings,
}:
# The Master configuration: one source, rendered as one DSH profile folder per
# transport and pair (DSH composes its app from the bundles a profile lists, so
# a web folder and a headless folder cannot be one profile).
#
#   master         web app, the superagent engine on: the floor instance
#   master-<pair>  headless, the engine off: one worker per dshd unit
#
# Every folder lists the same dependencies and the same non-app bundles (base,
# dsh-claude, dsh-superagent). They differ in the app bundle, the model row,
# the llm-claude row and the `engine` key of the dsh-superagent row, which is
# otherwise the same in every folder.
#
# The policy travels inside each profile's own cordis.patch.yml. dshd runs the
# unwrapped dsh (modules/dshd.nix), so the wrapper's `--patch` overlays never
# reach a dshd instance; the profile layer is read whatever starts the
# profile. A patch REPLACES a row's whole `config`, so every row restates every
# key it keeps. Dropped from the policy: the sandbox, permission and approval
# rows (workers run with full permissions, and the superagent needs the stock
# `danger-full-access` preset), and the default model (each folder sets its
# own).
#
# Outputs: $out/profiles/<p>/{package.json,cordis.patch.yml,pnpm-workspace.yaml},
# $out/manifest.json (profile names, file digests and the rows `dsh-master
# check` asserts in a config dump) and $out/bin/dsh-master. Home Manager never
# links into ~/.dsh: dsh replaces its profile files by atomic rename on a
# settings save, so `dsh-master render` installs copies instead
# (home/dsh-master.nix).
let
  yaml = formats.yaml { };

  off = id: {
    inherit id;
    disabled = true;
  };

  # A pair's model, as agent-default-model takes it. Gufo declares no effort.
  route =
    pair:
    lib.filterAttrs (_: v: v != null) {
      inherit (pair) provider model reasoningEffort;
    };

  pairNames = builtins.attrNames settings.pairs;
  workerName = pair: "master-${pair}";

  # Every Claude process dsh-claude starts (turns, titles, the model probe)
  # goes through executablePath, so the seat is fixed here and does not
  # depend on the environment of whoever created the instance.
  claudeSeat = writeShellScriptBin "claude" ''
    export CLAUDE_CONFIG_DIR=${lib.escapeShellArg settings.claudeConfigDir}
    exec ${lib.getExe llm-agents.claude-code} "$@"
  '';

  dropped = [
    "sandbox"
    "sandbox-policy"
    "approval"
    "permission"
    "agent-default-model"
  ];
  policyRows = lib.filter (row: !(builtins.elem row.id dropped)) dsh.policyRows;

  # The same row in every folder but for `engine` (docs/dsh-master.md).
  superagentRow = engine: {
    id = "dsh-superagent";
    config =
      lib.recursiveUpdate {
        inherit (settings) stateDir;
        executor = "dshd";
        dshd = {
          command = settings.dshdCommand;
          cwd = settings.workerCwd;
          inherit (settings) defaultPair;
          # Recorded in every unit's recipe (instance.json, 0600): no secrets.
          env = {
            CLAUDE_CONFIG_DIR = settings.claudeConfigDir;
            DSH_TELEMETRY_DISABLED = "1";
          };
          args = [
            "--permission-mode"
            "danger-full-access"
            "--approval-policy"
            "never"
          ];
          pairs = lib.mapAttrs (
            name: pair:
            {
              profile = workerName name;
            }
            // lib.optionalAttrs (pair.env != { }) { inherit (pair) env; }
            // lib.optionalAttrs (pair.maxWorkers != null) { inherit (pair) maxWorkers; }
          ) settings.pairs;
        };
      } settings.superagentConfig
      // {
        inherit engine;
      };
  };

  # Rows any DSH composition of the app bundle has; the offline check dumps
  # them against the first-party bundles alone.
  firstParty = {
    master = [
      {
        id = "agent-default-model";
        config = route settings.pairs.${settings.defaultPair};
      }
      {
        id = "webserver";
        config = {
          host = "127.0.0.1";
          port = settings.webPort;
          compression = "gzip";
          compressionLevel = 1;
          compressionThresholdBytes = 1024;
        };
      }
      # One scheduler only: DSH's own Schedule stays off.
      (off "schedule")
      (off "ui-schedule")
    ];
    worker = pair: [
      # The headless bundle has no preset registry (the web bundle carries
      # it), so dsh-claude's preset rows would wait for it forever.
      {
        insert = [
          {
            id = "agent-preset-registry";
            name = "@deepseek-ai/dsh-agent-preset-registry";
            config.default = "claude";
          }
        ];
      }
      {
        id = "agent-default-model";
        config = route settings.pairs.${pair};
      }
    ];
  };

  # Rows of the extension bundles (dsh-claude, dsh-superagent). The
  # llm-claude keys are dsh-claude floor-atomic's; a profile that leaves
  # `presets` unset gets its default (claude and the two superagent presets).
  # `permissionSelector: native` maps the sandbox alone to Claude's mode, so
  # danger-full-access is bypassPermissions whatever the shared plugin
  # setting says.
  extension = {
    master = [
      {
        id = "llm-claude";
        config = {
          executablePath = lib.getExe claudeSeat;
          idleTimeoutMs = 1800000;
          maxProcesses = 2;
          permissionSelector = "native";
          forwardedSources = [
            "user"
            "dsh-superagent"
          ];
          # The superagent's mandate is DSH's system prompt of its router preset.
          systemPromptPresets = [ "dsh-superagent-router" ];
        }
        // settings.claudeConfig.master;
      }
      (superagentRow true)
      (off "dsh-superagent-github")
      (off "dsh-superagent-feishu")
    ]
    ++ settings.superagentRows;
    worker =
      pair:
      # The headless one-shot runner binds no preset; dsh-claude's binder
      # selects the pair's preset for the top-level agent, after the registry
      # row above. A pair with none (Gufo) runs DSH's own agent.
      lib.optional (settings.pairs.${pair}.preset != null) {
        insert = [
          {
            id = "headless-preset";
            name = "@norman-else/dsh-claude/headless-preset";
            config.preset = settings.pairs.${pair}.preset;
          }
        ];
      }
      ++ [
        {
          id = "llm-claude";
          config = {
            executablePath = lib.getExe claudeSeat;
            idleTimeoutMs = 600000;
            maxProcesses = 1;
            permissionSelector = "native";
            presets = [ "claude" ];
            forwardedSources = [ "user" ];
            systemPromptPresets = [ ];
          }
          // settings.claudeConfig.worker;
        }
        # Dormant: the plugin mounts but runs no orchestrator, so no state,
        # lock, Session or environment change. Its Sources inject the missing
        # `orchestrator` service and never apply.
        (superagentRow false)
        (off "dsh-superagent-github")
        (off "dsh-superagent-feishu")
      ]
      ++ settings.superagentRows;
  };

  bundles = app: [
    "@deepseek-ai/dsh-base"
    app
    "@norman-else/dsh-claude"
    "dsh-superagent"
  ];
  dependencies = {
    "dsh-superagent" = settings.superagent;
    "@norman-else/dsh-claude" = settings.claude;
  };

  profiles = {
    master = {
      app = "@deepseek-ai/dsh-web-app";
      rows = firstParty.master ++ extension.master;
      firstPartyRows = firstParty.master;
    };
  }
  // lib.listToAttrs (
    map (
      pair:
      lib.nameValuePair (workerName pair) {
        app = "@deepseek-ai/dsh-headless";
        rows = firstParty.worker pair ++ extension.worker pair;
        firstPartyRows = firstParty.worker pair;
      }
    ) pairNames
  );

  header = writeText "dsh-master-header.yml" ''
    # Rendered by dsh-master (dotfiles pkgs/dsh-master) from programs.dsh.master.
    # `dsh-master render` replaces this file whenever it differs: change the
    # module, not this copy. Order: the fleet policy (pkgs/dsh/config.nix) minus
    # sandbox, permission, approval and the default model; the sessions row; the
    # profile's own rows.
  '';

  # The dsh-config policy file and sessions row are plain block sequences, so
  # the parts concatenate into one YAML list.
  patchFile =
    name: rows:
    runCommand "${name}-cordis.patch.yml" { } ''
      cat ${header} ${yaml.generate "policy.yml" policyRows} > "$out"
      echo >> "$out"
      cat ${dsh.sessions} >> "$out"
      echo >> "$out"
      echo "# The ${name} profile rows." >> "$out"
      cat ${yaml.generate "${name}-rows.yml" rows} >> "$out"
    '';

  # dsh writes this file beside package.json when it creates a profile
  # (dsh-app-boot initProfile) and never touches it again. A folder that
  # render creates has none, and pnpm then resolves the plugins' DSH peers
  # from the registry. render writes dsh's text only when the file is
  # missing; checks.dsh-master compares it with what the release's dsh writes.
  pnpmWorkspace = writeText "pnpm-workspace.yaml" ''
    packages:
      - .

    nodeLinker: hoisted
    autoInstallPeers: false
  '';

  # package.json content; assemble.py writes it in dsh's own key order.
  packageOf = name: deps: bundleList: {
    name = "dsh-profile-${name}";
    dependencies = deps;
    bundles = bundleList;
  };

  # What `dsh-master check` asserts in each profile's composed tree: every
  # rendered row by id, with its config as rendered (a patch replaces it) and
  # the disabled state it states (a row without `disabled` keeps the bundle's:
  # the web app disables the root tool-web and workflow-ptc rows). The
  # sessions row is text with `!!js`, so it is checked by its compression only.
  # The dsh-superagent row states no `disabled`, but it must be enabled in
  # every folder: the engine key, not a disabled row, keeps a worker dormant.
  expectRows =
    rows:
    lib.concatMap (
      row:
      if row ? insert then
        map (inserted: {
          inherit (inserted) id;
          config = inserted.config or null;
          disabled = inserted.disabled or null;
        }) row.insert
      else
        [
          {
            inherit (row) id;
            config = row.config or null;
            disabled = row.disabled or (if row.id == "dsh-superagent" then false else null);
          }
        ]
    ) rows;

  spec = writeText "dsh-master-spec.json" (
    builtins.toJSON {
      dsh = settings.dshCommand;
      profiles = lib.mapAttrs (name: profile: {
        package = packageOf name dependencies (bundles profile.app);
        patch = patchFile name profile.rows;
        workspace = pnpmWorkspace;
        expect = expectRows (policyRows ++ profile.rows);
      }) profiles;
    }
  );

  # The first-party half of each profile (policy, sessions, app rows), with
  # only the first-party bundles: a scratch DSH_HOME dumps it with no network
  # and no installed plugin (checks.dsh-master).
  probeSpec = writeText "dsh-master-probe-spec.json" (
    builtins.toJSON {
      profiles = lib.mapAttrs (name: profile: {
        package = packageOf name { } [
          "@deepseek-ai/dsh-base"
          profile.app
        ];
        patch = patchFile name profile.firstPartyRows;
        workspace = pnpmWorkspace;
        expect = expectRows (policyRows ++ profile.firstPartyRows);
      }) profiles;
    }
  );

  assemble = specFile: ''
    ${python3.interpreter} -I ${./assemble.py} ${specFile} "$out"
  '';

  probes = runCommand "dsh-master-probes" { } (assemble probeSpec);
in
runCommand "dsh-master"
  {
    nativeBuildInputs = [ makeWrapper ];
    passthru = {
      inherit
        claudeSeat
        pnpmWorkspace
        policyRows
        probes
        profiles
        dropped
        ;
      profileNames = builtins.attrNames profiles;
    };
    meta = {
      description = "Render, install and check the Master DSH profile folders";
      mainProgram = "dsh-master";
    };
  }
  ''
    ${assemble spec}
    install -Dm0644 ${./dsh-master.py} "$out/share/dsh-master/dsh-master.py"
    install -Dm0644 ${settings.settingsSeed} "$out/share/dsh-master/settings.seed.json"
    makeWrapper ${python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 "$out/bin/dsh-master" \
      --add-flags "$out/share/dsh-master/dsh-master.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          # dsh plugin runs pnpm from PATH, and pnpm asks git for a github: tag.
          pnpm
          git
        ]
      }
  ''
