{
  description = "mecattaf — one flake for the whole distribution: Strix Halo coordinator, headless AMD NAS, and Intel laptop.";

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

    # nixpkgs-stable — pins ONLY nixosConfigurations.nas (issue #135 ruling):
    # the NAS is a frozen self-sustaining appliance on standard stable nixpkgs,
    # maintained manually every few years. It never rides the unstable
    # kernel/Mesa churn the coordinator's pin exists to gate, and it accepts
    # EOL-pin CVE exposure because it is reachable only from the coordinator
    # over the private /30. Bump deliberately with
    # `nix flake update nixpkgs-stable` on the same few-years cadence.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    # nixpkgs-paperless — pins ONLY the NAS Paperless v3 module+package
    # (#136, hosts/nas/paperless.nix): the stable-pinned NAS needs v3 (stable
    # has 2.20.15, and 2.x is ruled out), the main pin deliberately lags, and
    # nixpkgs-fresh is a nightly ROLLING resolver — the wrong risk profile
    # for a database with schema migrations. A fixed rev makes Paperless
    # upgrades a deliberate one-line bump reviewed like any other change.
    # Pinned rev = nixos-unstable on 2026-08-04, paperless-ngx 3.0.4
    # (upstream latest stable is 3.0.5, 2026-08-01, not yet in nixpkgs; bump
    # this rev when it lands).
    nixpkgs-paperless.url = "github:NixOS/nixpkgs/e72e4f299401a3689d4b3d5fc6496b11db7064eb";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Voxtype — coordinator-only local streaming dictation. Consume the upstream
    # Home Manager module and canonical AMD ONNX/MIGraphX package; model weights
    # remain mutable user data outside both Git and the Nix store.
    voxtype = {
      url = "github:peteonrails/voxtype/dev";
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
    # time from Apple's own CDN DMGs — nothing redistributed.
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
    # nix builds. Its one feature we forgo — UDP auto-reconnect — is moot:
    # kitten ssh gives reliable graphics/clipboard while attached, and a
    # persistent session survives disconnects server-side.
    #
    # flake = false ON PURPOSE (2026-08-21): upstream's flake packages zmx via
    # Cloudef/zig2nix, whose import-from-derivation (zon2json/zon2nix built
    # MID-EVAL) made every dotfiles evaluation build zig tooling, broke
    # `nix flake check --no-build`, and turned one GC into
    # "path 'zon2json.drv' is not valid". pkgs/zmx.nix now builds the same
    # source with the nixpkgs zig toolchain from upstream's committed
    # build.zig.zon2json-lock — pure eval, zero IFD, and zig2nix leaves our
    # input graph entirely. `nix flake update zmx` still bumps the pin.
    zmx = {
      url = "github:neurosnap/zmx";
      flake = false;
    };

    # git-ai — AI-authorship tracking CLI (github.com/git-ai-project/git-ai).
    # Consume its flake package directly and pin it in flake.lock. The Home
    # Manager profile installs upstream's `minimal` output, which provides
    # `git-ai` and `git-og` without replacing the `git` binary already owned
    # by programs.git. Following nixpkgs keeps the Rust build on our one package
    # pin instead of adding another nixpkgs universe to the lock.
    # `nix flake update git-ai` bumps to the latest pushed commit.
    git-ai = {
      url = "github:git-ai-project/git-ai";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "tally/flake-utils";
    };

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
    # module and enables the daemon on the coordinator only. Other hosts leave
    # the module off. Composes onto
    # the dotfiles-owned zmx substrate — tally ships
    # none of it. follows nixpkgs so the Rust build resolves against our one pin
    # rather than dragging a second nixpkgs into the lock. `nix flake update
    # tally` bumps to the latest pushed commit (and, post-release, the tag).
    #
    # Repo is mecattaf/tally.nix (NOT mecattaf/tally, which is the pre-rebuild
    # spec history). It is public, so use the native `github:` fetcher: fleet
    # auto-upgrades need no GitHub credential helper or access token.
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
    # panels + an accelerometer; the coordinator never sees it.
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
    # The coordinator consumes the NPU module and runs IOMMU in translated mode.
    # Deliberately
    # NO inputs.nixpkgs.follows — the overlay is built against its OWN pinned
    # nixpkgs so its Cachix (nix-amd-ai.cachix.org, substituter added in
    # modules/common.nix) serves prebuilt XRT/FastFlowLM instead of source builds.
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";

    # nix-strix-halo — the broad gfx1151 package plane for the Framework Desktop:
    # llama.cpp ROCm/Vulkan, ds4-rocm, vLLM, MLX, tokenizers, MES firmware, and a
    # buildable live ISO. Consume its package
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
    # modules/microvm-host.nix, enabled on the coordinator alongside the local
    # artifact front door. follows
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
        # Fleet hostnames resolve through MagicDNS or the NAS's direct /etc/hosts
        # mapping. Force IPv4 so deploy-rs never selects a link-local AAAA record.
        "AddressFamily=inet"
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
          # zmx built by our own pkgs/zmx.nix from the non-flake source input:
          # nixpkgs zig + upstream's committed dependency lock, no zig2nix IFD
          # (see the input comment).
          zmx = final.callPackage ./pkgs/zmx.nix { src = inputs.zmx; };
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

      # Single host-wiring point. Interactive machines add Home Manager; the NAS
      # deliberately stops at NixOS so no user compositor or WayVNC unit exists.
      mkHost =
        {
          hostModule,
          withHomeManager ? true,
          # The nixpkgs universe this host's system closure evaluates from.
          # Interactive hosts ride the main unstable pin; the NAS passes
          # inputs.nixpkgs-stable (see that input's comment).
          hostNixpkgs ? nixpkgs,
        }:
        hostNixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            # rollingInputOverrides/fleetDeploySshOpts left this set 2026-08-21
            # with hosts/coordinator/fleet-deploy.nix, their only consumer;
            # both still exist at flake level (deploy nodes use the SSH opts,
            # and the NAS update-center will inherit the rolling-override
            # mechanic).
            inherit inputs;
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
          ]
          ++ nixpkgs.lib.optionals withHomeManager [
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

      # DHCP + operator-key installer used only to put the NAS on 10.77.0.2 so
      # nixos-anywhere can perform the reviewed eMMC installation over Ethernet.
      nasInstaller = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
          {
            nixpkgs.overlays = overlays;
            nixpkgs.config.allowUnfree = true;
            networking.hostName = "nas-installer";
            services.openssh.enable = true;
            services.openssh.settings.PermitRootLogin = "prohibit-password";
            users.users.root.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHuyYcI6TtVr2UBvyFXySczeRX+1tnaU3lJ8BdyVvw9s flasher@harness-20260427"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINwxGJ4IgTFfdMI+A2SDJO/E3jsZ7M/5McAioO87VX8Z tom@mesh-20260729"
            ];
            image.baseName = nixpkgs.lib.mkForce "nixos-nas-installer";
          }
        ];
      };
    in
    {
      # Evaluation-only metadata surface for deterministic local-AI workflows.
      # This serializes the accepted catalog without independently changing the
      # explicit per-host deployment/artifact allowlists.
      lib.localModelCatalog = localModelCatalog;

      overlays.default = import ./overlays {
        torchRocm = inputs.nix-strix-halo.packages.${system}.torch-rocm;
      };

      nixosConfigurations = {
        coordinator = mkHost { hostModule = ./hosts/coordinator; };
        nas = mkHost {
          hostModule = ./hosts/nas;
          withHomeManager = false;
          hostNixpkgs = inputs.nixpkgs-stable;
        };
        zenbook-duo = mkHost { hostModule = ./hosts/zenbook-duo; };
      };

      # deploy-rs owns HOW a selected generation reaches and activates on a node.
      # Since 2026-08-21 this graph is MANUAL-ONLY (`deploy .#<host>`): the
      # nightly Tally-owned fleet transaction (fleet-deploy.service) is dead,
      # superseded by the NAS update-center where devices pull instead of
      # being pushed. Manual pushes remain the operator's escape hatch.
      deploy = {
        sshUser = "root";
        user = "root";
        sshOpts = fleetDeploySshOpts;
        autoRollback = true;
        magicRollback = true;
        remoteBuild = false; # every selected profile is built locally on coordinator
        fastConnection = false; # let each destination substitute from Attic
        activationTimeout = 1200;
        confirmTimeout = 90;

        nodes =
          nixpkgs.lib.genAttrs
            [
              "coordinator"
              "nas"
              "zenbook-duo"
            ]
            (host: {
              # Canonical names resolve through MagicDNS or the direct NAS map.
              hostname = host;
              sshOpts = fleetDeploySshOpts;
              profiles.system.path =
                inputs.deploy-rs.lib.${system}.activate.nixos
                  self.nixosConfigurations.${host};
            });
      };

      packages.${system} =
        let
          amdAi = inputs.nix-amd-ai.packages.${system};
          strixAi = inputs.nix-strix-halo.packages.${system};
        in
        {
          inherit (pkgs)
            academic-ocr
            brother-print-text
            call-diarize
            crm
            dcal
            local-ai-monthly
            mactahoe-gtk-theme
            mactahoe-icon-theme
            music-acquire
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
            tokenizers-cpp
            vllm-rocm
            ;
          live-iso = strixAi.live-iso;
          nas-installer-iso = nasInstaller.config.system.build.isoImage;
        };

      # Artifact rows are individually buildable as `nix build .#models.<id>`.
      # This operator escape hatch does not change the one NixOS install switch.
      legacyPackages.${system}.models = localModelStore.packages;

      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          inputs.agenix.packages.${system}.default # `agenix -e/-r`
        ]
        ++ (with pkgs; [
          nixfmt
          deadnix
          statix
          nil
          git
        ]);
      };

      # The RAW out-of-store dotfiles are never checked at switch, so check them here.
      checks.${system} = {
        music-acquire = pkgs.music-acquire;

        nas-topology =
          let
            nas = self.nixosConfigurations.nas.config;
            coordinator = self.nixosConfigurations.coordinator.config;
          in
          assert !nas.services.tailscale.enable;
          # The NAS admits SSH/NFS via networking.firewall.extraInputRules,
          # which only renders under the nftables backend — with iptables the
          # appliance seals itself shut (hit live 2026-08-01).
          assert nas.networking.nftables.enable;
          assert !nas.programs.niri.enable;
          assert !nas.services.greetd.enable;
          assert !(nas.systemd.services ? wayvnc);
          assert !(nas.systemd.user.services ? wayvnc);
          assert !(builtins.hasAttr "home-manager" self.nixosConfigurations.nas.options);
          # Post-cutover topology (live since 2026-08-02, #131): the verified
          # data disk and the media stack run on the NAS; the coordinator only
          # relays. The pre-cutover extendModules simulation this check used
          # to carry became the real configuration and was retired.
          assert nas.myNas.storage.enable;
          assert nas.myNas.media.enable;
          assert nas.services.immich.enable;
          assert nas.services.navidrome.enable;
          assert nas.services.plex.enable;
          assert nas.fileSystems."/mnt/nas".fsType == "btrfs";
          assert nas.services.immich.mediaLocation == "/mnt/nas/photos";
          assert nas.services.navidrome.settings.MusicFolder == "/mnt/nas/music";
          assert !nas.services.immich.machine-learning.enable;
          assert nas.services.immich.environment.IMMICH_MACHINE_LEARNING_URL == "http://coordinator:3003";
          assert nas.services.immich.accelerationDevices == [ "/dev/dri/renderD128" ];
          # The stable-pinned NAS must keep running the SAME Immich the
          # unstable-riding coordinator would — the database schema follows
          # unstable (media.nix pulls module+package from inputs.nixpkgs).
          assert nas.services.immich.package.version == coordinator.services.immich.package.version;
          assert !coordinator.myCoordinatorMedia.enable;
          assert coordinator.myNasClient.useRemoteStorage;
          assert coordinator.myNasClient.relayMedia;
          assert !coordinator.services.immich.enable;
          assert !coordinator.services.navidrome.enable;
          assert coordinator.fileSystems."/mnt/nas".fsType == "nfs4";
          assert coordinator.systemd.sockets ? immich-relay;
          assert coordinator.systemd.sockets ? navidrome-relay;
          assert coordinator.systemd.sockets ? plex-relay;
          assert coordinator.systemd.sockets ? immich-ml-access;
          # ── cable admission (2026-08-06) + LAN admission (2026-08-20) ──────
          # The NAS has NO tailnet identity (asserted above). Its path to the
          # coordinator was the /30 cable; during the 2026-08-20 rewire
          # transition it is BOTH rails — the cable (enp191s0) and the BE550
          # LAN over the coordinator's wifi (wlp192s0). Failure modes held
          # off: re-blanket-trusting an interface, and anyone concluding
          # these flows need Tailscale. The enp191s0 half retires with the
          # /30 cleanup commit; drop those asserts in that same commit.
          assert !(builtins.elem "enp191s0" coordinator.networking.firewall.trustedInterfaces);
          assert !(builtins.elem "wlp192s0" coordinator.networking.firewall.trustedInterfaces);
          assert builtins.all
            (
              p:
              builtins.elem p coordinator.networking.firewall.interfaces.enp191s0.allowedTCPPorts
              && builtins.elem p coordinator.networking.firewall.interfaces.wlp192s0.allowedTCPPorts
            )
            [
              80 # caddy .internal front doors
              3003 # immich-ml, dialled by nas.services.immich above
              8080 # attic; without it the NAS builds from source
              9292 # llama-swap
            ];
          # dnsmasq for a factory/installer boot — the one moment nobody wants
          # to discover the appliance was firewalled off.
          assert builtins.elem 67 coordinator.networking.firewall.interfaces.enp191s0.allowedUDPPorts;
          # ── the NAS router plane (2026-08-20 rewire) ───────────────────────
          # The NAS is the house's gateway/DHCP/DNS (hosts/nas/router.nix).
          assert nas.services.dnsmasq.enable;
          # AdGuard owns :53 (the settings type lifts scalars into lists).
          assert nixpkgs.lib.toList nas.services.dnsmasq.settings.port == [ 0 ];
          assert nas.networking.nat.enable;
          assert nas.networking.nat.externalInterface == "wan0";
          assert nas.networking.nat.internalInterfaces == [ "enp1s0" ];
          assert nas.networking.nftables.tables ? dns_hijack;
          assert builtins.elem "10.42.0.1" nas.services.adguardhome.settings.dns.bind_hosts;
          # Never 0.0.0.0: resolved's stub holds 127.0.0.53:53 and a wildcard
          # bind EADDRINUSEs against it (26d4afdf lore).
          assert !(builtins.elem "0.0.0.0" nas.services.adguardhome.settings.dns.bind_hosts);
          # ── Strix Halo hard-lock protections must outlive the rewire ──────
          # The mt7925e wcid roam crash bricked the coordinator twice
          # (2026-07-16); the standing fixes are the ASPM escape hatch + the
          # sp5100_tco watchdog (modules/strix.nix) + never roaming: any wifi
          # profile this box could associate to must either pin a single
          # BSSID or name an SSID that only ever exists on ONE radio. The
          # sole exemption is thomas-6ghz since the 2026-08-21 6GHz ruling: it
          # joins thomas-6ghz, which broadcasts from exactly one radio (the
          # BE550's 5GHz radio is DISABLED — Tom's ruling, same day — and the
          # 2.4/5 SSID is distinct), so no roam surface exists. A pin there
          # is actively harmful: the 6GHz BSSID is an MLD address that
          # differs between scan and association (seen live: …6b:61:e6 in
          # scans, …6a:61:e6 on assoc) and pinning it broke activation on
          # the worker. If the BE550's 5GHz radio is EVER re-enabled with
          # the same SSID as 6GHz, this exemption must be revisited first.
          assert nixpkgs.lib.hasInfix "mt7925e disable_aspm=1" coordinator.boot.extraModprobeConfig;
          assert
            let
              profiles = coordinator.networking.networkmanager.ensureProfiles.profiles;
            in
            builtins.all (name: (profiles.${name}.wifi ? bssid) || name == "thomas-6ghz") (
              builtins.filter (
                name: (profiles.${name}.connection.type or "") == "wifi"
              ) (builtins.attrNames profiles)
            );
          # Split-horizon .internal: each box resolves the coordinator over
          # its shortest path, so stopping tailscaled cannot break traffic
          # between two hosts on the same LAN. The NAS's answer is the
          # coordinator's PINNED lease (hosts/nas/router.nix dhcp-host) and
          # since 2026-08-20 it also serves every LAN phone. A 100.x answer
          # on either of these is the regression this catches.
          assert builtins.all (
            r: r.answer == "10.42.0.2"
          ) nas.services.adguardhome.settings.filtering.rewrites;
          assert builtins.all (
            r: r.answer == "127.0.0.1"
          ) coordinator.services.adguardhome.settings.filtering.rewrites;
          # ── #130 expansion gates: all OFF, and the pairs agree ─────────────
          # These assert the STAGED shape, i.e. that today's switch is a no-op
          # on the NAS's running services. Each gate flips with its own runbook
          # (the header comment of the module named beside it); when one does,
          # invert the assertion here in the same commit rather than deleting
          # it — a gate that nothing checks is a gate that drifts.
          assert !nas.myNas.snapshots.enable; # ws2a hosts/nas/snapshots.nix
          # ws4 flipped ON 2026-08-20 (the Library's cold store): subvolume
          # created live with compression=none, gate + export + receipt
          # discipline landed together, per this block's own instructions.
          assert nas.myNas.models.enable; # model Library (was ws4 archive) hosts/nas/models.nix
          # ws5 EXECUTED 2026-08-21: atticd runs on the NAS M.2, no relay —
          # every host dials http://nas:8080/fleet directly.
          assert nas.myNas.attic.enable; # ws5  hosts/nas/attic.nix
          assert !nas.myNas.paperless.enable; # #136 hosts/nas/paperless.nix
          assert !nas.services.paperless.enable;
          assert !coordinator.myNasClient.relayAttic;
          # Plex is the video server (Tom's 2026-08-02 ruling, confirmed
          # 2026-08-03: the staged Jellyfin alternative was deleted, not kept
          # as a decoy). It must never be silently displaced.
          assert !nas.services.jellyfin.enable;
          # Cross-host invariants. Each relay and its backend must flip
          # together: a relay pointing at a service that is off is a black
          # hole, and a backend with no relay is unreachable from the tailnet.
          # (The attic relay pairing died with the 2026-08-21 direct-serve
          # move: the NAS serves 8080 itself and relayAttic must stay off.)
          assert nas.myNas.attic.enable && !coordinator.myNasClient.relayAttic;
          # Paperless backend and its tailnet relay flip together (#136).
          assert nas.myNas.paperless.enable == coordinator.myNasClient.relayPaperless;
          # The binary cache can only live in one place: moving it to the NAS
          # requires the coordinator's own atticd to go away in the same
          # commit, because both bind tcp/8080 on the coordinator (the relay
          # socket there, the server here). Enforced host-locally too, by an
          # assertion in hosts/coordinator/nas-client.nix.
          assert nas.myNas.attic.enable -> !coordinator.services.atticd.enable;
          # (ws2b borg deleted 2026-08-21 — Tom ruled it redundant against
          # the physical-redundancy stack; its asserts died with it.)
          pkgs.runCommand "nas-topology" { } ''
            touch "$out"
          '';

        # #136 gate-then-verify: evaluate the ENABLED Paperless shape without
        # deploying it, so the gate flip is an eval-proven one-liner. Same
        # extendModules simulation technique the NAS cutover used pre-#131.
        nas-paperless-staged =
          let
            nasOn =
              (self.nixosConfigurations.nas.extendModules {
                modules = [ { myNas.paperless.enable = true; } ];
              }).config;
          in
          assert nasOn.services.paperless.enable;
          # v3 only — a 2.x here means the nixpkgs-paperless input regressed.
          assert pkgs.lib.versionAtLeast nasOn.services.paperless.package.version "3";
          # PDFs only: no Tika/Gotenberg, no persistent PDF/A twin, no NAS AI.
          assert !nasOn.services.paperless.configureTika;
          assert nasOn.services.paperless.settings.PAPERLESS_ARCHIVE_FILE_GENERATION == "never";
          assert nasOn.services.paperless.settings.PAPERLESS_OCR_MODE == "auto";
          assert nasOn.services.paperless.settings.PAPERLESS_AI_ENABLED == false;
          # Same-subvolume storage contract for the hardlink projection.
          assert nasOn.services.paperless.consumptionDir == "/mnt/nas/documents/.paperless-consume";
          assert nasOn.services.paperless.mediaDir == "/mnt/nas/services/paperless/media";
          assert nasOn.fileSystems ? "/mnt/nas/services/paperless/media/documents/originals";
          # Enabling Paperless must not grow the NAS a Tailscale identity.
          assert !nasOn.services.tailscale.enable;
          assert nasOn.services.paperless.database.createLocally;
          pkgs.runCommand "nas-paperless-staged" { } ''
            touch "$out"
          '';

        home-profiles =
          let
            coordinatorHome = self.nixosConfigurations.coordinator.config.home-manager.users.tom;
            zenbookHome = self.nixosConfigurations.zenbook-duo.config.home-manager.users.tom;
          in
          assert coordinatorHome.home.username == "tom";
          assert coordinatorHome.programs.atuin.settings.auto_sync;
          assert coordinatorHome.services.tally.enable;
          assert coordinatorHome.programs.voxtype.enable;
          assert !(coordinatorHome.systemd.user.services ? ntm);
          assert coordinatorHome.systemd.user.services ? wayvnc;
          assert zenbookHome.home.username == "tom";
          assert zenbookHome.programs.atuin.settings.auto_sync;
          assert !zenbookHome.services.tally.enable;
          assert !zenbookHome.programs.voxtype.enable;
          assert zenbookHome.systemd.user.services ? ntm;
          assert zenbookHome.systemd.user.services ? wayvnc;
          pkgs.runCommand "home-profiles" { } ''
            touch "$out"
          '';

        ai-memory =
          let
            homeConfig = self.nixosConfigurations.coordinator.config.home-manager.users.tom;
            expectedJournal = "/home/tom/mecattaf/notes/journal";
          in
          assert homeConfig.programs.ai-memory.journalDir == expectedJournal;
          assert
            (builtins.fromJSON homeConfig.xdg.configFile."ai-memory/config.json".text) == {
              schema = 1;
              journal_dir = expectedJournal;
            };
          pkgs.runCommand "ai-memory"
            {
              nativeBuildInputs = [
                pkgs.jq
                pkgs.llm-agents.qmd
                pkgs.python3
              ];
            }
            ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              export XDG_CACHE_HOME="$TMPDIR/cache"
              export XDG_CONFIG_HOME="$TMPDIR/config"
              export XDG_RUNTIME_DIR="$TMPDIR/runtime"
              export PYTHONDONTWRITEBYTECODE=1
              export AI_MEMORY_ENGINE=${./home/dot_claude/skills/drain/scripts/ai_memory.py}
              export AI_MEMORY_DRAIN_SKILL=${./home/dot_claude/skills/drain/SKILL.md}
              export AI_MEMORY_HANDOFF_SKILL=${./home/dot_claude/skills/handoff/SKILL.md}
              export AI_MEMORY_PICKUP_SKILL=${./home/dot_claude/skills/pickup/SKILL.md}
              export AI_MEMORY_UTILITY_OWNER=${./pkgs/utility-model/utility_model.py}
              export AI_MEMORY_ZMX_TITLE=${./home/dot_local/bin/zmx-title}
              mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR"

              python3 -m unittest discover \
                -s ${./tests/ai-memory} \
                -p 'test_*.py' \
                -v
              ${pkgs.bash}/bin/bash -n \
                ${./home/dot_local/bin/zmx-title} \
                ${./home/dot_local/bin/zmx-retitle} \
                ${./home/dot_local/bin/new-terminal}

              mkdir -p "$HOME/journal"
              qmd --index ai-memory-check \
                collection add "$HOME/journal" --name journal >/dev/null
              printf '%s\n' \
                '# Synthetic journal result' \
                "" \
                'UNIQUE_MEMORY_BOUNDARY_SENTINEL' \
                > "$HOME/journal/note.md"
              cp "$HOME/journal/note.md" "$TMPDIR/note.before"
              qmd --index ai-memory-check update >/dev/null
              qmd --index ai-memory-check \
                search UNIQUE_MEMORY_BOUNDARY_SENTINEL --format json \
                > "$TMPDIR/search.json"
              jq -e '
                length == 1
                and .[0].file == "qmd://journal/note.md?index=ai-memory-check"
              ' "$TMPDIR/search.json" >/dev/null
              ${pkgs.diffutils}/bin/cmp \
                "$TMPDIR/note.before" "$HOME/journal/note.md"

              touch "$out"
            '';

        print-paper =
          pkgs.runCommand "print-paper"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              export PYTHONDONTWRITEBYTECODE=1
              export PRINT_PAPER_SCRIPT=${./home/dot_claude/skills/print/scripts/print-paper.py}
              export PRINT_PAPER_SKILL=${./home/dot_claude/skills/print/SKILL.md}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/print} \
                -p 'test_*.py' \
                -v

              touch "$out"
            '';

        nixos-only =
          let
            retiredPlatformPattern = nixpkgs.lib.concatStringsSep "|" [
              ("fed" + "ora")
              ("rpm-o" + "stree")
              ("d" + "nf")
              ("c" + "opr")
              ("boot" + "c")
              ("yum.repos." + "d")
              ("harness" + "RPM")
              ("chez" + "moi")
              ("k" + "run")
              ("tom@" + "bridge")
              ("/usr/share/backgrounds/" + "harness")
              ("osConfig" + "[[:space:]]*\\?[[:space:]]*null")
            ];
          in
          pkgs.runCommand "nixos-only"
            {
              nativeBuildInputs = [ pkgs.ripgrep ];
            }
            ''
              # go.sum lines are base64 hashes; the case-insensitive sweep
              # otherwise false-positives on three-letter substrings of them.
              if rg --ignore-case --line-number --glob '!go.sum' \
                '${retiredPlatformPattern}' ${self}; then
                echo "retired platform residue found in the canonical NixOS tree" >&2
                exit 1
              fi
              touch "$out"
            '';

        fleet-connectivity =
          let
            coordinator = self.nixosConfigurations.coordinator.config;
            nas = self.nixosConfigurations.nas.config;
            meshRegistry = import ./modules/mesh-registry.nix;
            retiredHost = "work" + "er";
            retiredPool = retiredHost + "-gpu";
            retiredExecutionPattern = nixpkgs.lib.concatStringsSep "|" [
              retiredHost
              retiredPool
              (retiredHost + "Flake")
              (retiredHost + "Models")
            ];
            retiredDeployment = "deepseek-v4-flash-q4-dual";
            activeHostSets = [
              (builtins.attrNames self.nixosConfigurations)
              (builtins.attrNames self.deploy.nodes)
              (builtins.attrNames meshRegistry)
            ];
            expectedHosts = [
              "coordinator"
              "nas"
              "zenbook-duo"
            ];
            retiredAliases = nixpkgs.lib.concatStringsSep "|" [
              (retiredHost + "-tb")
              ("coordinator-" + "tb")
            ];
            removedModel = "qwo" + "pus";
            monthlySources = builtins.fromJSON (builtins.readFile ./pkgs/local-ai-monthly/sources.json);
          in
          # Regression guard: the NixOS, deploy-rs, and mesh registries must agree
          # on the retired host's absence.
          assert nixpkgs.lib.all (hosts: !(nixpkgs.lib.elem retiredHost hosts)) activeHostSets;
          assert nixpkgs.lib.all (hosts: hosts == expectedHosts) activeHostSets;
          # 2026-08-20 rewire: names resolve to the LAN identities — the NAS
          # at its gateway address, the coordinator at its pinned lease. Both
          # are reachable over the legacy /30 cable too until the cleanup
          # commit, so these hold across the whole transition.
          assert coordinator.networking.hosts."10.42.0.1" == [ "nas" ];
          assert nas.networking.hosts."10.42.0.2" == [ "coordinator" ];
          # journald substrate (#135): coordinator is the sole sender, the NAS
          # receives on the NVMe, and the local journal stays bounded.
          assert nas.services.journald.remote.enable;
          assert coordinator.services.journald.upload.settings.Upload.URL == "http://10.42.0.1:19532";
          assert coordinator.services.journald.storage == "persistent";
          assert self.deploy.nodes.coordinator.hostname == "coordinator";
          assert self.deploy.nodes.nas.hostname == "nas";
          assert nixpkgs.lib.elem "AddressFamily=inet" self.deploy.sshOpts;
          assert coordinator.services.tailscale.extraUpFlags == [ "--ssh" ];
          assert !nas.services.tailscale.enable;
          assert nas.services.tailscale.extraUpFlags == [ ];
          assert nas.services.tailscale.extraSetFlags == [ ];
          assert !nas.programs.niri.enable;
          assert !nas.services.greetd.enable;
          assert !nas.services.printing.enable;
          assert !nas.services.avahi.enable;
          assert !nas.services.pipewire.enable;
          assert nas.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ ];
          assert !(builtins.hasAttr "home-manager" self.nixosConfigurations.nas.options);
          assert nas.myNas.storage.enable;
          assert nas.myNas.media.enable;
          assert nas.services.immich.enable;
          assert nas.services.navidrome.enable;
          assert !coordinator.myCoordinatorMedia.enable;
          assert coordinator.myNasClient.useRemoteStorage;
          assert coordinator.myNasClient.relayMedia;
          assert coordinator.systemd.sockets ? immich-ml-access;
          assert coordinator.systemd.services.tailscaled-autoconnect.serviceConfig.RestartSec == "1min";
          assert !coordinator.nix.distributedBuilds;
          assert coordinator.nix.buildMachines == [ ];
          assert !(builtins.hasAttr retiredHost coordinator.home-manager.users.tom.services.tally.executors);
          assert !(builtins.hasAttr retiredPool coordinator.home-manager.users.tom.services.tally.pools);
          assert !(builtins.hasAttr retiredHost coordinator.programs.ssh.knownHosts);
          assert !(self.nixosConfigurations.coordinator.options ? myCluster);
          assert coordinator.microvm.host.enable;
          assert !(self.nixosConfigurations.coordinator.options.myArtifacts ? livePortRange);
          assert !coordinator.home-manager.users.tom.services.tally.pools.coordinator-gpu.hardPreempt;
          # Crash surfacing (#134): the blanket OnFailure handler and both journal watchers exist.
          assert coordinator.systemd.services."failure-notify@".serviceConfig.Type == "oneshot";
          assert coordinator.systemd.timers ? tripwire-coredump;
          assert coordinator.systemd.timers ? tripwire-user-unit-failure;
          assert coordinator.systemd.timers ? failure-marker-reconcile;
          assert monthlySources.inference.url == "http://coordinator:9292";
          assert monthlySources.inference.compute_host == "coordinator";
          assert monthlySources.inference.tally_pool == "coordinator-gpu";
          assert !(builtins.hasAttr retiredDeployment localModelCatalog.deployments);
          pkgs.runCommand "fleet-connectivity" { } ''
            if ${pkgs.ripgrep}/bin/rg --line-number '${retiredAliases}' ${self}; then
              echo "retired mesh alias found" >&2
              exit 1
            fi
            if ${pkgs.ripgrep}/bin/rg --ignore-case --line-number '${removedModel}' ${self}; then
              echo "removed local-model identity found" >&2
              exit 1
            fi
            if ${pkgs.ripgrep}/bin/rg --line-number '${retiredExecutionPattern}' \
              ${./home/tally.nix} ${./flows}; then
              echo "retired Tally executor or pool found" >&2
              exit 1
            fi
            touch "$out"
          '';

        deadnix = pkgs.runCommand "deadnix" { } ''
          ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names \
            ${./flake.nix} ${./lib} ${./modules} ${./hosts} ${./overlays} ${./home} > $out 2>&1 \
            || (cat $out; exit 1)
        '';

        failure-marker-reconcile =
          pkgs.runCommand "failure-marker-reconcile"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.util-linux
              ];
              FAILURE_MARKER_RECONCILER = ./modules/failure-marker-reconcile.sh;
            }
            ''
              bash ${./tests/failure-marker-reconcile.sh}
              touch "$out"
            '';

        failure-marker-report =
          pkgs.runCommand "failure-marker-report"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.gawk
                pkgs.gnugrep
                pkgs.jq
                pkgs.util-linux
              ];
              FAILURE_MARKER_REPORTER = ./modules/failure-marker-report.sh;
              JOURNAL_SENSOR = ./modules/tripwire-journal-sensor.sh;
            }
            ''
              bash ${./tests/failure-marker-report.sh}
              touch "$out"
            '';

        printing =
          let
            coordinator = self.nixosConfigurations.coordinator.config;
            zenbook = self.nixosConfigurations.zenbook-duo.config;
            activeHosts = [
              coordinator
              zenbook
            ];
            expectedPrinter = {
              name = "Brother_HL_L2445DW";
              description = "Brother HL-L2445DW";
              location = "Home";
              deviceUri = "ipp://BRW08F97E55F396.local:631/ipp/print";
              model = "everywhere";
              ppdOptions.PageSize = "A4";
            };
          in
          assert nixpkgs.lib.all (host: host.services.printing.enable) activeHosts;
          assert nixpkgs.lib.all (host: host.services.avahi.enable) activeHosts;
          assert nixpkgs.lib.all (host: host.services.avahi.nssmdns4) activeHosts;
          assert nixpkgs.lib.all (host: host.services.avahi.openFirewall) activeHosts;
          assert nixpkgs.lib.all (
            host: host.services.resolved.settings.Resolve.MulticastDNS == false
          ) activeHosts;
          assert nixpkgs.lib.all (
            host: host.hardware.printers.ensureDefaultPrinter == expectedPrinter.name
          ) activeHosts;
          assert nixpkgs.lib.all (
            host: host.hardware.printers.ensurePrinters == [ expectedPrinter ]
          ) activeHosts;
          assert nixpkgs.lib.all (
            host: builtins.elem pkgs.brother-print-text host.environment.systemPackages
          ) activeHosts;
          pkgs.runCommand "printing"
            {
              nativeBuildInputs = [
                pkgs.brother-print-text
                pkgs.gnugrep
              ];
            }
            ''
              brother-print-text --help \
                | grep -F 'usage: brother-print-text [--] <text...>' >/dev/null
              touch "$out"
            '';

        huggingface-cli-smoke =
          let
            hf = pkgs.huggingface-cli;
            expectedVersion = "1.16.0";
            smokeRevision = "0123456789abcdef0123456789abcdef01234567";
            mockHub = pkgs.writeText "huggingface-metadata-mock.py" ''
              import json
              import sys
              from http.server import BaseHTTPRequestHandler, HTTPServer
              from pathlib import Path
              from urllib.parse import parse_qs, urlsplit

              PORT_FILE = Path(sys.argv[1])
              REQUEST_FILE = Path(sys.argv[2])
              REVISION = "${smokeRevision}"


              class Handler(BaseHTTPRequestHandler):
                  def do_GET(self):
                      parsed = urlsplit(self.path)
                      query = parse_qs(parsed.query)
                      expand = [
                          item
                          for value in query.get("expand", [])
                          for item in value.split(",")
                      ]
                      expected_path = (
                          "/api/models/smoke/model/revision/" + REVISION
                      )
                      valid = (
                          parsed.path == expected_path
                          and sorted(expand) == ["sha", "siblings"]
                          and "blobs" not in query
                          and self.headers.get("Authorization")
                          == "Bearer smoke-fixture-token"
                      )
                      REQUEST_FILE.write_text(
                          json.dumps(
                              {
                                  "path": parsed.path,
                                  "expand": sorted(expand),
                                  "has_blobs": "blobs" in query,
                                  "authenticated": self.headers.get("Authorization")
                                  == "Bearer smoke-fixture-token",
                              },
                              sort_keys=True,
                          )
                      )

                      if not valid:
                          self.send_error(400)
                          return

                      payload = json.dumps(
                          {
                              "id": "smoke/model",
                              "sha": REVISION,
                              "siblings": [{"rfilename": "config.json"}],
                          }
                      ).encode()
                      self.send_response(200)
                      self.send_header("Content-Type", "application/json")
                      self.send_header("Content-Length", str(len(payload)))
                      self.end_headers()
                      self.wfile.write(payload)

                  def log_message(self, _format, *_args):
                      pass


              server = HTTPServer(("127.0.0.1", 0), Handler)
              PORT_FILE.write_text(str(server.server_port))
              server.handle_request()
              server.server_close()
            '';
            coordinatorPackages =
              self.nixosConfigurations.coordinator.config.home-manager.users.tom.home.packages;
          in
          assert hf.version == expectedVersion;
          assert builtins.elem hf coordinatorPackages;
          pkgs.runCommand "huggingface-cli-smoke"
            {
              nativeBuildInputs = [
                hf
                pkgs.jq
                pkgs.python3
              ];
              # stdenv otherwise installs /no-cert-file.crt for pure builds.
              # httpx constructs an SSL context even for the loopback HTTP
              # fixture, so make the locked CA bundle an explicit remote input.
              SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
              NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            }
            ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              export HF_HOME="$TMPDIR/huggingface"
              mkdir -p "$HOME" "$HF_HOME"

              # Suppress the CLI's unrelated PyPI update probe. This marker is
              # included in both manifests, so any additional cache write fails.
              touch "$HF_HOME/.check_for_update_done"
              find "$HF_HOME" -mindepth 1 -printf '%P\t%y\t%s\n' \
                | sort > "$TMPDIR/cache-before"

              printf '%s\n' smoke-fixture-token > "$TMPDIR/hf-token"
              chmod 600 "$TMPDIR/hf-token"
              export HF_TOKEN_FILE="$TMPDIR/hf-token"

              hf --version > "$TMPDIR/version"
              grep -Fx '${expectedVersion}' "$TMPDIR/version"

              python ${mockHub} "$TMPDIR/port" "$TMPDIR/request.json" &
              server_pid=$!
              trap 'kill "$server_pid" 2>/dev/null || true' EXIT
              for _ in $(seq 1 200); do
                if [[ -s "$TMPDIR/port" ]]; then
                  break
                fi
                sleep 0.01
              done
              test -s "$TMPDIR/port"

              export HF_ENDPOINT="http://127.0.0.1:$(<"$TMPDIR/port")"
              hf models info smoke/model \
                --revision '${smokeRevision}' \
                --expand sha,siblings \
                --format json > "$TMPDIR/metadata.json"
              wait "$server_pid"
              trap - EXIT

              jq -e \
                --arg revision '${smokeRevision}' \
                '.id == "smoke/model"
                  and .sha == $revision
                  and (.siblings | map(.rfilename)) == ["config.json"]' \
                "$TMPDIR/metadata.json" > /dev/null
              jq -e \
                '.expand == ["sha", "siblings"]
                  and (.has_blobs | not)
                  and .authenticated' \
                "$TMPDIR/request.json" > /dev/null

              find "$HF_HOME" -mindepth 1 -printf '%P\t%y\t%s\n' \
                | sort > "$TMPDIR/cache-after"
              cmp "$TMPDIR/cache-before" "$TMPDIR/cache-after"
              test ! -e "$HF_HOME/hub"

              touch "$out"
            '';

        local-model-routing =
          let
            coordinator = self.nixosConfigurations.coordinator.config;
            zenbook = self.nixosConfigurations.zenbook-duo.config;
            coordinatorSettings = coordinator.services.llama-swap.settings;
            findPiWrapper =
              hostConfig:
              nixpkgs.lib.findFirst (package: nixpkgs.lib.getName package == "pi")
                (throw "evaluated host has no declarative Pi wrapper")
                hostConfig.home-manager.users.tom.home.packages;
            coordinatorPi = findPiWrapper coordinator;
            zenbookPi = findPiWrapper zenbook;
            coordinatorFlmManifest = coordinator.environment.etc."local-models/fastflowlm.json".source;
            canonicalUtilityDeployments = nixpkgs.lib.filterAttrs (
              _deploymentId: deployment:
              deployment.status == "canonical" && deployment.backend == "npu" && deployment.model == "qwen3:4b"
            ) localModelCatalog.deployments;
            modelPackagePaths = map toString (builtins.attrValues localModelStore.packages);
            coordinatorExtraDependencies = map toString coordinator.system.extraDependencies;
            selectedDeploymentIds = coordinator.services.local-models.allow;
            mageArtifactIds = [
              "mage-vl-bf16"
              "mage-flow-4b-turbo-bf16"
              "mage-flow-edit-4b-turbo-bf16"
            ];
            mageArtifacts = map (artifactId: localModelCatalog.artifacts.${artifactId}) mageArtifactIds;
            mageFiles = nixpkgs.lib.concatMap (artifact: artifact.source.files) mageArtifacts;
            mageUniqueFiles = builtins.attrValues (
              nixpkgs.lib.listToAttrs (
                map (file: {
                  name = file.oid;
                  value = file;
                }) mageFiles
              )
            );
            selectedWeightArtifactIds = nixpkgs.lib.unique (
              nixpkgs.lib.concatMap (
                deploymentId:
                let
                  refs = localModelCatalog.deployments.${deploymentId}.artifacts;
                in
                nixpkgs.lib.filter (artifactId: artifactId != null) [
                  refs.model
                  refs.mtpHead
                ]
              ) selectedDeploymentIds
            );
            selectedWeightQuantizations = map (
              artifactId: localModelCatalog.artifacts.${artifactId}.quantization
            ) selectedWeightArtifactIds;
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
              "allow"
              "artifacts"
            ];
          assert
            builtins.attrNames self.nixosConfigurations.coordinator.options.services.npu-llm == [
              "enable"
              "models"
            ];
          assert
            coordinator.services.local-models.allow == [
              "qwen36-35b-a3b-mtp-ud-q8-k-xl"
              "qwen36-27b-mtp-ud-q8-k-xl"
              "gemma4-26b-a4b-it-mtp-q8-0"
              "fara15-27b-q8-0"
              "fara15-9b-q8-0"
              # fara15-4b-q8-0 and qwen3-vl-32b-ocr-refine ruled out 2026-08-20
              # (#229); qwen3-vl-8b-ocr exits with the NPU2 OCR flip.
              "qwen3-vl-8b-ocr"
              "qwen3-embedding-8b-q8-0"
              "qwen3-vl-embedding-8b-q8-0"
              "qwen38-27b-mtp-q8-0"
              "ornith-15-35b-q8-0"
            ];
          assert
            coordinator.services.local-models.artifacts == [
              "mage-vl-bf16"
              "mage-flow-4b-turbo-bf16"
              "mage-flow-edit-4b-turbo-bf16"
              "vibevoice-asr-bf16"
              "vibevoice-large-bf16"
              "vibevoice-qwen25-7b-tokenizer"
            ];
          assert
            builtins.length (nixpkgs.lib.intersectLists modelPackagePaths coordinatorExtraDependencies) == 22;
          assert nixpkgs.lib.all (artifact: artifact.source.layout == "snapshot") mageArtifacts;
          assert builtins.length mageFiles == 164;
          assert nixpkgs.lib.foldl' (total: file: total + file.bytes) 0 mageFiles == 45863017994;
          assert nixpkgs.lib.foldl' (total: file: total + file.bytes) 0 mageUniqueFiles == 36583914927;
          assert nixpkgs.lib.all (
            quantization:
            nixpkgs.lib.elem quantization [
              "Q8_0"
              "UD-Q8_K_XL"
              # Qwen 3.8's MTP head: Q4_0 is the only published MTP asset;
              # the base model itself stays Q8_0.
              "Q4_0"
            ]
          ) selectedWeightQuantizations;
          assert
            builtins.attrNames coordinatorSettings.models == [
              "fara1.5-27b"
              "fara1.5-9b"
              "gemma4-26b-a4b-it"
              "ornith-1.5-35b"
              "qwen3-embedding-8b"
              "qwen3-vl-8b-ocr"
              "qwen3-vl-embedding-8b"
              "qwen3.6-27b"
              "qwen3.6-35b-a3b"
              "qwen3.8-27b"
            ];
          assert coordinatorSettings.peers == { };
          assert coordinator.systemd.services.llama-swap.environment.LLAMA_MEDIA_MARKER == "<__media__>";
          assert
            coordinator.systemd.services.llama-swap.environment.XDG_CACHE_HOME == "/var/cache/llama-swap";
          assert coordinator.hardware.amd-npu.enableNPU;
          assert nixpkgs.lib.elem "amd_iommu=on" coordinator.boot.kernelParams;
          assert
            coordinator.services.npu-llm.models == [
              "gemma4-it:e4b"
              "qwen3.6-moe:35b-a3b"
            ];
          assert nixpkgs.lib.all (unit: !(nixpkgs.lib.hasPrefix "flm-" unit)) (
            builtins.attrNames coordinator.systemd.services
          );
          assert nixpkgs.lib.all (
            unit: !(nixpkgs.lib.hasPrefix "flm-" unit)
          ) coordinator.systemd.services.llama-swap.wants;
          assert nixpkgs.lib.all (
            unit: !(nixpkgs.lib.hasPrefix "flm-" unit)
          ) coordinator.systemd.services.llama-swap.after;
          assert nixpkgs.lib.any (
            package: nixpkgs.lib.getName package == "fastflowlm"
          ) coordinator.environment.systemPackages;
          assert nixpkgs.lib.any (
            package: nixpkgs.lib.getName package == "utility-model"
          ) coordinator.environment.systemPackages;
          assert
            localModelCatalog.utility == {
              stableId = "utility";
              deployment = "flm-qwen3-4b-utility";
              contextTokens = 32768;
            };
          assert builtins.length (builtins.attrNames canonicalUtilityDeployments) == 1;
          assert canonicalUtilityDeployments ? "flm-qwen3-4b-utility";
          assert localModelCatalog.deployments."flm-qwen3-4b-utility".hosts == [ "coordinator" ];
          assert !(localModelCatalog.deployments."flm-qwen3-4b-utility" ? peer);
          assert !(localModelCatalog.deployments."flm-gemma4-it-e4b" ? peer);
          assert !(localModelCatalog.deployments."flm-gpt-oss-20b" ? peer);
          assert !(nixpkgs.lib.hasInfix "qwen3:4b" (builtins.toJSON coordinatorSettings));
          assert !(nixpkgs.lib.hasInfix "-hf" (builtins.toJSON coordinatorSettings));
          assert
            localModelCatalog.backendKinds == {
              appliances = [ "npu" ];
              local = [
                "rocm"
                "vulkan"
                "ds4"
                "vllm"
                "mlx"
              ];
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
            ${pkgs.jq}/bin/jq -e '
              .schema == 2
              and .runtime == "fastflowlm"
              and .lifecycle == "ad-hoc"
              and .persistentServer == false
              and (.models | map(.tag)) == [
                "gemma4-it:e4b",
                "qwen3.6-moe:35b-a3b",
                "qwen3:4b"
              ]
              and (.models | map(.command)) == [
                ["flm", "run", "gemma4-it:e4b"],
                ["flm", "run", "qwen3.6-moe:35b-a3b"],
                ["flm", "run", "qwen3:4b"]
              ]
              and .utility == {
                "id": "utility",
                "model": "qwen3:4b",
                "owner": "utility-model",
                "lifecycle": "request-scoped",
                "contextTokens": 32768,
                "command": ["utility-model"]
              }
            ' ${coordinatorFlmManifest} >/dev/null

            ${pkgs.gnugrep}/bin/grep -F 'export LLAMA_SWAP_PORT=9292' ${coordinatorPi}/bin/pi >/dev/null
            ${pkgs.gnugrep}/bin/grep -F -- '-e ${pkgs.pi-llama-swap-extension}' \
              ${coordinatorPi}/bin/pi >/dev/null
            if ${pkgs.gnugrep}/bin/grep -F -- '${pkgs.pi-llama-swap-extension}' \
              ${zenbookPi}/bin/pi >/dev/null; then
              echo "Pi loaded the llama-swap provider on a host without llama-swap" >&2
              exit 1
            fi
            touch "$out"
          '';
      }
      // inputs.deploy-rs.lib.${system}.deployChecks self.deploy;
    };
}
