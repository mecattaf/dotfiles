# Nix build — handoff (2026-06-20)

Pick-up point for the Fedora→NixOS migration build. Backlog: **TASK-21 / TASK-21.1**
(`~/mecattaf/notes/backlog`). Decisions system-of-record: `~/mecattaf/nix-decisions.md`.

## TL;DR
The deliberate migration is **built through Layer 1, validated, and pushed**. The real
source of truth is now the **`nix` branch of `github.com/mecattaf/dotfiles`** —
**`nix-test` is reference-only and superseded.** Next action is a human flashing the
**Asus Zenbook Duo** from `dotfiles/docs/zenbook-duo-flash.md`.

## The real source of truth (IMPORTANT)
- ✅ **`mecattaf/dotfiles` branch `nix`** — the deliberate, evaluated, item-by-item build.
- ❌ **`mecattaf/nix-test`** — the earlier autonomous/blind attempt. Reference only
  (mined into `~/mecattaf/nix-test-compare.md`). Do NOT build on it.
- `dotfiles` `main` stays **chezmoi** untouched until the `nix` branch is fully validated
  on real hardware; only then does it become `main` (and chezmoi → a `chezmoi` branch).

## What was built (all committed + pushed to `origin/nix`)
- **Layer 0** — `flake.nix` (nixpkgs unstable, home-manager, nixos-hardware; pinned
  `flake.lock`), `modules/common.nix` (device-agnostic), `modules/strix.nix`
  (`myCluster.role = coordinator|worker` + Strix-Halo kernel tuning), 4 hosts
  **`coordinator` / `worker` / `dell-xps` / `zenbook-duo`** (+ placeholder `hardware.nix`),
  add-only overlay, self-validating `deadnix` check. (`sodimo`/`companion` are dead names.)
- **mactahoe** overlay — the proven source-build + OLED postPatch (from `mactahoe-oled/`).
- **home-manager bridge** — RAW out-of-store config symlinks (niri/kitty/fish/…), the
  harness-sweep package inventory, the `python3.withPackages` niri-script bundle, `git`
  (typed), mactahoe theming, **11 Chrome PWA launchers** (flatpak→`google-chrome`).
- **nvim** (full `nvim-sweep.md`) — `programs.neovim` + nixpkgs tools replacing mason
  (`marksman` …), **lazy-nix-helper** store-resolution with a fail-closed assertion,
  treesitter `withPlugins`, 3 source-built plugins with **real pinned hashes**
  (lazy-nix-helper, leap codeberg fork, pipeline.nvim).
- **worker remote access** — Sunshine/Moonlight dropped (2026-07-05) for **wayvnc +
  Remmina** on mainline niri; see `remote-access-mesh.md`.
- **Duo flash runbook** — `dotfiles/docs/zenbook-duo-flash.md`.

## Validation performed (in a disposable `nixos/nix` podman container; harness host has NO Nix)
- **home generation BUILDS** (neovim 0.12.3, all plugins incl. the 3 source-built, mactahoe,
  full closure incl. mermaid-cli/chromium).
- **`zenbook-duo` system toplevel dry-run: realizable** (whole closure substitutable).
- **`nix flake check`: all pass**; **deadnix clean**; **statix** run; **nixfmt** applied.

## NEXT — flash the Zenbook Duo (the testing step)
Per `docs/zenbook-duo-flash.md`. Recommended flow (**Option B: puppeteer from harness**):
1. Write the **NixOS minimal ISO** to a USB; boot the Duo from it.
2. **One command at the Duo console** (unavoidable): bring up network (USB-C ethernet
   easiest; wifi via `iwctl`), `passwd` (or paste your SSH key), `systemctl start sshd`,
   `ip -brief addr`.
3. From harness: `ssh root@<duo-ip>` → partition → **regenerate
   `hosts/zenbook-duo/hardware.nix` on the machine** → clone the repo to
   `/home/tom/mecattaf/dotfiles` → `nixos-install --flake …#zenbook-duo`.
4. Reboot → greetd → niri with the full env.
- **Upgrade later (repeatable re-flashes):** add `hosts/zenbook-duo/disko.nix` + use
  **`nixos-anywhere`** (one command from harness). Disko was deliberately deferred; pull it
  forward once the manual install proves the flake.

## Not 100% — flagged, with why
1. **Full Duo *system* build only dry-run** (not fully downloaded/built in-container) — heavy
   closure; realizable + cached, builds at install. Low risk.
2. **`hardware.nix` is a placeholder** — must regenerate on the real Duo (runbook step 5);
   can't know real disk UUIDs without the machine.
3. **nvim runtime unproven** — everything *builds*; lazy-nix-helper store-resolution,
   treesitter highlighting, kitty-scrollback, image/mermaid rendering aren't *runtime*-
   confirmed (no nvim run in-container). Fail-closed assertion catches resolution misses.
4. **mactahoe theme dir-names** ("MacTahoe-grey-dark") best-guess — verify on first boot.
5. **`<leader>kg` lazygit via kitty-daemon** — used the systemic PATH fix, not the
   absolute-path mappings.lua templating. Verify on first boot; low risk.
6. **`~/.env` secrets** — bashrc sources it; harmless warning until the secrets session.
7. **wayvnc on worker (headless)** — declarative EDID injection + autologin
   (`hosts/worker/headless-display.nix`); verify the connector name on first boot.

## Deferred — own sessions / post-boot (tracked, NOT dropped)
secrets (sops/`~/.env`) · agent stack (pi.nix/llm-agents → claude/pi config) · asr-rs v2 ·
`skills/` · niri-flake + typed niri nixification · coordinator NEW work (router/NAS/
quadlets/Thunderbolt cluster) · disko + secure-boot (lanzaboote/TPM) · gws · fgp-browser ·
NAS share name (`/G`) · `HSA_OVERRIDE_GFX_VERSION` (follow the AMD-Strix-Halo nix repo).

## Cleanup
Disposable eval container still on harness: `podman rm -f nix-eval` when done.

## Pointers
`nix-decisions.md` (system of record) · `harness-sweep.md` · `dotfiles-sweep.md` ·
`nvim-sweep.md` · `nix-test-compare.md` · `remote-access-mesh.md` ·
`nix-ouverture.md` · `dotfiles/docs/zenbook-duo-flash.md`.
