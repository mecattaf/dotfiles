{ torchRocm, herdr }:
final: _prev: {
  qwentts = final.callPackage ../pkgs/qwentts.nix { };
  speech-session = final.callPackage ../pkgs/speech-session { };
  qwen-speech = final.callPackage ../pkgs/qwen-speech { };
  # Add-only overlay. Everything else is already in nixpkgs and referenced
  # directly.

  # mactahoe — the PROVEN source-build + OLED postPatch (NOT nix-test's prebuilt
  # tarball). Built/verified in a nixos/nix container 2026-06-19. Originated in
  # the mactahoe-oled staging repo (since deleted 2026-07-04); pkgs/ is the home.
  # Icons: stock default (blue folders); GTK: light+dark grey, dark OLED-patched.
  mactahoe-gtk-theme = final.callPackage ../pkgs/mactahoe-gtk-theme.nix { };
  # the same source build recoloured to claude.ai's light/dark tokens, for the
  # theme switcher's claude-dark / claude-light (home/themes/, docs/theme-switcher-2026-09-17.md)
  mactahoe-claude-gtk-theme = final.callPackage ../pkgs/mactahoe-gtk-theme.nix {
    variant = "claude";
  };
  mactahoe-icon-theme = final.callPackage ../pkgs/mactahoe-icon-theme.nix { };

  # Evidence-gated, resumable front door over the music acquisition campaign.
  music-acquire = final.callPackage ../pkgs/music-acquire { };

  # Audit-first prune for /var/lib/local-models (dotfiles#296). Two binaries:
  # a pure oracle the boot-time sync service prints an AUDIT from, and the one
  # verb that deletes — and only when its set matches a recorded dry-run.
  # Packaged rather than inlined in modules/local-models.nix so the hermetic
  # check in flake.nix can build and drive it directly.
  local-models-prune = final.callPackage ../pkgs/local-models-prune.nix { };

  # VibeVoice-ASR-Streaming-7B call transcription. Torch is the gfx1151 ROCm
  # wheel bundle from nix-strix-halo; upstream VibeVoice is pinned by commit, and
  # transformers 4.57.6 / huggingface-hub 0.36.2 come from pinned PyPI wheels
  # because upstream requires transformers < 5 (see pkgs/call-diarize).
  call-diarize = final.callPackage ../pkgs/call-diarize {
    inherit torchRocm;
  };

  # Paper loop (#384): the drop-folder print daemon that owns ~/Paper/intake
  # end to end — render, quiet hours, queue guard, printer-sourced receipts.
  # Replaces paper-intake (paper-print-flush). See home/paper.nix.
  paper-daemon = final.callPackage ../pkgs/paper-daemon { };

  # dsh (DeepSeek Harness) from llm-agents.nix behind the fleet policy: Qwen
  # Cloud as the default, Gufo for local picks, every DeepSeek-bound row off,
  # a hardened bwrap runner. Needs the flake's `llm-agents` overlay. See pkgs/dsh, home/dsh.nix.
  dsh = final.callPackage ../pkgs/dsh { };
  # The plugins of its hand-run `herdr` profile (gated dsh-herdr, herdr-guard,
  # offline jevcore). An attrset, not a package; pkgs/dsh picks them up.
  dsh-plugins = import ../pkgs/dsh-plugins {
    inherit (final) callPackage llm-agents;
    inherit herdr;
  };

  # CLI-Anything — pinned cli-hub Python app plus immutable Codex/Claude
  # integrations. Upstream has no flake; see modules/cli-anything.nix.
  cli-anything-hub = final.callPackage ../pkgs/cli-anything-hub.nix { };

  # fgp-browser: intentionally NOT packaged here — picked up as part of the
  # agency agency browser project (custom Chromium surface). Tracked in issue #45.

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
  browser-desktop = final.callPackage ../pkgs/browser-desktop { };
  # CDP screencast viewer; installed beside browser-desktop, coordinator only.
  chrome-stream = final.callPackage ../pkgs/chrome-stream { };
  keyring-unlock = final.callPackage ../pkgs/keyring-unlock { };

  # Monthly local-AI update bot: deterministic Git/HF preparation, one Pi
  # judgment, deterministic verification/publication. Tally leases only Pi.
  local-ai-monthly = final.callPackage ../pkgs/local-ai-monthly { };

  # Bounded academic OCR appliance: deterministic PDF mechanics, the tally
  # mutation-ladder driver, and canonical/chunk/embed/index receipt stages.
  academic-ocr = final.callPackage ../pkgs/academic-ocr { };

  # fleet-status (#356): the graded per-host collector and the coordinator's
  # bounded fan-out view. Stdlib Python; modules/fleet-status.nix installs it.
  fleet-status = final.callPackage ../pkgs/fleet-status { };

  # Huion Note X10 offline-note extractor over BLE, pinned by commit, thin
  # strokes. Only hosts/client/huion.nix consumes it. See pkgs/huion-notes.nix.
  huion-notes = final.callPackage ../pkgs/huion-notes.nix { };

  # land (CNA-M07): copy-then-verify for preservation packets — manifest,
  # README, sha256 over every row. Used by the nightly ~/today sweep and by
  # every one-time landing lane. Stdlib Python; see pkgs/land.
  land = final.callPackage ../pkgs/land { };

  # pnpm 11.17.0: the stack v1 pin (Tom's ruling G4, 2026-09-29: whatever upstream
  # cloudflare-os used, Node 24 and pnpm 11.17.0). nixpkgs here ships 11.15.0.
  # Used on the substrate puller PATH (modules/substrate.nix puller.extraPath) so
  # a spec-task gate runs bare `pnpm`. Add-only: pkgs.pnpm itself is untouched.
  # The upstream derivation derives its src url from finalAttrs.version, so
  # both are overridden together; the hash is the registry tarball's sha256.
  pnpm_11_17 = final.pnpm.overrideAttrs (_old: {
    version = "11.17.0";
    src = final.fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-11.17.0.tgz";
      hash = "sha256-ZE61B5ZU6H2uWaB+YtfwmBYrnOWPBgdzKLXd78ochUE=";
    };
  });
}
