{ torchRocm }:
final: prev: {
  # Add-only overlay + a single scoped upstream override (niri, below).
  # Everything else is already in nixpkgs and referenced directly.

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

  # Paper-loop print outbox: the quiet-hours flusher that drains
  # ~/Paper/outbox to CUPS at 06:05. Attribute name is historical (see git
  # history); the only binary is paper-print-flush. See home/paper.nix.
  paper-intake = final.callPackage ../pkgs/paper-intake { };

  # cliamp — terminal music player (Winamp-inspired TUI). Not in nixpkgs (2026-07-06).
  # Connects to navidrome via Subsonic API. Config at home/dot_config/cliamp/.
  # CGO on Linux via ebitengine/oto → ALSA. See pkgs/cliamp.nix.
  cliamp = final.callPackage ../pkgs/cliamp.nix { };

  # CLI-Anything — pinned cli-hub Python app plus immutable Codex/Claude/Pi
  # integrations. Upstream has no flake; see modules/cli-anything.nix.
  cli-anything-hub = final.callPackage ../pkgs/cli-anything-hub.nix { };

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
