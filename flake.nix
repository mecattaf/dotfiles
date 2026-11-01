{
  description = "mecattaf — NAS, client, strix-coordinator and strix-worker.";

  inputs = {
    # Unstable: Strix Halo (gfx1151) wants fresh kernels + Mesa.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nixpkgs-fresh — a second nixpkgs used ONLY to keep a handful of
    # fast-moving user packages (currently google-chrome and uv, see overlays
    # list below) and the fleet's linuxPackages_7_3 kernel series current
    # independent of the `nixpkgs` pin above. That pin is deliberately
    # lagging — the exact-candidate fleet deploy keeps it as the only door
    # Mesa/ROCm churn enters through, bumped manually. Browser point releases
    # and kernel point fixes stay within the selected series, so they shouldn't
    # have to wait on it.
    #
    # nixos-unstable-SMALL since 2026-08-30 (#244): the same rolling resolver,
    # gated by the same core Hydra jobs, minus the big-channel test set that
    # had nixos-unstable sitting 4+ days behind while 7.2.2 (a kernel point
    # fix the twins wanted) was already through. Everything this input feeds
    # is either an upstream binary (chrome), a leaf tool (uv), or the
    # versioned kernel attr whose whole doctrine is point-fix-only advance.
    #
    # The lock entry is the reviewed revision. The Projects nightly checker
    # proposes lock bumps in update/nixpkgs-fresh PRs; it never deploys.
    # rollingInputOverrides remains available to explicit fleet candidates.
    nixpkgs-fresh.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    # nixpkgs-stable — the NAS userspace base (issue #135 ruling).
    # Its kernel follows the fleet's current series from nixpkgs-fresh
    # (Tom, 2026-10-23, #584); ./hosts/nas/kernel.nix owns that exception.
    # Bump the stable userspace deliberately with
    # `nix flake update nixpkgs-stable`.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Stable Home Manager is isolated to the NAS's nixos-26.05 base.
    home-manager-nas = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    # The installed Projects CLI becomes a declared brain-role GC root (#552).
    # No nixpkgs.follows: upstream pins its pnpm-deps fixed-output hash against
    # its own lock (pnpm 12.3.4). Following our nixpkgs swapped in pnpm 11.15.0,
    # whose fetch hashes differently, so a fresh store failed with a hash
    # mismatch (2026-10-25, T-13; measured on both strix).
    project-cli.url = "git+https://github.com/agency-agency/backlog?rev=05e5f351ef5fdd1fc12fd5b805ee47e2e2be486a";

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

    # TOMBSTONE — apple-fonts (Lyndeno/apple-fonts.nix), removed 2026-09-15.
    # It locked Apple's CDN DMGs as `type = "file"` inputs, and Apple
    # re-releases them in place, so the locked narHash rots. The old
    # "containment" (only sf-pro is consumed, sibling locks sit inert) was
    # false: `nix flake archive` in update-center-seed fetches EVERY lock
    # node, and SF-Compact.dmg — never installed — failed it on 2026-09-15.
    # SF Pro itself stays (2026-08-21 ruling: "it's too good to have") but is
    # now pkgs/sf-pro.nix, pinned by sha256 to the fleet's own copy.
    #
    # ALL VENDOR FONT BYTES LIVE ON THE NAS M.2 (Tom, 2026-09-15: "i do not
    # want to download the fonts again everytime i do an update"; "keep the
    # fonts on the m2 ssd"): nas:/mnt/fast/fonts/<vendor>/ — apple/ since
    # 2026-09-15, anthropic/ since 2026-09-17 — one tarball per package, exact
    # bytes installed that day, requireFile-pinned: no flake input, no
    # download, and no font binary in this repo (see .gitignore).
    # (home/update-center-seed.nix, which seeded them into the NAS store
    # nightly, was deleted 2026-09-30; seed by hand before a NAS build.) The
    # press that produced the anthropic/ tarballs is pkgs/fontbuilder, which
    # ships the recipe and no bytes. Do not re-add a URL-locked font input.
    #
    # TOMBSTONE — sfmono-liga input (shaunsingh/SFMono-Nerd-Font-Ligaturized),
    # removed 2026-09-15 under the rule above; pkgs/sfmono-liga.nix. Liga SF
    # Mono: SF Mono ligaturized AND nerd-patched upstream — a different
    # derived font from apple-fonts' sf-mono-nerd (glyphs only, no
    # ligatures). DELETED in the 2026-08-21 sweep, RESTORED the
    # same evening: the sweep's premise ("no terminal ever used it") was
    # false — kitty.conf had named the nonexistent family "Maple Mono
    # Normal NF" since 2026-03-03 and silently rode the fontconfig
    # monospace alias, which pointed HERE, so this was the terminal face
    # the whole time (proven from the old kitty process's /proc maps).
    # Tom, on seeing real Maple: "i like whatever font was in use before
    # this afternoon's pushes." kitty.conf now names this family
    # EXPLICITLY, so no future sweep can silently swap the terminal again.
    #
    # 2026-09-17: the terminal face moved to `AnthropicMono Nerd Font`
    # (pkgs/anthropic-mono-nerd.nix, pressed by pkgs/fontbuilder). Deliberate,
    # with the family named explicitly in kitty.conf AND verified through
    # kitty's OWN resolver (`kitty +runpy` -> get_font_files), which is the
    # check the 2026-08-21 incident lacked: fc-scan alone would not have caught
    # it, because kitty does not consult fontconfig for an exact-name hit and
    # falls through to fc_match SILENTLY when it misses. sfmono-liga and sf-pro
    # remain INSTALLED and are the revert path — a four-line kitty.conf edit
    # plus a switch. A future sweep that removes either of them kills that
    # revert; do not remove them without replacing the revert plan.

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
      inputs.flake-utils.follows = "flake-utils";
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

    # flake-utils — shared by git-ai and deploy-rs through `follows`. It used to
    # be reached as "tally/flake-utils"; the Tally inputs (tally, tally-b,
    # tally-lake) were removed with the Tally sunset on 2026-09-30, and this
    # node keeps the exact rev that input had locked.
    flake-utils.url = "github:numtide/flake-utils";

    # deploy-rs — the fleet's one NixOS activation engine. (Tally, once the
    # scheduler/admission/proof plane around it, was removed 2026-09-30.) It
    # contributes target copy, activation, SSH confirmation, and automatic
    # rollback. Following our nixpkgs avoids a second package universe.
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };

    # Client desktop pilot: package and Home Manager module from one release.
    # Keep upstream's nixpkgs so its signed binary cache remains usable.
    vicinae.url = "github:vicinaehq/vicinae/v0.29.1";

    # herdr — the terminal workspace manager for AI coding agents
    # (github.com/herdrdev/herdr, Apache-2.0). It is the upstream PRODUCT that
    # replaces everything this repo used to invent for itself: the home-grown
    # kitten tier, its session layer, and its title-naming pipeline are all
    # deleted in favour of one server holding every PTY.
    #
    # PINNED TO A REV, not a branch: v0.9.1 (2026-09-16) is the current release
    # (plugin API + the agent sidebar), and nixpkgs carries an older release. Bump by
    # editing the rev here, deliberately, the way nixpkgs-paperless is bumped.
    #
    # Consume `packages.<sys>.herdr` ONLY (home/herdr.nix). Upstream composes
    # rust-overlay into its own pkgs fixpoint to build the Rust toolchain from
    # rust-toolchain.toml; that must never reach ours, so no overlay of theirs is
    # ever applied here. Following our nixpkgs keeps the build on our one pin.
    # NOT in `rollingInputOverrides`: herdr owns live PTYs, so its version moves
    # when Tom says so, never on a nightly resolve.
    herdr = {
      url = "github:herdrdev/herdr/7b116c05bfda646af39d2524c54e70c751f57ee8"; # v0.9.3, wire PROTOCOL_VERSION 22 as in 0.9.0
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-amd-ai — the proven strix NPU plane (hardware.amd-npu: amdxdna,
    # XRT plugin discovery, udev/memlock, FastFlowLM) plus the one accelerator
    # package nix-strix-halo does not expose: stable-diffusion-cpp-rocm.
    # The strix consumes the NPU module and runs IOMMU in translated mode.
    # Deliberately
    # NO inputs.nixpkgs.follows — the overlay is built against its OWN pinned
    # nixpkgs so its Cachix (nix-amd-ai.cachix.org, substituter added in
    # modules/common.nix) serves prebuilt XRT/FastFlowLM instead of source builds.
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";

    # nix-strix-halo — the broad gfx1151 package plane for the Framework Desktop:
    # llama.cpp ROCm/Vulkan, amdtop, MES firmware, and a buildable live ISO
    # (its ds4/vLLM/MLX outputs exist upstream but nothing here consumes them:
    # the resident model is served by Gufo). Consume its package
    # outputs directly rather than applying its global overlay: that preserves its
    # own TheRock/Python provider graph and avoids replacing the already-live
    # nix-amd-ai XRT/FastFlowLM pair. The two flakes currently pin identical XRT +
    # amdxdna revisions, so a second XRT in /run/current-system/sw would only create
    # colliding binaries. All NPU components remain exclusively sourced from
    # nix-amd-ai. No nixpkgs.follows: upstream's Hydra artifacts are keyed to its
    # own nixpkgs and provider pins (cache configured in common.nix).
    nix-strix-halo.url = "github:hellas-ai/nix-strix-halo";

    # gufo — the fleet's native inference engine for Strix Halo (gfx1151).
    # Its model collection is declared in lib/local-models.nix (#525).
    # One native binary,
    # no container (modules/gufo.nix). Pinned to the release the catalog matches
    # (v0.20.0). No nixpkgs.follows: upstream qualifies its build against its own
    # nixpkgs pin (GCC 15.3, ROCm 7.2.3).
    gufo.url = "github:gufo-org/gufo/0c03748a271eab895befc0d2343aa50ca4b6d836";

    # Separate, hardware-unqualified TP2 engine; the upstream single-box unit
    # above keeps its proven build. flake.lock pins both carry-forward heads.
    gufo-rdma.url = "github:neuhaus/gufo/rdma";
    donnerkeule.url = "github:mecattaf/donnerkeule/codex/framework-7-3-host-credits";

    # microvm.nix — declarative microVMs (astro → microvm-nix/microvm.nix). The
    # instrument behind the /microvm skill: it exports nixosModules.{microvm,host}
    # and, per guest, a `config.microvm.declaredRunner` package. DEFAULT USAGE is
    # EPHEMERAL — `nix run <guest>.config.microvm.declaredRunner` needs only this
    # input, no host module, so it works fleet-wide. The DURABLE path (the imperative
    # `microvm` CLI + `microvm@<name>` systemd units) is opt-in via
    # modules/microvm-host.nix, enabled on the strix alongside the local
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
      # flake.lock during the nightly fleet transaction. The strix resolves
      # each once and passes the same immutable URLs to every build and activation.
      #
      # This is intentionally NOT the main nixpkgs input: kernel/Mesa remain behind
      # an explicit lock-file review. These inputs are isolated package catalogs or
      # accelerator flakes that carry their own nixpkgs/provider pins and caches.
      rollingInputOverrides = [
        {
          name = "nixpkgs-fresh";
          # unstable-small since 2026-08-30 — must match the input URL above.
          url = "github:NixOS/nixpkgs/nixos-unstable-small";
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

      # One hardened operational SSH path for deploy-rs.
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

      # One overlay list everywhere (top-level pkgs + every host).
      overlays = [
        self.overlays.default
        (final: _prev: {
          # Whole llm-agents catalog under `pkgs.llm-agents.*` (prebuilt from its
          # own nixpkgs — no second eval of ours). home/home.nix pulls an
          # allowlisted set out of this namespace. See the input comment above.
          llm-agents = inputs.llm-agents.packages.${system};
          sfmono-liga = final.callPackage ./pkgs/sfmono-liga.nix { };
          sf-pro = final.callPackage ./pkgs/sf-pro.nix { };
          anthropic-mono-nerd = final.callPackage ./pkgs/anthropic-mono-nerd.nix { };
          anthropic-ui = final.callPackage ./pkgs/anthropic-ui.nix { };
          anthropic-webfonts = final.callPackage ./pkgs/anthropic-webfonts.nix { };
          fontbuilder = final.callPackage ./pkgs/fontbuilder { };
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

      # Test-only role fixture: preserve brain service contracts through relocation.
      agentProbe =
        (self.nixosConfigurations.strix-coordinator.extendModules {
          modules = [
            {
              myFleet.roles = nixpkgs.lib.mkForce [
                "brain"
                "compute"
              ];
            }
          ];
        }).config;

      localModelCatalog = import ./lib/local-models.nix { lib = nixpkgs.lib; };
      # The flake-level model-store binding is gone (2026-08-28, with the
      # #242 corpse removal): lib/model-store.nix still exists and is imported
      # where it is consumed — modules/local-models.nix and hosts/nas/models.nix
      # — but the flake itself no longer projects a package set from it, because
      # the 2026-08-21 "weights leave nix" ruling means there isn't one.

      # Single host-wiring point; roles keep desktop modules off headless hosts.
      mkHost =
        {
          hostModule,
          withHomeManager ? true,
          hostHomeManager ? home-manager,
          # The nixpkgs universe this host's system closure evaluates from.
          # Interactive hosts ride the main unstable pin; the NAS passes
          # inputs.nixpkgs-stable (see that input's comment).
          hostNixpkgs ? nixpkgs,
        }:
        hostNixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            # rollingInputOverrides/fleetDeploySshOpts left this set 2026-08-21
            # with hosts/strix/fleet-deploy.nix, their only consumer;
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
            hostHomeManager.nixosModules.home-manager
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

      # The reviewed rolling-input list, exposed the same evaluation-only way and
      # for the same reason. It lost its last CONSUMER when
      # hosts/strix/fleet-deploy.nix was deleted on 2026-08-21, but it did
      # not lose its MEANING: it is the reviewed set of inputs allowed to move
      # without a flake.lock review, and hosts/nas/default.nix cites it by name
      # as the reason a single leaf TUI (amdtop) moves nightly while the
      # appliance's stable base does not. Deleting it to satisfy deadnix would
      # have orphaned that prose and thrown away the reviewed URLs the NAS
      # update-center is expected to inherit; leaving it as a bare `let` binding
      # failed the deadnix check, which had been red at build time since that
      # deletion. Publishing it resolves both — the list stays reviewed, stays
      # cited, and is now inspectable by whatever wires the rolling resolution.
      lib.rollingInputOverrides = rollingInputOverrides;

      overlays.default = import ./overlays {
        torchRocm = inputs.nix-strix-halo.packages.${system}.torch-rocm;
        # The herdr home/herdr.nix installs, for pkgs/dsh-plugins to pin by
        # store path (dsh-herdr never looks `herdr` up on PATH).
        herdr = inputs.herdr.packages.${system}.herdr;
      };

      nixosConfigurations = {
        strix-coordinator = mkHost { hostModule = ./hosts/strix-coordinator; };
        strix-worker = mkHost { hostModule = ./hosts/strix-worker; };
        nas = mkHost {
          hostModule = ./hosts/nas;
          withHomeManager = true;
          hostHomeManager = inputs.home-manager-nas;
          hostNixpkgs = inputs.nixpkgs-stable;
        };
        # The ASUS Zenbook Duo, Tom's thin client since 2026-09-11 (its second
        # tenure here; `zenbook-duo` left on 2026-08-30 and came back from
        # omarchy-fleet under this name). Plain mkHost: it rides the unstable
        # pin like the twins and keeps Home Manager, because it is the box Tom
        # sits at — Sway, kitty and Chrome are real here, nothing else is.
        client = mkHost { hostModule = ./hosts/client; };
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
        remoteBuild = false; # every selected profile is built locally on strix
        fastConnection = false; # let each destination substitute from Attic
        activationTimeout = 1200;
        confirmTimeout = 90;

        nodes =
          nixpkgs.lib.genAttrs
            [
              "client"
              "nas"
              "strix-coordinator"
              "strix-worker"
            ]
            (host: {
              # Canonical names, every one: `nas` and `strix` through the
              # direct hosts pins, `worker` and `client` through
              # modules/fleet-hosts.nix (the worker's static 10.42.0.5, the
              # client's NAS-pinned DHCP lease 10.42.0.16). Every name is a
              # registry alias, so the host key stays pinned.
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
          # The Cloudflare Substrate's box-side programs, vendored from
          # agency-agency/substrate at the sha in pkgs/substrate-apps/SYNC.md.
          substrateApps = pkgs.callPackage ./pkgs/substrate-apps { };
        in
        {
          inherit (pkgs)
            qwentts
            qwen-speech
            speech-session
            academic-ocr
            brother-print-text
            paper-daemon
            paper-render
            call-diarize
            fleet-status
            # `nix build .#dsh -o .demo/dsh` is how a PR worktree runs dsh; its
            # passthru carries `.runner`, `.smoke` and `.unwrapped` for the gate.
            dsh
            # `nix run .#fontbuilder -- <capture-dir> <out-dir>` — the press for
            # the Anthropic suite. Exported because that IS the invocation. The
            # three anthropic-* font packages stay UNEXPORTED (matching sf-pro):
            # nothing needs to `nix build` a requireFile derivation by name, and
            # exporting them only gives `nix flake check` more ways to trip over
            # a tarball that is not in this machine's store. To build one anyway:
            #   nix build --impure --expr '(builtins.getFlake "'"$DOT"'").nixosConfigurations.strix.pkgs.anthropic-mono-nerd'
            fontbuilder
            land
            local-ai-monthly
            # `nix build .#local-models-prune` — the ONLY verb on this fleet
            # that deletes a working copy. Exposed so the guard suite can be
            # pointed at a built path (LOCAL_MODELS_PRUNE_BIN) instead of
            # requiring the binaries to be installed on the caller's PATH.
            local-models-prune
            mactahoe-gtk-theme
            mactahoe-claude-gtk-theme
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
            ec-su-axb35-monitor
            llama-cpp-rocm
            llama-cpp-vulkan
            strix-halo-mes-firmware
            ;
          # `nix build .#gufo` — the engine modules/gufo.nix runs (#525).
          gufo = inputs.gufo.packages.${system}.default;
          rdmaCoreUsb4 = pkgs.callPackage ./pkgs/rdma-core-usb4 { inherit (inputs) donnerkeule; };
          gufo-rdma = inputs.gufo-rdma.packages.${system}.tp2-rdma.override {
            rdma-core = self.packages.${system}.rdmaCoreUsb4;
          };
          thunderbolt-ibverbs =
            self.nixosConfigurations.strix-worker.config.hardware.thunderbolt-ibverbs.resolvedPackage;
          live-iso = strixAi.live-iso;
          nas-installer-iso = nasInstaller.config.system.build.isoImage;
          # Fresh worker install while its SSD is the coordinator's inactive
          # secondary. The generated script never mounts over the live /mnt.
          strix-worker-disko-offline =
            (self.nixosConfigurations.strix-worker.extendModules {
              modules = [ { disko.rootMountPoint = "/mnt/strix-worker-install"; } ];
            }).config.system.build.diskoScript;
          nas-home-migrate = self.nixosConfigurations.nas.config.system.build.nas-home-migrate;
          # `nix build .#substrate-pusher`, `.#substrate-puller`: the strix's
          # gentle capacity pusher and its interpreter-host puller from the
          # pinned substrate sha (pkgs/substrate-apps), installed by
          # modules/substrate.nix.
          substrate-pusher = substrateApps.pusher;
          substrate-puller = substrateApps.puller;
        };

      # `nix build .#models.<id>` retired with the 2026-08-21 "weights leave
      # nix" ruling: weights are no longer derivations, so there is nothing to
      # build — the NAS Library and library-fetch own materialization now.
      # (The binding this comment replaced read localModelStore.packages, an
      # attribute the same ruling's model-store rewrite deleted.)

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
        fleet-agent-transport = import ./tests/fleet-agent-transport {
          inherit pkgs self;
          inherit (nixpkgs) lib;
        };
        nas-agent-host = import ./tests/nas-agent-host {
          inherit pkgs self;
          inherit (nixpkgs) lib;
        };
        fleet-roles = import ./tests/fleet-roles {
          inherit pkgs self;
          inherit (nixpkgs) lib;
        };
        nas-home-disk = import ./tests/nas-home-disk {
          inherit pkgs self;
          inherit (nixpkgs) lib;
        };
        closet-topology = import ./tests/closet-topology {
          inherit pkgs self;
          inherit (nixpkgs) lib;
        };
        ds4-fleet = import ./tests/ds4 {
          inherit pkgs self inputs;
          lib = pkgs.lib;
        };
        gufo-rdma = import ./tests/gufo-rdma {
          inherit pkgs self inputs;
          inherit (nixpkgs) lib;
        };
        strix-reachability =
          pkgs.runCommand "strix-reachability"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.bash
                pkgs.jq
              ];
              SENSOR = pkgs.writeText "strix-reachability-sensor" self.nixosConfigurations.client.config.myTripwire.strix-reachability.sensor;
            }
            ''
              python3 ${./tests/strix-reachability/test_sensor.py}
              touch "$out"
            '';
        claude-settings = pkgs.runCommand "claude-settings" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          export CLAUDE_SETTINGS_MODULE=${./home/claude-settings.py}
          python3 ${./tests/claude-settings/test_settings.py}
          touch "$out"
        '';

        # modules/substrate.nix rendered OFF on the strix and armed with
        # fixtures (tests/substrate-modules); every assertion is eval-time.
        substrate-modules = import ./tests/substrate-modules {
          inherit pkgs self;
          inherit (nixpkgs) lib;
        };

        # DF-5: the vendored Cargo.lock must equal upstream's at the pinned rev.
        # A build-time comparison, not an evaluation-time read, so evaluation
        # never needs the fetched source (no import-from-derivation).
        zenbook-duo-daemon-lock =
          let
            daemon = self.nixosConfigurations.client.config.services.zenbook-duo-daemon.package;
          in
          pkgs.runCommand "zenbook-duo-daemon-lock-check" { } ''
            cmp ${daemon.src}/Cargo.lock ${./pkgs/zenbook-duo-daemon.Cargo.lock}
            touch "$out"
          '';

        qwen-speech =
          pkgs.runCommand "qwen-speech-tests"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              mkdir -p repo/pkgs repo/tests/qwen-speech
              cp -r ${./pkgs/qwen-speech} repo/pkgs/qwen-speech
              cp ${./tests/qwen-speech/test_speech.py} repo/tests/qwen-speech/test_speech.py
              python3 repo/tests/qwen-speech/test_speech.py
              touch "$out"
            '';
        qwen-speech-topology =
          let
            coord = self.nixosConfigurations.strix-coordinator.config;
            speechUnit = coord.systemd.user.services.qwen-tts;
          in
          assert speechUnit.wantedBy == [ ];
          assert speechUnit.serviceConfig.Type == "notify";
          assert
            speechUnit.environment.VK_ICD_FILENAMES
            == "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";

          assert builtins.elem pkgs.qwen-speech
            self.nixosConfigurations.client.config.home-manager.users.tom.home.packages;
          assert
            !(builtins.elem pkgs.qwentts self.nixosConfigurations.client.config.home-manager.users.tom.home.packages);
          pkgs.runCommand "qwen-speech-topology" { } ''touch "$out"'';

        music-acquire = pkgs.music-acquire;

        # The Claude capacity oracle (DECISION-R2-1). It is BOTH the waybar
        # module and the dispatch admission gate, so its three exit codes
        # (0 headroom / 1 defer / 2 cannot determine) are a fleet contract:
        # a regression that turns "cannot determine" into 0 would dispatch
        # into a spent subscription window, and one that turns headroom into
        # nonzero would stall the queue silently. Both are cheap to pin and
        # impossible to notice by eye, so they are asserted here.
        #
        # The suite is hermetic — it drives the script through a seeded cache
        # in a temp XDG_RUNTIME_DIR with a temp HOME holding a deliberately
        # dead token — so it runs inside the sandbox with no network.
        claude-capacity = pkgs.runCommand "claude-capacity" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          set -euo pipefail
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          CLAUDE_CAPACITY=${./home/dot_local/bin/claude-capacity} \
            python3 ${./tests/claude-capacity/test-claude-capacity.py} | tee "$TMPDIR/out"
          # The count is asserted against the doc, not just printed. P05's
          # handoff called this suite "21 hermetic cases" when it had 23 and
          # had never had any other number; a receipt drifted from the code
          # and nothing caught it. docs/local-ai/claude-capacity.md now
          # states the number, and this check fails if the two disagree —
          # whichever of them moved (U-D8).
          n=$(tail -1 "$TMPDIR/out" | grep -o '^[0-9]*')
          test -n "$n"
          grep -q "$n" ${./docs/local-ai/claude-capacity.md} || {
            echo "claude-capacity: the suite reports $n cases but" >&2
            echo "docs/local-ai/claude-capacity.md does not say $n." >&2
            echo "Fix the doc, or the suite — do not fix the receipt." >&2
            exit 1
          }
          # py_compile is a second, independent guard: a syntax error in the
          # oracle would otherwise only surface when waybar or a dispatch
          # asked it a question.
          python3 -m py_compile ${./home/dot_local/bin/claude-capacity}
          cp "$TMPDIR/out" $out
        '';

        # The l8-flash reconciliation's own row (U-D16, #319, #293).
        #
        # home/dot_local/bin/l8-flash-probe gained a row that says whether the
        # two HAND-WRITTEN claude-transcript-mirror units are still plain files
        # in ~/.config/systemd/user. They are, today: removing them is Tom's
        # shell act in P05 walkthrough step 4 (DEFERRED.md DF-U-D16-1), and it
        # must not happen before the switch that replaces them. So the row ships
        # RED, and a row that is red on the day it is written is exactly the row
        # nobody notices has stopped working. It is asserted here instead, in a
        # temp HOME, in all four states that matter: pair present, half
        # deleted, gone, and — the one an `-e` test would get backwards —
        # present as home-manager's own symlinks, which is the switch having
        # SUCCEEDED. Hermetic: no systemd, no tally, no network.
        l8-flash-probe-row =
          pkgs.runCommand "l8-flash-probe-row"
            {
              nativeBuildInputs = [
                pkgs.gnugrep
                pkgs.gawk
              ];
            }
            ''
              set -euo pipefail
              L8_FLASH_PROBE=${./home/dot_local/bin/l8-flash-probe} \
                bash ${./tests/l8-flash-probe/test-handwritten-row.sh} | tee "$TMPDIR/out"
              cp "$TMPDIR/out" $out
            '';

        # The two UTIL-01 rows l8-flash-probe gained with the reconciliation
        # (U-D17, #320). Same reasoning as l8-flash-probe-row above: both rows
        # ship RED, because nothing has switched yet and neither timer has a
        # fragment, and a row that is red on the day it is written is the row
        # nobody notices has stopped working. Asserted here in a fake HOME with
        # a fake `systemctl` on PATH, in every state that matters — pre-switch,
        # declared, hand-installed (the Rule 9 failure), and off the
        # strix, where util-row is SKIP and must never be FAIL. The count
        # is asserted too: the issue says the probe gains EXACTLY these two
        # rows. Hermetic: no systemd, no tally, no network.
        # Offline replay must preserve partial/missing token windows and closed
        # days. Gufo's uncalibrated live counts remain UNKNOWN, never zero.
        util-row-closed-day =
          pkgs.runCommand "util-row-closed-day" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              set -euo pipefail
              UTIL_ROW=${./home/dot_local/bin/util-row} \
                bash ${./tests/util-row/test-closed-day-idempotent.sh} | tee $out
            '';
        util-01-token-windows =
          pkgs.runCommand "util-01-token-windows" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              set -euo pipefail
              UTIL_SAMPLER=${./home/dot_local/bin/util-sampler} \
              UTIL_ROW=${./home/dot_local/bin/util-row} \
                bash ${./tests/util-01/test-token-windows.sh} | tee $out
            '';

        gufo-demand = import ./tests/gufo-demand { inherit pkgs self; };

        gufo-unit-policy =
          let
            strix = self.nixosConfigurations.strix-coordinator.config;
          in
          assert builtins.all (name: !(nixpkgs.lib.hasPrefix "podman-halogen" name)) (
            builtins.attrNames strix.systemd.services
          );
          assert !(strix.services ? halogen);
          assert builtins.all (name: !(nixpkgs.lib.hasPrefix "halogen-" name)) (
            builtins.attrNames (import ./lib/local-models.nix { lib = nixpkgs.lib; }).artifacts
          );
          assert builtins.all (
            artifact: builtins.all (file: !(nixpkgs.lib.hasSuffix ".hgn" file.path)) artifact.source.files
          ) (builtins.attrValues (import ./lib/local-models.nix { lib = nixpkgs.lib; }).artifacts);
          assert strix.services.gufo.enable;
          assert strix.services.gufo.llm.sessions == 1;
          assert strix.services.gufo.llm.context == 102400;
          assert !(strix.systemd.user.services ? substrate-puller);
          pkgs.runCommand "gufo-unit-policy" { } ''
            touch "$out"
          '';

        l8-flash-probe-util-rows =
          pkgs.runCommand "l8-flash-probe-util-rows"
            {
              nativeBuildInputs = [
                pkgs.gnugrep
                pkgs.gawk
              ];
            }
            ''
              set -euo pipefail
              L8_FLASH_PROBE=${./home/dot_local/bin/l8-flash-probe} \
                bash ${./tests/l8-flash-probe/test-util-timer-rows.sh} | tee "$TMPDIR/out"
              cp "$TMPDIR/out" $out
            '';

        nas-topology =
          let
            nas = self.nixosConfigurations.nas.config;
            strix = self.nixosConfigurations.strix-coordinator.config;

          in
          # ── the tailnet (2026-10-08, Tom's final closet decision) ──────────
          # The NAS is the closet's subnet router on official Tailscale
          # (hosts/nas/tailscale.nix): it advertises the house LAN so the
          # Zenbook reaches every home device through one node. Headscale is
          # gone, so no --login-server may be passed: its appearance would
          # point the node at a control plane that no longer exists, and in
          # extraSetFlags it would also fail the tailscaled-set unit on boot
          # (`tailscale set` has no such flag).
          assert nas.services.tailscale.enable;
          assert nas.services.tailscale.useRoutingFeatures == "server";
          assert builtins.elem "--advertise-routes=10.42.0.0/24" nas.services.tailscale.extraUpFlags;
          assert builtins.elem "--advertise-routes=10.42.0.0/24" nas.services.tailscale.extraSetFlags;
          assert !builtins.any (nixpkgs.lib.hasPrefix "--login-server=") nas.services.tailscale.extraUpFlags;
          assert !builtins.any (nixpkgs.lib.hasInfix "tailscale.com") nas.services.tailscale.extraUpFlags;
          assert !builtins.any (nixpkgs.lib.hasPrefix "--login-server=") nas.services.tailscale.extraSetFlags;
          # The strix keeps its own Tailscale identity as an independent
          # fallback for when the NAS is down (hosts/strix/tailscale.nix). It
          # is a plain node, not a second router: the NAS stays the only one
          # advertising the LAN, and no --login-server ties it to anything but
          # official Tailscale.
          assert strix.services.tailscale.enable;
          assert
            !builtins.any (nixpkgs.lib.hasPrefix "--login-server=") strix.services.tailscale.extraUpFlags;
          assert
            !builtins.any (nixpkgs.lib.hasPrefix "--advertise-routes") strix.services.tailscale.extraUpFlags;

          # The NAS admits SSH/NFS via networking.firewall.extraInputRules,
          # which only renders under the nftables backend — with iptables the
          # appliance seals itself shut (hit live 2026-08-01).
          assert nas.networking.nftables.enable;
          # The NAS is a storage/router appliance with no graphical session.
          assert !nas.programs.niri.enable;
          assert !nas.services.greetd.enable;
          assert !nas.services.pipewire.enable;
          assert !(nas.systemd.user.services ? wayvnc);
          assert !(nas.systemd.services ? wayvnc);
          assert nas.hardware.graphics.enable;
          assert builtins.hasAttr "home-manager" self.nixosConfigurations.nas.options;
          # Post-cutover topology (live since 2026-08-02, #131): the verified
          # data disk and the media stack run on the NAS; the strix only
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
          # Immich ML MOVED strix -> worker 2026-08-21 (#229). The URL, the
          # endpoint, and the name resolution behind it must agree, so all three
          # are asserted together: a repoint without the pin is a black hole, and
          # a pin without the endpoint is a connection refused.
          assert
            nas.services.immich.environment.IMMICH_MACHINE_LEARNING_URL == "http://strix-coordinator:3003";

          assert nas.services.immich.accelerationDevices == [ "/dev/dri/renderD128" ];
          # The stable-pinned NAS must keep running the SAME Immich the
          # unstable-riding strix would — the database schema follows
          # unstable (media.nix pulls module+package from inputs.nixpkgs).
          assert nas.services.immich.package.version == strix.services.immich.package.version;
          # And since 2026-08-21 the server and its ML backend live on DIFFERENT
          # boxes (#229), so their version coupling is now a cross-host
          # invariant rather than an implicit local one. hosts/worker/immich-ml.nix
          # takes its package from this same option for exactly this assert.

          # The NAS fronts every .internal site; the strix runs no Caddy and
          # no media relays. The relayMedia option is gone, so test the attr.
          assert strix.myNasClient.useRemoteStorage;
          assert !strix.services.immich.enable;
          assert !strix.services.navidrome.enable;
          assert strix.fileSystems."/mnt/nas".fsType == "nfs4";
          assert !strix.services.caddy.enable;
          assert nas.services.caddy.enable;
          assert !(strix.systemd.sockets ? immich-relay);
          assert !(strix.systemd.sockets ? navidrome-relay);
          assert !(strix.systemd.sockets ? plex-relay);
          assert !(strix.myNasClient ? relayMedia);
          # ML is the one endpoint that is NOT a strix relay any more: the
          # socket must exist on the worker and must be GONE from the
          # strix. Asserting both directions is deliberate — a half-move
          # that left both boxes listening on :3003 would work by accident and
          # then rot.

          assert strix.systemd.sockets ? immich-ml-access;
          # ── LAN admission (2026-08-20 rewire; /30 half retired 2026-08-21) ──
          # The enp191s0 half of this block is GONE, as its own instructions
          # said it should be: the /30 cable was unplugged at the TV-corner
          # move and every module-side admission for it was deleted on cutover
          # day. What was NOT deleted was these asserts, which kept naming
          # `strix.networking.firewall.interfaces.enp191s0` — an
          # attribute that no longer exists, so the whole check threw. Squared
          # up here with the #229 work. The installer-dnsmasq :67 assert dies
          # with it for the same reason (no cable, no factory boot over it).
          #
          # Failure modes still held off: re-blanket-trusting an interface, and
          # anyone concluding these LAN flows need Tailscale.
          assert !(builtins.elem "wlp192s0" strix.networking.firewall.trustedInterfaces);

          # Coordinator LAN doors: the .internal front doors and the LLM
          # endpoint. :3003 is deliberately ABSENT — it left with Immich ML.
          assert !(builtins.elem 80 (strix.networking.firewall.interfaces.enp191s0.allowedTCPPorts or [ ]));
          # The strix serves no model: no inference door on its LAN leg.
          assert !(builtins.elem 9292 (strix.networking.firewall.interfaces.wlp192s0.allowedTCPPorts or [ ]));
          assert !(builtins.elem 8731 (strix.networking.firewall.interfaces.wlp192s0.allowedTCPPorts or [ ]));
          assert !(builtins.elem 3003 (strix.networking.firewall.interfaces.wlp192s0.allowedTCPPorts or [ ]));
          # Worker LAN doors: Immich ML (dialled by nas.services.immich above),
          # the Gufo API (modules/gufo.nix) and the academic drain that
          # drain site (dropped 2026-10-31 with the strix Caddy)
          # (hosts/worker/default.nix). Nothing else — and no
          # tailnet to hide behind, which is exactly why these stay
          # interface-scoped rather than global. On enp191s0: the worker is
          # WIRED into the BE550 and has no wifi profile at all.

          # Attic moved to the NAS at ws5 — the strix serves no :8080 and
          # every host, worker included, dials http://nas:8080/fleet instead.

          # NAS gateway/DNS .1 forwards on Ethernet to BE550 .3.
          assert nas.services.dnsmasq.enable;
          assert nixpkgs.lib.toList nas.services.dnsmasq.settings.port == [ 0 ];
          assert builtins.elem "option:router,10.42.0.1" nas.services.dnsmasq.settings.dhcp-option;
          assert builtins.elem "option:dns-server,10.42.0.1" nas.services.dnsmasq.settings.dhcp-option;
          # The worker's LAN address is declared TWICE on purpose, and the two
          # must never drift. The box itself holds it statically (the `lan`
          # profile, asserted further down: method=manual, no DHCP on
          # enp191s0), which is what makes it survive a reboot without the NAS
          # being up. The NAS additionally RESERVES it, so the pool can never
          # hand .5 to anything else and the name stays stable. The reservation
          # names the WIRED 5GbE NIC — the worker's only link since 2026-09-11;
          # the earlier pin named the box's idle wifi MAC and could never have
          # matched. This assert derives the address from the worker's own
          # profile, so changing one side without the other fails the build.

          assert
            nas.networking.networkmanager.ensureProfiles.profiles.coordinator-fast-lane.ipv4.gateway
            == "10.42.0.3";
          assert !(nas.networking.networkmanager.ensureProfiles.profiles ? freebox-uplink);
          assert !(nas.systemd.services ? wan0-watchdog);
          assert !(nas.systemd.network.links ? "10-wan0");
          assert nas.systemd.network.links."10-lan".matchConfig.PermanentMACAddress == "ec:1a:c3:04:9d:54";
          assert nas.systemd.network.links."10-lan".linkConfig.Name == "enp1s0";
          assert !(nas.systemd.network.links ? "10-nas-lan");
          assert !(builtins.elem "usbcore.autosuspend=-1" nas.boot.kernelParams);
          assert !nas.networking.nat.enable;
          assert nas.networking.nftables.tables ? nas_upstream;
          assert nas.networking.nftables.tables ? dns_hijack;
          assert nas.boot.kernel.sysctl."net.ipv4.ip_forward" == 1;
          assert nas.boot.kernel.sysctl."net.ipv4.conf.all.send_redirects" == 0;
          assert nas.boot.kernel.sysctl."net.ipv4.conf.enp1s0.send_redirects" == 0;
          assert nas.services.adguardhome.enable;
          assert
            nas.services.adguardhome.settings.dns.bind_hosts == [
              "127.0.0.1"
              "10.42.0.1"
            ];
          assert nas.services.resolved.settings.Resolve.DNSStubListenerExtra == [ "100.65.85.114" ];
          assert nas.services.resolved.settings.Resolve.DNS == "127.0.0.1";
          assert nas.services.resolved.settings.Resolve.Domains == "~.";
          assert strix.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.gateway == "10.42.0.3";
          assert strix.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.dns == "10.42.0.1";
          assert strix.networking.networkmanager.ensureProfiles.profiles.lan.ipv6.method == "disabled";
          assert nixpkgs.lib.hasInfix "mt7925e disable_aspm=1" strix.boot.extraModprobeConfig;

          # Static, lease-free LAN identity — the property every cross-host
          # reference to this box depends on (NAS ML URL, NAS journal ACL, the
          # hosts pins). A silent revert to DHCP breaks all three.

          # AdGuard and local host lookups agree on the media front doors.
          # Wildcard rewrites (`*.art.mecattaf.dev`, M-4) cannot appear in
          # /etc/hosts, so they are filtered out of the second test; the first
          # still holds every rewrite, wildcard included, to the NAS address.
          assert builtins.all (
            r: r.answer == "10.42.0.1"
          ) nas.services.adguardhome.settings.filtering.rewrites;
          assert builtins.all (n: builtins.elem n nas.networking.hosts."10.42.0.1") (
            map (r: r.domain) (
              builtins.filter (
                r: !(nixpkgs.lib.hasPrefix "*." r.domain)
              ) nas.services.adguardhome.settings.filtering.rewrites
            )
          );
          # Filtering is centralized on the NAS.
          assert !strix.services.adguardhome.enable;

          # ── #130 expansion gates: all OFF, and the pairs agree ─────────────
          # These assert the STAGED shape, i.e. that today's switch is a no-op
          # on the NAS's running services. Each gate flips with its own runbook
          # (the header comment of the module named beside it); when one does,
          # invert the assertion here in the same commit rather than deleting
          # it — a gate that nothing checks is a gate that drifts.
          # ws2a FLIPPED ON 2026-08-21 per the runbook in hosts/nas/snapshots.nix
          # (btrbk over the data subvolumes). The gate moved in that day's commit
          # but this assertion did not, against this block's own standing
          # instruction to invert it in the same commit — so it had been failing.
          # Inverted here with the #229 work; the gate discipline is intact again.
          # FLIPPED OFF 2026-10-28 on Tom's word ("no time machine for file etc"):
          # the nine btrbk snapshots were deleted by hand with the .snapshots
          # subvolume; files are backed up as files, not as snapshots.
          assert !nas.myNas.snapshots.enable; # ws2a hosts/nas/snapshots.nix
          # ws4 flipped ON 2026-08-20 (the Library's cold store): subvolume
          # created live with compression=none, gate + export + receipt
          # discipline landed together, per this block's own instructions.
          assert nas.myNas.models.enable; # model Library (was ws4 archive) hosts/nas/models.nix
          # ws5 EXECUTED 2026-08-21: atticd runs on the NAS M.2, no relay —
          # every host dials http://nas:8080/fleet directly.
          assert nas.myNas.attic.enable; # ws5  hosts/nas/attic.nix
          # Paperless was removed on 2026-10-13 (Tom 2026-09-29: "i m removing
          # paperless fully"); nothing on the NAS or the strix may bring it back.
          assert !nas.services.paperless.enable;
          assert nas.services.caddy.virtualHosts ? "http://photos.internal";
          assert nas.services.caddy.virtualHosts ? "http://music.internal";
          assert nas.services.caddy.virtualHosts ? "http://videos.internal";
          assert !(nas.services.caddy.virtualHosts ? "http://drain.internal");
          assert !(nas.services.caddy.virtualHosts ? "http://paperless.internal");
          assert nixpkgs.lib.hasInfix "default_bind 10.42.0.1 127.0.0.1" nas.services.caddy.globalConfig;
          assert !(builtins.elem "tailscale0" nas.networking.firewall.trustedInterfaces);
          assert !strix.myNasClient.relayAttic;
          # Plex is the video server (Tom's 2026-08-02 ruling, confirmed
          # 2026-08-03: the staged Jellyfin alternative was deleted, not kept
          # as a decoy). It must never be silently displaced.
          assert !nas.services.jellyfin.enable;
          # Cross-host invariants. Each relay and its backend must flip
          # together: a relay pointing at a service that is off is a black
          # hole, and a backend with no relay is unreachable from the tailnet.
          # (The attic relay pairing died with the 2026-08-21 direct-serve
          # move: the NAS serves 8080 itself and relayAttic must stay off.)
          assert nas.myNas.attic.enable && !strix.myNasClient.relayAttic;
          # The binary cache can only live in one place: moving it to the NAS
          # requires the strix's own atticd to go away in the same
          # commit, because both bind tcp/8080 on the strix (the relay
          # socket there, the server here). Enforced host-locally too, by an
          # assertion in hosts/strix/nas-client.nix.
          assert nas.myNas.attic.enable -> !strix.services.atticd.enable;
          # (ws2b borg deleted 2026-08-21 — Tom ruled it redundant against
          # the physical-redundancy stack; its asserts died with it.)
          pkgs.runCommand "nas-topology" { } ''
            touch "$out"
          '';

        home-profiles =
          let
            strixHome = self.nixosConfigurations.strix-coordinator.config.home-manager.users.tom;

            clientHome = self.nixosConfigurations.client.config.home-manager.users.tom;
            cfgOf = h: self.nixosConfigurations.${h}.config;
            # Every host whose seat this block adjudicates — named, not
            # discovered, so a fifth host added tomorrow (a seat by default,
            # modules/display.nix) is either listed here on purpose or its
            # absence is visible at eval. The list is the roll call, not a
            # claim that all four have displays: what is asserted per host is
            # the EQUALITY greetd == Sway == myDisplay, plus the three
            # topology facts below that never flip.
            displayHosts = [
              "strix-coordinator"
              "strix-worker"
              "client"

              "nas"
            ];
          in
          assert strixHome.home.username == "tom";
          assert strixHome.programs.atuin.settings.auto_sync;
          # Tally is gone (sunset 2026-09-30): no module, no option, no unit.
          assert !(strixHome.services ? tally);
          assert
            !(builtins.any (n: nixpkgs.lib.hasPrefix "tally" n) (
              builtins.attrNames strixHome.systemd.user.services
              ++ builtins.attrNames strixHome.systemd.user.timers
            ));
          # speech-wake and Parakeet are gone (2026-09-30): no transcription
          # unit, no virtual mic, no Voxtype on any seat.
          assert !(strixHome.systemd.user.services ? parakeet-service);
          assert !(strixHome.systemd.user.services ? speech-wake);
          assert !(strixHome.systemd.user.services ? voxtype);
          assert !(strixHome.xdg.configFile ? "pipewire/pipewire.conf.d/60-client-mic.conf");
          # Production compute has no Herdr server; its protection is tested on
          # the brain role fixture in herdr-oom-isolation.
          assert !(strixHome.systemd.user.services ? herdr);
          # The seats oracle's peer cache and substrate's metersDir outlive the
          # seat feeder that used to write it (home/harness-records.nix).
          assert
            !(builtins.elem "d %h/.local/state/tally-rewrite/meters 0700 - - -" strixHome.systemd.user.tmpfiles.rules);
          # herdr WITHOUT the kitten (#385, 2026-09-13). herdr-kitten is gone
          # fleet-wide: no package, no generated kitty alias file.
          assert !(builtins.any (p: nixpkgs.lib.getName p == "herdr-kitten") strixHome.home.packages);
          assert !(strixHome.xdg.configFile ? "kitty-herdr-nix.conf");
          assert builtins.any (p: nixpkgs.lib.getName p == "herdr") strixHome.home.packages;
          # The client's herdr chords live in Sway's RAW, hot-reloaded binds.conf,
          # which no generation renders, so they are asserted here by content
          # (precedent: the readFile assert on dot_claude/settings.json below).
          # Each one goes through herdr-chord into ONE projector window.
          # Whole lines, so a commented-out or re-targeted bind fails here.
          # (Mod+Shift+N moves a window on Sway, #538, so rename is not here.)
          assert
            let
              swayBinds = nixpkgs.lib.splitString "\n" (builtins.readFile ./home/dot_config/sway/binds.conf);
            in
            builtins.all (l: builtins.elem l swayBinds) [
              "bindsym $mod+Ctrl+space exec env HERDR_PROJECTOR_TARGET=nas HERDR_PICKER_HOSTNAME=nas HERDR_SWAY_LOCAL=0 ~/.local/bin/herdr-picker"
              "bindsym $mod+Return exec env HERDR_PROJECTOR_TARGET=nas HERDR_PICKER_HOSTNAME=nas HERDR_SWAY_LOCAL=0 ~/.local/bin/herdr-chord new"
              "bindsym $mod+Ctrl+Shift+Return exec env HERDR_PROJECTOR_TARGET=nas HERDR_PICKER_HOSTNAME=nas HERDR_SWAY_LOCAL=0 ~/.local/bin/herdr-chord sidebar"
              "bindsym $mod+Shift+Return exec kitty -e fish"
              # AGENTS.md seat rule: Alt+H/L left/right monitor, Alt+J/K down/up.
              "bindsym Alt+h focus output left"
              "bindsym Alt+l focus output right"
              "bindsym Alt+j focus output down"
              "bindsym Alt+k focus output up"
            ];
          # kitty.conf may not map anything to the removed `hk` action: kitty
          # turns an unknown action into a bad-config overlay on every start,
          # and a `map ctrl+b …` would eat herdr's prefix before herdr sees it.
          assert
            !(builtins.any (
              l:
              nixpkgs.lib.hasPrefix "map " l
              && (nixpkgs.lib.hasInfix " hk " l || nixpkgs.lib.hasPrefix "map ctrl+b " l)
            ) (nixpkgs.lib.splitString "\n" (builtins.readFile ./home/dot_config/kitty/kitty.conf)));
          # Without `--remote-keybindings server` a projector strips the tally
          # [[keys.command]] popups (herdr src/client/shell/config.rs:158-162).
          assert nixpkgs.lib.hasInfix "--remote-keybindings server" (
            builtins.readFile ./home/dot_local/bin/herdr-projector
          );
          # The worker keeps Home Manager (unlike the NAS, which stops at NixOS):
          # it is an ordinary interactive box that merely has nobody sitting at
          # it, so the shell, atuin sync and the user timers are all real. What
          # it must NOT pick up are the things gated on being the strix —
          # the Tally daemon, voxtype, and since 2026-09-11 the graphical
          # session itself (no display output on that box: Tom's ruling).

          # …and the herdr SERVER. The worker still gets the herdr binary (it is
          # how `herdr --remote strix` works at all), just no unit.

          # The BINARY, though, is the worker's too — the client is how you
          # reach a server at all (`herdr --remote strix`). One server
          # (ruling B5, #309 settled), clients elsewhere, unchanged.

          # The shared browser desktop and chrome-stream left strix-coordinator
          # on 2026-10-31 (#651): no host declares the browser-desktop user
          # service, and Google Chrome lives on the seat (client) only.
          assert builtins.all (h: !((cfgOf h).systemd.user.services ? browser-desktop)) displayHosts;
          assert builtins.all
            (
              h:
              let
                names = p: p.pname or p.name or "";
                isChrome = p: nixpkgs.lib.hasPrefix "google-chrome" (names p);
                homePkgs = (cfgOf h).home-manager.users.tom.home.packages;
              in
              !(builtins.any isChrome (cfgOf h).environment.systemPackages) && !(builtins.any isChrome homePkgs)
            )
            [
              "strix-coordinator"
              "strix-worker"
            ];

          assert !(strixHome.systemd.user.services ? wayvnc);
          # The seat EQUALITIES: greetd == Sway == myDisplay, greetd starts the
          # Sway session launcher, and niri (retired 2026-10-13) is on nowhere.
          assert builtins.all (
            h:
            let
              c = cfgOf h;
              d = c.myDisplay;
            in
            c.services.greetd.enable == d.enable
            && c.programs.swayPhysical.enable == d.enable
            && !c.programs.niri.enable
            && (
              !d.enable
              || nixpkgs.lib.hasSuffix "/bin/sway-physical-session" c.services.greetd.settings.initial_session.command
            )
          ) displayHosts;
          # The client is the Sway seat; the Herdr server remains independent.
          assert (cfgOf "client").myDisplay.enable;
          assert (cfgOf "client").programs.sway.enable;
          assert clientHome.programs.vicinae.enable;
          assert clientHome.services.mako.enable;
          assert clientHome.systemd.user.services.mako.Service.Type == "dbus";
          assert clientHome.systemd.user.services.mako.Service.BusName == "org.freedesktop.Notifications";
          assert
            clientHome.systemd.user.services.mako.Service.ExecStart
            == [ "${clientHome.services.mako.package}/bin/mako" ];
          assert !clientHome.programs.waybar.enable;
          assert !strixHome.programs.vicinae.enable;
          assert !strixHome.services.mako.enable;
          assert !strixHome.programs.waybar.enable;
          assert strixHome.home.sessionVariables.HERDR_SWAY_LOCAL == "0";
          assert clientHome.home.sessionVariables.HERDR_SWAY_LOCAL == "0";
          assert !(strixHome.systemd.user.services ? herdr);
          assert (cfgOf "client").systemd.user.services.sway-physical.restartIfChanged == false;
          assert clientHome.programs.vicinae.settings.font.normal.family == "Anthropic Sans";
          assert clientHome.services.mako.settings.font == "Anthropic Sans 11";
          assert clientHome.xdg.configFile ? "sway-local.conf";
          # MacTahoe on every session (non-negotiable): Home Manager's gtk
          # block keeps MacTahoe for GTK3 and its icons, and GTK4's gtk.css,
          # gtk-dark.css and assets point through ~/.config/theme at the
          # selected theme's MacTahoe gtk-4.0 dir. No generated libadwaita
          # colour sheet stands in for it.
          assert builtins.all
            (
              hm:
              hm.gtk.enable
              && nixpkgs.lib.hasPrefix "MacTahoe-" hm.gtk.theme.name
              && nixpkgs.lib.hasPrefix "MacTahoe" hm.gtk.iconTheme.name
              && builtins.all (f: hm.xdg.configFile ? "gtk-4.0/${f}") [
                "gtk.css"
                "gtk-dark.css"
                "assets"
              ]
              && hm.xdg.configFile ? "themes/noir/gtk-4.0"
              && nixpkgs.lib.hasInfix "MacTahoe" (toString hm.xdg.configFile."themes/noir/gtk-4.0".source)
              && !(hm.xdg.configFile ? "themes/noir/gtk4.css")
            )
            [
              clientHome
            ];
          # pkgs.sway stays stock for the seats and the headless browser desktop.
          assert pkgs.sway-unwrapped.src.repo or "sway" == "sway";
          assert nixpkgs.lib.getName pkgs.sway == "sway";
          assert (cfgOf "client").myDisplay.enable;
          assert !(cfgOf "strix-coordinator").myDisplay.enable;
          # No Claude Desktop or ChatGPT apps and no Chrome --app launcher
          # entries on any host (Tom, 2026-10-12).
          assert builtins.all
            (
              h:
              let
                hm = self.nixosConfigurations.${h}.config.home-manager.users.tom;
              in
              !(builtins.elem pkgs.llm-agents.claude-desktop hm.home.packages)
              && !(builtins.elem pkgs.llm-agents.chatgpt hm.home.packages)
              && !(builtins.any (n: hm.xdg.desktopEntries ? ${n}) [
                "chatgpt"
                "claude"
                "gcloud"
                "github"
                "open-webui"
                "perplexity"
                "photos"
                "railway"
                "soundcloud"
                "whatsapp"
                "youtube-music"
              ])
            )
            [
              "client"
              "strix-coordinator"
            ];
          # No Brave, cmux or Claude Desktop on client, strix-coordinator or
          # the NAS, whichever way they arrive (Tom, 2026-10-31). Name-based,
          # so a renamed attribute or a wrapper still trips it.
          assert builtins.all
            (
              h:
              let
                cfg = self.nixosConfigurations.${h}.config;
                names = map nixpkgs.lib.getName (
                  builtins.filter nixpkgs.lib.isDerivation (
                    cfg.home-manager.users.tom.home.packages ++ cfg.environment.systemPackages
                  )
                );
              in
              !(builtins.any (
                n:
                builtins.any (p: nixpkgs.lib.hasPrefix p n) [
                  "brave"
                  "claude-desktop"
                  "cmux"
                ]
              ) names)
            )
            [
              "client"
              "strix-coordinator"
              "nas"
            ];

          assert !(cfgOf "nas").myDisplay.enable;
          # The thin client (2026-09-11): Tom's seat, so Sway and greetd are
          # ON and the whole strix-gated tier is OFF — no tally, no
          # voxtype, no herdr SERVER (the binary is here: Mod+Return is
          # herdr-chord into a local `herdr --remote strix` projector,
          # #385 — asserted above on the RAW sway/binds.conf, and below as the
          # generated sway-local.conf overriding none of those chords), no
          # wayvnc SERVER (while the strix
          # had a display the client VIEWED it through a `strix (VNC)`
          # Remmina profile — asserted below as an equality, absent since the
          # 2026-09-11 flip — and no
          # `client (VNC)` profile ever exists on the strix, in either
          # direction of the flip), no :5900 door, no
          # seat-feeder clocks. Touch is mapped to eDP-1 in sway-local.conf.
          assert clientHome.home.username == "tom";
          # The client's home stays clean by construction (2026-10-11): every
          # file Home Manager places there is hidden, no XDG user dir but
          # Downloads is visible or created, and no activation names
          # ~/mecattaf (the checkout and the journal lane are gone there).
          assert builtins.all (f: nixpkgs.lib.hasPrefix "." f.target) (
            builtins.attrValues clientHome.home.file
          );
          assert clientHome.xdg.userDirs.enable;
          assert !clientHome.xdg.userDirs.createDirectories;
          assert clientHome.xdg.userDirs.package == null;
          assert clientHome.xdg.userDirs.download == "/home/tom/Downloads";
          assert builtins.all (nixpkgs.lib.hasPrefix "/home/tom/.local/share/user-dirs/") (
            with clientHome.xdg.userDirs;
            [
              desktop
              documents
              music
              pictures
              projects
              publicShare
              templates
              videos
            ]
          );
          assert
            !(builtins.any (a: nixpkgs.lib.hasInfix "/home/tom/mecattaf" a.data) (
              builtins.attrValues clientHome.home.activation
            ));
          assert !(clientHome.services ? tally);
          # No transcription model, wake listener or Voxtype on the client
          # (speech-wake and Parakeet removed 2026-09-30).
          assert
            !(builtins.any (
              p: nixpkgs.lib.hasPrefix "voxtype" (nixpkgs.lib.getName p)
            ) clientHome.home.packages);
          assert !(clientHome.xdg.configFile ? "voxtype/config.toml");
          assert !(clientHome.systemd.user.services ? voxtype);
          assert !(clientHome.systemd.user.services ? parakeet-service);
          assert !(clientHome.systemd.user.services ? speech-wake);
          assert !(builtins.any (p: nixpkgs.lib.getName p == "dictate-hold") clientHome.home.packages);
          assert
            !(nixpkgs.lib.hasInfix "HERDR_DICTATION_COMMAND" (
              builtins.readFile ./home/dot_local/bin/herdr-projector
            ));
          assert !(clientHome.systemd.user.services ? herdr);
          assert builtins.any (p: nixpkgs.lib.getName p == "herdr") clientHome.home.packages;
          assert !(builtins.any (p: nixpkgs.lib.getName p == "herdr-kitten") clientHome.home.packages);
          assert !(clientHome.systemd.user.services ? wayvnc);
          assert !(clientHome.xdg.configFile ? "wayvnc/config");
          # Physical-session VNC stays retired on both seats.
          assert !(clientHome.xdg.dataFile ? "remmina/strix.remmina");
          assert !(strixHome.xdg.dataFile ? "remmina/client.remmina");
          assert
            !builtins.elem 5900 (
              self.nixosConfigurations.client.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts
                or [ ]
            );
          # The client's generated slot: touch mapped, the lid handled by
          # bindswitch (hosts/client/lid.nix relies on the compositor for the
          # panel), and no override of the herdr chords.
          assert nixpkgs.lib.hasInfix "input type:touch map_to_output eDP-1"
            clientHome.xdg.configFile."sway-local.conf".text;
          assert nixpkgs.lib.hasInfix "bindswitch --reload --locked lid:on output eDP-1 disable"
            clientHome.xdg.configFile."sway-local.conf".text;
          assert !(nixpkgs.lib.hasInfix "$mod+Return " clientHome.xdg.configFile."sway-local.conf".text);
          assert !(nixpkgs.lib.hasInfix "$mod+Shift+n " clientHome.xdg.configFile."sway-local.conf".text);
          assert !(strixHome.xdg.configFile ? "sway-local.conf");

          assert
            !builtins.elem 5900 (
              self.nixosConfigurations.strix-coordinator.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts
                or [ ]
            );

          pkgs.runCommand "home-profiles" { } ''
            touch "$out"
          '';

        # A pane child selected by the kernel OOM killer must not turn into a
        # systemd stop of the Herdr server and every unrelated pane (#352).
        # The policy is ours and remains required across upstream Herdr
        # versions.
        herdr-oom-isolation =
          let
            strixHome = agentProbe.home-manager.users.tom;

            service = strixHome.systemd.user.services.herdr;
          in
          assert service.Service.OOMPolicy == "continue";
          # #354: a switch (update-adopt's or Tom's) never restarts Herdr.
          # sd-switch 0.6.4 reads X-SwitchMethod=keep-old (home/herdr.nix);
          # the rendered unit text is checked too, so a renamed option cannot
          # silently drop the line.
          assert service.Unit.X-SwitchMethod == "keep-old";

          pkgs.runCommand "herdr-oom-isolation" { } ''
            unit=${strixHome.xdg.configFile."systemd/user/herdr.service".source}
            grep -qx 'X-SwitchMethod=keep-old' "$unit"
            grep -qx 'OOMPolicy=continue' "$unit"
            touch "$out"
          '';

        # #354 producer half and the 2026-09-13 seed preflight: per-host signed
        # candidate publication only after a successful push, a failed host
        # keeping its previous pointer byte-identical, release pruning,
        # --publish-only refusals, and seed-missing naming a private input.
        update-center =
          let
            nas = self.nixosConfigurations.nas.config;
          in
          assert nas.myNas.updateCenter.enable;
          assert nas.myNas.updateCenter.candidates.port == 8734;
          assert nas.services.nginx.virtualHosts ? fleet-candidates;
          pkgs.runCommand "update-center"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.openssh
                pkgs.jq
                pkgs.findutils
              ];
            }
            ''
              mkdir -p hosts/nas tests/update-center
              cp ${./hosts/nas/update-center.sh} hosts/nas/update-center.sh
              cp ${./tests/update-center/test_update_center.py} tests/update-center/test_update_center.py
              python -m unittest discover -v -s tests/update-center
              touch "$out"
            '';

        # Exercise the request-scoped utility seam without qmd or live models.
        utility-model = pkgs.runCommand "utility-model" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          set -euo pipefail
          export PYTHONDONTWRITEBYTECODE=1
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
          export AI_MEMORY_UTILITY_OWNER=${./pkgs/utility-model/utility_model.py}
          python3 -m unittest discover -s ${./tests/ai-memory} -p 'test_utility_model.py' -v
          touch "$out"
        '';

        ai-memory =
          let
            homeConfig = agentProbe.home-manager.users.tom;
            clientHome = self.nixosConfigurations.client.config.home-manager.users.tom;
            expectedJournal = "/home/tom/mecattaf/notes/journal";
          in
          assert homeConfig.programs.ai-memory.journalDir == expectedJournal;
          assert homeConfig.home.activation ? aiMemoryJournal;
          # Strix only: on the client it recreated ~/mecattaf/notes/journal.
          assert !(clientHome.home.activation ? aiMemoryJournal);
          assert !(clientHome.xdg.configFile ? "ai-memory/config.json");
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
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
              export AI_MEMORY_ENGINE=${./home/dot_claude/skills/drain/scripts/ai_memory.py}
              export AI_MEMORY_ENQUEUE_CHECK=${./tools/enqueue-row-check.py}
              export AI_MEMORY_DRAIN_SKILL=${./home/dot_claude/skills/drain/SKILL.md}
              export AI_MEMORY_HANDOFF_SKILL=${./home/dot_claude/skills/handoff/SKILL.md}
              export AI_MEMORY_PICKUP_SKILL=${./home/dot_claude/skills/pickup/SKILL.md}
              export AI_MEMORY_UTILITY_OWNER=${./pkgs/utility-model/utility_model.py}
              mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR"

              python3 -m unittest discover \
                -s ${./tests/ai-memory} \
                -p 'test_*.py' \
                -v

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

        # NO Claude Code hook is declared, and none is delivered. The MEM-2
        # SessionEnd harvest hook (dotfiles#339) was removed 2026-09-23: the
        # session process WAITS for a SessionEnd hook, and the runs that
        # actually harvested took up to 57 s, so Claude Code aborted the hook
        # and reported "SessionEnd hook [...] failed: Hook cancelled" on every
        # close. Of its last 101 logged runs 54 were skips. The harvest verb is
        # untouched and still reachable on demand through the `drain` skill.
        #
        # This check is the GUARD on that removal, and it is deliberately
        # broader than the block it replaces: it fails if ANY hook comes back
        # into settings.json, not just a SessionEnd one. The original reason
        # still holds — the dead SessionStart hook removed 2026-09-13 named
        # ~/.claude/hooks/herdr-agent-state.sh, a file that existed in no
        # repository and on no disk, so it failed on every session start. A
        # hook naming a script the repository does not ship must not come back.
        # Re-adding a hook here is a deliberate edit to this check.
        #
        # EVALUATION-time on purpose, like the block it replaces:
        # `nix flake check --offline --no-build` evaluates and does not build.
        no-claude-code-hooks =
          let
            homeConfig = self.nixosConfigurations.strix-coordinator.config.home-manager.users.tom;
            settings = builtins.fromJSON (builtins.readFile ./home/dot_claude/settings.json);
          in
          assert !(settings ? hooks);
          # Nothing is delivered into ~/.claude/hooks, and the directory itself
          # is still not a whole-dir link, so it stays real and writable.
          assert !(homeConfig.home.file ? ".claude/hooks/ai-memory-harvest.sh");
          assert !(homeConfig.home.file ? ".claude/hooks");
          pkgs.runCommand "no-claude-code-hooks" { } ''
            set -euo pipefail
            touch "$out"
          '';

        utility-storage =
          let
            owner = self.nixosConfigurations.nas.config.home-manager.users.tom;
            compute = self.nixosConfigurations.strix-coordinator.config;
          in
          assert owner.systemd.user.paths ? speech-queue;
          assert owner.systemd.user.services ? speech-queue;
          assert owner.systemd.user.timers.speech-queue.Timer.OnCalendar == "*-*-* 06:05:00";
          assert !(compute.systemd.user.services ? speech-queue);
          assert !(compute.systemd.user.paths ? speech-queue);
          assert !(compute.systemd.user.timers ? speech-queue);
          assert !(compute.home-manager.users.tom.systemd.user.services ? speech-queue);
          pkgs.runCommand "utility-storage" {
            nativeBuildInputs = [ pkgs.python3 pkgs.systemd ];
          } ''
            export PYTHONDONTWRITEBYTECODE=1
            export PYTHONPATH=${./lib/python}
            export CALL_DIARIZE_REMOTE_SCRIPT=${./home/dot_local/bin/call-diarize-remote}
            export SPEECH_QUEUE_SCRIPT=${./pkgs/speech-session/queue.py}
            python3 -m unittest discover -s ${./tests/utility-storage} -v
            python3 -m unittest discover -s ${./tests/speech-session} -v
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
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
              export PRINT_AUTO_SCRIPT=${./home/dot_claude/skills/print/scripts/print-auto.py}
              export PRINT_PAPER_SCRIPT=${./home/dot_claude/skills/print/scripts/print-paper.py}
              export PRINT_PAPER_SKILL=${./home/dot_claude/skills/print/SKILL.md}
              export PRINT_SCRIPTS_README=${./home/dot_claude/skills/print/scripts/README.md}
              # paper-daemon (#384) against stub lp/lpstat/ipptool/sudo: no paper.
              export PYTHONPATH=${./lib/python}
              export PAPER_DAEMON_SCRIPT=${./pkgs/paper-daemon/paper-daemon.py}
              export PAPER_JOBS_TEST_FILE=${./pkgs/paper-daemon/get-jobs.test}
              export PAPER_PRINTER_TEST_FILE=${./pkgs/paper-daemon/printer-state.test}
              export PAPER_RENDER_BRIDGE=${./pkgs/paper-daemon/render-remote.py}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/print} \
                -p 'test_*.py' \
                -v

              touch "$out"
            '';

        print-render = pkgs.runCommand "print-render" {
          nativeBuildInputs = [ pkgs.python3 pkgs.python3Packages.weasyprint pkgs.fontconfig pkgs.poppler-utils ];
          FONTCONFIG_FILE = pkgs.paper-render.fonts;
          PRINT_PAPER_SCRIPT = ./home/dot_claude/skills/print/scripts/print-paper.py;
        } ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          python3 ${./tests/print/render_integration.py} -v
          touch "$out"
        '';

        # nightly-record (dotfiles#298): five lanes, five rows, every night,
        # from the harness transcripts and nothing else. Same shape as
        # print-paper — the real program, driven against fixtures.
        nightly-record =
          pkgs.runCommand "nightly-record"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              export PYTHONDONTWRITEBYTECODE=1
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
              export NIGHTLY_RECORD_SCRIPT=${./home/dot_local/bin/nightly-record}
              export NIGHTLY_RECORD_FIXTURES=${./tests/nightly-record/fixtures}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/nightly-record} \
                -p 'test_*.py' \
                -v

              touch "$out"
            '';

        # #313 — raw-dotfiles-guard, the real binary against fixture checkouts:
        # one missing nightly-record must fail naming it, a complete one must
        # pass, and no checkout at all only warns. The eval half pins what
        # each host's guard checks and that it runs before writeBoundary.
        # These lists are pinned ON PURPOSE: adding a user unit that runs
        # %h/.local/bin/<program> means adding <program> here deliberately,
        # knowing a switch now needs it in ~/mecattaf/dotfiles first. Update
        # the list; do not delete the assert.
        raw-dotfiles-guard =
          let
            lib = nixpkgs.lib;
            guard = pkgs.callPackage ./pkgs/raw-dotfiles-guard.nix { };
            homeOf = h: self.nixosConfigurations.${h}.config.home-manager.users.tom;
            entry = (homeOf "nas").home.activation.rawDotfilesGuard;
          in
          assert (homeOf "strix-coordinator").rawDotfiles.programs == [ ];

          assert (homeOf "client").rawDotfiles.programs == [ ];
          # The client and strix-coordinator carry no checkout: their raw
          # dotfiles come from the store, so they have no guard to run, no
          # bootstrap clone and not one home file linked into ~/mecattaf. The
          # NAS keeps the out-of-store links and the guard.
          assert (homeOf "client").rawDotfiles.inStore;
          assert !((homeOf "client").home.activation ? rawDotfilesGuard);
          assert !(self.nixosConfigurations.client.config.systemd.services ? dotfiles-bootstrap);
          assert
            !(builtins.any (
              f: builtins.isAttrs f.source && lib.hasInfix "/mecattaf/" (f.source.buildCommand or "")
            ) (builtins.attrValues (homeOf "client").home.file));
          assert (homeOf "strix-coordinator").rawDotfiles.inStore;
          assert !((homeOf "strix-coordinator").home.activation ? rawDotfilesGuard);
          assert !(self.nixosConfigurations.strix-coordinator.config.systemd.services ? dotfiles-bootstrap);
          assert
            !(builtins.any (
              f: builtins.isAttrs f.source && lib.hasInfix "/mecattaf/" (f.source.buildCommand or "")
            ) (builtins.attrValues (homeOf "strix-coordinator").home.file));
          assert !(homeOf "nas").rawDotfiles.inStore;
          assert
            entry.before == [
              "checkLinkTargets"
              "writeBoundary"
            ];
          assert lib.hasInfix "/bin/raw-dotfiles-guard" entry.data;
          pkgs.runCommand "raw-dotfiles-guard" { } ''
            # stdenv runs with errexit; the stale fixture must be allowed to fail.
            set +e -u
            progs="claude-transcript-mirror nightly-record tally-seat-feeder util-row util-sampler"
            mk() {
              mkdir -p "$1/.git" "$1/home/dot_local/bin"
              for p in $progs; do
                printf '#!/bin/sh\n' > "$1/home/dot_local/bin/$p"
                chmod +x "$1/home/dot_local/bin/$p"
              done
            }

            mk "$TMPDIR/complete"
            res=$(${lib.getExe guard} "$TMPDIR/complete" $progs 2>&1)
            rc=$?
            echo "$res"
            [ "$rc" -eq 0 ] || { echo "complete fixture: rc=$rc" >&2; exit 1; }
            case "$res" in *"ok (5 programs)"*) ;; *) echo "complete fixture: no ok line" >&2; exit 1 ;; esac

            mk "$TMPDIR/stale"
            rm "$TMPDIR/stale/home/dot_local/bin/nightly-record"
            res=$(${lib.getExe guard} "$TMPDIR/stale" $progs 2>&1)
            rc=$?
            echo "$res"
            [ "$rc" -ne 0 ] || { echo "stale fixture: guard passed" >&2; exit 1; }
            case "$res" in *"bin/nightly-record does not exist"*) ;; *) echo "stale fixture: nightly-record not named" >&2; exit 1 ;; esac
            case "$res" in *"bin/util-row does not exist"*) echo "stale fixture: named a present program" >&2; exit 1 ;; esac

            res=$(${lib.getExe guard} "$TMPDIR/absent" $progs 2>&1)
            rc=$?
            echo "$res"
            [ "$rc" -eq 0 ] || { echo "absent checkout: rc=$rc" >&2; exit 1; }
            case "$res" in *warning*) ;; *) echo "absent checkout: no warning" >&2; exit 1 ;; esac

            touch "$out"
          '';

        # Post-mortem transcript discovery must cover all three isolated
        # CLAUDE_CONFIG_DIR roots; ~/.claude alone is a partial answer (#352).
        claude-sessions =
          pkgs.runCommand "claude-sessions"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              export PYTHONDONTWRITEBYTECODE=1
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
              export CLAUDE_SESSIONS_SCRIPT=${./home/dot_local/bin/claude-sessions}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/claude-sessions} \
                -p 'test_*.py' \
                -v

              touch "$out"
            '';

        # update-check (#550): the nightly update check's contract, hermetically.
        # A fake nix and gh stand in for upstream and GitHub around a real git
        # origin: one PR per moved input, a draft on a failed gate, nothing on a
        # quiet night, review commits carried across a rebuilt bump, the PR
        # closed when main catches up; and lib/update-watch.json is read
        # against this flake.lock, so a watched input that stops being bumpable
        # turns the check red.
        downloads-mirror =
          let
            fixtureSsh = pkgs.writeShellScriptBin "ssh" ''
              exec ${pkgs.python3}/bin/python3 "$DOWNLOADS_MIRROR_FIXTURE_SSH" "$@"
            '';
            fixtureMirror = pkgs.downloads-mirror.override { openssh = fixtureSsh; };
          in
          pkgs.runCommand "downloads-mirror"
            { nativeBuildInputs = [ pkgs.python3 pkgs.rsync ]; }
            ''
              export PYTHONDONTWRITEBYTECODE=1
              export DOWNLOADS_MIRROR_SCRIPT=${./pkgs/downloads-mirror/downloads-mirror.py}
              export DOWNLOADS_MIRROR_BINARY=${pkgs.lib.getExe pkgs.downloads-mirror}
              export DOWNLOADS_MIRROR_FIXTURE_BINARY=${pkgs.lib.getExe fixtureMirror}
              export DOWNLOADS_SYSTEMD_ANALYZE=${pkgs.systemd}/bin/systemd-analyze
              export DOWNLOADS_SYSTEMD_USER_UNITS=${pkgs.systemd}/example/systemd/user
              export DOWNLOADS_MIRROR_PATH_UNIT=${self.nixosConfigurations.client.config.home-manager.users.tom.xdg.configFile."systemd/user/downloads-mirror-watch.path".source}
              export DOWNLOADS_MIRROR_SERVICE_UNIT=${self.nixosConfigurations.client.config.home-manager.users.tom.xdg.configFile."systemd/user/downloads-mirror-notify.service".source}
              python3 -m unittest discover -s ${./tests/downloads-mirror} -p 'test_*.py' -v
              touch "$out"
            '';

        update-check =
          pkgs.runCommand "update-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.git
              ];
              PYTHONTZPATH = "${pkgs.tzdata}/share/zoneinfo";
            }
            ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              export PYTHONDONTWRITEBYTECODE=1
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
              export UPDATE_CHECK_SCRIPT=${./home/dot_local/bin/update-check}
              export UPDATE_WATCH=${./lib/update-watch.json}
              export UPDATE_FLAKE_LOCK=${./flake.lock}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/update-check} \
                -p 'test_*.py' \
                -v

              touch "$out"
            '';

        # fleet-status (#356): the snapshot's contract, hermetically. The suite
        # drives the fan-out through a fake ssh playing four nodes (healthy,
        # 30 s slow, ssh exit 255, garbage) and asserts bounded wall time,
        # partial results, and that an absent node is UNREACHABLE/unknown and
        # never zero; it runs the collector with no systemd on PATH, which must
        # grade unknown, and with the appliance profile, which must grade
        # missing-by-design. The eval asserts pin the per-host profiles every
        # collector reads and the strix-only host list.
        fleet-status =
          let
            etc = host: self.nixosConfigurations.${host}.config.environment.etc;
            profile = host: builtins.fromJSON (etc host)."fleet-status/profile.json".text;
            hostsJson = builtins.fromJSON agentProbe.environment.etc."fleet-status/hosts.json".text;
          in
          assert (profile "strix-coordinator").name == "strix-compute";
          assert
            (profile "strix-coordinator").roles == [
              "gufo"
            ];

          assert (profile "nas").name == "appliance";
          assert (profile "nas").user_manager;
          assert (profile "nas").roles == [ "attention" ];
          assert (profile "client").name == "thin-client";
          assert (profile "client").user_manager;

          # Root over ssh for every node, the strix too: update-adopt's
          # state is root-only, so a local run as tom could never read it.
          assert builtins.all (h: h.transport == "ssh") hostsJson;
          pkgs.runCommand "fleet-status" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            set -euo pipefail
            export HOME="$TMPDIR/home"
            export PYTHONDONTWRITEBYTECODE=1
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
            export FLEET_STATUS_PY=${pkgs.fleet-status}/share/fleet-status/fleet_status.py
            mkdir -p "$HOME"
            python3 -m unittest discover -s ${./tests/fleet-status} -p 'test_*.py' -v
            touch "$out"
          '';

        # land (CNA-M07): the landing tool that carries a working lane into the
        # notes repository. The suite builds its own fixture lane in $TMPDIR --
        # nested .git, symlink, 3-byte file, excluded glob, sparse file over the
        # 95 MiB ceiling -- and drives copy/verify/diff over it. rsync is in the
        # build inputs so the diff cross-check is exercised here and not only on
        # a host that happens to have it; the sparse file costs no store space.
        # What is pinned: a packet's row count equals `find -type f`, a flipped
        # byte or a stray file FAILS verify, the sources are byte-identical
        # afterwards, and the secret guard aborts before writing anything while
        # printing the file's name and never the matched value.
        land =
          pkgs.runCommand "land"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.rsync
              ];
            }
            ''
              set -euo pipefail
              export HOME="$TMPDIR/home"
              export PYTHONDONTWRITEBYTECODE=1
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
              export LAND_PY=${pkgs.land}/share/land/land.py
              mkdir -p "$HOME"
              python3 -m unittest discover -s ${./tests/land} -p 'test_*.py' -v
              touch "$out"
            '';

        # dsh-config (T-31): the wrapped dsh boots every allowed profile with
        # the fleet policy as the last layer, and refuses what it must. Runs
        # against the NAS package in the build sandbox: no network, private
        # HOME and DSH_HOME under $TMPDIR, no key path in the wrapper. Each dump
        # must leave stderr empty (a patch that matches no row warns there)
        # and carry the policy rows; tests/dsh-config/check_dump.py reads its
        # expectations from pkgs.dsh's passthru. lib/update-watch.json builds
        # this on every llm-agents bump.
        dsh-config =
          let
            dshPackage = self.nixosConfigurations.nas.pkgs.dsh.override { qwenKeyFile = null; };
            expect = pkgs.writeText "dsh-config-expect.json" (
              builtins.toJSON {
                localProviders = dshPackage.localProviders;
                disabled = dshPackage.disabledIds;
                runner = "${dshPackage.runner}/bin/dsh-bwrap";
              }
            );
          in
          pkgs.runCommand "dsh-config"
            {
              nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
            }
            ''
              set -euo pipefail
              # The wrapper refuses a DSH_HOME under $TMPDIR, so the build
              # dir holds both and TMPDIR moves one level down.
              build="$TMPDIR"
              export HOME="$build/home" DSH_HOME="$build/dsh-home" TMPDIR="$build/tmp"
              export PYTHONDONTWRITEBYTECODE=1
              mkdir -p "$HOME" "$build/cwd" "$TMPDIR" "$build/homes/tom"
              mkdir -m 700 "$DSH_HOME"
              cd "$build/cwd"
              dsh=${dshPackage}/bin/dsh

              test "$($dsh --version)" = ${dshPackage.unwrapped.version}

              dump() {
                name="$1"
                shift
                "$dsh" "$@" > "$TMPDIR/$name.yml" 2> "$TMPDIR/$name.err"
                if [ -s "$TMPDIR/$name.err" ]; then
                  echo "dsh $*: stderr not empty:" >&2
                  cat "$TMPDIR/$name.err" >&2
                  exit 1
                fi
                python3 -I ${./tests/dsh-config/check_dump.py} "$TMPDIR/$name.yml" ${expect}
              }
              dump headless headless --dump-config
              dump headless-flag --profile headless --dump-config
              dump sdk sdk --dump-config
              dump acp acp --dump-config

              refused() {
                set +e
                "$@" > /dev/null 2> "$TMPDIR/refused.err"
                code=$?
                set -e
                if [ "$code" != 2 ] || ! grep -q 'refused by the fleet wrapper' "$TMPDIR/refused.err"; then
                  echo "expected a refusal (exit 2), got $code from: $*" >&2
                  cat "$TMPDIR/refused.err" >&2
                  exit 1
                fi
              }
              refused "$dsh" web --help
              refused "$dsh" --profile=web --help
              refused "$dsh" sdk-minimal --help
              refused "$dsh" headless --from-default-profile web --dump-config
              refused "$dsh" plugin --profile headless add left-pad
              # An empty profile token must not fall through to unwrapped dsh.
              refused "$dsh" --profile= headless --dump-config
              refused "$dsh" --profile "" headless --dump-config
              refused "$dsh" "" web --help
              refused "$dsh" --dump-config
              # A DSH_HOME the in-process write tool can reach (/tmp, $TMPDIR).
              refused env DSH_HOME="$TMPDIR/dsh-home" "$dsh" headless --dump-config
              refused env DSH_HOME=/tmp/dsh-home "$dsh" headless --dump-config
              refused env DSH_PERMISSION_MODE=danger-full-access "$dsh" headless --dump-config
              (cd "$HOME" && refused "$dsh" headless --dump-config)
              (cd "$DSH_HOME" && refused "$dsh" headless --dump-config)
              (cd "$build" && refused "$dsh" headless --dump-config)
              (cd / && refused "$dsh" headless --dump-config)
              # A parent of $HOME that does not hold DSH_HOME.
              (cd "$build/homes" && HOME="$build/homes/tom" refused "$dsh" headless --dump-config)

              # No DeepSeek identity minted by any of the boots above.
              test ! -e "$DSH_HOME/.anonymous-user-id"
              touch "$out"
            '';

        # dsh-plugins (T-31): the hand-run `herdr` profile. Its plugins' own
        # check phases are part of this closure: dsh-herdr's node tests (argv,
        # runtime, preview, the 23-tool registration against the real
        # dsh-tools) and the herdr-guard unit test (foreign pane_run, malformed
        # ids, writes without HERDR_ENV=1) and the stderr-log unit test. Here:
        # jevcore's $out has the pinned build and no network path, the wrapper
        # composes `herdr` with every plugin row mounted and none skipped, the
        # stock headless profile (substrate's) mounts none of them, and a boot
        # of `herdr` with a blank task (it stops before any model call) prints
        # the ready lines of herdr-guard, dsh-herdr and jevcore on stderr.
        # Same sandbox as dsh-config: no network, a private DSH_HOME, no herdr,
        # and no key by construction: the wrapper here is built without a key
        # file and the key variable is unset, whatever the sandbox exposes.
        dsh-plugins =
          let
            dshNoKey = self.nixosConfigurations.nas.pkgs.dsh.override { qwenKeyFile = null; };
            plugins = dshNoKey.plugins;
            base = {
              localProviders = dshNoKey.localProviders;
              disabled = dshNoKey.disabledIds;
              runner = "${dshNoKey.runner}/bin/dsh-bwrap";
            };
            pluginRows = [
              "stderr-log"
              "herdr-guard"
              "dsh-herdr-toolkit"
              "jev"
            ];
            expectHerdr = pkgs.writeText "dsh-plugins-herdr.json" (
              builtins.toJSON (
                base
                // {
                  rows = dshNoKey.herdrRows;
                  present = pluginRows;
                }
              )
            );
            expectHeadless = pkgs.writeText "dsh-plugins-headless.json" (
              builtins.toJSON (base // { absent = pluginRows; })
            );
            semver = "${dshNoKey.unwrapped}/lib/node_modules/@deepseek-ai/dsh/node_modules/semver";
          in
          pkgs.runCommand "dsh-plugins"
            {
              nativeBuildInputs = [
                (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
                pkgs.nodejs
              ];
            }
            ''
              set -euo pipefail
              # Built, so their check phases passed.
              : ${plugins.dsh-herdr} ${plugins.herdr-guard} ${plugins.stderr-log}

              # jevcore: the git 0.4.2 that admits this dsh, core beside it,
              # the skill, and no TypeSafe SDK or network call in the JS.
              j=${plugins.jevcore}
              node -e '
                const [pkg, semver, dsh] = process.argv.slice(1)
                const m = require(pkg)
                if (m.version !== "0.4.2" || m.dependencies.jevcore !== "0.4.2") throw new Error("not 0.4.2")
                if (!require(semver).satisfies(dsh, m.engines.dsh, { includePrerelease: true }))
                  throw new Error("engines.dsh " + m.engines.dsh + " refuses " + dsh)
              ' "$j/package.json" ${semver} ${dshNoKey.unwrapped.version}
              test -f "$j/lib/index.js"
              test -f "$j/skills/typesafe-ai-dsh/SKILL.md"
              test -f "$j/node_modules/jevcore/lib/index.js"
              test ! -e "$j/node_modules/@typesafe-ai"

              # The owned plugins' private scope: nothing in the dsh
              # installation, which resolves bundle names first, may shadow it.
              u=${dshNoKey.unwrapped}/lib/node_modules
              test ! -e "$u/@mecattaf"
              test ! -e "$u/@deepseek-ai/dsh/node_modules/@mecattaf"
              if grep -rnE 'fetch\(|node:https?' "$j/lib" "$j/node_modules/jevcore/lib"; then
                echo "jevcore: a network call in the built JS" >&2
                exit 1
              fi

              build="$TMPDIR"
              export HOME="$build/home" DSH_HOME="$build/dsh-home" TMPDIR="$build/tmp"
              export HERDR_SOCKET_PATH="$build/no-herdr.sock"
              export PYTHONDONTWRITEBYTECODE=1
              unset QWEN_TOKEN_PLAN_API_KEY
              mkdir -p "$HOME" "$build/cwd" "$TMPDIR"
              mkdir -m 700 "$DSH_HOME"
              cd "$build/cwd"
              dsh=${dshNoKey}/bin/dsh
              if grep -qF qwencloud-token "$dsh"; then
                echo "dsh-plugins: the check's wrapper reads a key file" >&2
                exit 1
              fi

              dump() {
                name="$1" expect="$2"
                shift 2
                "$dsh" "$@" > "$TMPDIR/$name.yml" 2> "$TMPDIR/$name.err"
                if [ -s "$TMPDIR/$name.err" ]; then
                  echo "dsh $*: stderr not empty:" >&2
                  cat "$TMPDIR/$name.err" >&2
                  exit 1
                fi
                python3 -I ${./tests/dsh-config/check_dump.py} "$TMPDIR/$name.yml" "$expect"
              }
              dump herdr ${expectHerdr} herdr --dump-config
              dump headless ${expectHeadless} headless --dump-config

              # The synced profile: a private manifest and store links only.
              p="$DSH_HOME/profiles/herdr"
              test "$(stat -c %a "$p/package.json")" = 600
              test "$(readlink "$p/node_modules/@mecattaf/stderr-log")" = ${plugins.stderr-log}
              test "$(readlink "$p/node_modules/@mecattaf/herdr-guard")" = ${plugins.herdr-guard}
              test "$(readlink "$p/node_modules/@dsh-external/dsh-herdr-toolkit")" = ${plugins.dsh-herdr}
              test "$(readlink "$p/node_modules/jevcore-dsh")" = ${plugins.jevcore}
              test ! -e "$DSH_HOME/profiles/headless/node_modules"
              # A store link no longer declared goes on the next boot; a
              # profile file dsh owns stays.
              ln -s ${plugins.jevcore} "$p/node_modules/dropped-plugin"
              echo '[]' > "$p/cordis.patch.yml"
              dump herdr-again ${expectHerdr} --profile herdr --dump-config
              test ! -e "$p/node_modules/dropped-plugin"
              test "$(cat "$p/cordis.patch.yml")" = '[]'
              # No per-boot staging directory is left behind.
              test -z "$(find "$p" -maxdepth 1 -name '.sync.*')"

              # The whole tree boots: an unknown --session-id fails in headless
              # after the loader settled and before any model call. The guard,
              # dsh-herdr (which loads only with the guard's service) and jevcore
              # (on the offline mock) each print a ready line through stderr-log.
              rc=0
              "$dsh" herdr --session-id session-none "reply OK" > "$TMPDIR/boot.out" 2> "$TMPDIR/boot.err" || rc=$?
              cat "$TMPDIR/boot.err" >&2
              echo "dsh herdr boot: exit $rc" >&2
              test "$rc" = 1
              grep -qF 'dsh: session "session-none" does not exist' "$TMPDIR/boot.err"
              grep -qF '[jevcore] ready · provider=mock · gates: safety=off context=off' "$TMPDIR/boot.err"
              grep -qF 'info: herdr-guard ready' "$TMPDIR/boot.err"
              grep -qF 'info: dsh-herdr ready: 23 tools' "$TMPDIR/boot.err"
              touch "$out"
            '';

        # seats: one capacity oracle across every seat on this box. Hermetic —
        # SEATS_NO_NETWORK=1 and a home tree the test builds itself, because
        # every fact the program reports is relative to now and a checked-in
        # fixture would rot on the second day.
        seats =
          pkgs.runCommand "seats"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              export PYTHONDONTWRITEBYTECODE=1
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
              export SEATS_SCRIPT=${./home/dot_local/bin/seats}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/seats} \
                -p 'test_*.py' \
                -v

              touch "$out"
            '';

        # bin/screenshot on the client (2026-10-11): hidden spool, push to
        # strix:~/Pictures/Screenshots, local delete only after a sha256 match,
        # kept while the strix is down, never an overwrite there; other hosts
        # unchanged. Hermetic: the "strix-coordinator" is a temp home behind a fake ssh.
        screenshot-spool =
          pkgs.runCommand "screenshot-spool"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.findutils
                pkgs.gnugrep
                pkgs.jq
                pkgs.rsync
                pkgs.util-linux
              ];
            }
            ''
              set -euo pipefail
              bash ${./tests/screenshot/test-spool.sh} ${./home/dot_local/bin/screenshot}
              touch "$out"
            '';

        # call-diarize-start: the detached launcher that `call-record stop`
        # calls now that Tally (the old queue) is gone (removed 2026-09-30,
        # handoff 2026-10-10). Hermetic: a fake systemd-run records its argv and
        # a fake call-diarize only satisfies the PATH check; nothing is launched.
        call-diarize-start =
          pkgs.runCommand "call-diarize-start"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.bash
                pkgs.coreutils
              ];
            }
            ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              export PYTHONDONTWRITEBYTECODE=1
              export LOCAL_MODEL_ENDPOINT=${(import ./lib/local-model.nix).endpoint}
              export CALL_DIARIZE_START_SCRIPT=${./home/dot_local/bin/call-diarize-start}
              export CALL_RECORD_SCRIPT=${./home/dot_local/bin/call-record}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/call-diarize-start} \
                -p 'test_*.py' \
                -v

              touch "$out"
            '';

        # Native controls are exercised with fake CLI/desktop commands only.
        inzone-audio = pkgs.runCommand "inzone-audio" {
          nativeBuildInputs = [
            pkgs.python3 pkgs.bash pkgs.coreutils pkgs.util-linux pkgs.gawk
          ];
        } ''
          export HOME="$TMPDIR/home"
          export PYTHONDONTWRITEBYTECODE=1
          export INZONE_MENU_SCRIPT=${./home/dot_local/bin/inzone-menu}
          export INZONE_VOLUME_SCRIPT=${./home/dot_local/bin/volume}
          mkdir -p "$HOME"
          python3 -m unittest discover -s ${./tests/inzone-audio} -p 'test_*.py' -v
          touch "$out"
        '';

        # Model bytes are explicit transactions, never activation work. Drive
        # the evaluated worker borrow binary against tiny fixtures, then keep
        # the guarded prune contract from dotfiles#296. Hermetic: no network,
        # systemd, /var, or production weights.
        local-model-transactions =
          let
            computeConfig = self.nixosConfigurations.strix-coordinator.config;
            borrowPackage =
              nixpkgs.lib.findFirst (package: nixpkgs.lib.getName package == "local-models-borrow")
                (throw "worker has no explicit local-models-borrow command")
                computeConfig.environment.systemPackages;
          in
          pkgs.runCommand "local-model-transactions"
            {
              nativeBuildInputs = [
                borrowPackage
                pkgs.local-models-prune
                pkgs.findutils
                pkgs.coreutils
              ];
            }
            ''
              set -euo pipefail
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              export LOCAL_MODELS_BORROW_BIN=${borrowPackage}/bin/local-models-borrow
              ${pkgs.bash}/bin/bash ${./tests/local-models-sync/test-borrow.sh}
              ${pkgs.bash}/bin/bash ${./tests/local-models-sync/test-prune-guard.sh}
              touch "$out"
            '';

        nixos-only =
          let
            retiredPlatformPattern = nixpkgs.lib.concatStringsSep "|" [
              ("fed" + "ora")
              ("rpm-o" + "stree")
              ("d" + "nf")
              ("c" + "opr")
              ("(^|[^[:alnum:]_])boot" + "c([^[:alnum:]_]|$)")
              ("yum.repos." + "d")
              ("harness" + "RPM")
              ("chez" + "moi")
              # Match command/library names, not identifier or hash substrings.
              ("(^|[^[:alnum:]_])(lib)?k" + "run")
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
              # Exclusions are narrow and cover non-executable material:
              #
              #   go.sum   — base64 hashes, on which a case-insensitive sweep for
              #              three-letter substrings false-positives endlessly.
              #
              #   secrets/*.age — encrypted payloads and recipient stanzas are
              #              random bytes/base64, not platform declarations.
              #
              #   docs/**/*.md — RESEARCH PROSE, not tree content that runs. Added
              #              2026-08-21 (#229) after this check turned out to have
              #              been failing at build time since cutover day. The
              #              speech-aug26 notes describe an UPSTREAM project
              #              (kyuz0/amd-strix-halo-voice-toolbox) that ships a
              #              toolbox built on the retired distro, and one flagged
              #              line is literally an instruction NOT to copy that
              #              project's IOMMU advice — doctrine being preserved,
              #              i.e. the exact opposite of residue. Banning the NAME
              #              in prose about other people's systems protects
              #              nothing and costs the ability to write down why we
              #              don't do what they do. Everything that actually runs
              #              — flake, modules, hosts, home, pkgs, overlays, flows,
              #              scripts — stays swept.
              #
              # NB the failure was invisible to `nix flake check --no-build`,
              # which evaluates a runCommand's derivation without ever running its
              # builder. Sweeps like this one only assert when BUILT.
              #
              # NB2 the glob is anchored with a leading **/ because the search
              # root is an absolute /nix/store path, against which a bare
              # `docs/...` glob never matches. And this comment deliberately does
              # not spell the retired platform's name — the sweep reads its own
              # source tree, which is why the pattern list above is assembled from
              # split string literals.
              if rg --ignore-case --line-number \
                --glob '!go.sum' --glob '!**/secrets/*.age' --glob '!**/docs/**/*.md' \
                '${retiredPlatformPattern}' ${self}; then
                echo "retired platform residue found in the canonical NixOS tree" >&2
                exit 1
              fi
              touch "$out"
            '';

        fleet-connectivity =
          let
            strix = self.nixosConfigurations.strix-coordinator.config;
            strixWorker = self.nixosConfigurations.strix-worker.config;
            nas = self.nixosConfigurations.nas.config;

            client = self.nixosConfigurations.client.config;
            meshRegistry = import ./modules/mesh-registry.nix;
            # `worker` is spelled by concatenation throughout this check for one
            # narrow reason that SURVIVES its reinstatement: the ripgrep sweep at
            # the bottom greps the flake's own source tree, and a literal here
            # would match itself. It is no longer a "retired host" — see below.
            retiredWorker = "work" + "er";
            # HALF of Tom's old ruling survives, and the halves are now split
            # (dotfiles#310, dotfiles#291). It used to read: the worker is a
            # HOST again, never a Tally executor AND never a Tally pool.
            #
            #   STILL TRUE, and asserted structurally below: never an EXECUTOR.
            #   All jobs execute locally on the strix, home/tally.nix
            #   declares `executors = { }`, and the worker runs no daemon
            #   (CONSOLIDATED §3 Q2). The GPU cooldown tripwire that used to
            #   reach across for a lease is dead and deleted.
            #
            #   SUPERSEDED by CONSOLIDATED §3 Q1 at the sheet's default
            #   (RULINGS.md R-2026-09-06-03, 2026-09-06): "capacity one per
            #   device until jobs carry a VRAM request the engine reads". There
            #   is now a per-GPU row for each of the two devices, and the second
            #   one is named after the box that holds it. It is a ROW IN THE
            #   COORDINATOR'S POOL TABLE, not an executor and not a daemon —
            #   nothing leases it yet. It exists so the first job that runs over
            #   there has a lane to name instead of borrowing the strix's
            #   and lying about which device it sat on.
            #
            # A pool row and an executor are different objects; the old guard
            # conflated them because, while the host was retired, no row could
            # be anything but the first step back toward an executor.
            # The sweep below is now TWO sweeps, because the relaxation Q1 needs
            # is narrower than the file it lands in.
            #
            #   retiredExecutionPattern — the two RETIRED EXECUTOR attribute
            #   names, still banned from home/tally.nix AND flows/. Nothing in
            #   this branch wants either back.
            #
            #   retiredFlowHostPattern — the bare host name, banned from the
            #   CODE under flows/ except in two spellings: the local inference endpoint
            #   `http://<host>:8731` and the `<host>-gpu` pool. A flow is a
            #   script that ENQUEUES work; a flow naming the other box as a
            #   place to run is the executor half that stayed retired (Q2: one
            #   daemon, on the strix). Dialling the box's inference
            #   server over HTTP, or leasing the pool row that describes its
            #   device (home/tally.nix declares it), is neither — every model
            #   call on this fleet lands on the worker now. Prose (README.md)
            #   is not checked. The pool row keeps its own structural
            #   assertion below, which is stronger than a grep over prose.
            retiredExecutionPattern = nixpkgs.lib.concatStringsSep "|" [
              (retiredWorker + "Flake")
              (retiredWorker + "Models")
            ];
            # The bare name subsumes the "<host>-gpu" pool name: a flow may name
            # neither.
            retiredFlowHostPattern = retiredWorker;
            activeHostSets = [
              (builtins.attrNames self.nixosConfigurations)
              (builtins.attrNames self.deploy.nodes)
              (builtins.attrNames meshRegistry)
            ];
            # Alphabetical, because the three sets are attrNames and the assert
            # below is list EQUALITY: `client` sorts first.
            expectedHosts = [
              "client"
              "nas"
              "strix-coordinator"
              "strix-worker"
            ];
            retiredAliases = nixpkgs.lib.concatStringsSep "|" [
              (retiredWorker + "-tb")
              ("strix-" + "tb")
            ];
            removedModel = "qwo" + "pus";
            monthlySources = import ./lib/local-ai-monthly-sources.nix;
          in

          assert nixpkgs.lib.all (hosts: hosts == expectedHosts) activeHostSets;

          # Every dialable identity addressable without TOFU — exactly one per
          # twin, the static LAN address; an alias that answers nowhere only
          # buys TOFU prompts.

          assert
            meshRegistry.strix-coordinator.aliases == [
              "strix-coordinator"
              "strix"
              "10.42.0.2"
            ];
          assert meshRegistry.client.hostKey != "";
          assert !(nixpkgs.lib.hasInfix "QoQJxxP" meshRegistry.client.hostKey);
          assert meshRegistry.client.userKey == meshRegistry.strix-coordinator.userKey;
          assert
            meshRegistry.client.aliases == [
              "client"
              "10.42.0.16"
            ];
          assert strix.networking.hosts."10.42.0.16" == [ "client" ];

          assert
            client.networking.hosts."10.42.0.2" == [
              "strix-coordinator"
              "strix"
            ];

          assert client.networking.hosts."10.42.0.1" == [ "nas" ];
          assert client.networking.hosts."127.0.0.2" == [ "client" ];
          assert client.networking.hostName == "client";
          # Thin client: no journal upload or printing queue, agenix on.
          # Tailscale enrollment is interactive, without a delivered auth key.
          assert !client.services.journald.upload.enable;
          assert client.services.tailscale.enable;
          assert !(client.age.secrets ? tailscale-authkey);
          assert !(client.systemd.services ? tailscaled-autoconnect);
          assert !client.services.printing.enable;
          assert client.mySecrets.enable;
          assert client.services.zenbook-duo-daemon.enable;
          assert self.deploy.nodes.client.hostname == "client";
          assert strix.networking.hosts."10.42.0.1" == [ "nas" ];
          assert builtins.elem "strix-coordinator" nas.networking.hosts."10.42.0.2";
          # #273: the TWINS' own names must NEVER resolve to loopback again.
          # Stock NixOS sets networking.hosts."127.0.0.2" = [ hostName ]; that
          # address resolves fine, so every gethostname()-and-bind library
          # (torch/Gloo measured: rank 0 dies in 6.3 s, rank 1 hangs to a 90 s
          # kill) binds loopback WITHOUT the warning its own fallback path would
          # have printed. modules/fleet-hosts.nix mkForce-empties it on both
          # twins and points each name at its static LAN address; an empty list
          # renders no /etc/hosts line at all (nixpkgs filters it).
          # Exact lists: a second entry for either name would be ordered by
          # systemd-resolved, not by the file.
          assert strix.networking.hosts."127.0.0.2" == [ ];

          assert
            strix.networking.hosts."10.42.0.2" == [
              "strix-coordinator"
              "strix"
            ];

          # NAS keeps its stock loopback self pin; the shared table only removes
          # it for compute ranks.
          assert nas.networking.hosts."127.0.0.2" == [ "nas" ];
          # journald substrate (#135): the NAS receives on the NVMe, and the
          # senders are the STRIX HALO BOXES ONLY (Tom's 2026-08-21 ruling) —
          # the worker joined as the second sender with #229. Each sender keeps
          # its own bounded persistent local journal, which is the half that
          # actually matters in an mt7925e hard lockup: the upload is best-effort
          # and the local ring is the forensic record.
          assert nas.services.journald.remote.enable;
          assert strix.services.journald.upload.settings.Upload.URL == "http://10.42.0.1:19532";
          assert strix.services.journald.storage == "persistent";

          # A sender the receiver does not admit is a silent hole: journald-remote
          # would simply never see it. Assert the NAS's nftables ACL names both.
          assert nixpkgs.lib.hasInfix "ip saddr 10.42.0.2 tcp dport 19532 accept"
            nas.networking.firewall.extraInputRules;

          assert self.deploy.nodes.strix-coordinator.hostname == "strix-coordinator";
          assert self.deploy.nodes.nas.hostname == "nas";
          # The worker is dialled by NAME since 2026-09-11 — it resolves to the
          # static LAN address on the strix (modules/fleet-hosts.nix),
          # which is the box's only address now. Asserted against the registry
          # so this can never drift into an address that carries no pinned
          # host key.

          # The `worker` -> 10.42.0.5 NAME pin exists on every host that dials
          # it, and every host agrees on the answer: the NAS from
          # hosts/nas/network.nix (its Immich dials http://strix-coordinator:3003), the
          # twins from modules/fleet-hosts.nix. Host-scoped rather than
          # fleet-wide on purpose — two /etc/hosts lines for one name are
          # ordered by systemd-resolved, not by the file (#277), so each host
          # carries exactly one and modules/common.nix carries none.

          assert nixpkgs.lib.elem "AddressFamily=inet" self.deploy.sshOpts;
          # The coordinator keeps its own enrolled tailscale.com identity as the
          # independent recovery box (Tom, 2026-10-25): no exit node, no
          # accepted routes, internet straight through the BE550, so it stays
          # reachable when the NAS is down. Enrollment/expiry is an explicit
          # operator step, not an agenix auth key. The worker is LAN-only.
          assert strix.services.tailscale.enable;
          assert
            strix.services.tailscale.extraUpFlags == [
              "--hostname=strix-coordinator"
              "--accept-dns=false"
              "--ssh=false"
              "--accept-routes=false"
              "--exit-node="
            ];
          assert strix.services.tailscale.extraSetFlags == strix.services.tailscale.extraUpFlags;
          # It reuses its persistent state: no enrollment key is deployed, so a
          # stale key can never silently re-join the box under a new identity.
          assert !(strix.age.secrets ? tailscale-authkey);

          # The NAS is the subnet router; see the tailnet block in nas-topology.
          assert nas.services.tailscale.enable;
          assert nixpkgs.lib.elem "--advertise-routes=10.42.0.0/24" nas.services.tailscale.extraUpFlags;
          assert !nas.programs.niri.enable;
          assert !nas.services.greetd.enable;
          assert !nas.services.pipewire.enable;
          # NAS owns the print scheduler; document rendering and inference
          # remain on the active compute host.
          assert nas.services.printing.enable;
          assert !nas.services.printing.browsed.enable;
          # Discovery remains restricted to the wired LAN.
          assert nas.services.avahi.enable;
          assert nas.services.avahi.allowInterfaces == [ "enp1s0" ];
          assert
            (nixpkgs.lib.sort builtins.lessThan nas.networking.firewall.interfaces.tailscale0.allowedTCPPorts)
            == [
              22
              53
              80
              443
              2283
              4533
              27321
              32400
            ];
          assert builtins.hasAttr "home-manager" self.nixosConfigurations.nas.options;
          assert nas.myNas.storage.enable;
          assert nas.myNas.media.enable;
          assert nas.services.immich.enable;
          assert nas.services.navidrome.enable;
          assert strix.myNasClient.useRemoteStorage;
          assert !(strix.myNasClient ? relayMedia);
          # ML is the one endpoint that is NOT a strix relay any more: the
          # socket must exist on the worker and must be GONE from the
          # strix. Asserting both directions is deliberate — a half-move
          # that left both boxes listening on :3003 would work by accident and
          # then rot.

          assert strix.systemd.sockets ? immich-ml-access;

          # Distributed builds stay OFF. The worker being back does NOT make it a
          # build farm: the fleet's build story is the NAS update-center (build
          # nightly on the appliance, pull everywhere), which is why
          # hosts/worker/cache-push.nix was dropped rather than restored.
          assert !strix.nix.distributedBuilds;
          assert strix.nix.buildMachines == [ ];

          # Doctrine, 2026-09-10: no model byte transfer may enter update,
          # activation, boot, or service ordering. Both endpoints get one
          # explicit borrow CLI; neither gets a transfer service or timer.

          assert !(strix.systemd.services ? local-models-sync);

          assert !(strix.systemd.services ? local-models-borrow);

          assert !(strix.systemd.timers ? local-models-sync);

          assert !(strix.systemd.timers ? local-models-borrow);

          assert
            builtins.length (
              nixpkgs.lib.filter (
                package: nixpkgs.lib.getName package == "local-models-borrow"
              ) strix.environment.systemPackages
            ) == 1;
          # The Gufo unit orders after nothing model-shaped either: its
          # pre-start CHECKS the bundle and refuses; it never fetches.

          # NAS downloads remain a separate timer/operator action, never an
          # update-center or activation dependency.
          assert (nas.systemd.services.library-fetch.wantedBy or [ ]) == [ ];
          # Tally is gone (sunset 2026-09-30), so there is no executor or pool
          # table left to hold a row for the worker.
          assert !(strix.home-manager.users.tom.services ? tally);
          # ...but very much present in the SSH mesh, in both directions. This
          # assertion was the inverse until #229 and was failing at HEAD, since
          # the audit had already added the registry row.

          # myCluster died with the role option; per-host policy in
          # Both compute hosts import the same Strix hardware and engine profile.
          assert !(self.nixosConfigurations.strix-coordinator.options ? myCluster);

          # ── mono-model: the wanted sets, exact ─────────────────────────────
          # Exact sets keep additional model loans explicit. Gufo's text
          # bundles and its ASR/TTS/image defaults (Tom 2026-10-25: every
          # gufo-rdma documented model on both Strix) join the production
          # diarization, TTS and voice artifacts;
          # retired engine formats are absent from both wanted set and catalog.
          # Each list is everything that host holds since the 2026-10-25
          # loans, so a default borrow restores it and prune keeps it. The
          # coordinator's disk cannot hold Flash-Next Q8 or the ds4 Q2 (D-A).
          assert
            nixpkgs.lib.sort builtins.lessThan strix.services.local-models.artifacts
            == nixpkgs.lib.sort builtins.lessThan [
              "qwen38-flash-next-gguf"
              "qwen38-27b-gguf"
              "qwen38-27b-q8-gguf"
              "qwen38-27b-dflash2-gguf"
              "qwen3-asr-1.7b"
              "qwen3-tts-12hz-1.7b-base"
              "qwen-image-2.1"
              "vibevoice-asr-streaming-7b-bf16"
              "qwen3-tts-1.7b-base-q8-0"
              "qwen-k2so-midway-b"
              "qwen3-tts-tokenizer-f32"
            ];
          assert
            nixpkgs.lib.sort builtins.lessThan strixWorker.services.local-models.artifacts
            == nixpkgs.lib.sort builtins.lessThan (
              strix.services.local-models.artifacts
              ++ [
                "deepseek-v41-flash-1017-q2-gguf"
                "qwen38-flash-next-q8-gguf"
              ]
            );
          # The catalogue is the kept estate after Tom's 2026-09-16 ruling,
          # narrowed on 2026-09-30 (sweep F1: the three Mage rows and the text
          # embedder retired); no other top-level attribute — no deployments,
          # no backend kinds, no utility pointer.
          assert builtins.attrNames localModelCatalog == [ "artifacts" ];
          # Plus Gufo's collection (lib/gufo-models.json), as gufo-org/gufo
          # v0.22.0 plus Q8 and the separately pinned ds4 V4.1 model.
          assert
            builtins.attrNames localModelCatalog.artifacts == [
              "deepseek-v41-flash-1017-q2-gguf"
              "deepseek-v41-flash-dspark-gguf"
              "deepseek-v41-flash-vision-gguf"
              "minimax-h3-fl2va"
              "qwen-image-2.1"
              "qwen-k2so-midway-b"
              "qwen3-asr-1.7b"
              "qwen3-tts-1.7b-base-q8-0"
              "qwen3-tts-12hz-1.7b-base"
              "qwen3-tts-tokenizer-f32"
              "qwen38-27b-dflash2-gguf"
              "qwen38-27b-gguf"
              "qwen38-27b-q8-gguf"
              "qwen38-flash-next-gguf"
              "qwen38-flash-next-q8-gguf"
              "vibevoice-asr-streaming-7b-bf16"
            ];
          # No row is gated: Tom accepted the MiniMax H3 licence on 2026-10-25,
          # so library-fetch archives every row. source.gate stays supported
          # for the next step only Tom can take.
          assert builtins.all (id: localModelCatalog.artifacts.${id}.source.gate == null) (
            builtins.attrNames localModelCatalog.artifacts
          );
          # The proven Gufo endpoint is the only resident text engine.
          assert strix.services.gufo.enable;
          # Consumers name exactly what Gufo serves (lib/local-model.nix): it
          # answers 404 to any other id.
          assert strix.services.gufo.llm.servedModelName == (import ./lib/local-model.nix).modelId;
          assert
            builtins.sort builtins.lessThan (
              pkgs.lib.unique (
                map (n: strix.services.gufo.alternates.${n}.servedModelName) (
                  builtins.attrNames strix.services.gufo.alternates
                )
              )
            ) == builtins.sort builtins.lessThan (import ./lib/local-model.nix).alternates;
          assert strix.services.utilityModel.endpoint == (import ./lib/local-model.nix).endpoint;
          assert
            (import ./lib/local-model.nix).endpoint
            == "http://strix-coordinator:${toString strix.services.gufo.port}";

          assert strix.services.utilityModel.enable;
          assert strix.services.utilityModel.modelId == "qwen3.8-flash-next";
          assert !(strix.virtualisation.oci-containers.containers ? halogen);
          assert !(strix.systemd.services ? podman-halogen);

          assert nixpkgs.lib.elem "amdgpu.gttsize=126976" strix.boot.kernelParams;
          # The utility-model wrapper lives on the strix only.
          assert
            builtins.length (
              nixpkgs.lib.filter (
                package: nixpkgs.lib.getName package == "utility-model"
              ) strix.environment.systemPackages
            ) == 1;

          # Gufo is demand-loaded behind the standard llama-swap endpoint.
          assert strix.services.llama-swap.enable;
          assert strix.services.llama-swap.port == strix.services.gufo.port;
          assert strix.systemd.services.gufo-llm.wantedBy == [ ];

          assert !(strix.systemd.targets ? flashnext-lane);

          # AdGuard is FORBIDDEN per-device on this LAN (DoH vs the NAS's
          # dns_hijack). The worker is the box that collision was first proven
          # on, so its closure must not carry the service at all.

          assert !strix.services.adguardhome.enable;
          assert strix.microvm.host.enable;
          assert !(self.nixosConfigurations.strix-coordinator.options.myArtifacts ? livePortRange);
          # Crash surfacing (#134): the blanket OnFailure handler and both journal watchers exist.
          assert strix.systemd.services."failure-notify@".serviceConfig.Type == "oneshot";
          assert strix.systemd.timers ? tripwire-coredump;
          assert strix.systemd.timers ? tripwire-user-unit-failure;
          assert strix.systemd.timers ? failure-marker-reconcile;
          assert monthlySources.inference.provider == "gufo";
          assert monthlySources.inference.url == "http://strix-coordinator:8731";
          assert monthlySources.inference.compute_host == "strix-coordinator";
          assert monthlySources.inference.tally_pool == "strix-gpu";
          # ── NPU decommission, 2026-08-29 (fleet-7.2) ──────────────────────
          # These used to assert the NPU stack was PRESENT. The house style for
          # a removal is to flip them negative rather than delete them, so the
          # absence is locked in and a silent re-enable is a build failure.
          assert !strix.hardware.amd-npu.enable;
          assert !strix.hardware.amd-npu.enableNPU;

          assert nixpkgs.lib.elem "amd_iommu=off" strix.boot.kernelParams;
          assert !(nixpkgs.lib.elem "amd_iommu=on" strix.boot.kernelParams);

          # #244 checklist: sp5100_tco must stay armed through the reboot
          # transition, which is exactly when a wedged box needs it.
          assert nixpkgs.lib.elem "watchdog.stop_on_reboot=0" strix.boot.kernelParams;

          # Every host follows Linux 7.3, including the NAS's stable userspace.
          # Compare major.minor so point releases pass but 7.30 cannot match.
          assert builtins.all (
            host: nixpkgs.lib.versions.majorMinor host.config.boot.kernelPackages.kernel.version == "7.3"
          ) (builtins.attrValues self.nixosConfigurations);

          # `assert !{strix,worker}.services.npu-llm.enable` stood here
          # until 2026-08-31 (#270): with modules/npu-llm.nix deleted the
          # option no longer evaluates, and the absence asserts below are the
          # ones that still bite (they guard the upstream nix-amd-ai module,
          # which keeps shipping fastflowlm/flm machinery we must not enable).
          # The ad-hoc FLM manifest was a product of services.npu-llm; with the
          # module gone the etc entry must not exist at all.
          assert !(strix.environment.etc ? "local-models/fastflowlm.json");

          assert nixpkgs.lib.all (unit: !(nixpkgs.lib.hasPrefix "flm-" unit)) (
            builtins.attrNames strix.systemd.services
          );
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
              ${./flows}; then
              echo "retired Tally executor attribute found" >&2
              exit 1
            fi
            if ${pkgs.ripgrep}/bin/rg --line-number --glob '!README.md' '${retiredFlowHostPattern}' \
              ${./flows} \
              | ${pkgs.ripgrep}/bin/rg --invert-match 'strix-${retiredWorker}|http://${retiredWorker}:8731|${retiredWorker}-gpu'; then
              echo "a flow names the retired execution host outside its inference endpoint or GPU pool" >&2
              exit 1
            fi
            touch "$out"
          '';

        deadnix = pkgs.runCommand "deadnix" { } ''
          ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names \
            ${./flake.nix} ${./lib} ${./modules} ${./hosts} ${./overlays} ${./home} > $out 2>&1 \
            || (cat $out; exit 1)
        '';

        keyring-boot-runtime =
          let
            coord = self.nixosConfigurations.strix-coordinator.config;
          in
          assert builtins.elem "user@1000.service" coord.systemd.services.keyring-unlock-boot.partOf;
          assert builtins.elem "user@1000.service" coord.systemd.services.keyring-unlock-boot.wantedBy;
          pkgs.runCommand "keyring-boot-runtime" { } ''
            touch "$out"
          '';

        herdr-launchers =
          pkgs.runCommand "herdr-launchers"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.python3
                pkgs.jq
                pkgs.gawk
                pkgs.coreutils
              ];
              HERDR_SCRIPTS = ./home/dot_local/bin;
            }
            ''
              ${pkgs.shellcheck}/bin/shellcheck \
                ${./home/dot_local/bin/herdr-chord} \
                ${./home/dot_local/bin/herdr-projector} \
                ${./home/dot_local/bin/herdr-sway-projector} \
                ${./home/dot_local/bin/sway-workspace} \
                ${./home/dot_local/bin/theme} \
                ${./home/dot_local/bin/runtime-test}
              python3 ${./tests/herdr/test_launchers.py}
              python3 ${./tests/herdr/test_sway_picker.py}
              touch "$out"
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
            nasCfg = self.nixosConfigurations.nas.config;
            computeHosts = [
              self.nixosConfigurations.strix-coordinator.config
              self.nixosConfigurations.strix-worker.config
            ];
            activeHosts = [
              nasCfg
            ];
            expectedPrinter = {
              name = "Brother_HL_L2445DW";
              description = "Brother HL-L2445DW";
              location = "Home";
              # The PINNED address, not the mDNS name. modules/printing.nix moved
              # to ipp://10.42.0.4 on 2026-08-21 after a job was stranded by the
              # Brother's Deep Sleep: its mDNS responder goes fully mute in that
              # state (avahi-resolve times out while the IP still pings), so a
              # .local deviceUri fails exactly when the printer has been idle a
              # while — which is most of the time. This expectation was left
              # behind on the old name in that commit and had been failing since.
              deviceUri = "ipp://10.42.0.4:631/ipp/print";
              model = "everywhere";
              ppdOptions.PageSize = "A4";
            };
          in
          assert nixpkgs.lib.all (host: host.services.printing.enable) activeHosts;
          assert nixpkgs.lib.all (
            host: !host.services.printing.enable && !host.services.avahi.enable
          ) computeHosts;
          assert nasCfg.services.avahi.enable;
          assert nasCfg.services.avahi.allowInterfaces == [ "enp1s0" ];
          assert !nasCfg.services.avahi.openFirewall;
          assert !nasCfg.services.printing.openFirewall;
          assert nasCfg.services.printing.listenAddresses == [ "localhost:631" ];
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
            # The NAS follows its own nixpkgs pin, so match by name, not store path.
            host:
            builtins.any (p: (p.name or "") == pkgs.brother-print-text.name) host.environment.systemPackages
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

        # print-plane (#384): the two silent failures of 2026-09-11/12 and the
        # daemon that now owns /print, asserted at eval time. cups-browsed off
        # on EVERY host that prints (it rewrote the pinned DeviceURI to
        # implicitclass://, job 303); ensure-printers' postStart asserts the
        # pinned URI and the urf PPD filter (the raw queue of job 304); the
        # paper-daemon units exist on the NAS brain only; the retired
        # trust-lp flusher is gone.
        print-plane =
          let
            hosts = nixpkgs.lib.attrValues (
              nixpkgs.lib.mapAttrs (_: host: host.config) self.nixosConfigurations
            );
            printingHosts = builtins.filter (host: host.services.printing.enable) hosts;
            nas = self.nixosConfigurations.nas.config;
            brainHome = nas.home-manager.users.tom;
            compute = self.nixosConfigurations.strix-coordinator.config;
            daemonService = brainHome.systemd.user.services.paper-daemon;
            postStart =
              self.nixosConfigurations.nas.config.systemd.services.ensure-printers.postStart;
          in
          assert printingHosts != [ ];
          assert nixpkgs.lib.all (host: !host.services.printing.browsed.enable) printingHosts;
          # NAS has a stable userspace and compute tracks unstable: command
          # store paths differ, but every scheduler must enforce the same guard.
          assert nixpkgs.lib.all (
            host:
            let guard = host.systemd.services.ensure-printers.postStart;
            in nixpkgs.lib.hasInfix "ipp://10.42.0.4:631/ipp/print" guard
              && nixpkgs.lib.hasInfix ''cupsFilter2: "image/urf'' guard
              && nixpkgs.lib.hasInfix "implicitclass:" guard
          ) printingHosts;
          assert nixpkgs.lib.hasInfix "ipp://10.42.0.4:631/ipp/print" postStart;
          assert nixpkgs.lib.hasInfix ''cupsFilter2: "image/urf'' postStart;
          assert nixpkgs.lib.hasInfix "implicitclass:" postStart;
          assert nas.services.printing.enable;
          assert brainHome.systemd.user.paths ? paper-daemon;
          assert brainHome.systemd.user.paths.paper-daemon.Path.PathChanged == "%h/.local/share/utility-data/paper/intake";
          assert !(brainHome.systemd.user.timers ? paper-daemon-sweep);
          assert brainHome.systemd.user.timers ? paper-daemon-flush;
          assert brainHome.systemd.user.timers.paper-daemon-flush.Timer.Persistent;
          assert daemonService.Unit.X-RestartIfChanged == false;
          assert daemonService.Unit.StartLimitIntervalSec == 0;
          assert nixpkgs.lib.elem "PAPER_RENDER_HOST=strix-coordinator" daemonService.Service.Environment;
          assert !(brainHome.systemd.user.services ? paper-print-flush);
          assert !(compute.home-manager.users.tom.systemd.user.paths ? paper-daemon);
          assert builtins.any (package: nixpkgs.lib.getName package == "paper-render") compute.environment.systemPackages;

          pkgs.runCommand "print-plane" { } ''
            ${builtins.head (nixpkgs.lib.toList daemonService.Service.ExecStart)} --help >/dev/null 2>&1 \
              || { echo "paper-daemon --help failed" >&2; exit 1; }
            ${pkgs.paper-daemon}/bin/paper-daemon check-queue --help >/dev/null
            test -f ${pkgs.paper-daemon}/share/paper-daemon/scripts/print-auto.py
            test -f ${pkgs.paper-daemon}/share/paper-daemon/get-jobs.test
            test -f ${pkgs.paper-daemon}/share/paper-daemon/printer-state.test
            touch "$out"
          '';

        huggingface-cli-smoke =
          let
            hf = self.nixosConfigurations.nas.pkgs.huggingface-cli;
            expectedVersion = "1.10.2"; # NAS stable userspace; same metadata/cache contract.
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
            brainPackages = self.nixosConfigurations.nas.config.home-manager.users.tom.home.packages;
          in
          assert hf.version == expectedVersion;
          assert builtins.elem hf brainPackages;
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

      }
      // inputs.deploy-rs.lib.${system}.deployChecks self.deploy;
    };
}
