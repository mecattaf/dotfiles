{
  description = "mecattaf — one flake for the whole distribution: Strix Halo coordinator, headless AMD NAS, and Intel laptop.";

  inputs = {
    # Unstable: Strix Halo (gfx1151) wants fresh kernels + Mesa.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nixpkgs-fresh — a second nixpkgs used ONLY to keep a handful of
    # fast-moving user packages (currently google-chrome and uv, see overlays
    # list below) and the twins'/NAS's linuxPackages_7_2 kernel series current
    # independent of the `nixpkgs` pin above. That pin is deliberately
    # lagging — the exact-candidate fleet deploy keeps it as the only door
    # Mesa/ROCm churn enters through, bumped manually. Browser point releases
    # and 7.2.y kernel point fixes carry none of that risk, so they shouldn't
    # have to wait on it.
    #
    # nixos-unstable-SMALL since 2026-08-30 (#244): the same rolling resolver,
    # gated by the same core Hydra jobs, minus the big-channel test set that
    # had nixos-unstable sitting 4+ days behind while 7.2.2 (a kernel point
    # fix the twins wanted) was already through. Everything this input feeds
    # is either an upstream binary (chrome), a leaf tool (uv), or the
    # versioned kernel attr whose whole doctrine is point-fix-only advance.
    #
    # Its lock entry is a reproducible fallback. The nightly fleet transaction uses
    # `rollingInputOverrides` below to resolve it (with llm-agents and the two AMD
    # catalogs) exactly once, then builds and deploys those immutable URLs without
    # writing the lock. A plain local build uses the reviewed fallback revision.
    nixpkgs-fresh.url = "github:NixOS/nixpkgs/nixos-unstable-small";

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

    # Apple SF Pro — kept by explicit ruling (2026-08-21: "it's too good to
    # have, let's not skip it"), with eyes open about the failure mode this
    # input carries: it locks Apple's CDN DMGs as `type = "file"` inputs, and
    # Apple re-releases those DMGs in place, changing the bytes under the
    # locked narHash. The very first update-center run failed all three
    # fleet builds on exactly that (a box with the old DMG already in store
    # never notices; a cold fetch — the NAS, or any fresh machine — dies).
    # Containment: ONLY sf-pro is consumed anywhere (fonts.packages in
    # modules/common.nix), so only SF-Pro.dmg is ever fetched; the sibling
    # family locks (sf-compact, sf-mono, ny, …) sit inert and cannot rot a
    # build. WHEN the nightly fails here again with "mismatch in field
    # 'narHash'", the fix is one line: `nix flake update apple-fonts`,
    # commit, push. The rest of the 2026-08-21 font sweep stands in part:
    # sf-compact/sf-mono/ny uninstalled, serif alias moved to Source Serif 4.
    apple-fonts = {
      url = "github:Lyndeno/apple-fonts.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Liga SF Mono: SF Mono ligaturized AND nerd-patched upstream — a
    # different derived font from apple-fonts' sf-mono-nerd (glyphs only, no
    # ligatures). Plain repo of OTFs, not a flake; consumed by
    # pkgs/sfmono-liga.nix. DELETED in the 2026-08-21 sweep, RESTORED the
    # same evening: the sweep's premise ("no terminal ever used it") was
    # false — kitty.conf had named the nonexistent family "Maple Mono
    # Normal NF" since 2026-03-03 and silently rode the fontconfig
    # monospace alias, which pointed HERE, so this was the terminal face
    # the whole time (proven from the old kitty process's /proc maps).
    # Tom, on seeing real Maple: "i like whatever font was in use before
    # this afternoon's pushes." kitty.conf now names this family
    # EXPLICITLY, so no future sweep can silently swap the terminal again.
    sfmono-liga = {
      url = "github:shaunsingh/SFMono-Nerd-Font-Ligaturized";
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

    # tally — contention and proof for agent sessions (a Rust workspace: one
    # daemon + CLI, embedded taskchampion, witness ledger). THE packaging
    # channel is this flake input + `homeManagerModules.tally`: the module is
    # load-bearing — it generates the systemd user units, the producer
    # timers/services and the build-time `checkedConfig` validator, which a bare
    # pkg can't deliver; NO bespoke pkgs/tally.nix. home/tally.nix imports the
    # module and enables the daemon on the coordinator only. Other hosts leave
    # the module off. Composes onto whatever terminal substrate the dotfiles own —
    # tally ships none of it. follows nixpkgs so the Rust build resolves against
    # our one pin rather than dragging a second nixpkgs into the lock. `nix flake
    # update tally` bumps to the latest pushed commit (and, post-release, the tag).
    #
    # Repo is mecattaf/tally.nix (NOT mecattaf/tally, which is the pre-rebuild
    # spec history). It is public, so use the native `github:` fetcher: fleet
    # auto-upgrades need no GitHub credential helper or access token.
    # tally's one law: contention and proof, never content or control.
    tally = {
      url = "github:mecattaf/tally.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # tally-b — the REWRITE kernel (github.com/mecattaf/tally, the repo whose
    # pre-rebuild spec history the `tally` comment above names): the Rust
    # workspace of TALLY-SPEC §2.1 — admission, leases, the witness chain and
    # the typed socket — delivered by U-B1…U-B13 on `main`.
    #
    # `flake = false` because the repo ships NO flake of its own: it is a cargo
    # workspace (std-only crates, no build.rs, no external dependency), so
    # there is nothing to consume but source, and modules/tally-b.nix does the
    # whole packaging — rustPlatform over crates/tally-socket, whose binary IS
    # `tally-kernel` (serve/call/chain/guard), run as the SYSTEM service
    # tally-kernel.service. Same plain-source consumption sfmono-liga uses.
    #
    # PINNED TO A REV on `main`, deliberately, the way nixpkgs-paperless and
    # herdr are bumped: `nix flake lock --update-input tally-b` must be a
    # NO-OP at the pin (asserted by tests/tally-b/test-tally-b-input.sh), and
    # moving the kernel is an edit here, reviewed like any other change.
    #
    # The repo is PRIVATE (`gh repo view mecattaf/tally --json isPrivate` →
    # true, MEASURED 2026-09-06) and this unit flips no visibility — no
    # executor does; contrast U-D15's herdr-kitten, whose `github:` form a Tom
    # line had already cleared (R-2026-09-06-22) before the flip. The native
    # `github:` fetcher was MEASURED against that wall: it downloads the
    # codeload tarball with nix's own `access-tokens`, of which this fleet has
    # none configured, and answers `HTTP error 404` on the private repo. So
    # the URL is the `git+https://` form, which fetches through git and
    # therefore through the machine's OWN persistent credential path — the
    # `gh auth git-credential` helper in root's and tom's global gitconfig —
    # with no token in this file, in flake.lock or in the environment nix
    # needs at eval time. Consequence, stated plainly and recorded in
    # DECISIONS.md: the ONE network act (the lock update / first fetch) works
    # only on a host whose git can authenticate to github.com; after that the
    # git cache and store path make every gate `--offline`-clean anywhere.
    # Nothing was printed or read from any credential store to establish this.
    tally-b = {
      url = "git+https://github.com/mecattaf/tally?rev=d4e54d5f7c41335e4a1c5f539e3ab8865fc04412";
      flake = false;
    };

    # tally-lake — the LAKE (github.com/mecattaf/tally-ts-sdk), TALLY-SPEC §2.2:
    # packages/schema, packages/factory (the CONWIP release station), apps/worker
    # (the deployed Durable Object, `tally-lake` on Tom's own account) and
    # apps/uplink (W-03, the box side: probe every row, POST the reading, pull
    # /proposals, admit over the socket, POST /outcomes, execute under lease,
    # mirror the chain, re-arm the plan). The lake PROPOSES; the kernel answers.
    #
    # The THIRD tally-named input in this file, and the three are easy to
    # confuse, so here they are side by side:
    #   tally       mecattaf/tally.nix      the LIVE daemon's public packaging flake
    #   tally-b     mecattaf/tally          the REWRITE kernel's cargo workspace
    #   tally-lake  mecattaf/tally-ts-sdk   the LAKE that proposes to that kernel
    #
    # CONSUMED AS A FLAKE, unlike tally-b: this repo DOES ship a flake.nix.
    # W-03 added it (lake commit c29fdfb, "packages.uplink and
    # homeManagerModules.tally-uplink (D-B65)") under an explicit supersession
    # of that repo's own CONTRIBUTING §2 rule 6 ("No Nix in this deliverable"),
    # because U-D14's card assigns the package derivation and the home-manager
    # module to the lake and no other unit was chartered to build them. So there
    # is no `flake = false` here, and home/tally-uplink.nix imports
    # `inputs.tally-lake.homeManagerModules.tally-uplink` exactly the way
    # home/tally.nix imports `inputs.tally.homeManagerModules.tally` — the
    # motion this unit replicates (the card's exemplar).
    #
    # NO `inputs.nixpkgs.follows`, because there is nothing to follow: the
    # lake's flake takes NO inputs at all, on purpose (its own comment: a
    # nixpkgs input would be a fetch, and its lock would pin bytes nobody in
    # that repository chose). It records the node store path its
    # scripts/node-env.sh records and refuses to evaluate if the two disagree,
    # so our pin drags no second package universe along and our nixpkgs cannot
    # move its toolchain under it.
    #
    # `git+https://`, NOT `github:`, for the wall U-D13 established over
    # mecattaf/tally and re-MEASURED here for THIS repo on 2026-09-07: it is
    # PRIVATE (`gh repo view mecattaf/tally-ts-sdk --json isPrivate,visibility`
    # → {"isPrivate":true,"visibility":"PRIVATE"}) and no executor flips
    # visibility. `nix flake metadata
    # github:mecattaf/tally-ts-sdk/a233c303246efb6eceb8e84ac409f85d3d41879b`
    # answers `HTTP error 404` (MEASURED) because the tarball fetcher spends
    # nix's own `access-tokens`, of which this fleet configures none. The
    # `git+https://` form fetches through git and therefore through the
    # machine's own persistent credential path (`gh auth git-credential` in the
    # global gitconfig) — no token in this file, none in flake.lock, none needed
    # in the environment at eval time, and none read or printed to establish any
    # of it. Same stated consequence as tally-b: the ONE network act (the lock
    # update / a cold fetch) works only on a host whose git can authenticate to
    # github.com; after it, the git cache and the store path make every gate
    # `--offline`-clean anywhere.
    #
    # PINNED TO A REV on `main`, deliberately, the way tally-b and
    # nixpkgs-paperless are bumped: `nix flake lock --update-input tally-lake`
    # must be a NO-OP at the pin (asserted as clause A0 of
    # tests/tally-uplink/test-tally-uplink-input.sh), and moving the lake is an
    # edit here, reviewed like any other change. NOT in
    # `rollingInputOverrides`: the lake proposes work onto this box's rows, so
    # its version moves when Tom says so, never on a nightly resolve — the same
    # reason herdr and herdr-kitten are out.
    #
    # REV: 897f901 = origin/main of mecattaf/tally-ts-sdk on 2026-09-10
    # (MEASURED: `git rev-parse origin/main` in the local clone; 32 commits
    # ahead of the previous pin 38a526ba, and the whole range is on `main`).
    # The lineage of this line, so a reader can see what each bump bought:
    #   a233c30  W-03's delivery (PR #99 `lake/uplink`, merged as e3249b7,
    #            whose flake.nix commit c29fdfb is an ancestor) plus U-A22's
    #            evaluator probe — the first `main` that exports
    #            `homeManagerModules.tally-uplink` at all; anything before
    #            c29fdfb has no flake to import and this input cannot evaluate.
    #   38a526ba the pin this bump replaces.
    #   897f901  THIS pin. What it carries that 38a526ba lacks (TL-18 /
    #            dotfiles#304, runbook step 3 of tally-ts-sdk docs/deploy.md):
    #            packages/planning/src/objects/factory.ts:617 `level_rank` and
    #            the uplink's `level_rank` passthrough — without it a proposal
    #            arrives without the level the floor ranks it by; FIX-E04, the
    #            uplink SHUTTING THE DOOR on the lake's 5xx instead of retrying
    #            into it (the deployed Worker answers 500 FactoryError /
    #            PersistenceFailed today, tally-ts-sdk docs/e2e.md:178-186, so
    #            this is the difference between a legible refusal every five
    #            minutes and a hot loop); FIX-E05 and FIX-E10.
    # BUMPING THE PIN IS NOT DEPLOYING THE LAKE and is not a switch: this line
    # moves the bytes the BOX evaluates against. The deployed Worker
    # (f95beed) already carries the factory fix; only the box-side pin lacked
    # it. The switch that installs the result is Tom's (dotfiles#322 U-D19),
    # and so is any further bump once FT-2/FT-4/FT-5/FT-6 merge.
    # See docs/local-ai/tally-uplink-input.md.
    tally-lake = {
      url = "git+https://github.com/mecattaf/tally-ts-sdk?rev=897f9015e7c22304c3bfd7ca2ec990b294966ded";
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

    # piri — niri IPC extension daemon (github.com/Asthestarsfalll/piri): one
    # Rust daemon that tails niri's event stream and layers plugins on top —
    # scratchpads, marks, window/workspace rules. We use it for the "music"
    # auto-scratchpad (Mod+M toggles a right-side SoundCloud/cliamp pane).
    # Third-party but consumed exactly like tally: flake input pinned in
    # flake.lock, follows nixpkgs so the Rust build resolves against our one pin.
    # piri ships packages.default + a NixOS module, but NOT a home-manager
    # module, so home/piri.nix does the module work: package + user service, with
    # piri.toml delivered RAW through the niri whole-dir symlink for hot-reload.
    # `nix flake update piri` bumps to the latest pushed commit.
    piri = {
      url = "github:Asthestarsfalll/piri";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # herdr — the terminal workspace manager for AI coding agents
    # (github.com/herdrdev/herdr, Apache-2.0). It is the upstream PRODUCT that
    # replaces everything this repo used to invent for itself: the home-grown
    # kitten tier, its session layer, and its title-naming pipeline are all
    # deleted in favour of one server holding every PTY.
    #
    # PINNED TO A REV, not a branch: 0.9.0 is the current reviewed release
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
      url = "github:herdrdev/herdr/b99002ac99b09e00b4ca692436cb15a6b0d676f1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # herdr-kitten — the repo where herdr IS the kitty kitten: one stdlib-Python
    # kitten (four gestures on kitty's GUI thread) plus the `hk` CLI (workspace
    # create/attach/resume/rename, the dictation endpoint, the recording
    # spinner). It is the whole integration layer between kitty and herdr, and
    # it is the reason this repo could delete its six home-grown kittens and the
    # whole script tier under them outright.
    #
    # CONSUMED AS AN INPUT, NEVER VENDORED (ruling B3): `nix flake update
    # herdr-kitten` is the entire upgrade story. Consume
    # `packages.<sys>.herdr-kitten` only — no overlay of its own reaches our pkgs
    # fixpoint (F.3) — and keep it out of `rollingInputOverrides` (F.4) for the
    # same reason herdr is out: it fronts live PTYs.
    #
    # URL — `github:mecattaf/herdr-kitten/<rev>`, the URL its own README
    # documents and the same shape the `tally` input above uses for exactly the
    # stated reason: "fleet auto-upgrades need no GitHub credential helper or
    # access token". The local-checkout URL it replaces resolved only on THIS
    # box — a `file://` git tree under /home/tom — so no other host could
    # evaluate this flake at all; that is what U-D15 removed. (No `file://`
    # spelling of it survives anywhere in this file or in flake.lock: that
    # absence is an asserted clause of U-D15's oracle, not a tidiness.)
    #
    # The form is admissible because the Tom line that barred it has been taken:
    # `~/research-methods/RULINGS.md` R-2026-09-06-22 ("herdr kitten goes public
    # is fine") records `gh repo edit mecattaf/herdr-kitten --visibility public`
    # run by the planning session at 20:31Z and names this unit — "U-D15 resumes
    # with no Tom line left on it". No executor here ran a visibility command.
    # MEASURED 2026-09-06T22:05Z on the coordinator:
    # `gh repo view mecattaf/herdr-kitten --json isPrivate,visibility` answers
    # `{"isPrivate":false,"visibility":"PUBLIC"}`, and `nix flake metadata
    # github:mecattaf/herdr-kitten/ccc16393…` resolves to the same narHash
    # (sha256-X5b1Fi6ObCI5xHPpEXTL8k1FbWO5JZeBnqMYAfG6jVU=) that the local
    # `file://` git checkout under /home/tom reports for the SAME rev — the same
    # object by content, not merely by rev name. (Neither spelling of the old
    # local URL is written here, not even in a comment: the oracle greps this
    # file for both, so a nostalgic mention would read as the fault.)
    # The survey's Q-7 ("the repo is PRIVATE by standing wall. No executor flips
    # visibility") is spent by that ruling, not overridden. Pinned BY REV and
    # never by branch: this input fronts live PTYs, so it moves when Tom says so
    # (F.4 keeps it out of rollingInputOverrides for the same reason herdr is
    # out). See docs/herdr/herdr-kitten-input.md.
    #
    # REV: the merged head of `mecattaf/herdr-kitten` main past the round-2
    # merges — U-C2…U-C5 (`97e4b9c`, `5e857f0`, `ccc1639`) and herdr-kitten #26's
    # `homeManagerModules.default`. The previous pin `41a6de5` predates every one
    # of them and installs a kitten that cannot load under kitty; RULING-kitten
    # §0 rules that tree "must not ship", so no box may switch on it.
    #
    # Upstream's herdr and nixpkgs inputs both follow these top-level inputs,
    # so one herdr and one nixpkgs serve the whole closure.
    herdr-kitten = {
      url = "github:mecattaf/herdr-kitten/ccc16393cc35e2cce2b8cd9a55718b3c84849a8f";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.herdr.follows = "herdr";
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
    # llama.cpp ROCm/Vulkan, amdtop, MES firmware, and a buildable live ISO
    # (its ds4/vLLM/MLX outputs exist upstream but nothing here consumes them:
    # the fleet is mono-model on Halogen). Consume its package
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
        inputs.apple-fonts.overlays.default
        (final: _prev: {
          # Whole llm-agents catalog under `pkgs.llm-agents.*` (prebuilt from its
          # own nixpkgs — no second eval of ours). home/home.nix pulls an
          # allowlisted set out of this namespace. See the input comment above.
          llm-agents = inputs.llm-agents.packages.${system};
          sfmono-liga = final.callPackage ./pkgs/sfmono-liga.nix { src = inputs.sfmono-liga; };
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
      # The flake-level model-store binding is gone (2026-08-28, with the
      # #242 corpse removal): lib/model-store.nix still exists and is imported
      # where it is consumed — modules/local-models.nix and hosts/nas/models.nix
      # — but the flake itself no longer projects a package set from it, because
      # the 2026-08-21 "weights leave nix" ruling means there isn't one.

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

      # The reviewed rolling-input list, exposed the same evaluation-only way and
      # for the same reason. It lost its last CONSUMER when
      # hosts/coordinator/fleet-deploy.nix was deleted on 2026-08-21, but it did
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
      };

      nixosConfigurations = {
        coordinator = mkHost { hostModule = ./hosts/coordinator; };
        nas = mkHost {
          hostModule = ./hosts/nas;
          withHomeManager = false;
          hostNixpkgs = inputs.nixpkgs-stable;
        };
        # PERMANENT fleet member again since 2026-08-21 (#229). Plain mkHost with
        # every default: it rides the same unstable pin as its twin (the two are
        # identical Strix Halo silicon and the pin exists to gate exactly that
        # kernel/Mesa churn) and it keeps Home Manager, because unlike the NAS it
        # is an ordinary interactive NixOS box that happens to be headless.
        worker = mkHost { hostModule = ./hosts/worker; };
        # The ASUS Zenbook Duo, Tom's thin client since 2026-09-11 (its second
        # tenure here; `zenbook-duo` left on 2026-08-30 and came back from
        # omarchy-fleet under this name). Plain mkHost: it rides the unstable
        # pin like the twins and keeps Home Manager, because it is the box Tom
        # sits at — niri, kitty and Chrome are real here, nothing else is.
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
        remoteBuild = false; # every selected profile is built locally on coordinator
        fastConnection = false; # let each destination substitute from Attic
        activationTimeout = 1200;
        confirmTimeout = 90;

        nodes =
          nixpkgs.lib.genAttrs
            [
              "client"
              "coordinator"
              "nas"
              "worker"
            ]
            (host: {
              # Canonical names, every one: `nas` and `coordinator` through the
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
        in
        {
          inherit (pkgs)
            academic-ocr
            brother-print-text
            call-diarize
            crm
            dcal
            local-ai-monthly
            # `nix build .#local-models-prune` — the ONLY verb on this fleet
            # that deletes a working copy. Exposed so the guard suite can be
            # pointed at a built path (LOCAL_MODELS_PRUNE_BIN) instead of
            # requiring the binaries to be installed on the caller's PATH.
            local-models-prune
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
            ec-su-axb35-monitor
            llama-cpp-rocm
            llama-cpp-vulkan
            strix-halo-mes-firmware
            ;
          live-iso = strixAi.live-iso;
          nas-installer-iso = nasInstaller.config.system.build.isoImage;
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
        coordinator-uplink =
          pkgs.runCommand "coordinator-uplink-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              mkdir -p hosts/coordinator tests/coordinator-uplink
              cp ${./hosts/coordinator/uplink.py} hosts/coordinator/uplink.py
              cp ${./tests/coordinator-uplink/test_uplink.py} tests/coordinator-uplink/test_uplink.py
              python -m unittest discover -s tests/coordinator-uplink -v
              touch $out
            '';
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

        # The UTIL-01 reconciliation's own topology (U-D17, #320, #311, #314).
        #
        # `nix flake check --offline --no-build` is this unit's DOMINANT gate,
        # and on its own it only proves the merged tree EVALUATES. That catches
        # the mutation the unit is graded against — a conflict marker left in a
        # .nix file is a syntax error and evaluation dies — but it would stay
        # green through a resolution that silently dropped
        # `./util-sampler.nix` from home/home.nix's imports, or that resolved
        # the merge by taking main's side of a file the branch had edited. This
        # check is the difference: every assertion below is an eval-time one, so
        # it runs under --no-build, and each names a property of the SAMPLER's
        # semantics, which this reconciliation's non-goal says it must not
        # change.
        #
        # Nothing here restates the card (/home/tom/research-methods/cards/
        # UTIL-01.md) or adds a threshold. The last two assertions are the
        # sharpest: the card's `instrument_sha256` locks the two programs at
        # arming, and `abort_on` makes a row written by any other instrument a
        # CRASH — so a merge that touched either program is not a merge that can
        # be graded. The sampler digest is the halogen-era script (UTIL-01's
        # instrument_sha256 must be re-armed to it); the row writer's is the one
        # in 34a613dc's message.
        util-sampler-topology =
          let
            coordinator = self.nixosConfigurations.coordinator.config.home-manager.users.tom;
            worker = self.nixosConfigurations.worker.config.home-manager.users.tom;
            samplerPath =
              box:
              builtins.head (
                builtins.filter (nixpkgs.lib.hasPrefix "PATH=") box.systemd.user.services.util-sampler.Service.Environment
              );
            metersRule = "d %h/.local/state/tally/meters/util-sampler 0700 - - -";
          in
          # ── the import line survived the merge ─────────────────────────────
          # home/home.nix is the ONE file both branches touched, and its imports
          # list is where the resolution happened. These four say the resolution
          # kept all three entries: two units on the coordinator, one on the
          # worker, none of which exist if ./util-sampler.nix was dropped.
          assert coordinator.systemd.user.timers ? util-sampler;
          assert coordinator.systemd.user.timers ? util-row;
          assert worker.systemd.user.timers ? util-sampler;
          # The row writer is the JOINER — it reads both boxes' logs, the
          # coordinator's lease events and the drain ledger — so it is
          # coordinator-gated, and a copy on the worker would pull from itself.
          assert !(worker.systemd.user.timers ? util-row);
          # ── the sampler's own semantics ────────────────────────────────────
          # Persistent=false on the sampler is a measurement decision, not a
          # style one: a catch-up burst would write several samples carrying one
          # instant, each a fabricated reading of a GPU nobody was watching. A
          # box that was off must show as ABSENT samples. The row writer is the
          # opposite — a row is a pure function of a sampler log that is already
          # closed, so catching up fabricates nothing.
          assert coordinator.systemd.user.timers.util-sampler.Timer.Persistent == false;
          assert coordinator.systemd.user.timers.util-row.Timer.Persistent == true;
          assert worker.systemd.user.timers.util-sampler.Timer.Persistent == false;
          # `tally` on the COORDINATOR sampler's PATH and nowhere else: the
          # worker has no tally daemon and no tally binary, so putting it there
          # would be a lie about what that box can answer. The sampler records a
          # failed pools call with its error string, never as zero.
          assert nixpkgs.lib.hasInfix "-tally-" (samplerPath coordinator);
          assert !(nixpkgs.lib.hasInfix "-tally-" (samplerPath worker));
          # The one tmpfiles rule, on both boxes. systemd-tmpfiles creates the
          # missing parent for a `d` line, which is why the worker gets the
          # whole path from this rule alone and no duplicate is emitted for the
          # parent home/tally.nix already declares on the coordinator.
          assert builtins.elem metersRule coordinator.systemd.user.tmpfiles.rules;
          assert builtins.elem metersRule worker.systemd.user.tmpfiles.rules;
          # ── the programs are byte-for-byte the ones the card locked ────────
          assert
            builtins.hashFile "sha256" ./home/dot_local/bin/util-sampler
            == "25709720ad9e05e18061148076f015fb83f7e02aa64ebbb57b69861306b8e5a0";
          assert
            builtins.hashFile "sha256" ./home/dot_local/bin/util-row
            == "1fdb80179595dc151af67e4ed2bc03e6a3bcf34685acb869b1cc9d9bcfa90906";
          pkgs.runCommand "util-sampler-topology" { } ''
            touch "$out"
          '';

        # The two UTIL-01 rows l8-flash-probe gained with the reconciliation
        # (U-D17, #320). Same reasoning as l8-flash-probe-row above: both rows
        # ship RED, because nothing has switched yet and neither timer has a
        # fragment, and a row that is red on the day it is written is the row
        # nobody notices has stopped working. Asserted here in a fake HOME with
        # a fake `systemctl` on PATH, in every state that matters — pre-switch,
        # declared, hand-installed (the Rule 9 failure), and off the
        # coordinator, where util-row is SKIP and must never be FAIL. The count
        # is asserted too: the issue says the probe gains EXACTLY these two
        # rows. Hermetic: no systemd, no tally, no network.
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

        # The tally-b topology (U-D13, #316). Same reasoning as
        # util-sampler-topology: `nix flake check --offline --no-build` on its
        # own only proves the tree EVALUATES, and it would stay green through a
        # merge resolution that dropped ../../modules/tally-b.nix from
        # hosts/coordinator/default.nix's imports or that repointed the unit at
        # the live estate's state root. Every assertion is eval-time, so each
        # runs under --no-build, and each names a property the card's non-goals
        # or the kernel's own refusals make load-bearing:
        #   - the service exists on the coordinator and ONLY there (one kernel,
        #     spec §2.4 Q2 — the worker twin is a row, not a second kernel);
        #   - its state root carries the tally-rewrite component, because the
        #     kernel's Ledger::open refuses branch (a)'s paths by name
        #     (ledger.rs:31-35) — a unit pointed at ~/.local/state/tally is a
        #     crash loop, caught here instead;
        #   - the socket is kernel.sock BESIDE that root (tally-socket's own
        #     default_socket_path: SOCKET_BASENAME beside the chain it fronts);
        #   - ExecStart is the store-built binary with all three flags;
        #   - the live user-bus tally-daemon declaration still evaluates — the
        #     card's non-goal "the live tally-daemon.service stays" as bytes —
        #     and no system-bus twin of it appeared.
        tally-b-topology =
          let
            coordinator = self.nixosConfigurations.coordinator.config;
            worker = self.nixosConfigurations.worker.config;
            nas = self.nixosConfigurations.nas.config;
            svc = coordinator.systemd.services.tally-kernel;
            execStart = svc.serviceConfig.ExecStart;
            coordinatorHome = coordinator.home-manager.users.tom;
          in
          assert svc.enable;
          assert !(worker.systemd.services ? tally-kernel);
          assert !(nas.systemd.services ? tally-kernel);
          assert svc.serviceConfig.User == "tom";
          assert coordinator.services.tally-kernel.stateDir == "/home/tom/.local/state/tally-rewrite";
          assert
            coordinator.services.tally-kernel.socketPath == "/home/tom/.local/state/tally-rewrite/kernel.sock";
          assert nixpkgs.lib.hasInfix "-tally-b-kernel-" execStart;
          assert nixpkgs.lib.hasInfix "/bin/tally-kernel serve " execStart;
          assert nixpkgs.lib.hasInfix "--state /home/tom/.local/state/tally-rewrite " execStart;
          assert nixpkgs.lib.hasInfix "--socket /home/tom/.local/state/tally-rewrite/kernel.sock" execStart;
          assert !(nixpkgs.lib.hasInfix "state/tally/" execStart);
          assert builtins.elem "d /home/tom/.local/state/tally-rewrite 0700 tom users - -"
            coordinator.systemd.tmpfiles.rules;
          assert builtins.elem "d /home/tom/.local/state/tally-rewrite/meters 0700 tom users - -"
            coordinator.systemd.tmpfiles.rules;
          # the rows are exactly the three kernel-owned rows of the rewrite's
          # docs/rows.md, each carrying every cell row_from_json refuses to
          # default (a missing grace is a startup refusal by name).
          assert
            builtins.map (r: r.row) coordinator.services.tally-kernel.rows == [
              "gpu-coordinator"
              "gpu-worker"
              "mechanical"
            ];
          assert builtins.all (
            r:
            builtins.all (c: r ? ${c}) [
              "row"
              "capacity"
              "context_window"
              "checkpoint_grace_seconds"
              "kill_grace_seconds"
              "per_attempt_token_cap"
              "running"
            ]
          ) coordinator.services.tally-kernel.rows;
          # the non-goal: the live daemon stays, on the user bus, and this unit
          # did not grow a system-bus twin of it.
          assert coordinatorHome.systemd.user.services ? tally-daemon;
          assert !(coordinator.systemd.services ? tally-daemon);
          pkgs.runCommand "tally-b-topology" { } ''
            touch "$out"
          '';

        # tally-uplink-topology (U-D14, dotfiles#317) — the LAKE's box-side
        # loop, declared on the coordinator's USER bus by home/tally-uplink.nix
        # importing inputs.tally-lake.homeManagerModules.tally-uplink.
        #
        # This check is where a home-manager module's eval-time guard lives in
        # this repository. modules/tally-b.nix could put its invariants in
        # NixOS `assertions`; home-manager gives no option of that kind
        # (MEASURED: no `options.assertions` anywhere in the pinned
        # home-manager's modules/), and a top-level `assert` over `config` in a
        # home module recurses. So the RENDERED unit is asserted here, under
        # `nix flake check --offline --no-build`, which is the card's own first
        # clause.
        #
        # Each assert names a property the card's oracle, its non-goals, or the
        # kernel's own refusals make load-bearing:
        #   - the service is DECLARED, on the coordinator and only there (one
        #     uplink per box that serves a kernel, spec §2.4 Q2 — the worker
        #     twin is a row the coordinator's kernel serves, not a second
        #     uplink); this pair is the mutation hint's target, so dropping
        #     `./tally-uplink.nix` from home/home.nix turns the first of them
        #     false and this check red;
        #   - every path it runs against is under ~/.local/state/tally-rewrite,
        #     never branch (a)'s ~/.local/state/tally — the served kernel's
        #     Ledger::open refuses those paths by name (tally
        #     crates/tally-kernel/src/ledger.rs:31-35) and the two estates are
        #     kept apart by declaration rather than by discovery at first run;
        #   - the rows file is the PINNED kernel's docs/rows.md out of the
        #     store, so the rows probed and the kernel they are probed against
        #     are one pin and cannot drift; a live checkout path would let a
        #     `git checkout` move the unit under nobody's review;
        #   - the token is a PATH and the SERVICE carries no `Install` section —
        #     no secret in the store, and no target this unit installs itself
        #     onto (DEFERRED.md DF-U-D14-2);
        #   - the KIT is a store file that reaches the rendered argv, and the
        #     PLAN is still null with no `--plan` on it (TL-18 / D-B18,
        #     dotfiles#304): the argv table the box resolves against must be a
        #     reviewed artifact, never a file edited on the box (Rule 9,
        #     dotfiles#293), and arming remains Tom's act and not this module's;
        #   - the WAKE exists and is a timer's, not a human's (FIX-E12, spec id
        #     `uplink-has-no-trigger`, dotfiles#351, D-E24): MEASURED, the
        #     service had been failed for 7h with TriggeredBy/WantedBy/
        #     RequiredBy/Wants all empty, no .timer file, and no reverse
        #     dependency, so nothing on the box could ever start it again. The
        #     asserts below require the TIMER on the coordinator and NOT on the
        #     worker, in the monotonic form (`OnUnitInactiveSec`, which measures
        #     from the end of the previous pass — failures included — so wakes
        #     cannot pile up behind a red run) at the drain's own declared
        #     cadence, armed by `timers.target`, with no `Persistent` catch-up;
        #     `Install.WantedBy` is this unit's mutation target, so dropping
        #     that one line makes this check red;
        #   - and the service is still the oneshot it was: `Type=oneshot`,
        #     `--wakes 1`, no `Install` of its own — the timer owns the cadence,
        #     the uplink owns the pass;
        #   - the non-goals as bytes: no system-bus twin of the uplink, and the
        #     live user-bus tally-daemon declaration still evaluates.
        tally-uplink-topology =
          let
            coordinator = self.nixosConfigurations.coordinator.config;
            coordinatorHome = coordinator.home-manager.users.tom;
            workerHome = self.nixosConfigurations.worker.config.home-manager.users.tom;
            cfg = coordinatorHome.services.tally-uplink;
            unit = coordinatorHome.systemd.user.services.tally-uplink;
            timer = coordinatorHome.systemd.user.timers.tally-uplink;
            # The drain's own cadence, read from its declaration rather than
            # retyped: FIX-E12 ties the uplink's wake to it (as
            # home/tally-filler.nix ties the filler's), so a move on either side
            # is red instead of silent.
            drain = coordinatorHome.systemd.user.timers.tally-drain;
            # home-manager renders Service.ExecStart through a settings type
            # that admits either form; join whatever it produced so the infix
            # assertions below read the argv as one string.
            execStart =
              let
                e = unit.Service.ExecStart;
              in
              if builtins.isList e then builtins.concatStringsSep " " e else e;
            state = "/home/tom/.local/state/tally-rewrite";
          in
          # DECLARED on the coordinator, and nowhere else.
          assert coordinatorHome.systemd.user.services ? tally-uplink;
          assert !(workerHome.systemd.user.services ? tally-uplink);
          assert cfg.enable;
          # the options, as this estate sets them.
          assert cfg.tokenFile == "${state}/lake-token";
          assert cfg.socket == "${state}/kernel.sock";
          assert cfg.ledger == "${state}/ledger.jsonl";
          assert cfg.stateDir == "${state}/uplink";
          assert cfg.executor == "coordinator";
          assert cfg.wakes == 1;
          # THE KIT is a store file, not null and not a path on the box
          # (TL-18 / D-B18, dotfiles#304). This is the assert FT-3 flipped:
          # `cfg.kit == null` was the honest state while no kit named an argv
          # for this estate, and the honest state now is that exactly one
          # reviewed store artifact does. The three clauses say what a kit must
          # be here — in the store (so nothing hand-edited on the box can become
          # the argv table, Rule 9 / dotfiles#293), named by the module that
          # builds it, and actually REACHING the unit, which the third clause
          # reads off the rendered argv rather than off the option.
          assert nixpkgs.lib.hasPrefix "/nix/store/" cfg.kit;
          assert nixpkgs.lib.hasSuffix "-tally-uplink-kit.json" cfg.kit;
          assert nixpkgs.lib.hasInfix "--kit /nix/store/" execStart;
          # THE PLAN stays null, and null is still the honest state for it: the
          # plan body is the acceptor's and arming is Tom's act, so the unit
          # must carry no `--plan` either.
          assert cfg.plan == null;
          assert !(nixpkgs.lib.hasInfix "--plan" execStart);
          # the rows file is the pinned kernel's, out of the store.
          assert nixpkgs.lib.hasPrefix "/nix/store/" cfg.rows;
          assert nixpkgs.lib.hasSuffix "/docs/rows.md" cfg.rows;
          assert !(nixpkgs.lib.hasInfix "/home/tom/" cfg.rows);
          # the rendered argv says what it runs against.
          assert nixpkgs.lib.hasInfix "/bin/node " execStart;
          assert nixpkgs.lib.hasInfix "/bin/uplink.mjs " execStart;
          assert nixpkgs.lib.hasInfix "--rows /nix/store/" execStart;
          assert nixpkgs.lib.hasInfix "--token-file ${state}/lake-token" execStart;
          assert nixpkgs.lib.hasInfix "--socket ${state}/kernel.sock" execStart;
          assert nixpkgs.lib.hasInfix "--ledger ${state}/ledger.jsonl" execStart;
          assert nixpkgs.lib.hasInfix "--executor coordinator" execStart;
          assert nixpkgs.lib.hasInfix "--state ${state}/uplink" execStart;
          assert nixpkgs.lib.hasInfix "--wakes 1" execStart;
          # branch (a)'s live root appears nowhere in it.
          assert !(nixpkgs.lib.hasInfix "state/tally/" execStart);
          # the SERVICE still installs itself onto no target and still does one
          # pass per invocation: the timer below owns the cadence, and the unit
          # it wakes is the same oneshot U-D14 declared.
          assert !(unit ? Install);
          assert unit.Service.Type == "oneshot";
          # the WAKE (FIX-E12, dotfiles#351): DECLARED on the coordinator, and
          # nowhere else.
          assert coordinatorHome.systemd.user.timers ? tally-uplink;
          assert !(workerHome.systemd.user.timers ? tally-uplink);
          # in the monotonic form, at the drain's own cadence, with the first
          # wake a full period after the timer is armed — never a wall clock.
          assert timer.Timer ? OnUnitInactiveSec;
          assert timer.Timer.OnUnitInactiveSec != "";
          assert timer.Timer.OnUnitInactiveSec == drain.Timer.OnUnitActiveSec;
          assert timer.Timer.OnActiveSec == timer.Timer.OnUnitInactiveSec;
          assert !(timer.Timer ? OnCalendar);
          # no catch-up burst at switch time, declared false rather than omitted.
          assert timer.Timer.Persistent == false;
          # it wakes ITS OWN service, and it is armed by timers.target — the
          # line whose removal is this unit's mutation.
          assert timer.Timer.Unit == "tally-uplink.service";
          assert builtins.elem "timers.target" (timer.Install.WantedBy or [ ]);
          # a clock and nothing else: no argv, no path, no credential in it.
          assert !(timer ? Service);
          assert !(nixpkgs.lib.hasInfix "lake-token" (builtins.toJSON timer));
          # the uplink's own outbox, declared with its mode.
          assert builtins.elem "d ${state}/uplink 0700 - - -" coordinatorHome.systemd.user.tmpfiles.rules;
          # and the kit's usage drop, where every `usage_source.path_glob` the
          # kit names resolves: the kernel resolves the glob, it does not create
          # the directory.
          assert builtins.elem "d ${state}/uplink/usage 0700 - - -" coordinatorHome.systemd.user.tmpfiles.rules;
          # the non-goals: no system-bus twin of either half, and the live
          # daemon stays.
          assert !(coordinator.systemd.services ? tally-uplink);
          assert !(coordinator.systemd.timers ? tally-uplink);
          assert coordinatorHome.systemd.user.services ? tally-daemon;
          pkgs.runCommand "tally-uplink-topology" { } ''
            touch "$out"
          '';

        # tally-filler-topology (U-D18, dotfiles#321) — the filler lane's
        # CLOCK: home/tally-filler.nix's user timer and the oneshot it wakes.
        #
        # Same reasoning as tally-uplink-topology directly above: home-manager
        # gives no `assertions` option, so the invariants over the RENDERED
        # units live here, under `nix flake check --offline --no-build`, which
        # is the card's own first clause. The card's second clause — "nix eval
        # shows tally-filler.timer declared on the coordinator with
        # OnUnitActiveSec set and the service calling the uplink's filler
        # verb" — is asserted here as well as read out by
        # tools/u-d18-filler-timer-oracle.sh, so the two halves are one gate.
        #
        # Each assert names a property the card's oracle, its non-goals or
        # D-B10 makes load-bearing:
        #   - the TIMER is declared, on the coordinator and only there, with
        #     OnUnitActiveSec set and pointing at its own service; this pair is
        #     the mutation hint's target ("remove the timer -> the eval is
        #     false"), so dropping ./tally-filler.nix from home/home.nix turns
        #     the first of them false and this check red;
        #   - its period EQUALS the drain's own declared period, because D-B10
        #     rules the two fillers alternate by round-robin: a literal here
        #     would let the upstream drain's cadence move without a review, and
        #     the equality makes that drift red instead;
        #   - the service calls the lane's verb — e1-loop.sh with `--all`
        #     (D-U-E1LOOP-7) — and does NOT carry `--dry-run`, which is the
        #     probe's selector and never the installed unit's;
        #   - the non-goals as bytes: no llama-swap, no :9292, no unload
        #     anywhere in the rendered unit, and no system-bus twin;
        #   - nothing under ~/.local/state is written by it, and branch (a)'s
        #     live root ~/.local/state/tally/ appears nowhere in it;
        #   - the uplink is given no schedule by THIS unit: it still renders
        #     with no Install section. (DF-U-D14-4 was to be discharged by a
        #     timer of the filler's own; MEASURED, it never was — the lane's
        #     e1-loop.sh names the uplink nowhere — so FIX-E12 discharged it in
        #     home/tally-uplink.nix with a tally-uplink.timer instead, and the
        #     assert below still holds: a timer wakes the service, nothing
        #     installs it.)
        tally-filler-topology =
          let
            coordinator = self.nixosConfigurations.coordinator.config;
            coordinatorHome = coordinator.home-manager.users.tom;
            workerHome = self.nixosConfigurations.worker.config.home-manager.users.tom;
            timer = coordinatorHome.systemd.user.timers.tally-filler;
            service = coordinatorHome.systemd.user.services.tally-filler;
            drain = coordinatorHome.systemd.user.timers.tally-drain;
            execStart =
              let
                e = service.Service.ExecStart;
              in
              if builtins.isList e then builtins.concatStringsSep " " e else e;
            fillerPath = nixpkgs.lib.removePrefix "PATH=" (
              nixpkgs.lib.findFirst (
                value: nixpkgs.lib.hasPrefix "PATH=" value
              ) (throw "tally-filler.service has no PATH environment") service.Service.Environment
            );
            # Everything the unit says, as one string, so the non-goal
            # assertions cannot be satisfied by a value hiding in Environment.
            rendered = execStart + " " + builtins.concatStringsSep " " service.Service.Environment;
          in
          # DECLARED on the coordinator, and nowhere else.
          assert coordinatorHome.systemd.user.timers ? tally-filler;
          assert coordinatorHome.systemd.user.services ? tally-filler;
          assert !(workerHome.systemd.user.timers ? tally-filler);
          assert !(workerHome.systemd.user.services ? tally-filler);
          # the timer: OnUnitActiveSec SET, pointing at its own service, armed
          # by timers.target, and not a wall-clock backlog.
          assert timer.Timer ? OnUnitActiveSec;
          assert timer.Timer.OnUnitActiveSec != "";
          assert timer.Timer.Unit == "tally-filler.service";
          assert builtins.elem "timers.target" timer.Install.WantedBy;
          assert !(timer.Timer ? Persistent);
          # D-B10: the two fillers alternate, so the filler's period IS the
          # drain's period. Asserted as an equality against the other filler's
          # own declaration, never as a literal.
          assert timer.Timer.OnUnitActiveSec == drain.Timer.OnUnitActiveSec;
          assert coordinatorHome.systemd.user.services ? tally-drain;
          # the service calls the lane's verb, and calls it as a pass and not
          # as a probe.
          assert nixpkgs.lib.hasInfix "/research-methods/tools/e1-loop.sh " execStart;
          assert nixpkgs.lib.hasSuffix " --all" execStart;
          assert !(nixpkgs.lib.hasInfix "--dry-run" execStart);
          assert service.Service.Type == "oneshot";
          # and it is a PASS, not a latch: no RemainAfterExit, so every wake
          # actually starts the lane again. (The oracle's transient probe DOES
          # set RemainAfterExit, so its exit status stays readable after it
          # fires; that difference is the probe's, never this unit's.)
          assert !(service.Service ? RemainAfterExit);
          # the non-goals as bytes: it never calls llama-swap, never unloads.
          assert !(nixpkgs.lib.hasInfix "llama" rendered);
          assert !(nixpkgs.lib.hasInfix "9292" rendered);
          assert !(nixpkgs.lib.hasInfix "unload" rendered);
          # no state of its own: the lane's state is the register's git tree.
          assert !(nixpkgs.lib.hasInfix "/.local/state/" rendered);
          assert
            !(builtins.any (
              r: nixpkgs.lib.hasInfix "tally-filler" r
            ) coordinatorHome.systemd.user.tmpfiles.rules);
          # no system-bus twin, and the uplink still carries no schedule.
          assert !(coordinator.systemd.services ? tally-filler);
          assert !(coordinator.systemd.timers ? tally-filler);
          assert !(coordinatorHome.systemd.user.services.tally-uplink ? Install);
          pkgs.runCommand "tally-filler-topology" { } ''
            set -euo pipefail
            # #346: use the rendered service PATH, not the check derivation's
            # nativeBuildInputs. The first python3 the timer can see must own
            # numpy; falling through to Tom's mutable profile is not a unit
            # dependency and is exactly how calibrate failed after verdicts.
            export PATH=${nixpkgs.lib.escapeShellArg fillerPath}
            python3 -c 'import numpy'
            touch "$out"
          '';

        # tally-pump-topology (FIX-E11, dotfiles#350) — the RELEASE STATION's
        # clock: home/tally-pump.nix's user timer and the oneshot tick it wakes.
        #
        # Same reasoning as tally-filler-topology and tally-uplink-topology
        # above: home-manager gives no `assertions` option, so the invariants
        # over the RENDERED units live here, under `nix flake check`, and the
        # unit's own file asserts only literals (a top-level assert that forces
        # `pkgs` dies "infinite recursion encountered" — U-D14's finding).
        #
        # What each assert holds, and why it is load-bearing:
        #   - the pair is DECLARED on the coordinator and NOWHERE ELSE. The
        #     worker holds no seat, no manifest and no lane, so a pump there
        #     would be a second release station racing this one; and the
        #     coordinator-only shape is also the mutation target (drop
        #     ./tally-pump.nix from home/home.nix -> the first assert is false
        #     and this check goes red, exactly as the `nix eval` half does);
        #   - the timer is a five-minute WALL CLOCK schedule pointing at its own
        #     service, armed by timers.target, and explicitly NOT Persistent:
        #     a catch-up burst at switch time would be a burst of ticks each
        #     able to launch paid workers;
        #   - the service calls the lane's verb as `pump.sh --once` — the tick,
        #     never the loop — is a oneshot, and is not a latch (no
        #     RemainAfterExit, so every wake really runs a tick);
        #   - MAXW is set, and set to the value the two typed starts on record
        #     used, because the seat budget and not the machine is the scarce
        #     resource here;
        #   - the tick's PATH carries what the tick actually shells out to
        #     (python3, git, gh) plus the harness profile dir launch.sh execs
        #     `claude`/`codex`/`pi` from;
        #   - the non-goals as bytes: no llama-swap, no :9292, no unload
        #     anywhere in the rendered unit (the release station never touches
        #     the GPU lane), nothing written under ~/.local/state, no tmpfiles
        #     rule of its own, and no system-bus twin.
        tally-pump-topology =
          let
            coordinator = self.nixosConfigurations.coordinator.config;
            coordinatorHome = coordinator.home-manager.users.tom;
            workerHome = self.nixosConfigurations.worker.config.home-manager.users.tom;
            timer = coordinatorHome.systemd.user.timers.tally-pump;
            service = coordinatorHome.systemd.user.services.tally-pump;
            execStart =
              let
                e = service.Service.ExecStart;
              in
              if builtins.isList e then builtins.concatStringsSep " " e else e;
            # Everything the unit says, as one string, so a non-goal cannot be
            # satisfied by a value hiding in Environment or in a redirect.
            rendered =
              execStart
              + " "
              + builtins.concatStringsSep " " service.Service.Environment
              + " "
              + service.Service.StandardOutput
              + " "
              + service.Service.StandardError;
            env = builtins.concatStringsSep " " service.Service.Environment;
          in
          # DECLARED on the coordinator, and nowhere else.
          assert coordinatorHome.systemd.user.timers ? tally-pump;
          assert coordinatorHome.systemd.user.services ? tally-pump;
          assert !(workerHome.systemd.user.timers ? tally-pump);
          assert !(workerHome.systemd.user.services ? tally-pump);
          # the timer: a five-minute wall-clock schedule, its own service,
          # armed by timers.target, and no catch-up backlog.
          assert timer.Timer ? OnCalendar;
          assert timer.Timer.OnCalendar == "*:0/5";
          assert timer.Timer.Unit == "tally-pump.service";
          assert builtins.elem "timers.target" timer.Install.WantedBy;
          assert timer.Timer ? Persistent;
          assert timer.Timer.Persistent == false;
          # the service: the lane's TICK verb, as a oneshot, not a latch.
          assert nixpkgs.lib.hasInfix "/codex-lane/pump.sh " execStart;
          assert nixpkgs.lib.hasSuffix " --once" execStart;
          assert service.Service.Type == "oneshot";
          assert !(service.Service ? RemainAfterExit);
          assert !(service.Service ? Restart);
          # the cap the two typed starts on record used.
          assert nixpkgs.lib.hasInfix "MAXW=2" env;
          # what the tick shells out to, and where the harnesses live.
          # matched on the store-path segment (".../<name>-<version>/bin") and
          # not on "/bin/<name>", which is not what makeBinPath renders.
          assert nixpkgs.lib.hasInfix "-python3-" env;
          assert nixpkgs.lib.hasInfix "-git-" env;
          assert nixpkgs.lib.hasInfix "-gh-" env;
          assert nixpkgs.lib.hasInfix "/etc/profiles/per-user/tom/bin" env;
          # one log for both forms.
          assert nixpkgs.lib.hasInfix "append:" service.Service.StandardOutput;
          assert nixpkgs.lib.hasSuffix "/codex-lane/pump.log" service.Service.StandardOutput;
          assert service.Service.StandardError == service.Service.StandardOutput;
          # the non-goals as bytes: it never touches the GPU lane.
          assert !(nixpkgs.lib.hasInfix "llama" rendered);
          assert !(nixpkgs.lib.hasInfix "9292" rendered);
          assert !(nixpkgs.lib.hasInfix "unload" rendered);
          # no state of its own: the station's state is the lane's own files.
          assert !(nixpkgs.lib.hasInfix "/.local/state/" rendered);
          assert
            !(builtins.any (
              r: nixpkgs.lib.hasInfix "tally-pump" r
            ) coordinatorHome.systemd.user.tmpfiles.rules);
          # no system-bus twin.
          assert !(coordinator.systemd.services ? tally-pump);
          assert !(coordinator.systemd.timers ? tally-pump);
          pkgs.runCommand "tally-pump-topology" { } ''
            touch "$out"
          '';

        omarchy-update-center =
          let
            nas = self.nixosConfigurations.nas.config;
          in
          assert nas.myNas.omarchyUpdateCenter.enable;
          assert nas.myNas.omarchyUpdateCenter.listenAddress == "100.64.0.1";
          assert nas.myNas.omarchyUpdateCenter.port == 8091;
          assert nas.services.headscale.settings.policy.mode == "file";
          pkgs.runCommand "omarchy-update-center-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.openssh
                nas.services.headscale.package
              ];
            }
            ''
              headscale policy check -f ${./hosts/nas/headscale-policy.hujson}
              python ${./tests/omarchy-update-center/policy_test.py} ${./hosts/nas/headscale-policy.hujson}
              mkdir -p hosts/nas tests/omarchy-update-center
              cp ${./hosts/nas/omarchy-update-publish.py} hosts/nas/omarchy-update-publish.py
              cp ${./tests/omarchy-update-center/test_publisher.py} tests/omarchy-update-center/test_publisher.py
              python -m unittest discover -v -s tests/omarchy-update-center
              touch "$out"
            '';

        nas-personal-tailnet =
          (import ./tests/tailscale-personal {
            pkgs = self.nixosConfigurations.nas.pkgs;
          }).check;

        nas-personal-https =
          let
            nas =
              (self.nixosConfigurations.nas.extendModules {
                modules = [
                  {
                    myNas.tailscalePersonal.media.https.enable = true;
                    # Evaluation-only fixture. No certificate request or deployment.
                    age.secrets.nas-cloudflare-dns.file = nixpkgs.lib.mkForce (
                      pkgs.writeText "dns-secret-fixture" "synthetic-not-a-credential"
                    );
                  }
                ];
              }).config;
            cert = nas.security.acme.certs."music.mecattaf.dev";
          in
          assert builtins.all (a: a.assertion) nas.assertions;
          assert cert.dnsProvider == "cloudflare";
          assert cert.extraDomainNames == [ "plex.mecattaf.dev" ];
          assert cert.environmentFile == nas.age.secrets.nas-cloudflare-dns.path;
          assert nas.age.secrets.nas-cloudflare-dns.mode == "0400";
          assert !nas.myNas.headscale.publicEndpoint.enable;
          assert nas.services.headscale.settings.server_url == "https://nas-saas.tail8dd1.ts.net:8443";
          assert nas.myNas.headscale.clientLoginServer == "http://10.42.0.1:8090";
          assert nas.myNas.tailscalePersonal.funnel.enable;
          assert
            nas.services.caddy.virtualHosts."https://music.mecattaf.dev:8443".listenAddresses
            == [ "172.31.255.1" ];
          pkgs.runCommand "nas-personal-https-check" { } ''touch "$out"'';

        headscale-endpoint =
          let
            nas = self.nixosConfigurations.nas.config;
          in
          assert nas.myNas.headscale.clientLoginServer == "http://10.42.0.1:8090";
          pkgs.runCommand "headscale-endpoint-check"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.jq
                pkgs.python3
              ];
              HEADSCALE_ENROLL_SCRIPT = pkgs.writeText "headscale-enroll-script" nas.systemd.services.headscale-nas-enroll.script;
              HEADSCALE_CONNECT_SCRIPT = pkgs.writeText "headscale-connect-script" nas.systemd.services.tailscaled-autoconnect.script;
            }
            ''
              python3 -m unittest discover -s ${./tests/headscale-endpoint} -v
              touch "$out"
            '';

        fleet-identity-backup =
          pkgs.runCommand "fleet-identity-backup-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.openssh
                pkgs.age
              ];
            }
            ''
              mkdir -p hosts/nas tests/fleet-identity-backup
              cp ${./hosts/nas/fleet-identity-backup.py} hosts/nas/fleet-identity-backup.py
              cp ${./tests/fleet-identity-backup/test_backup.py} tests/fleet-identity-backup/test_backup.py
              python -m unittest discover -v -s tests/fleet-identity-backup
              touch "$out"
            '';

        headscale-backup =
          let
            nas = self.nixosConfigurations.nas.config;
          in
          assert nas.myNas.headscale.backup.enable;
          assert nas.systemd.services.headscale-backup.unitConfig.AssertPathIsMountPoint == "/mnt/nas";
          assert nas.systemd.timers.headscale-backup.timerConfig.Persistent == false;
          pkgs.runCommand "headscale-backup-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            mkdir -p hosts/nas tests/headscale-backup
            cp ${./hosts/nas/headscale-backup.py} hosts/nas/headscale-backup.py
            cp ${./tests/headscale-backup/test_backup.py} tests/headscale-backup/test_backup.py
            python -m unittest discover -v -s tests/headscale-backup
            touch "$out"
          '';

        nas-topology =
          let
            nas = self.nixosConfigurations.nas.config;
            coordinator = self.nixosConfigurations.coordinator.config;
            worker = self.nixosConfigurations.worker.config;
          in
          # ── the tailnet sink, on its OWN control plane (2026-09-01) ────────
          # This assertion once read `!nas.services.tailscale.enable` and was
          # left inverted when the ws5 pivot landed — the NAS became the fleet's
          # tailscale SINK and subnet router in commit 33fb9a15 while the check
          # still demanded it have no tailnet identity, so `nix flake check` had
          # been failing here ever since. Corrected with the #229 work in the
          # direction the architecture actually went: the appliance IS the
          # tailnet node and it advertises the house LAN.
          #
          # What changed 2026-09-01 is not WHETHER it has a tailnet but WHOSE:
          # the appliance is now a client of the headscale running on itself
          # (hosts/nas/headscale.nix), and controlplane.tailscale.com no longer
          # holds its node key. The sink asserts below are untouched by that on
          # purpose — routing features and the advertised route are properties of
          # this node's job, not of who issues its netmap.
          assert nas.services.tailscale.enable;
          assert nas.services.tailscale.useRoutingFeatures == "server";
          assert builtins.elem "--advertise-routes=10.42.0.0/24" nas.services.tailscale.extraUpFlags;
          assert builtins.elem "--advertise-routes=10.42.0.0/24" nas.services.tailscale.extraSetFlags;
          # The control plane itself, asserted by SHAPE rather than by URL. The
          # address and port are hosts/nas/headscale.nix's to choose and will
          # change at its phase-2 public-endpoint flip; what must never drift is
          # that SOME --login-server is passed (without it the node silently
          # falls back to tailscale.com, which is a regression to the superseded
          # #233 design and would look perfectly healthy) and that it is not
          # tailscale.com's. --login-server rides extraUpFlags ONLY: `tailscale
          # set` has no such flag, so its appearance in extraSetFlags would fail
          # the packaged tailscaled-set unit on every boot — assert its absence
          # there too, because that failure is a boot-time surprise, not an
          # eval-time one.
          assert builtins.any (nixpkgs.lib.hasPrefix "--login-server=") nas.services.tailscale.extraUpFlags;
          assert !builtins.any (nixpkgs.lib.hasInfix "tailscale.com") nas.services.tailscale.extraUpFlags;
          assert !builtins.any (nixpkgs.lib.hasPrefix "--login-server=") nas.services.tailscale.extraSetFlags;
          # ...and the mirror image on the coordinator, which is the fleet's LAST
          # official tailscale.com node and keeps it as the emergency rail
          # (hosts/coordinator/tailscale.nix). The ABSENCE of --login-server is
          # the entire content of "official tailscale.com", so it is the thing
          # worth pinning: a well-meaning sweep that pointed this box at the
          # NAS's headscale would destroy the rail's whole reason for existing —
          # a fallback that shares a control plane with what it backs up.
          assert coordinator.services.tailscale.enable;
          assert
            !builtins.any (nixpkgs.lib.hasPrefix "--login-server=") coordinator.services.tailscale.extraUpFlags;
          # The worker is the counter-example that keeps the sink meaningful: a
          # LAN compute node reached over ordinary SSH, with no node of its own
          # on EITHER control plane. All three knobs still, but the reason
          # changed on 2026-09-01: the empty flag lists used to be mkForced here
          # against the fleet-wide default in modules/common.nix, and now hold by
          # default because that default is gone. Asserting them is how a
          # re-introduced fleet tailscale tier gets caught.
          assert !worker.services.tailscale.enable;
          assert worker.services.tailscale.extraUpFlags == [ ];
          assert worker.services.tailscale.extraSetFlags == [ ];
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
          # Immich ML MOVED coordinator -> worker 2026-08-21 (#229). The URL, the
          # endpoint, and the name resolution behind it must agree, so all three
          # are asserted together: a repoint without the pin is a black hole, and
          # a pin without the endpoint is a connection refused.
          assert nas.services.immich.environment.IMMICH_MACHINE_LEARNING_URL == "http://worker:3003";
          assert nas.networking.hosts."10.42.0.5" == [ "worker" ];
          assert nas.services.immich.accelerationDevices == [ "/dev/dri/renderD128" ];
          # The stable-pinned NAS must keep running the SAME Immich the
          # unstable-riding coordinator would — the database schema follows
          # unstable (media.nix pulls module+package from inputs.nixpkgs).
          assert nas.services.immich.package.version == coordinator.services.immich.package.version;
          # And since 2026-08-21 the server and its ML backend live on DIFFERENT
          # boxes (#229), so their version coupling is now a cross-host
          # invariant rather than an implicit local one. hosts/worker/immich-ml.nix
          # takes its package from this same option for exactly this assert.
          assert nas.services.immich.package.version == worker.services.immich.package.version;
          assert !coordinator.myCoordinatorMedia.enable;
          assert coordinator.myNasClient.useRemoteStorage;
          assert coordinator.myNasClient.relayMedia;
          assert !coordinator.services.immich.enable;
          assert !coordinator.services.navidrome.enable;
          assert coordinator.fileSystems."/mnt/nas".fsType == "nfs4";
          assert coordinator.systemd.sockets ? immich-relay;
          assert coordinator.systemd.sockets ? navidrome-relay;
          assert coordinator.systemd.sockets ? plex-relay;
          # ML is the one endpoint that is NOT a coordinator relay any more: the
          # socket must exist on the worker and must be GONE from the
          # coordinator. Asserting both directions is deliberate — a half-move
          # that left both boxes listening on :3003 would work by accident and
          # then rot.
          assert worker.systemd.sockets ? immich-ml-access;
          assert !(coordinator.systemd.sockets ? immich-ml-access);
          # ── LAN admission (2026-08-20 rewire; /30 half retired 2026-08-21) ──
          # The enp191s0 half of this block is GONE, as its own instructions
          # said it should be: the /30 cable was unplugged at the TV-corner
          # move and every module-side admission for it was deleted on cutover
          # day. What was NOT deleted was these asserts, which kept naming
          # `coordinator.networking.firewall.interfaces.enp191s0` — an
          # attribute that no longer exists, so the whole check threw. Squared
          # up here with the #229 work. The installer-dnsmasq :67 assert dies
          # with it for the same reason (no cable, no factory boot over it).
          #
          # Failure modes still held off: re-blanket-trusting an interface, and
          # anyone concluding these LAN flows need Tailscale.
          assert !(builtins.elem "wlp192s0" coordinator.networking.firewall.trustedInterfaces);
          assert !(builtins.elem "wlp192s0" worker.networking.firewall.trustedInterfaces);
          # Coordinator LAN doors: the .internal front doors and the LLM
          # endpoint. :3003 is deliberately ABSENT — it left with Immich ML.
          assert builtins.elem 80 coordinator.networking.firewall.interfaces.wlp192s0.allowedTCPPorts;
          # The coordinator serves no model: no inference door on its LAN leg.
          assert !(builtins.elem 9292 coordinator.networking.firewall.interfaces.wlp192s0.allowedTCPPorts);
          assert !(builtins.elem 8731 coordinator.networking.firewall.interfaces.wlp192s0.allowedTCPPorts);
          assert !(builtins.elem 3003 coordinator.networking.firewall.interfaces.wlp192s0.allowedTCPPorts);
          # Worker LAN doors: Immich ML (dialled by nas.services.immich above)
          # and the Halogen API (modules/halogen.nix). Nothing else — and no
          # tailnet to hide behind, which is exactly why these stay
          # interface-scoped rather than global. On enp191s0: the worker is
          # WIRED into the BE550 and has no wifi profile at all.
          assert
            worker.networking.firewall.interfaces.enp191s0.allowedTCPPorts == [
              3003 # immich-ml
              8731 # halogen
            ];
          assert !(worker.networking.firewall.interfaces ? wlp192s0);
          assert !(builtins.elem "enp191s0" worker.networking.firewall.trustedInterfaces);
          # Attic moved to the NAS at ws5 — the coordinator serves no :8080 and
          # every host, worker included, dials http://nas:8080/fleet instead.
          assert builtins.elem "http://nas:8080/fleet" worker.nix.settings.extra-substituters;
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
            builtins.elem
              "9c:bf:0d:01:cc:65,worker,${
                nixpkgs.lib.head (
                  nixpkgs.lib.splitString "/" worker.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.address1
                )
              },infinite"
              nas.services.dnsmasq.settings.dhcp-host;
          assert
            nas.networking.networkmanager.ensureProfiles.profiles.coordinator-fast-lane.ipv4.gateway
            == "10.42.0.3";
          assert !(nas.networking.networkmanager.ensureProfiles.profiles ? freebox-uplink);
          assert !(nas.systemd.services ? wan0-watchdog);
          assert !(nas.systemd.network.links ? "10-wan0");
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
          assert nas.services.resolved.settings.Resolve.DNSStubListenerExtra == [ "100.64.0.1" ];
          assert nas.services.resolved.settings.Resolve.DNS == "127.0.0.1";
          assert nas.services.resolved.settings.Resolve.Domains == "~.";
          assert
            coordinator.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.ipv4.gateway
            == "10.42.0.1";
          assert
            coordinator.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.ipv4.dns == "10.42.0.1";
          assert
            coordinator.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.ipv6.method == "disabled";
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
          #
          # BOTH Strix boxes are checked since 2026-08-21 (#229): the worker is
          # the same silicon with the same mt7925e RZ717, and it is in fact the
          # box where the 6GHz BSSID pin was proven to break activation. Since
          # 2026-09-11 the worker is WIRED and declares no wifi profile at all
          # (asserted below), so the check is vacuous there today — it stays so
          # that a wifi profile re-added to the headless box that cannot report
          # a lockup is held to the same rule as the coordinator's.
          assert nixpkgs.lib.hasInfix "mt7925e disable_aspm=1" coordinator.boot.extraModprobeConfig;
          assert nixpkgs.lib.hasInfix "mt7925e disable_aspm=1" worker.boot.extraModprobeConfig;
          assert
            let
              wifiProfilesArePinnedOrExempt =
                hostConfig:
                let
                  profiles = hostConfig.networking.networkmanager.ensureProfiles.profiles;
                in
                builtins.all (name: (profiles.${name}.wifi ? bssid) || name == "thomas-6ghz") (
                  builtins.filter (name: (profiles.${name}.connection.type or "") == "wifi") (
                    builtins.attrNames profiles
                  )
                );
            in
            builtins.all wifiProfilesArePinnedOrExempt [
              coordinator
              worker
            ];
          # The worker declares NO wifi profile since 2026-09-11: it is wired
          # into the BE550's Ethernet port 2 in another room, and the only
          # profile it ensures is the wired `lan` one. A wifi profile
          # reappearing here would be a silent roam surface on the machine
          # least able to report the resulting lockup — and, with the address
          # static on both, a second holder of 10.42.0.5.
          assert
            builtins.filter (
              name:
              (worker.networking.networkmanager.ensureProfiles.profiles.${name}.connection.type or "") == "wifi"
            ) (builtins.attrNames worker.networking.networkmanager.ensureProfiles.profiles) == [ ];
          assert builtins.attrNames worker.networking.networkmanager.ensureProfiles.profiles == [ "lan" ];
          assert
            worker.networking.networkmanager.ensureProfiles.profiles.lan.connection.interface-name
            == "enp191s0";
          # Static, lease-free LAN identity — the property every cross-host
          # reference to this box depends on (NAS ML URL, NAS journal ACL, the
          # hosts pins). A silent revert to DHCP breaks all three.
          assert
            worker.networking.networkmanager.ensureProfiles.profiles.lan.ipv4 == {
              method = "manual";
              address1 = "10.42.0.5/24";
              gateway = "10.42.0.1";
              dns = "10.42.0.1";
              ignore-auto-dns = true;
            };
          # AdGuard and local host lookups agree on the media front doors.
          # Wildcard rewrites (`*.art.mecattaf.dev`, M-4) cannot appear in
          # /etc/hosts, so they are filtered out of the second test; the first
          # still holds every rewrite, wildcard included, to the NAS address.
          assert builtins.all (
            r: r.answer == "10.42.0.2"
          ) nas.services.adguardhome.settings.filtering.rewrites;
          assert builtins.all (n: builtins.elem n nas.networking.hosts."10.42.0.2") (
            map (r: r.domain) (
              builtins.filter (
                r: !(nixpkgs.lib.hasPrefix "*." r.domain)
              ) nas.services.adguardhome.settings.filtering.rewrites
            )
          );
          # Filtering is centralized on the NAS.
          assert !coordinator.services.adguardhome.enable;
          assert !worker.services.adguardhome.enable;
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
          assert nas.myNas.snapshots.enable; # ws2a hosts/nas/snapshots.nix
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
            nasOff = self.nixosConfigurations.nas.config;
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
          # Enabling Paperless must not CHANGE the NAS's tailnet posture. This
          # read `!nasOn.services.tailscale.enable` until 2026-08-21, expressing
          # the same intent back when the answer was "the NAS has no tailnet at
          # all"; the ws5 pivot made the appliance the fleet's tailscale sink and
          # left this assert unconditionally false, so the gate-then-verify check
          # had been failing. Stated as an equality against the gate-OFF
          # configuration, it now says the thing that was always meant: this gate
          # is orthogonal to the tailnet, whichever way the tailnet is set.
          #
          # That equality form is why the 2026-09-01 control-plane cutover needed
          # no edit here — the appliance moved from tailscale.com to its own
          # headscale, --login-server appeared in extraUpFlags, and both asserts
          # stayed true without being retargeted. Keep it stated this way: an
          # assert that names a specific tailnet posture has now had to be
          # rewritten twice, and this one has survived both pivots.
          assert nasOn.services.tailscale.enable == nasOff.services.tailscale.enable;
          assert nasOn.services.tailscale.extraUpFlags == nasOff.services.tailscale.extraUpFlags;
          # And it must not grow the appliance a secret. This read
          # `!nasOn.mySecrets.enable` until 2026-08-28, encoding the "NO SECRET
          # LIVES ON THIS BOX" ruling — which that ruling's own named door was
          # walked through the same day (hf token for models.nix's library
          # fetch, commit 7f1072e2), leaving this assert unconditionally false
          # exactly like the tailscale one above it before the ws5 restatement.
          # Same cure: state it against the gate-OFF configuration. Paperless
          # must not CHANGE the secrets posture, whatever it is — the flip
          # itself may not be what sneaks a credential onto the appliance.
          assert nasOn.mySecrets.enable == nasOff.mySecrets.enable;
          assert builtins.attrNames nasOn.age.secrets == builtins.attrNames nasOff.age.secrets;
          assert nasOn.services.paperless.database.createLocally;
          pkgs.runCommand "nas-paperless-staged" { } ''
            touch "$out"
          '';

        home-profiles =
          let
            coordinatorHome = self.nixosConfigurations.coordinator.config.home-manager.users.tom;
            workerHome = self.nixosConfigurations.worker.config.home-manager.users.tom;
            clientHome = self.nixosConfigurations.client.config.home-manager.users.tom;
            cfgOf = h: self.nixosConfigurations.${h}.config;
            # Every host whose seat this block adjudicates — named, not
            # discovered, so a fifth host added tomorrow (a seat by default,
            # modules/display.nix) is either listed here on purpose or its
            # absence is visible at eval. The list is the roll call, not a
            # claim that all four have displays: what is asserted per host is
            # the EQUALITY niri == greetd == myDisplay, plus the three
            # topology facts below that never flip.
            displayHosts = [
              "coordinator"
              "client"
              "worker"
              "nas"
            ];
            seatFeederNames = [
              "tally-seat-feeder-claude"
              "tally-seat-feeder-codex"
              "tally-seat-feeder-pi-qwencloud"
            ];
            seatFeederRows = {
              tally-seat-feeder-claude = "cc,cc2,cc3";
              tally-seat-feeder-codex = "codex";
              tally-seat-feeder-pi-qwencloud = "pi-qwencloud";
            };
            isSeatFeeder = name: builtins.match "tally-seat-feeder-.*" name != null;
            coordinatorSeatFeeders = builtins.filter isSeatFeeder (
              builtins.attrNames coordinatorHome.systemd.user.timers
            );
            workerSeatFeeders = builtins.filter isSeatFeeder (
              builtins.attrNames workerHome.systemd.user.timers
            );
            clientSeatFeeders = builtins.filter isSeatFeeder (
              builtins.attrNames clientHome.systemd.user.timers
            );
          in
          assert coordinatorHome.home.username == "tom";
          assert coordinatorHome.programs.atuin.settings.auto_sync;
          assert coordinatorHome.services.tally.enable;
          assert coordinatorHome.programs.voxtype.enable == (cfgOf "coordinator").myDisplay.enable;
          # ONE herdr server, coordinator only (ruling B5), and it must never be
          # tied to the compositor's lifetime (ruling B6) — the PTYs outlive it.
          assert coordinatorHome.systemd.user.services ? herdr;
          assert !(coordinatorHome.systemd.user.services.herdr.Unit ? PartOf);
          assert coordinatorHome.systemd.user.services.herdr.Install.WantedBy == [ "default.target" ];
          # U-D12 / D-B54: exactly three coordinator-only feeder clocks. The
          # enforced freshness arithmetic is period 30 + accuracy 1 + service
          # cap 20 = 51 seconds, strictly inside the kernel's 60-second bound.
          # Rows and duration live on the service as evaluated data so the
          # fixture cannot silently replay a friendlier clock than the estate.
          assert coordinatorSeatFeeders == seatFeederNames;
          assert workerSeatFeeders == [ ];
          assert clientSeatFeeders == [ ];
          assert builtins.all (
            name:
            let
              timer = coordinatorHome.systemd.user.timers.${name};
              service = coordinatorHome.systemd.user.services.${name};
            in
            timer.Timer.OnUnitActiveSec == "30s"
            && timer.Timer.AccuracySec == "1s"
            && timer.Timer.Unit == "${name}.service"
            && timer.Install.WantedBy == [ "timers.target" ]
            && service.Unit.X-TallyRows == seatFeederRows.${name}
            && service.Unit.X-TallyTickSeconds == "60"
            && service.Unit.X-TallyServiceDurationSeconds == "20"
            && service.Service.TimeoutStartSec == "20s"
            # CAP-1: no feeder environment entry may carry whitespace. systemd
            # splits an unquoted `Environment=` value on whitespace into
            # separate assignments, and `TALLY_CLAUDE_SEATS=cc cc2 cc3` was
            # therefore reaching the program as `cc` alone — one Claude row on
            # disk for three seats, MEASURED 2026-09-07 17:0xZ. A list this
            # module writes with a comma cannot be silently truncated again.
            && builtins.all (entry: builtins.match ".*[[:space:]].*" entry == null) service.Service.Environment
          ) seatFeederNames;
          assert builtins.elem "d %h/.local/state/tally-rewrite/meters 0700 - - -"
            coordinatorHome.systemd.user.tmpfiles.rules;
          # `hk` ON PATH (U-D15). home/herdr.nix consumes
          # `inputs.herdr-kitten.packages.<sys>.herdr-kitten` and nothing else —
          # no overlay of the input's own reaches our pkgs fixpoint (F.3) — so
          # the ONLY way the CLI can be in this list is that consumption. This
          # assert is the reason the input pin may never silently go missing:
          # the niri terminal binds, the kitty gestures and the dictation route
          # all shell out to `hk`.
          assert builtins.any (p: nixpkgs.lib.getName p == "herdr-kitten") coordinatorHome.home.packages;
          # …and the kitten half is addressed by STORE PATH out of a neutral
          # ~/.config file, because kitty resolves a bare `kitten foo.py` against
          # ~/.config/kitty, which is a whole-dir out-of-store symlink into the
          # git tree. The generated action_alias must therefore name a
          # /nix/store path ending in the kitten's own entry point; a pin that
          # predates round2-01/03/04 (e.g. 41a6de5) ships a tree kitty cannot
          # load at all, which is why the rev, not just the URL, is asserted
          # material here.
          assert nixpkgs.lib.hasInfix "/share/hk/kitten/hk.py"
            coordinatorHome.xdg.configFile."kitty-herdr-nix.conf".text;
          assert nixpkgs.lib.hasInfix "/nix/store/"
            coordinatorHome.xdg.configFile."kitty-herdr-nix.conf".text;
          # The worker keeps Home Manager (unlike the NAS, which stops at NixOS):
          # it is an ordinary interactive box that merely has nobody sitting at
          # it, so the shell, atuin sync and the user timers are all real. What
          # it must NOT pick up are the things gated on being the coordinator —
          # the Tally daemon, voxtype, and since 2026-09-11 the graphical
          # session itself (no display output on that box: Tom's ruling).
          assert workerHome.home.username == "tom";
          assert workerHome.programs.atuin.settings.auto_sync;
          assert !workerHome.services.tally.enable;
          assert !workerHome.programs.voxtype.enable;
          # …and the herdr SERVER. The worker still gets the herdr binary (it is
          # how `herdr --remote coordinator` works at all), just no unit.
          assert !(workerHome.systemd.user.services ? herdr);
          # The BINARY, though, is the worker's too — the client is how you
          # reach a server at all (`herdr --remote coordinator`), and `hk` rides
          # with it. Asserting it here is what keeps U-D15's pin move from
          # turning into a topology move: one server (ruling B5, #309 is Tom's),
          # two clients, unchanged.
          assert builtins.any (p: nixpkgs.lib.getName p == "herdr-kitten") workerHome.home.packages;
          # No wayvnc on the worker since 2026-09-11: with no display there
          # (hosts/worker/default.nix) home/remote.nix rendered nothing, and
          # since the headless flip later that day the module is gone from
          # the tree: no VNC server anywhere, no session to capture, no door.
          #
          # THE INVARIANT, stated once: VNC, voxtype and piri exist on the
          # coordinator EXACTLY while the coordinator has a display. These are
          # equalities against myDisplay.enable (modules/display.nix), not
          # fixed values, so the headless flip (R-13, plan §8.3, §10 steps
          # 10-11; landed 2026-09-11) did not have to re-key them — but a
          # HALF flip is refused: when hosts/coordinator/default.nix sets
          # myDisplay.enable = false, the same commit must delete the wayvnc
          # unit, the Remmina viewer profile and the :5900 door, or this check
          # does not build. What never flips is the topology: the client is a
          # seat, the worker and the NAS are not — asserted separately below,
          # because a half-move that left a session on the wrong host would
          # look identical from either side alone.
          assert !(workerHome.systemd.user.services ? wayvnc);
          assert (coordinatorHome.systemd.user.services ? wayvnc) == (cfgOf "coordinator").myDisplay.enable;
          assert (coordinatorHome.systemd.user.services ? piri) == (cfgOf "coordinator").myDisplay.enable;
          assert clientHome.systemd.user.services ? piri;
          assert builtins.all (
            h:
            (cfgOf h).programs.niri.enable == (cfgOf h).myDisplay.enable
            && (cfgOf h).services.greetd.enable == (cfgOf h).myDisplay.enable
          ) displayHosts;
          assert (cfgOf "client").myDisplay.enable;
          assert !(cfgOf "worker").myDisplay.enable;
          assert !(cfgOf "nas").myDisplay.enable;
          # The thin client (2026-09-11): Tom's seat, so niri and greetd are
          # ON and the whole coordinator-gated tier is OFF — no tally, no
          # voxtype, no herdr SERVER (the binary and `hk` are here: Mod+Return
          # is a plain `ssh -t coordinator hk-new-inplace` — a NEW herdr
          # workspace on the coordinator, not a second view of its one
          # existing session as the superseded `hk ssh --in-place coordinator`
          # was — asserted below through the generated niri-local.kdl), no
          # wayvnc SERVER (while the coordinator
          # had a display the client VIEWED it through a `coordinator (VNC)`
          # Remmina profile — asserted below as an equality, absent since the
          # 2026-09-11 flip — and no
          # `client (VNC)` profile ever exists on the coordinator, in either
          # direction of the flip), no dcal daemon, no :5900 door, no
          # seat-feeder clocks. Touch is mapped globally to
          # eDP-1 on stock niri (PR #1856 accepted as a defect, no fork).
          assert clientHome.home.username == "tom";
          assert !clientHome.services.tally.enable;
          assert !clientHome.programs.voxtype.enable;
          assert !(clientHome.systemd.user.services ? herdr);
          assert builtins.any (p: nixpkgs.lib.getName p == "herdr-kitten") clientHome.home.packages;
          assert !(clientHome.systemd.user.services ? wayvnc);
          assert !(clientHome.xdg.configFile ? "wayvnc/config");
          assert !(clientHome.systemd.user.services ? dcal-daemon);
          assert coordinatorHome.systemd.user.services ? dcal-daemon;
          # A viewer profile exists exactly while there is a server to view.
          assert
            (clientHome.xdg.dataFile ? "remmina/coordinator.remmina")
            == (cfgOf "coordinator").myDisplay.enable;
          assert !(coordinatorHome.xdg.dataFile ? "remmina/client.remmina");
          assert
            !builtins.elem 5900 (
              self.nixosConfigurations.client.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts
                or [ ]
            );
          assert nixpkgs.lib.hasInfix "map-to-output \"eDP-1\"" clientHome.xdg.configFile."niri-local.kdl".text;
          assert nixpkgs.lib.hasInfix "ssh -t coordinator hk-new-inplace" clientHome.xdg.configFile."niri-local.kdl".text;
          assert !(nixpkgs.lib.hasInfix "hk ssh --in-place coordinator" clientHome.xdg.configFile."niri-local.kdl".text);
          assert nixpkgs.lib.hasInfix "\"ssh\" \"-t\" \"coordinator\" \"hk\" \"resume\"" clientHome.xdg.configFile."niri-local.kdl".text;
          assert !(nixpkgs.lib.hasInfix "binds" coordinatorHome.xdg.configFile."niri-local.kdl".text);
          assert
            !builtins.elem 5900 (
              self.nixosConfigurations.worker.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts
                or [ ]
            );
          assert
            builtins.elem 5900
              self.nixosConfigurations.coordinator.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts
            == (cfgOf "coordinator").myDisplay.enable;
          assert !self.nixosConfigurations.worker.config.services.tailscale.enable;
          pkgs.runCommand "home-profiles" { } ''
            touch "$out"
          '';

        # U-D15 — the herdr-kitten INPUT, end to end. home/herdr.nix emits ONE
        # `action_alias` carrying a store path and kitty spends it as
        # `map <chord> hk <gesture>`; if that path is wrong, or the tree behind
        # it predates round2-01/03/04, every gesture dies inside kitty's own
        # loader with nothing in this repo going red — which is exactly how the
        # BUG-1/BUG-2 class shipped once already. So the alias is parsed back
        # out of the coordinator's own generation here and the file it names is
        # READ in the store. `nix flake check --offline --no-build` gets the
        # eval half (the alias is a store path under THIS input's package and it
        # ends at the kitten's entry point); a full `nix flake check` gets the
        # build half (the entry point and the `hk` CLI are really there).
        herdr-kitten-input =
          let
            lib = nixpkgs.lib;
            herdr-kitten = inputs.herdr-kitten.packages.${system}.herdr-kitten;
            conf =
              self.nixosConfigurations.coordinator.config.home-manager.users.tom.xdg.configFile."kitty-herdr-nix.conf".text;
            aliasLine = lib.findFirst (l: lib.hasPrefix "action_alias hk kitten " l) null (
              lib.splitString "\n" conf
            );
            kittenPath = lib.last (lib.splitString " " aliasLine);
          in
          assert aliasLine != null;
          assert lib.hasPrefix "${herdr-kitten}/" kittenPath;
          assert lib.hasSuffix "/share/hk/kitten/hk.py" kittenPath;
          pkgs.runCommand "herdr-kitten-input" { } ''
            test -f ${herdr-kitten}/share/hk/kitten/hk.py
            test -x ${herdr-kitten}/bin/hk
            touch "$out"
          '';

        # A pane child selected by the kernel OOM killer must not turn into a
        # systemd stop of the Herdr server and every unrelated pane (#352).
        # Keep this separate from the herdr-kitten input check: the policy is
        # ours and remains required across upstream Herdr versions.
        herdr-oom-isolation =
          let
            coordinatorHome = self.nixosConfigurations.coordinator.config.home-manager.users.tom;
            workerHome = self.nixosConfigurations.worker.config.home-manager.users.tom;
            service = coordinatorHome.systemd.user.services.herdr;
          in
          assert service.Service.OOMPolicy == "continue";
          assert !(workerHome.systemd.user.services ? herdr);
          pkgs.runCommand "herdr-oom-isolation" { } ''
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

        # MEM-2 (dotfiles#339): SessionEnd -> the harvest verb. The asserts
        # are EVALUATION-time on purpose — `nix flake check --offline --no-build`
        # evaluates and does not build, so the wiring this unit adds (the hook
        # block, the path it names, the timeout ordering, the delivered file) is
        # checked by the same command the unit's oracle already runs.
        ai-memory-harvest-hook =
          let
            lib = nixpkgs.lib;
            homeConfig = self.nixosConfigurations.coordinator.config.home-manager.users.tom;
            settings = builtins.fromJSON (builtins.readFile ./home/dot_claude/settings.json);
            hookPath = "/home/tom/.claude/hooks/ai-memory-harvest.sh";
            hookText = builtins.readFile ./home/dot_claude/hooks/ai-memory-harvest.sh;
            sessionEnd = settings.hooks.SessionEnd;
            entry = builtins.head (builtins.head sessionEnd).hooks;
            # The script's own timeout must fire BEFORE Claude Code's, so the
            # hook always ends by its own hand and always writes its log line.
            scriptTimeout = 420;
          in
          # Exactly one SessionEnd matcher, carrying exactly one command hook.
          assert builtins.length sessionEnd == 1;
          assert builtins.length (builtins.head sessionEnd).hooks == 1;
          assert entry.type == "command";
          assert entry.command == "bash '${hookPath}'";
          assert entry.timeout > scriptTimeout;
          assert lib.hasInfix "AI_MEMORY_HARVEST_HOOK_TIMEOUT:-${toString scriptTimeout}}" hookText;
          # The hook runs `harvest` and nothing else: the drain verb, the
          # journal and branch (a)'s live state dir are absent from the script.
          assert lib.hasInfix "python3 \"$engine\" \"\${harvest_argv[@]}\"" hookText;
          # FIX-E08 (dotfiles#348): the close -> row -> floor leg is wired. The
          # verb is still `harvest` and the flag is `--enqueue`, so a hook that
          # writes a note but no rows cannot pass evaluation again.
          assert lib.hasInfix "harvest_argv=(harvest)" hookText;
          assert lib.hasInfix "harvest_argv+=(--enqueue)" hookText;
          assert !(lib.hasInfix "$engine\" drain" hookText);
          assert !(lib.hasInfix "state/tally/" hookText);
          # The SessionStart hook is this unit's non-goal and stays as it was.
          assert
            (builtins.head (builtins.head settings.hooks.SessionStart).hooks).command
            == "bash '/home/tom/.claude/hooks/herdr-agent-state.sh' session";
          # The file the block names is actually delivered, as ONE link (not a
          # whole-dir one), so ~/.claude/hooks stays a real directory beside
          # herdr's raw hook, which this repository does not ship.
          assert homeConfig.home.file ? ".claude/hooks/ai-memory-harvest.sh";
          assert
            homeConfig.home.file.".claude/hooks/ai-memory-harvest.sh".target
            == ".claude/hooks/ai-memory-harvest.sh";
          # mkOutOfStoreSymlink names its store entry after the file it points
          # at, so this is the out-of-store link and not a copied-in blob: the
          # hook stays editable in the checkout, like every other raw dotfile.
          assert lib.hasSuffix "-hm_aimemoryharvest.sh" (
            toString homeConfig.home.file.".claude/hooks/ai-memory-harvest.sh".source
          );
          assert !(homeConfig.home.file ? ".claude/hooks");
          pkgs.runCommand "ai-memory-harvest-hook"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              export PYTHONDONTWRITEBYTECODE=1
              export MEM2_HOOK=${./home/dot_claude/hooks/ai-memory-harvest.sh}
              mkdir -p "$HOME"

              bash ${./tests/ai-memory-hook/harvest-hook-test.sh}

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
              export PRINT_AUTO_SCRIPT=${./home/dot_claude/skills/print/scripts/print-auto.py}
              export PRINT_PAPER_SCRIPT=${./home/dot_claude/skills/print/scripts/print-paper.py}
              export PRINT_PAPER_SKILL=${./home/dot_claude/skills/print/SKILL.md}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/print} \
                -p 'test_*.py' \
                -v

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
              export NIGHTLY_RECORD_SCRIPT=${./home/dot_local/bin/nightly-record}
              export NIGHTLY_RECORD_FIXTURES=${./tests/nightly-record/fixtures}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/nightly-record} \
                -p 'test_*.py' \
                -v

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
              export CLAUDE_SESSIONS_SCRIPT=${./home/dot_local/bin/claude-sessions}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/claude-sessions} \
                -p 'test_*.py' \
                -v

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
              export SEATS_SCRIPT=${./home/dot_local/bin/seats}
              mkdir -p "$HOME"

              python3 -m unittest discover \
                -s ${./tests/seats} \
                -p 'test_*.py' \
                -v

              touch "$out"
            '';

        # Model bytes are explicit transactions, never activation work. Drive
        # the evaluated worker borrow binary against tiny fixtures, then keep
        # the guarded prune contract from dotfiles#296. Hermetic: no network,
        # systemd, /var, or production weights.
        local-model-transactions =
          let
            workerConfig = self.nixosConfigurations.worker.config;
            borrowPackage =
              nixpkgs.lib.findFirst (package: nixpkgs.lib.getName package == "local-models-borrow")
                (throw "worker has no explicit local-models-borrow command")
                workerConfig.environment.systemPackages;
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
              # Two exclusions, both narrow and both earned:
              #
              #   go.sum   — base64 hashes, on which a case-insensitive sweep for
              #              three-letter substrings false-positives endlessly.
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
                --glob '!go.sum' --glob '!**/docs/**/*.md' \
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
            worker = self.nixosConfigurations.worker.config;
            client = self.nixosConfigurations.client.config;
            meshRegistry = import ./modules/mesh-registry.nix;
            # `worker` is spelled by concatenation throughout this check for one
            # narrow reason that SURVIVES its reinstatement: the ripgrep sweep at
            # the bottom greps the flake's own source tree, and a literal here
            # would match itself. It is no longer a "retired host" — see below.
            strixWorker = "work" + "er";
            # HALF of Tom's old ruling survives, and the halves are now split
            # (dotfiles#310, dotfiles#291). It used to read: the worker is a
            # HOST again, never a Tally executor AND never a Tally pool.
            #
            #   STILL TRUE, and asserted structurally below: never an EXECUTOR.
            #   All jobs execute locally on the coordinator, home/tally.nix
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
            #   there has a lane to name instead of borrowing the coordinator's
            #   and lying about which device it sat on.
            #
            # A pool row and an executor are different objects; the old guard
            # conflated them because, while the host was retired, no row could
            # be anything but the first step back toward an executor.
            devicePool = strixWorker + "-gpu";
            # The sweep below is now TWO sweeps, because the relaxation Q1 needs
            # is narrower than the file it lands in.
            #
            #   retiredExecutionPattern — the two RETIRED EXECUTOR attribute
            #   names, still banned from home/tally.nix AND flows/. Nothing in
            #   this branch wants either back.
            #
            #   retiredFlowHostPattern — the bare host name, banned from the
            #   CODE under flows/ except in two spellings: the Halogen endpoint
            #   `http://<host>:8731` and the `<host>-gpu` pool. A flow is a
            #   script that ENQUEUES work; a flow naming the other box as a
            #   place to run is the executor half that stayed retired (Q2: one
            #   daemon, on the coordinator). Dialling the box's inference
            #   server over HTTP, or leasing the pool row that describes its
            #   device (home/tally.nix declares it), is neither — every model
            #   call on this fleet lands on the worker now. Prose (README.md)
            #   is not checked. The pool row keeps its own structural
            #   assertion below, which is stronger than a grep over prose.
            retiredExecutionPattern = nixpkgs.lib.concatStringsSep "|" [
              (strixWorker + "Flake")
              (strixWorker + "Models")
            ];
            # The bare name subsumes devicePool ("<host>-gpu"): a flow may name
            # neither.
            retiredFlowHostPattern = strixWorker;
            activeHostSets = [
              (builtins.attrNames self.nixosConfigurations)
              (builtins.attrNames self.deploy.nodes)
              (builtins.attrNames meshRegistry)
            ];
            # Alphabetical, because the three sets are attrNames and the assert
            # below is list EQUALITY: `client` sorts first.
            expectedHosts = [
              "client"
              "coordinator"
              "nas"
              strixWorker
            ];
            retiredAliases = nixpkgs.lib.concatStringsSep "|" [
              (strixWorker + "-tb")
              ("coordinator-" + "tb")
            ];
            removedModel = "qwo" + "pus";
            monthlySources = builtins.fromJSON (builtins.readFile ./pkgs/local-ai-monthly/sources.json);
          in
          # ── the fleet roll call ────────────────────────────────────────────
          # This assertion pair used to demand the worker's ABSENCE from all
          # three registries. It was already failing at HEAD: the 2026-08-21
          # audit added the worker's row to mesh-registry.nix (host key live,
          # user key deliberately empty) without touching this guard, so
          # `nix flake check` had been red here too.
          #
          # Inverted with #229, and deliberately kept as a three-way agreement
          # rather than deleted. The registries drifting apart is the actual
          # failure mode this catches, in either direction: a host in the flake
          # but not in deploy-rs cannot be pushed to in an emergency; a host in
          # the mesh registry but not in the flake is a set of authorized keys
          # for a machine nobody builds. Both happened to this very host.
          assert nixpkgs.lib.all (hosts: nixpkgs.lib.elem strixWorker hosts) activeHostSets;
          assert nixpkgs.lib.all (hosts: hosts == expectedHosts) activeHostSets;
          # Permanence, in config rather than prose (Tom: "not a lease"). The
          # worker's registry row must carry BOTH keys: the host key is agenix's
          # decryption identity and the reason the reintegration is a switch and
          # not a reflash, and the user key must be the SHARED rotated key — the
          # same string the coordinator carries. The old tom@mesh key that left
          # on this device in July must never reappear; any value other than the
          # coordinator's fails here.
          assert meshRegistry.${strixWorker}.hostKey != "";
          assert meshRegistry.${strixWorker}.userKey == meshRegistry.coordinator.userKey;
          assert nixpkgs.lib.hasInfix "tom@mesh-20260729" meshRegistry.${strixWorker}.userKey;
          # Every dialable identity addressable without TOFU — exactly one per
          # twin, the static LAN address; an alias that answers nowhere only
          # buys TOFU prompts.
          assert
            meshRegistry.${strixWorker}.aliases == [
              "worker"
              "10.42.0.5"
            ];
          assert
            meshRegistry.coordinator.aliases == [
              "coordinator"
              "10.42.0.2"
            ];
          # The client (2026-09-11): the fleet host key omarchy-fleet minted on
          # 2026-09-07, REUSED — the return was an in-place switch, and the key
          # is the agenix identity — never the 2026-07-05 `zenbook-duo` key
          # that is public in git history; the shared rotated user key, same
          # string as the twins; the name plus the NAS-pinned lease. Every
          # host that dials `client` answers 10.42.0.16, and the client dials
          # both twins by their static addresses without importing the twins'
          # own hosts module (it keeps its stock loopback self-mapping).
          assert meshRegistry.client.hostKey != "";
          assert !(nixpkgs.lib.hasInfix "QoQJxxP" meshRegistry.client.hostKey);
          assert meshRegistry.client.userKey == meshRegistry.coordinator.userKey;
          assert
            meshRegistry.client.aliases == [
              "client"
              "10.42.0.16"
            ];
          assert coordinator.networking.hosts."10.42.0.16" == [ "client" ];
          assert worker.networking.hosts."10.42.0.16" == [ "client" ];
          assert client.networking.hosts."10.42.0.2" == [ "coordinator" ];
          assert client.networking.hosts."10.42.0.5" == [ strixWorker ];
          assert client.networking.hosts."10.42.0.1" == [ "nas" ];
          assert client.networking.hosts."127.0.0.2" == [ "client" ];
          assert client.networking.hostName == "client";
          # Thin client: no journal upload (hosts/nas/journal.nix admits the
          # twins only), no tailnet join (daemon declared, no key, no
          # autoconnect), no printing queue, agenix on.
          assert !client.services.journald.upload.enable;
          assert client.services.tailscale.enable;
          assert !(client.age.secrets ? tailscale-authkey);
          assert !(client.systemd.services ? tailscaled-autoconnect);
          assert !client.services.printing.enable;
          assert client.mySecrets.enable;
          assert client.services.zenbook-duo-daemon.enable;
          assert self.deploy.nodes.client.hostname == "client";
          assert coordinator.networking.hosts."10.42.0.1" == [ "nas" ];
          assert builtins.elem "coordinator" nas.networking.hosts."10.42.0.2";
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
          assert coordinator.networking.hosts."127.0.0.2" == [ ];
          assert worker.networking.hosts."127.0.0.2" == [ ];
          assert coordinator.networking.hosts."10.42.0.2" == [ "coordinator" ];
          assert coordinator.networking.hosts."10.42.0.5" == [ strixWorker ];
          assert worker.networking.hosts."10.42.0.2" == [ "coordinator" ];
          assert worker.networking.hosts."10.42.0.5" == [ strixWorker ];
          # ...and the NAS keeps the stock mapping, deliberately: it is an
          # appliance, not a rank in a job, and it does not import
          # modules/fleet-hosts.nix.
          assert nas.networking.hosts."127.0.0.2" == [ "nas" ];
          # journald substrate (#135): the NAS receives on the NVMe, and the
          # senders are the STRIX HALO BOXES ONLY (Tom's 2026-08-21 ruling) —
          # the worker joined as the second sender with #229. Each sender keeps
          # its own bounded persistent local journal, which is the half that
          # actually matters in an mt7925e hard lockup: the upload is best-effort
          # and the local ring is the forensic record.
          assert nas.services.journald.remote.enable;
          assert coordinator.services.journald.upload.settings.Upload.URL == "http://10.42.0.1:19532";
          assert coordinator.services.journald.storage == "persistent";
          assert worker.services.journald.upload.enable;
          assert worker.services.journald.upload.settings.Upload.URL == "http://10.42.0.1:19532";
          assert worker.services.journald.storage == "persistent";
          # A sender the receiver does not admit is a silent hole: journald-remote
          # would simply never see it. Assert the NAS's nftables ACL names both.
          assert nixpkgs.lib.hasInfix "ip saddr 10.42.0.2 tcp dport 19532 accept"
            nas.networking.firewall.extraInputRules;
          assert nixpkgs.lib.hasInfix "ip saddr 10.42.0.5 tcp dport 19532 accept"
            nas.networking.firewall.extraInputRules;
          assert self.deploy.nodes.coordinator.hostname == "coordinator";
          assert self.deploy.nodes.nas.hostname == "nas";
          # The worker is dialled by NAME since 2026-09-11 — it resolves to the
          # static LAN address on the coordinator (modules/fleet-hosts.nix),
          # which is the box's only address now. Asserted against the registry
          # so this can never drift into an address that carries no pinned
          # host key.
          assert self.deploy.nodes.${strixWorker}.hostname == strixWorker;
          assert nixpkgs.lib.elem self.deploy.nodes.${strixWorker}.hostname
            meshRegistry.${strixWorker}.aliases;
          # The `worker` -> 10.42.0.5 NAME pin exists on every host that dials
          # it, and every host agrees on the answer: the NAS from
          # hosts/nas/network.nix (its Immich dials http://worker:3003), the
          # twins from modules/fleet-hosts.nix. Host-scoped rather than
          # fleet-wide on purpose — two /etc/hosts lines for one name are
          # ordered by systemd-resolved, not by the file (#277), so each host
          # carries exactly one and modules/common.nix carries none.
          assert nas.networking.hosts."10.42.0.5" == [ strixWorker ];
          assert coordinator.networking.hosts."10.42.0.5" == [ strixWorker ];
          assert worker.networking.hosts."10.42.0.5" == [ strixWorker ];
          assert nixpkgs.lib.elem "AddressFamily=inet" self.deploy.sshOpts;
          # ── the emergency rail (2026-09-01) ────────────────────────────────
          # This box owns its own tailnet since the fleet-wide default in
          # modules/common.nix was retired; the enable assert is NEW and is the
          # half that matters, because `extraUpFlags == [ "--ssh" ]` alone passed
          # happily back when the flags came from the fleet tier and would pass
          # again if the enable were dropped and the flags left behind as inert
          # decoration. Exact list, not `elem`: the flag set is the rail's whole
          # configuration and a silent addition to it is a change of posture.
          assert coordinator.services.tailscale.enable;
          assert coordinator.services.tailscale.extraUpFlags == [ "--ssh" ];
          assert coordinator.services.tailscale.extraSetFlags == [ "--ssh" ];
          # ...and it must actually be able to JOIN unattended, which is the one
          # property an idle fallback cannot prove by being idle. The authkey is
          # wired by modules/secrets.nix's host-gated block, not by hand — assert
          # the wiring rather than the file's existence, so a rename of the
          # ciphertext or a change to that gate surfaces here.
          assert coordinator.age.secrets ? tailscale-authkey;
          assert coordinator.services.tailscale.authKeyFile == coordinator.age.secrets.tailscale-authkey.path;
          # The worker is the counter-example, and since 2026-09-01 the empty
          # flag lists hold BY DEFAULT rather than by mkForce — which is the
          # positive statement that no fleet-wide tailscale tier is back. Keep
          # all three: they are the tripwire on modules/common.nix.
          assert !worker.services.tailscale.enable;
          assert worker.services.tailscale.extraUpFlags == [ ];
          assert worker.services.tailscale.extraSetFlags == [ ];
          # No tailnet means no authkey secret may be declared for this host —
          # the guard added to modules/secrets.nix with #229. A stale key here
          # would silently re-join the box on its next flash.
          assert !(worker.age.secrets ? tailscale-authkey);
          # The NAS keeps a tailnet, on its OWN control plane — see the
          # headscale block in nas-topology for the shape assert.
          assert nas.services.tailscale.enable;
          assert nixpkgs.lib.elem "--advertise-routes=10.42.0.0/24" nas.services.tailscale.extraUpFlags;
          assert !nas.programs.niri.enable;
          assert !nas.services.greetd.enable;
          assert !nas.services.pipewire.enable;
          assert !nas.services.printing.enable;
          # Discovery remains restricted to the wired LAN.
          assert nas.services.avahi.enable;
          assert nas.services.avahi.allowInterfaces == [ "enp1s0" ];
          assert nas.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ 53 ];
          assert !(builtins.hasAttr "home-manager" self.nixosConfigurations.nas.options);
          assert nas.myNas.storage.enable;
          assert nas.myNas.media.enable;
          assert nas.services.immich.enable;
          assert nas.services.navidrome.enable;
          assert !coordinator.myCoordinatorMedia.enable;
          assert coordinator.myNasClient.useRemoteStorage;
          assert coordinator.myNasClient.relayMedia;
          # ML is the one endpoint that is NOT a coordinator relay any more: the
          # socket must exist on the worker and must be GONE from the
          # coordinator. Asserting both directions is deliberate — a half-move
          # that left both boxes listening on :3003 would work by accident and
          # then rot.
          assert worker.systemd.sockets ? immich-ml-access;
          assert !(coordinator.systemd.sockets ? immich-ml-access);
          assert coordinator.systemd.services.tailscaled-autoconnect.serviceConfig.RestartSec == "1min";
          # Distributed builds stay OFF. The worker being back does NOT make it a
          # build farm: the fleet's build story is the NAS update-center (build
          # nightly on the appliance, pull everywhere), which is why
          # hosts/worker/cache-push.nix was dropped rather than restored.
          assert !coordinator.nix.distributedBuilds;
          assert coordinator.nix.buildMachines == [ ];
          assert !worker.nix.distributedBuilds;
          assert worker.nix.buildMachines == [ ];
          assert !(worker.nix.settings ? post-build-hook);
          assert nixpkgs.lib.elem "http://nas:8080/fleet" worker.nix.settings.extra-substituters;
          # Doctrine, 2026-09-10: no model byte transfer may enter update,
          # activation, boot, or service ordering. Both endpoints get one
          # explicit borrow CLI; neither gets a transfer service or timer.
          assert !(worker.systemd.services ? local-models-sync);
          assert !(coordinator.systemd.services ? local-models-sync);
          assert !(worker.systemd.services ? local-models-borrow);
          assert !(coordinator.systemd.services ? local-models-borrow);
          assert !(worker.systemd.timers ? local-models-sync);
          assert !(coordinator.systemd.timers ? local-models-sync);
          assert !(worker.systemd.timers ? local-models-borrow);
          assert !(coordinator.systemd.timers ? local-models-borrow);
          assert
            builtins.length (
              nixpkgs.lib.filter (
                package: nixpkgs.lib.getName package == "local-models-borrow"
              ) worker.environment.systemPackages
            ) == 1;
          assert
            builtins.length (
              nixpkgs.lib.filter (
                package: nixpkgs.lib.getName package == "local-models-borrow"
              ) coordinator.environment.systemPackages
            ) == 1;
          # The Halogen unit orders after nothing model-shaped either: its
          # pre-start CHECKS the bundle and refuses; it never fetches.
          assert
            !(nixpkgs.lib.elem "local-models-sync.service" (
              worker.systemd.services.podman-halogen.after or [ ]
            ));
          assert
            !(nixpkgs.lib.elem "local-models-borrow.service" (
              worker.systemd.services.podman-halogen.after or [ ]
            ));
          # NAS downloads remain a separate timer/operator action, never an
          # update-center or activation dependency.
          assert (nas.systemd.services.library-fetch.wantedBy or [ ]) == [ ];
          # The executor half, still asserted in the NEGATIVE: a host, never a
          # Tally executor. Both directions, because `executors == { }` alone
          # would pass a config that renamed the attribute.
          assert !(builtins.hasAttr strixWorker coordinator.home-manager.users.tom.services.tally.executors);
          assert coordinator.home-manager.users.tom.services.tally.executors == { };
          # The pool half, now asserted in the POSITIVE (Q1; dotfiles#310).
          # Pinning the SHAPE is worth more than pinning the absence: capacity
          # one per device, declared vram — not a budget row, not a mutex, and
          # never given a budgetGb, because a GB budget means nothing until an
          # enqueue states how much VRAM it wants and none of them does.
          assert builtins.hasAttr devicePool coordinator.home-manager.users.tom.services.tally.pools;
          assert coordinator.home-manager.users.tom.services.tally.pools.${devicePool}.resource == "vram";
          assert coordinator.home-manager.users.tom.services.tally.pools.${devicePool}.capacity == 1;
          assert coordinator.home-manager.users.tom.services.tally.pools.${devicePool}.budgetGb == null;
          assert !worker.home-manager.users.tom.services.tally.enable;
          # ...but very much present in the SSH mesh, in both directions. This
          # assertion was the inverse until #229 and was failing at HEAD, since
          # the audit had already added the registry row.
          assert builtins.hasAttr strixWorker coordinator.programs.ssh.knownHosts;
          assert builtins.hasAttr "coordinator" worker.programs.ssh.knownHosts;
          assert nixpkgs.lib.elem meshRegistry.coordinator.userKey
            worker.users.users.tom.openssh.authorizedKeys.keys;
          # myCluster died with the role option; per-host policy in
          # modules/strix.nix is selected by hostname on BOTH Strix boxes now.
          assert !(self.nixosConfigurations.coordinator.options ? myCluster);
          assert !(self.nixosConfigurations.${strixWorker}.options ? myCluster);
          # ── mono-model: the wanted sets, exact ─────────────────────────────
          # Exact lists, not membership tests, so a new hundred-gigabyte row
          # has to be argued for here in writing before it can cost a twin its
          # disk. The worker wants ONE thing, the Halogen bundle it serves; the
          # coordinator wants the small GGUFs an operator serves by hand. There
          # is no `allow` any more: nothing is a deployment, nothing is served
          # by a roster.
          assert !(worker.services.local-models ? allow);
          assert
            worker.services.local-models.artifacts == [
              "halogen-qwen38-flash-next"
              "halogen-qwen38-27b"
            ];
          assert
            coordinator.services.local-models.artifacts == [
              "qwen36-35b-a3b-mtp-ud-q8-k-xl"
              "gemma4-12b-it-q8-0"
              "gemma4-12b-it-mtp-q8-0"
              "fara15-9b-q8-0"
              "fara15-9b-mmproj-bf16"
            ];
          # The catalogue itself: sixteen artifacts and no other top-level
          # attribute — no deployments, no backend kinds, no utility pointer.
          assert builtins.attrNames localModelCatalog == [ "artifacts" ];
          assert
            builtins.attrNames localModelCatalog.artifacts == [
              "fara15-9b-mmproj-bf16"
              "fara15-9b-q8-0"
              "gemma4-12b-it-mtp-q8-0"
              "gemma4-12b-it-q8-0"
              "halogen-qwen38-27b"
              "halogen-qwen38-flash-next"
              "mage-flow-4b-turbo-bf16"
              "mage-flow-edit-4b-turbo-bf16"
              "mage-vl-bf16"
              "qwen3-embedding-8b-q8-0"
              "qwen3-vl-embedding-8b-mmproj-f16"
              "qwen3-vl-embedding-8b-q8-0"
              "qwen36-35b-a3b-mtp-ud-q8-k-xl"
              "vibevoice-asr-bf16"
              "vibevoice-large-bf16"
              "vibevoice-qwen25-7b-tokenizer"
            ];
          assert localModelCatalog.artifacts.halogen-qwen38-flash-next.source.layout == "snapshot";
          assert builtins.length localModelCatalog.artifacts.halogen-qwen38-flash-next.source.files == 9;
          # ── Halogen: one server, on the worker, dialled from the coordinator ─
          assert worker.services.halogen.enable;
          assert !coordinator.services.halogen.enable;
          assert coordinator.services.halogen.client.enable;
          assert !worker.services.halogen.client.enable;
          assert worker.virtualisation.oci-containers.containers ? halogen;
          assert !(coordinator.virtualisation.oci-containers.containers ? halogen);
          assert nixpkgs.lib.hasPrefix "ghcr.io/peonist-ai/halogen-flash-server@sha256:"
            worker.virtualisation.oci-containers.containers.halogen.image;
          assert
            worker.virtualisation.oci-containers.containers.halogen.volumes == [
              "/var/lib/local-models/halogen-qwen38-flash-next:/models:ro"
            ];
          assert
            worker.virtualisation.oci-containers.containers.halogen.environment.HALOGEN_TOKENIZER
            == "/models/tokenizer";
          assert worker.virtualisation.oci-containers.containers.halogen.environment ? HALOGEN_VISION_TOWER;
          # The service never downloads weights (model-byte doctrine).
          assert !(worker.virtualisation.oci-containers.containers.halogen.environment ? HALOGEN_DOWNLOAD);
          assert nixpkgs.lib.all
            (flag: nixpkgs.lib.elem flag worker.virtualisation.oci-containers.containers.halogen.extraOptions)
            [
              "--network=host"
              "--device=/dev/kfd"
              "--device=/dev/dri"
              "--ipc=host"
              "--ulimit=memlock=-1:-1"
            ];
          assert worker.systemd.services.podman-halogen.serviceConfig.TimeoutStartSec == "45min";
          # The alternate 27B engine: declared, never started at boot, and
          # never resident together with Flash (mutual Conflicts=), on the same
          # port so clients need not care which one answers.
          assert builtins.attrNames worker.services.halogen.alternates == [ "qwen38-27b" ];
          assert worker.virtualisation.oci-containers.containers ? halogen-qwen38-27b;
          assert !worker.virtualisation.oci-containers.containers.halogen-qwen38-27b.autoStart;
          assert nixpkgs.lib.hasPrefix "ghcr.io/peonist-ai/halogen@sha256:"
            worker.virtualisation.oci-containers.containers.halogen-qwen38-27b.image;
          assert
            worker.virtualisation.oci-containers.containers.halogen-qwen38-27b.environment.HALOGEN_API_PORT
            == worker.virtualisation.oci-containers.containers.halogen.environment.HALOGEN_API_PORT;
          assert worker.systemd.services.podman-halogen.conflicts == [ "podman-halogen-qwen38-27b.service" ];
          assert worker.systemd.services.podman-halogen-qwen38-27b.conflicts == [ "podman-halogen.service" ];
          assert
            builtins.length (
              nixpkgs.lib.filter (
                package: nixpkgs.lib.getName package == "halogen-switch"
              ) worker.environment.systemPackages
            ) == 1;
          assert nixpkgs.lib.elem "amdgpu.gttsize=126976" worker.boot.kernelParams;
          assert !(nixpkgs.lib.elem "amdgpu.gttsize=126976" coordinator.boot.kernelParams);
          # The utility-model wrapper lives on the coordinator only.
          assert
            builtins.length (
              nixpkgs.lib.filter (
                package: nixpkgs.lib.getName package == "utility-model"
              ) coordinator.environment.systemPackages
            ) == 1;
          assert
            builtins.length (
              nixpkgs.lib.filter (
                package: nixpkgs.lib.getName package == "utility-model"
              ) worker.environment.systemPackages
            ) == 0;
          # llama-swap is gone from every host: no unit, no proxy, no door.
          assert !coordinator.services.llama-swap.enable;
          assert !worker.services.llama-swap.enable;
          assert !(coordinator.systemd.services ? llama-swap);
          assert !(worker.systemd.services ? llama-swap);
          assert !(coordinator.systemd.targets ? flashnext-lane);
          assert !(worker.systemd.targets ? flashnext-lane);
          # AdGuard is FORBIDDEN per-device on this LAN (DoH vs the NAS's
          # dns_hijack). The worker is the box that collision was first proven
          # on, so its closure must not carry the service at all.
          assert !worker.services.adguardhome.enable;
          assert !coordinator.services.adguardhome.enable;
          assert coordinator.microvm.host.enable;
          assert !(self.nixosConfigurations.coordinator.options.myArtifacts ? livePortRange);
          assert !coordinator.home-manager.users.tom.services.tally.pools.coordinator-gpu.hardPreempt;
          # Crash surfacing (#134): the blanket OnFailure handler and both journal watchers exist.
          assert coordinator.systemd.services."failure-notify@".serviceConfig.Type == "oneshot";
          assert coordinator.systemd.timers ? tripwire-coredump;
          assert coordinator.systemd.timers ? tripwire-user-unit-failure;
          assert coordinator.systemd.timers ? failure-marker-reconcile;
          assert monthlySources.inference.provider == "halogen";
          assert monthlySources.inference.url == "http://worker:8731";
          assert monthlySources.inference.compute_host == "worker";
          assert monthlySources.inference.tally_pool == "coordinator-gpu";
          # ── NPU decommission, 2026-08-29 (fleet-7.2) ──────────────────────
          # These used to assert the NPU stack was PRESENT. The house style for
          # a removal is to flip them negative rather than delete them, so the
          # absence is locked in and a silent re-enable is a build failure.
          assert !coordinator.hardware.amd-npu.enable;
          assert !coordinator.hardware.amd-npu.enableNPU;
          assert !worker.hardware.amd-npu.enable;
          assert !worker.hardware.amd-npu.enableNPU;
          assert nixpkgs.lib.elem "amd_iommu=off" coordinator.boot.kernelParams;
          assert !(nixpkgs.lib.elem "amd_iommu=on" coordinator.boot.kernelParams);
          assert nixpkgs.lib.elem "amd_iommu=off" worker.boot.kernelParams;
          assert !(nixpkgs.lib.elem "amd_iommu=on" worker.boot.kernelParams);
          # #244 checklist: sp5100_tco must stay armed through the reboot
          # transition, which is exactly when a wedged box needs it.
          assert nixpkgs.lib.elem "watchdog.stop_on_reboot=0" coordinator.boot.kernelParams;
          assert nixpkgs.lib.elem "watchdog.stop_on_reboot=0" worker.boot.kernelParams;
          # The twins ride linux 7.2 from nixpkgs-fresh (modules/strix.nix).
          # hasPrefix, not equality: the versioned attr advances within 7.2.x.
          assert nixpkgs.lib.hasPrefix "7.2" coordinator.boot.kernelPackages.kernel.version;
          assert nixpkgs.lib.hasPrefix "7.2" worker.boot.kernelPackages.kernel.version;
          # `assert !{coordinator,worker}.services.npu-llm.enable` stood here
          # until 2026-08-31 (#270): with modules/npu-llm.nix deleted the
          # option no longer evaluates, and the absence asserts below are the
          # ones that still bite (they guard the upstream nix-amd-ai module,
          # which keeps shipping fastflowlm/flm machinery we must not enable).
          # The ad-hoc FLM manifest was a product of services.npu-llm; with the
          # module gone the etc entry must not exist at all.
          assert !(coordinator.environment.etc ? "local-models/fastflowlm.json");
          assert !(worker.environment.etc ? "local-models/fastflowlm.json");
          assert nixpkgs.lib.all (unit: !(nixpkgs.lib.hasPrefix "flm-" unit)) (
            builtins.attrNames coordinator.systemd.services
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
              ${./home/tally.nix} ${./flows}; then
              echo "retired Tally executor attribute found" >&2
              exit 1
            fi
            if ${pkgs.ripgrep}/bin/rg --line-number --glob '!README.md' '${retiredFlowHostPattern}' \
              ${./flows} \
              | ${pkgs.ripgrep}/bin/rg --invert-match 'http://${strixWorker}:8731|${strixWorker}-gpu'; then
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
            activeHosts = [
              coordinator
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

      }
      // inputs.deploy-rs.lib.${system}.deployChecks self.deploy;
    };
}
