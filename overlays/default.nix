{ torchRocm }:
final: prev: {
  # Add-only overlay + a single scoped upstream override (niri, below).
  # Everything else is already in nixpkgs and referenced directly.
  # NB: sfmono-liga (pkgs/sfmono-liga.nix) is wired in flake.nix, not here —
  # it needs the sfmono-liga flake input as src, and this file has no inputs.

  # Silence the upstream niri-session deprecation warning that prints (orange) at
  # every session start: "Calling 'import-environment' without a list of variable
  # names is deprecated". It comes from the ONE bare `systemctl --user
  # import-environment` in niri's resources/niri-session; the upstream fix is still
  # unmerged as of jul5 (niri #254/#3572). Redirect just that call's stderr — zero
  # behaviour change, only the deprecation text is dropped. --replace-fail makes a
  # future upstream rename fail the build loudly instead of silently no-op'ing.
  # Flows fleet-wide via programs.niri.package. NB: makes niri a from-source rebuild.
  # This stock+patch niri is what the Strix coordinator runs.
  niri = prev.niri.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace resources/niri-session \
        --replace-fail \
          'systemctl --user import-environment' \
          'systemctl --user import-environment 2>/dev/null'
    '';
  });

  # ── Zenbook Duo dual-touchscreen (PR #1856) — zenbook ONLY ───────────────────
  # Stock niri has NO per-device input config: output_for_touch() takes no device
  # arg, so BOTH ELAN panels map to a single output. niri-wm/niri PR #1856
  # ("Per-device touch and tablet config") adds `touch "<name>" {…}` / `tablet
  # "<name>" {…}` blocks — proven on the Zenbook Duo (incl. NixOS) by its author +
  # others. Not merged upstream (open ~1yr, conflicts with main), so we build from
  # the PR-head fork commit rather than wait. Pinned to a SPECIFIC commit (the
  # branch is a moving target). Per-device blocks are delivered per-host via
  # ~/.config/niri-local.kdl (home.nix) — the shared niri config stays stock-safe.
  #
  # SEPARATE attr (not the fleet `niri`) so it's LAZY: only the zenbook, which sets
  # programs.niri.package = pkgs.niri-pr1856 (hosts/zenbook-duo), builds this fork.
  # The coordinator never evaluates it. Based on `final.niri` so it inherits the
  # niri-session deprecation patch above. Revert: drop the zenbook's package
  # override + the per-host niri-local.kdl once #1856 lands upstream.
  #   PR:   https://github.com/niri-wm/niri/pull/1856  (head 3b75b96, 2026-06-19)
  #   fork: stefanboca/niri   ·   tracking: dotfiles#67
  #
  # cargoHash is captured by buildRustPackage at call time, so overrideAttrs can't
  # change it — override cargoDeps (the fetchCargoVendor FOD) directly. The PR
  # touches only Rust source (no Cargo.lock), but the fork's base ≠ v26.04, so the
  # vendor hash is recomputed for the fork tree.
  niri-pr1856 =
    let
      niriSrc = final.fetchFromGitHub {
        owner = "stefanboca";
        repo = "niri";
        rev = "3b75b9613a762f3022083e74fc47a66b7da79b6e";
        hash = "sha256-CeTJ7Fm6qoTPK+acIrj/fd1bQ7HENHnQo0wKRxezpDE=";
      };
    in
    final.niri.overrideAttrs (_: {
      version = "26.04-pr1856-3b75b96";
      # versionCheckHook asserts `niri --version` contains our version string; the
      # fork binary self-reports its own upstream (25.11.0) version, so skip it.
      doInstallCheck = false;
      src = niriSrc;
      cargoDeps = final.rustPlatform.fetchCargoVendor {
        src = niriSrc;
        hash = "sha256-XbKhPJ/VxcLf4J2I6dekKnUvCnmoXndvQsLx2B04ihE=";
      };
    });

  # mactahoe — the PROVEN source-build + OLED postPatch (NOT nix-test's prebuilt
  # tarball). Built/verified in a nixos/nix container 2026-06-19. Originated in
  # the mactahoe-oled staging repo (since deleted 2026-07-04); pkgs/ is the home.
  # Icons: stock default (blue folders); GTK: light+dark grey, dark OLED-patched.
  mactahoe-gtk-theme = final.callPackage ../pkgs/mactahoe-gtk-theme.nix { };
  mactahoe-icon-theme = final.callPackage ../pkgs/mactahoe-icon-theme.nix { };

  # Backlog.md — markdown-native task manager CLI (`backlog`). Not in nixpkgs;
  # packaged from the upstream release binary (Bun compile). See pkgs/backlog-md.nix.
  backlog-md = final.callPackage ../pkgs/backlog-md.nix { };

  # Personal git-backed CRM CLI, vendored with its package definition.
  crm = final.callPackage ../pkgs/crm/nix/package.nix { };

  # Evidence-gated, resumable front door over the music acquisition campaign.
  music-acquire = final.callPackage ../pkgs/music-acquire { };

  # Headless calendar CLI, vendored with its package definition.
  dcal = final.callPackage ../pkgs/dcal/nix/package.nix { };

  # VibeVoice call transcription. Torch is the gfx1151 ROCm wheel bundle from
  # nix-strix-halo; pure-Python runtime pieces stay on this flake's Python pin.
  call-diarize = final.callPackage ../pkgs/call-diarize {
    inherit torchRocm;
  };

  # cliamp — terminal music player (Winamp-inspired TUI). Not in nixpkgs (2026-07-06).
  # Connects to navidrome via Subsonic API. Config at home/dot_config/cliamp/.
  # CGO on Linux via ebitengine/oto → ALSA. See pkgs/cliamp.nix.
  cliamp = final.callPackage ../pkgs/cliamp.nix { };

  # CLI-Anything — pinned cli-hub Python app plus immutable Codex/Claude/Pi
  # integrations. Upstream has no flake; see modules/cli-anything.nix.
  cli-anything-hub = final.callPackage ../pkgs/cli-anything-hub.nix { };

  # amdtop — AMD GPU/CPU/XDNA NPU monitor. Not yet in our pinned nixpkgs;
  # source-built from the latest stable upstream release for the coordinator.
  amdtop = final.callPackage ../pkgs/amdtop.nix { };

  # llama-swap — nixos-unstable is still on v224; pin the current official v240
  # static release while retaining nixpkgs' first-class services.llama-swap module.
  llama-swap = final.callPackage ../pkgs/llama-swap.nix { };

  # fgp-browser: intentionally NOT packaged here — picked up as part of the
  # agency agency browser project (custom Chromium surface). Tracked in issue #45.
  # gws ships as a home package + agenix credentials, with no overlay.

  # Hugging Face Hub CLI — the Python package comes from the locked nixpkgs
  # input; this wrapper reads the coordinator's agenix token only at runtime.
  huggingface-cli = final.callPackage ../pkgs/huggingface-cli.nix { };

  # Direct Brother JetDirect path for trivial text. CUPS remains the rendered
  # document path; modules/printing.nix installs this only on the active fleet.
  brother-print-text = final.callPackage ../pkgs/brother-print-text.nix { };

  # Artifact system toolchain (sovereign replacement for claude.ai Artifacts;
  # skills: md-artifact / presentation-beta / publish-artifact). Identity knobs
  # come from modules/artifacts-defaults.nix — the one edit point — passed in
  # here because an overlay can't read NixOS `config`.
  artifact-render = final.callPackage ../pkgs/artifact-render { };
  artifact-view = final.callPackage ../pkgs/artifact-view.nix {
    inherit (import ../modules/artifacts-defaults.nix) namespace;
  };
  artifact-deck = final.callPackage ../pkgs/artifact-deck { };

  # One immutable provider source is shared by interactive Pi and the monthly
  # appliance. Explicit `-e` loading needs no npm install or mutable Pi state.
  pi-llama-swap-extension = final.fetchFromGitHub {
    owner = "danielmeneses";
    repo = "pi-llama-swap";
    rev = "915861a1fc2dfd01991720d1c8854bc974cb5322"; # v0.1.1
    hash = "sha256-z0KJYGrl5QF+IRdTXQv1mS/v4XC/XdslEjJ2WI2Xmyk=";
  };

  # Monthly local-AI update bot: deterministic Git/HF preparation, one Pi
  # judgment, deterministic verification/publication. Tally leases only Pi.
  local-ai-monthly = final.callPackage ../pkgs/local-ai-monthly { };

  # Bounded academic OCR appliance: deterministic PDF mechanics, the tally
  # mutation-ladder driver, and canonical/chunk/embed/index receipt stages.
  academic-ocr = final.callPackage ../pkgs/academic-ocr { };

  # Reference CLI for Microsoft's Fara1.5 computer-use-agent models. Not in
  # nixpkgs; upstream ships no release tags, so this pins the exact commit
  # cloned 2026-08-03. See pkgs/fara-cli.nix.
  fara-cli = final.callPackage ../pkgs/fara-cli.nix { };
}
