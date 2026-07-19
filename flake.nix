{
  description = "mecattaf — one flake for the whole distribution (NixOS + home-manager). Coordinator/worker AMD Strix Halo cluster + Intel laptops.";

  inputs = {
    # Unstable: Strix Halo (gfx1151) wants fresh kernels + Mesa.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nixpkgs-fresh — a second nixpkgs, tracking the SAME nixos-unstable branch, used
    # ONLY to keep a handful of fast-moving user packages (currently
    # google-chrome and uv, see overlays list below) current independent of the `nixpkgs`
    # pin above. That pin is deliberately lagging — modules/auto-update.nix explains
    # it's the only door kernel/Mesa churn enters through, bumped as a manual act.
    # Browser point releases carry none of that risk, so they shouldn't have to wait
    # on it.
    #
    # This input's OWN locked rev is never what actually builds: every real build
    # (modules/auto-update.nix `system.autoUpgrade.flags`, hosts/worker/fleet-prebuild.nix)
    # passes `--override-input nixpkgs-fresh github:NixOS/nixpkgs/nixos-unstable`,
    # which re-resolves it to nixos-unstable HEAD at build time without writing
    # anything to flake.lock — true "always latest" for just this input, no git-push
    # automation or new credentials needed (only the coordinator holds a
    # GitHub-authenticated `gh`; the worker, which builds nightly at 02:00, doesn't).
    # Same decoupling trick the llm-agents.nix input comment describes for
    # claude-code, inlined here instead of via a whole separate flake. A local build
    # that omits the override flag just falls back to whatever's locked — bump it
    # manually with `nix flake update nixpkgs-fresh` if that ever goes noticeably stale.
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
    # newest claude-code DECOUPLED from our (deliberately lagging) nixpkgs pin:
    # `nix flake update llm-agents` bumps agents without touching kernel/Mesa.
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

    # tally — agent-session orchestration (one Bun-compiled daemon + CLI). THE
    # packaging channel is this flake input + `homeManagerModules.tally` (tally
    # DECISIONS Q1: the module is load-bearing — systemd user units + the pls
    # broker/pool config — which a bare pkg can't deliver; NO bespoke
    # pkgs/tally.nix). home/tally.nix imports the module and enables it on the
    # coordinator (conductor role); other hosts leave it off. Composes onto the
    # dotfiles-owned zmx substrate — tally ships none of it (V0.1-PATH step 1).
    # follows nixpkgs so the Bun/bun2nix build resolves against our one pin
    # rather than dragging a second nixpkgs into the lock. `nix flake update
    # tally` bumps to the latest pushed commit (and, post-release, the tag).
    tally = {
      url = "github:mecattaf/tally";
      inputs.nixpkgs.follows = "nixpkgs";
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

    # nix-amd-ai — AMD Ryzen AI NPU stack (amdxdna driver + XRT + FastFlowLM).
    # COORDINATOR ONLY: the conductor turns the NPU on (needs IOMMU in translated
    # mode); the worker keeps the NPU off for max iGPU (iommu off). Deliberately
    # NO inputs.nixpkgs.follows — the overlay is built against its OWN pinned
    # nixpkgs so its Cachix (nix-amd-ai.cachix.org, substituter added in
    # modules/common.nix) serves prebuilt XRT/FastFlowLM instead of source builds.
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";

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
        (_final: _prev:
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
          })
      ];

      pkgs = import nixpkgs {
        inherit system overlays;
        config.allowUnfree = true; # google-chrome
      };

      # Single host-wiring point. Every host = common.nix + its own module + HM.
      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
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
      overlays.default = import ./overlays;

      nixosConfigurations = {
        coordinator = mkHost ./hosts/coordinator;
        worker = mkHost ./hosts/worker;
        zenbook-duo = mkHost ./hosts/zenbook-duo;
      };

      # Standalone home-manager bridge for the live Fedora host (coexists with Fedora):
      #   nix run home-manager -- switch --flake .#tom@bridge
      homeConfigurations."tom@bridge" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./home/home.nix ];
      };

      packages.${system} = {
        inherit (pkgs) mactahoe-gtk-theme mactahoe-icon-theme sfmono-liga;
      };

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
            ${./flake.nix} ${./modules} ${./hosts} ${./overlays} ${./home} > $out 2>&1 \
            || (cat $out; exit 1)
        '';
      };
    };
}
