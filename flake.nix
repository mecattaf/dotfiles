{
  description = "mecattaf — one flake for the whole distribution (NixOS + home-manager). Coordinator/worker AMD Strix Halo cluster + Intel laptops.";

  inputs = {
    # Unstable: Strix Halo (gfx1151) wants fresh kernels + Mesa.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nixpkgs-fresh — a second nixpkgs, tracking the SAME nixos-unstable branch, used
    # ONLY to keep a handful of fast-moving user packages (currently
    # google-chrome and uv, see overlays list below) current independent of the `nixpkgs`
    # pin above. That pin is deliberately lagging — the exact-candidate fleet deploy
    # keeps it as the only door kernel/Mesa churn enters through, bumped manually.
    # Browser point releases carry none of that risk, so they shouldn't have to wait
    # on it.
    #
    # Its lock entry is a reproducible fallback. The nightly fleet transaction uses
    # `rollingInputOverrides` below to resolve it (with llm-agents and the two AMD
    # catalogs) exactly once, then builds and deploys those immutable URLs without
    # writing the lock. A plain local build uses the reviewed fallback revision.
    nixpkgs-fresh.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Per-device hardware quirks. No nixpkgs.follows — it's just module files.
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Secrets — agenix (host-level; SSH host key = decryption identity).
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Declarative disk partitioning (drives nixos-anywhere). Only hosts that define
    # disko.devices are partitioned; the module is inert elsewhere.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Apple SF/NY fonts (sf-pro, sf-compact, sf-mono, ny), built at nix-build
    # time from Apple's own CDN DMGs — nothing redistributed. Replaces the old
    # Fedora-image url-fonts Apple-SF zip (its mecattaf/San-Francisco-family
    # release no longer exists; repo deleted).
    apple-fonts = {
      url = "github:Lyndeno/apple-fonts.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # zmx — LOCAL terminal session persistence (neurosnap/zmx, built on
    # ghostty-vt). THE projector primitive (jul7 ruling, tally morning-annotation
    # §12): every kitty on the coordinator is a persistent local zmx session
    # (`zmx attach <name>`); other boxes reach it via `kitten ssh coordinator -t
    # zmx attach <session>` over the tailnet. Supersedes shpool fleet-wide.
    #
    # We tried zmosh (a zmx fork adding encrypted-UDP roaming) but it is
    # unmaintained and ships a stale build.zig.zon2json-lock that breaks offline
    # nix builds. zmx is maintained with a valid lock, so we consume its flake
    # `packages.default` directly (no zig2nix rebuild). Its one feature we forgo
    # — UDP auto-reconnect — is moot: kitten ssh gives reliable graphics/clipboard
    # while attached, and a persistent session survives disconnects server-side.
    zmx.url = "github:neurosnap/zmx";

    # llm-agents.nix — numtide's daily-rebuilt catalog of ~100 AI coding agents
    # and tooling (claude-code, codex, gemini-cli, opencode, crush, goose, amp,
    # ...). Its `overlays.default` exposes the whole set, prebuilt against its OWN
    # fresh nixpkgs-unstable, under the namespaced `pkgs.llm-agents.*` — so it
    # neither re-evaluates our nixpkgs nor collides with it. This is how we get
    # newest claude-code DECOUPLED from our (deliberately lagging) nixpkgs pin.
    # Nightly fleet builds re-resolve this input at HEAD via
    # `rollingInputOverrides`; `nix flake update llm-agents` updates the local and
    # failure-fallback lock without touching kernel/Mesa.
    # Deliberately NO inputs.nixpkgs.follows — following our pin would rebuild
    # against stale deps and miss the numtide cache (substituter added in
    # modules/common.nix). home/home.nix installs the entire set via buildEnv.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Liga SF Mono: SF Mono ligaturized AND nerd-patched upstream — a different
    # derived font from apple-fonts' sf-mono-nerd (glyphs only, no ligatures).
    # Plain repo of OTFs, not a flake; consumed by pkgs/sfmono-liga.nix.
    sfmono-liga = {
      url = "github:shaunsingh/SFMono-Nerd-Font-Ligaturized";
      flake = false;
    };

    # tally — contention and proof for agent sessions (a Rust workspace: one
    # daemon + CLI, embedded taskchampion, witness ledger). THE packaging
    # channel is this flake input + `homeManagerModules.tally`: the module is
    # load-bearing — it generates the systemd user units, the producer
    # timers/services and the build-time `checkedConfig` validator, which a bare
    # pkg can't deliver; NO bespoke pkgs/tally.nix. home/tally.nix imports the
    # module and enables the daemon on the coordinator only. worker carries the
    # same binary solely for the daemonless SSH executor helper; no queue or
    # lease engine runs there. Other hosts leave the module off. Composes onto
    # the dotfiles-owned zmx substrate — tally ships
    # none of it. follows nixpkgs so the Rust build resolves against our one pin
    # rather than dragging a second nixpkgs into the lock. `nix flake update
    # tally` bumps to the latest pushed commit (and, post-release, the tag).
    #
    # Repo is mecattaf/tally.nix (NOT mecattaf/tally, which is the pre-rebuild
    # spec history). It is public, so use the native `github:` fetcher: worker
    # and fleet auto-upgrades need no GitHub credential helper or access token.
    # tally's one law: contention and proof, never content or control.
    tally = {
      url = "github:mecattaf/tally.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # deploy-rs — the fleet's one NixOS activation engine. Tally remains the
    # scheduler/admission/proof plane; deploy-rs runs inside that one durable job
    # and contributes target copy, activation, SSH confirmation, and automatic
    # rollback. Following our nixpkgs avoids a second package universe.
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "tally/flake-utils";
    };

    # ntm — niri tablet management (github.com/mecattaf/ntm): one Rust daemon
    # for edge-initiated multi-finger touchscreen gestures + accelerometer
    # rotation via iio-sensor-proxy. ZENBOOK-DUO ONLY — the one host with touch
    # panels + an accelerometer; the Strix pair and the bridge never see it.
    # Consumed like tally (same author, same channel: flake input pinned in
    # flake.lock, follows nixpkgs so the Rust build resolves against our one
    # pin) — but ntm ships no home-manager module, only packages.*.ntm, so
    # home/ntm.nix does the module work: package + config + manual-start user
    # service, hostname-gated. Complements the PR #1856 niri fork's per-device
    # touch→output mapping (overlays/default.nix, niri-local.kdl): niri routes
    # each panel's touches, ntm layers bezel gestures + rotation on top.
    # `nix flake update ntm` bumps to the latest pushed commit.
    ntm = {
      url = "github:mecattaf/ntm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # piri — niri IPC extension daemon (github.com/Asthestarsfalll/piri): one
    # Rust daemon that tails niri's event stream and layers plugins on top —
    # scratchpads, marks, window/workspace rules. We use it for the "music"
    # auto-scratchpad (Mod+M toggles a right-side SoundCloud/cliamp pane).
    # Third-party but consumed exactly like ntm/tally: flake input pinned in
    # flake.lock, follows nixpkgs so the Rust build resolves against our one pin.
    # piri ships packages.default + a NixOS module, but NOT a home-manager
    # module, so home/piri.nix does the module work: package + user service, with
    # piri.toml delivered RAW through the niri whole-dir symlink for hot-reload.
    # `nix flake update piri` bumps to the latest pushed commit.
    piri = {
      url = "github:Asthestarsfalll/piri";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-amd-ai — the proven coordinator NPU plane (hardware.amd-npu: amdxdna,
    # XRT plugin discovery, udev/memlock, FastFlowLM) plus the one accelerator
    # package nix-strix-halo does not expose: stable-diffusion-cpp-rocm.
    # COORDINATOR ONLY for the NPU module: the conductor turns the NPU on (needs
    # IOMMU in translated mode); the worker keeps it off for max iGPU. Deliberately
    # NO inputs.nixpkgs.follows — the overlay is built against its OWN pinned
    # nixpkgs so its Cachix (nix-amd-ai.cachix.org, substituter added in
    # modules/common.nix) serves prebuilt XRT/FastFlowLM instead of source builds.
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";

    # nix-strix-halo — the broad gfx1151 package plane for BOTH Framework Desktop
    # nodes: llama.cpp ROCm/Vulkan, ds4-rocm, vLLM, MLX, tokenizers, MES firmware,
    # the two-host benchmark driver, and a buildable live ISO. Consume its package
    # outputs directly rather than applying its global overlay: that preserves its
    # own TheRock/Python provider graph and avoids replacing the already-live
    # nix-amd-ai XRT/FastFlowLM pair. The two flakes currently pin identical XRT +
    # amdxdna revisions, so a second XRT in /run/current-system/sw would only create
    # colliding binaries. All NPU components remain exclusively sourced from
    # nix-amd-ai. No nixpkgs.follows: upstream's Hydra artifacts are keyed to its
    # own nixpkgs and provider pins (cache configured in common.nix).
    nix-strix-halo.url = "github:hellas-ai/nix-strix-halo";

    # microvm.nix — declarative microVMs (astro → microvm-nix/microvm.nix). The
    # instrument behind the /microvm skill: it exports nixosModules.{microvm,host}
    # and, per guest, a `config.microvm.declaredRunner` package. DEFAULT USAGE is
    # EPHEMERAL — `nix run <guest>.config.microvm.declaredRunner` needs only this
    # input, no host module, so it works fleet-wide. The DURABLE path (the imperative
    # `microvm` CLI + `microvm@<name>` systemd units) is opt-in via
    # modules/microvm-host.nix, enabled on the WORKER only (the Strix Halo compute
    # node — keeps the coordinator light per the no-heavy-build doctrine). follows
    # nixpkgs so the runner builds against our one pin.
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-hardware,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # Inputs whose PACKAGE CONTENT may move independently of the committed
      # flake.lock during the nightly fleet transaction. The coordinator resolves
      # each once and passes the same immutable URLs to every build and activation.
      #
      # This is intentionally NOT the main nixpkgs input: kernel/Mesa remain behind
      # an explicit lock-file review. These inputs are isolated package catalogs or
      # accelerator flakes that carry their own nixpkgs/provider pins and caches.
      rollingInputOverrides = [
        {
          name = "nixpkgs-fresh";
          url = "github:NixOS/nixpkgs/nixos-unstable";
        }
        {
          name = "llm-agents";
          url = "github:numtide/llm-agents.nix";
        }
        {
          name = "nix-amd-ai";
          url = "github:noamsto/nix-amd-ai";
        }
        {
          name = "nix-strix-halo";
          url = "github:hellas-ai/nix-strix-halo";
        }
      ];

      # One hardened operational SSH path for deploy-rs and the Zenbook preflight.
      # Use the tailnet names (rather than localhost / worker-tb) so magic rollback
      # confirms the connectivity the fleet actually depends on after activation.
      fleetDeploySshOpts = [
        "-F"
        "/dev/null"
        "-o"
        "BatchMode=yes"
        "-o"
        "PasswordAuthentication=no"
        "-o"
        "KbdInteractiveAuthentication=no"
        "-o"
        "IdentitiesOnly=yes"
        "-o"
        "IdentityAgent=none"
        "-o"
        "ForwardAgent=no"
        "-o"
        "ClearAllForwardings=yes"
        "-o"
        "StrictHostKeyChecking=yes"
        "-o"
        "UserKnownHostsFile=/etc/ssh/ssh_known_hosts"
        "-o"
        "ConnectTimeout=10"
        "-o"
        "ConnectionAttempts=1"
        "-o"
        "ServerAliveInterval=15"
        "-o"
        "ServerAliveCountMax=3"
        "-i"
        "/run/agenix/ssh-user-key"
      ];

      # One overlay list everywhere (top-level pkgs + every host): bespoke pkgs,
      # the apple-fonts families, and sfmono-liga — wired inline because it
      # needs the flake input as src (overlays/default.nix has no inputs).
      overlays = [
        self.overlays.default
        inputs.apple-fonts.overlays.default
        (final: _prev: {
          # Whole llm-agents catalog under `pkgs.llm-agents.*` (prebuilt from its
          # own nixpkgs — no second eval of ours). home/home.nix pulls an
          # allowlisted set out of this namespace. See the input comment above.
          llm-agents = inputs.llm-agents.packages.${system};
          sfmono-liga = final.callPackage ./pkgs/sfmono-liga.nix { src = inputs.sfmono-liga; };
          # zmx's own flake builds the `zmx` binary (zig2nix, valid lock — builds
          # offline under nixos-rebuild). Exposed as .default; pull it straight
          # onto the fleet-wide pkgs set.
          zmx = inputs.zmx.packages.${system}.default;
        })
        # Pin-decoupled "hot" packages — see the nixpkgs-fresh input comment above.
        # Cherry-picked, not a wholesale pkgs swap: only packages named here track
        # nixos-unstable HEAD independent of the main nixpkgs pin.
        (
          _final: _prev:
          let
            fresh = import inputs.nixpkgs-fresh {
              inherit system;
              config.allowUnfree = true;
            };
          in
          {
            google-chrome = fresh.google-chrome;
            # uv — Astral's Python package/project manager. Point releases land
            # weekly; riding nixpkgs-fresh HEAD keeps it current without waiting on
            # the deliberately-lagging main pin (which exists only to gate kernel/
            # Mesa churn — uv carries none of that risk).
            uv = fresh.uv;
          }
        )
      ];

      pkgs = import nixpkgs {
        inherit system overlays;
        config.allowUnfree = true; # google-chrome
      };

      localModelCatalog = import ./lib/local-models.nix { lib = nixpkgs.lib; };
      localModelStore = import ./lib/model-store.nix {
        inherit pkgs;
        lib = nixpkgs.lib;
        catalog = localModelCatalog;
      };

      # Single host-wiring point. Every host = common.nix + its own module + HM.
      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs rollingInputOverrides fleetDeploySshOpts;
          };
          modules = [
            {
              nixpkgs.overlays = overlays;
              nixpkgs.config.allowUnfree = true;
            }
            ./modules/common.nix
            hostModule
            inputs.agenix.nixosModules.default
            inputs.disko.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users.tom = import ./home/home.nix;
              # A pre-existing unmanaged dotfile (e.g. atuin's 14 KB first-run
              # config.toml) otherwise makes HM activation HARD-FAIL the whole
              # switch (exit 4) — which silently broke the daily auto-upgrade
              # fleet-wide. Back the stray file aside instead of aborting.
              home-manager.backupFileExtension = "hm-bak";
            }
          ];
        };
    in
    {
      # Evaluation-only metadata surface for deterministic local-AI workflows.
      # This serializes the accepted catalog without instantiating model FODs or
      # changing the independent downloadAllModels gate.
      lib.localModelCatalog = localModelCatalog;

      overlays.default = import ./overlays;

      nixosConfigurations = {
        coordinator = mkHost ./hosts/coordinator;
        worker = mkHost ./hosts/worker;
        zenbook-duo = mkHost ./hosts/zenbook-duo;
      };

      # deploy-rs owns HOW a selected generation reaches and activates on a node.
      # Tally still owns WHEN this graph may run and atomically leases every
      # affected build/GPU resource around the complete nightly transaction.
      deploy = {
        sshUser = "root";
        user = "root";
        sshOpts = fleetDeploySshOpts;
        autoRollback = true;
        magicRollback = true;
        remoteBuild = false; # coordinator's Nix daemon already offloads to worker
        fastConnection = false; # let each destination substitute from Attic
        activationTimeout = 1200;
        confirmTimeout = 90;

        nodes =
          nixpkgs.lib.genAttrs
            [
              "worker"
              "coordinator"
              "zenbook-duo"
            ]
            (host: {
              hostname = host;
              profiles.system.path =
                inputs.deploy-rs.lib.${system}.activate.nixos
                  self.nixosConfigurations.${host};
            });
      };

      # Standalone home-manager bridge for the live Fedora host (coexists with Fedora):
      #   nix run home-manager -- switch --flake .#tom@bridge
      homeConfigurations."tom@bridge" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./home/home.nix ];
      };

      packages.${system} =
        let
          amdAi = inputs.nix-amd-ai.packages.${system};
          strixAi = inputs.nix-strix-halo.packages.${system};
        in
        {
          inherit (pkgs)
            local-ai-monthly
            mactahoe-gtk-theme
            mactahoe-icon-theme
            sfmono-liga
            ;

          # Explicit accelerator escape hatches. The host module installs the
          # operational subset safely; these aliases also make every requested
          # upstream output directly buildable with `nix build .#<name>` without
          # applying either upstream overlay to the fleet's global pkgs fixpoint.
          stable-diffusion-cpp-rocm = amdAi.stable-diffusion-cpp-rocm;
          inherit (strixAi)
            ds4-rocm
            ec-su-axb35-monitor
            llama-cpp-rocm
            llama-cpp-vulkan
            mlx-lm
            mlx-rocm
            strix-halo-mes-firmware
            strix-halo-vllm-pair-bench-gfx1151
            tokenizers-cpp
            vllm-rocm
            ;
          live-iso = strixAi.live-iso;
        };

      # Artifact rows are individually buildable as `nix build .#models.<id>`.
      # This operator escape hatch does not change the one NixOS install switch.
      legacyPackages.${system}.models = localModelStore.packages;

      formatter.${system} = pkgs.nixfmt-rfc-style;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          inputs.agenix.packages.${system}.default # `agenix -e/-r`
        ]
        ++ (with pkgs; [
          nixfmt-rfc-style
          deadnix
          statix
          nil
          git
        ]);
      };

      # The RAW out-of-store dotfiles are never checked at switch, so check them here.
      checks.${system} = {
        deadnix = pkgs.runCommand "deadnix" { } ''
          ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names \
            ${./flake.nix} ${./lib} ${./modules} ${./hosts} ${./overlays} ${./home} > $out 2>&1 \
            || (cat $out; exit 1)
        '';

        local-model-routing =
          let
            coordinator = self.nixosConfigurations.coordinator.config;
            worker = self.nixosConfigurations.worker.config;
            coordinatorSettings = coordinator.services.llama-swap.settings;
            workerSettings = worker.services.llama-swap.settings;
            modelPackagePaths = map toString (builtins.attrValues localModelStore.packages);
            coordinatorExtraDependencies = map toString coordinator.system.extraDependencies;
            workerExtraDependencies = map toString worker.system.extraDependencies;
            testRenderers = import ./lib/local-model-runtime.nix {
              lib = nixpkgs.lib;
              packages = {
                llamaRocm = "/runtime/rocm";
                llamaVulkan = "/runtime/vulkan";
                ds4 = "/runtime/ds4";
                vllm = "/runtime/vllm";
                mlxLm = "/runtime/mlx-lm";
              };
            };
            testRender =
              renderer:
              renderer {
                deployment.model = "test-model";
                modelPath = "/models/model.gguf";
                modelDirectory = "/models/model-directory";
              };
            renderedBackends = nixpkgs.lib.mapAttrs (_: testRender) testRenderers;
          in
          assert
            builtins.attrNames self.nixosConfigurations.coordinator.options.services.local-models == [
              "downloadAllModels"
            ];
          assert !coordinator.services.local-models.downloadAllModels;
          assert !worker.services.local-models.downloadAllModels;
          assert nixpkgs.lib.intersectLists modelPackagePaths coordinatorExtraDependencies == [ ];
          assert nixpkgs.lib.intersectLists modelPackagePaths workerExtraDependencies == [ ];
          assert coordinatorSettings.models == { };
          assert workerSettings.models == { };
          assert
            coordinatorSettings.peers == {
              flm = {
                proxy = "http://127.0.0.1:52625";
                models = [ "gemma4-it:e4b" ];
              };
            };
          assert workerSettings.peers == { };
          assert !(nixpkgs.lib.hasInfix "-hf" (builtins.toJSON coordinatorSettings));
          assert !(nixpkgs.lib.hasInfix "-hf" (builtins.toJSON workerSettings));
          assert
            localModelCatalog.backendKinds == {
              local = [
                "rocm"
                "vulkan"
                "ds4"
                "vllm"
                "mlx"
              ];
              peers = [ "npu" ];
            };
          assert
            builtins.attrNames renderedBackends == [
              "ds4"
              "mlx"
              "rocm"
              "vllm"
              "vulkan"
            ];
          assert
            renderedBackends.rocm.cmd == "/runtime/rocm/bin/llama-server --port \${PORT} -m /models/model.gguf";
          assert
            renderedBackends.vulkan.cmd
            == "/runtime/vulkan/bin/llama-server --port \${PORT} -m /models/model.gguf";
          assert
            renderedBackends.ds4.cmd
            == "/runtime/ds4/bin/ds4-server --host 127.0.0.1 --port \${PORT} -m /models/model.gguf";
          assert
            renderedBackends.vllm.cmd
            == "/runtime/vllm/bin/vllm serve /models/model-directory --host 127.0.0.1 --port \${PORT} --served-model-name test-model";
          assert renderedBackends.vllm.useModelName == "test-model";
          assert nixpkgs.lib.elem "HF_HUB_OFFLINE=1" renderedBackends.vllm.env;
          assert
            renderedBackends.mlx.cmd
            == "/runtime/mlx-lm/bin/mlx_lm.server --model /models/model-directory --host 127.0.0.1 --port \${PORT}";
          assert renderedBackends.mlx.useModelName == "default_model";
          assert nixpkgs.lib.elem "HF_HUB_OFFLINE=1" renderedBackends.mlx.env;
          assert builtins.hasAttr "mlx-lm" inputs.nix-strix-halo.packages.${system};
          pkgs.runCommand "local-model-routing" { } ''
            touch "$out"
          '';
      }
      // inputs.deploy-rs.lib.${system}.deployChecks self.deploy;
    };
}
