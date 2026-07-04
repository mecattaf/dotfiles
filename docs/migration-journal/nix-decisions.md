# Nix transition — decisions (system of record)

The one place to return to. Every deliberate call about moving
`harness` + `harnessRPM` + `dotfiles` (+ skills) into one Nix setup lands here.

**Final home of the real config:** the `dotfiles` repo.
**`nix-test`:** throwaway reference only (top-down, authored blind, never
evaluated — keep for its audits/decisions, don't build on it).

Legend: ✅ decided & proven (built/tested) · ☑️ decided · 🤔 leaning, needs my
ratification · ❌ dropped (reductive) · ⏳ open question

---

## Current status — RESUME HERE (updated 2026-06-20)

Sweep progress (human-driven, item-by-item; mactahoe was the proof loop):
- ✅ **harness** swept → `harness-sweep.md` (system layer fully dispositioned).
- ✅ **harnessRPM** collapsed → ledger below (open: gws, fgp-browser).
- ☑️ **dotfiles** swept (3-agent) → `dotfiles-sweep.md`. Clear calls recorded;
  open items **resolved 2026-06-20:**
  - ✅ **niri → RAW for now** (home-manager `mkOutOfStoreSymlink`, hot-reload).
    *Could change to typed `programs.niri.settings` later* — annotated as a
    candidate, not committed. **Supersedes** the harness-sweep "typed" ratification.
  - ✅ **D2 qs ipc scripts → native re-point, NO rofi.** brightness→brightnessctl,
    media→playerctl, wallpaper→swaybg. **launcher + every rofi-dependent script
    (dms-launcher, spotlight, …) LEFT DEAD — no rofi wanted.** bar/panel/
    notification scripts dropped (bar-less).
  - ☑️ **D4 `~/.env` secrets → intentionally deferred** to the sops layer (later
    phase); explicitly out of the dotfiles sweep.
  - ✅ **nvim → Nix** dedicated session **DONE → `nvim-sweep.md`** (high-scrutiny
    multi-agent plan: 27 findings, 18 fixed; keeps lazy.nvim, zero functionality
    loss; lazy-nix-helper + mason→Nix + tree-sitter pre-seed). Plan only — not built.
- ✅ **BUILT 2026-06-20 — Layer 0 + Layer 1 done, validated, PUSHED to `origin/nix`.**
  flake (4 hosts) + common/strix modules + mactahoe overlay + home-manager bridge +
  nvim (full nvim-sweep, lazy-nix-helper, real pinned hashes) + worker sunshine +
  Duo flash runbook (`dotfiles/docs/zenbook-duo-flash.md`). Validated in a disposable
  `nixos/nix` container (harness host untouched, no Nix on it): **home generation
  BUILDS**, zenbook-duo toplevel **dry-run realizable**, `nix flake check` all-pass,
  deadnix clean, nixfmt applied. `main` (chezmoi) untouched.
- ⏭️ **NEXT (manual, on the Duo):** follow `docs/zenbook-duo-flash.md` — make the USB,
  boot, partition, **regenerate `hosts/zenbook-duo/hardware.nix` on the machine**,
  `nixos-install --flake …#zenbook-duo`. Then post-boot sessions: secrets, agent stack
  (pi.nix/llm-agents), niri nixification, coordinator router/NAS/quadlets, `skills/`.

🔄 **ASR correction (2026-06-20):** no more WhisperLiveKit. asr-rs **v2 = single
Rust binary** (parakeet model, WIP). Drop the WLK quadlet; nix-test's
"WLK-containerized + asr-rs-native" split is obsolete. **asr-rs v2 is NOT in the
first push** (still being built).

Nothing is built yet beyond mactahoe (Nix not installed on the host).

---

## Guiding principle + session-2 refinements (ratified 2026-06-20)

### THE governing principle (overrides convenience everywhere)
- **Maximal nix-native is the committed end-state.** Whatever the most nix-native
  (nix default) format is for a thing, that is where it must land *eventually*.
- **RAW / `mkOutOfStoreSymlink` / hand-rolled / interim re-points are TEMPORARY
  scaffolding** — only to reach a first successful boot. **Do NOT overbuild around
  the current shape**; do not invest in the scaffolding as if it's the end-state.
- **Build gate:** **nothing gets built until Nix is flashed on ALL my devices.**
  The milestone that opens the deepening-nixification phase is a **first successful
  boot on a fresh Asus Zenbook Duo (2024)**. Until then: scope, don't build.
- Anything kept "RAW for now" (niri, bin scripts, configs) carries this caveat:
  it is interim, slated for the nix-native rung post-first-boot.

### Refinements recorded this session
- 🚫 **Naming (final):** AMD pair = **`coordinator`** (main) + **`worker`**
  (secondary compute). **Neither `companion` nor `sodimo` ever appears in nix
  config** — both are dead names. (See fleet list above.)
- ⏳ **bin/ scripts → eventual nix-native** (e.g. `writeShellApplication` with
  declared deps), NOT a permanent whole-dir RAW symlink. RAW only as interim.
- ☑️ **Claude Code config → via the AI-agent nix flake** (llm-agents.nix / the
  agent-harness flake), **not hand-rolled** copy-activation — unless that flake has
  no mechanism for settings/skills, in which case revisit. Pi config likewise via
  **pi.nix** (`programs.pi.coding-agent`) + whatever configures extra pi-agent bits.
- 🤔 **Secrets = own dedicated session** (mechanism undecided; edit identity =
  personal age key; **scope MAXIMAL — all keys**; no impermanence). See secrets row.
- ⏳ **pipx replacement = the nix-native Python story** (I still need Python on the
  box). Direction: `python3.withPackages` for declared libs (backs the niri helper
  scripts) + `uv`/`uvx` for ephemeral tools + per-repo devshells for project work.
  Settle the exact shape; pipx itself stays dropped.
- ⏳ **Local-LLM serving mechanism = TBD via testing.** Models may run as **podman
  quadlets** rather than raw llama.cpp; **llama-swap** can be native. Decide by
  benchmarking on the real Strix Halo boxes. (ds4 is already quadlet-based.)
- 🔬 **`HSA_OVERRIDE_GFX_VERSION` (gfx1151) → follow the dedicated AMD-Strix-Halo
  nix repo's CURRENT value** (want the latest). NOT guesswork, NOT the stale
  `11.0.0` — track that repo's recommendation. (nix-test referenced
  hellas-ai/nix-strix-halo; confirm the canonical repo + value at build time.)
- ✅ **nvim → keep lazy.nvim; ZERO functionality loss** — DONE → **`nvim-sweep.md`**
  (the most nix-native way: `programs.neovim` binary + lazy-nix-helper store-resolution
  + Nix-provided LSPs/tools, mason→Nix, tree-sitter pre-seed). Adversarially scrutinized.
- 📉 **CI shape (nix-test's) = "B-minus" baseline.** Keep the realised host-matrix +
  free-runner-disk + weekly lock-bump, but it needs work — the obvious gaps:
  **binary-cache push** (Attic/Cachix) and a **`nix-update`** job for pinned release
  versions (lock-bump alone doesn't move them).
- ⏸️ **fgp-browser = conceptual inspiration only**, NOT committed; will explore
  alternatives later. (Its CDP_URL idea is the keeper, not the package/patch.)
- ⏸️ **gws / NAS-share-name (`/G` vs `/LaCie`) → keep placeholder, fix once the
  machine is underway.** Both small, **non-blocking** for the Zenbook-Duo flash test.

## Method (how we make each call)

- **Reductive, not additive.** Find a project I like → run it through my
  constraints → keep the load-bearing bit → smallest reproducible Nix shape.
  The best migration of a thing is often *not having it*.
- **The nixpill ladder** — every item gets a rung, chosen deliberately:
  1. place raw file via home-manager (lazy, hot-editable)
  2. typed/validated module (e.g. `programs.niri.settings`)
  3. overlay / build-from-source + patch (e.g. mactahoe)
  4. flake-module + systemd unit (my own tools; the microvm.nix shape)
  5. leave mutable, let the tool's own manager handle it (lazy.nvim, `pi install`)
- **Human-driven, item-by-item, each proven.** I make the call; it gets built
  (container-tested like mactahoe) before it counts as decided. This is the
  opposite of nix-test's one-shot agent migration.

## The three buckets (what the transition actually is)

- **GONE** — just delete; the only work is confidence. (flatpak, brew, chezmoi,
  mkosi/bootc/ostree, quickshell.)
- **SAME** — mechanical port chezmoi→home-manager. (packages, niri/kitty/fish.)
- **NEW** — the real project; Fedora couldn't do these. (secrets, per-device,
  my own flake-modules.) ← where the deliberate discussion lives.

---

## Decisions so far

### GONE (reductive deletions)
- ❌ **flatpak** — use `google-chrome` from nixpkgs (unfree). No `nix-flatpak`
  input, no flathub remote, no preinstall set. (Re-add only if a degoogled
  browser or OBS plugins ever need flatpak's update latency.)
- ❌ **brew** — not used; nix devshells cover per-repo toolchains.
- ❌ **chezmoi** — replaced by home-manager.
- ❌ **mkosi / bootc / ostree / rechunk / cosign** — the whole image pipeline.
- ❌ **quickshell / quickshellX** — shell not used; already dropped in harness.

### NEW (the Nix-native unlocks)
- 🤔 **Secrets — partially decided, TOOL open (own session).** Confirmed:
  **edit identity = a personal age key** (on my laptop, e.g. `ssh-to-age` of my
  user SSH key) — **no YubiKey**; SSH-host-key decryption model leaning; zero
  shared secret in git. **NOT yet decided:** the mechanism itself (sops-nix vs
  alternative) — **dedicated session; I need to understand the options first.**
  - ⭐ **Scope = MAXIMAL — ALL secrets live here:** pi · claude-code · gcloud ·
    gh **and** wifi PSK · tailscale authkey · immich-db · cloudflare-tunnel. Not a
    minimal wifi/tailscale set — the agent-harness keys belong here too, so the
    harness is reproducible across all devices.
  - ❌ Drop the YubiKey machinery nix-test/harness assumed: `age-plugin-yubikey`,
    `pam_yubico`/`security.pam.u2f`, pcscd-for-YubiKey, yubikey-manager.
  - ❌ **No impermanence** (no benefit to me) — so the "/etc/ssh must persist"
    erase-your-darlings caveat is moot.
- ☑️ **Per-device = one flake, `modules/common.nix` + `hosts/<device>/` +
  `nixos-hardware`.** Fleet:
  - `zenbook-duo` — Intel **Meteor Lake**, dual-screen (panel/rotation/dock) ← bespoke
  - `dell-xps` — Intel XPS 13 9315 (dev laptop)
  - **`coordinator`** — AMD **Strix Halo** (gfx1151), the **main** device:
    NAS/LAN-router/quadlets host
  - **`worker`** — AMD Strix Halo, the **secondary** device: specific compute (headless)
  - 🚫 **HARD NAMING RULE (final — this terminology is used forever):** the AMD
    Strix Halo pair is **`coordinator`** (main) and **`worker`** (specific compute)
    — that's it. Matches the ds4 coordinator/worker terms. **The names `companion`
    AND `sodimo` NEVER appear in any nix config, ever** — both are dead. (The box
    the ds4 postmortem calls `sodimo`/`companion` = `worker`; the former
    `harness`/`server` box = `coordinator`.)
  - `hardware.nix` must be generated on each real machine (placeholders today).
  - **AMD-Strix cluster (`coordinator` + `worker`):** Thunderbolt direct link — static
    `thunderbolt0` IPs 10.77.0.1 (coordinator) / .2 (worker) (persistent NM profile) + `networking.hosts`
    + `firewall.trustedInterfaces=["thunderbolt0"]` on **both** + bolt auto-auth;
    ds4/LLM as quadlet-nix. The headless-worker access saga collapses: declarative
    `authorized_keys` + secrets from first boot.
  - **Declarative-runtime insight:** harness's empty `firewalld/zones` &
    `system-connections` dirs = runtime state (`firewall-cmd`/`nmcli`) never
    committed → NixOS makes them declarative. This is the migration's whole point.
- ☑️ **My own tools become flake-modules** (microvm.nix shape: module + systemd
  user service + CLI on PATH). Candidates: **kmux/kerdr**, **asr-rs** user
  service, **microvm** sandbox. The only legitimately *additive* work — it's mine.
  Not yet written out.

### Packages / tools (nixpill rung per item)
- ✅ **mactahoe GTK theme + icons** — rung 3, build-from-source + OLED postPatch.
  Built & verified in a nixos/nix container. Lives at `~/mecattaf/mactahoe-oled/`.
  (Found: grey + solid are stock flags; only OLED-black is custom; icons 100%
  stock vinceliuice.)
- ✅ **nvim** — keep lazy.nvim, add **lazy-nix-helper.nvim**; Nix provides the
  nvim binary + LSPs/formatters, lazy manages plugins. Rung 5+2. Skip nixvim/nvf.
  **Full migration plan: `nvim-sweep.md`** (binary via `programs.neovim`, explicit
  store-path plugin map, mason→`pkgs.marksman`, treesitter `withPlugins`).
- ☑️ **pi coding agent** — **lukasl-dev/pi.nix** config module
  (`programs.pi.coding-agent`); skills/extensions/themes as paths; keys via sops.
- ☑️ **agent binaries** (claude-code, codex, pi, …) — **numtide/llm-agents.nix**
  (daily-updated, cached). Also a prior-art catalog for kmux.
- ☑️ **shpool** — keep, for remote session persistence (one PTY, kitty-native).
- ✅ **niri → RAW for now** (rung 1: raw KDL via home-manager
  `mkOutOfStoreSymlink`, keeps hot-reload). Ratified 2026-06-20 in the dotfiles
  sweep; all 9 `*.kdl` carry a `// NIX-MIGRATION:` note marking typed
  `programs.niri.settings` (rung 2) as a *later candidate*, not committed.
  Resolves the earlier RAW-vs-typed split; **overrides** the harness-sweep typed call.
  **RAW is explicitly temporary scaffolding** — after a first successful boot,
  niri gets nixified (typed) **together with adding niri-flake**, as one bundled
  post-first-boot effort. (The `local.kdl` per-machine-override trick survives
  only if it stays nix-native — no contortions.)
- 🤔 **kmux/kerdr** — personal flake-module: daemon (session/pane data model +
  delta stream) + thin CLI; delegate persistence→shpool, render→kitty,
  sidebar→CEF. Scope held to "one model + deltas + CLI." Design done in
  june18; not built.

### Project-level
- ☑️ **nixpkgs channel:** unstable (Strix Halo wants fresh kernels); revisit later.
- ☑️ **Delivery:** CI builds → binary cache (Cachix/Attic) → devices substitute.
  (Same shape as COPR→bootc, content-addressed. Keeps per-update build time ~0.)
- ☑️ **Bottom-up layer order:** install Nix (Determinate) → home-manager bridge
  → packages → NixOS host on real hardware → disko/secrets/secure-boot last.

### Harness layer — ratified (full detail in `harness-sweep.md`)
- ⚠️ niri rung: harness-sweep originally ratified typed `programs.niri.settings`,
  but the dotfiles sweep (2026-06-20) **superseded this → RAW for now** (hot-reload
  wins; typed kept as a later candidate). See the niri row under Packages/tools.
- Bar-less + notification-less (own shell later). Drop fcitx5/ibus, all
  YubiKey/smartcard bits, just/hjust/gum, iio-niri, valent, kf6-*, ramalama,
  antigravity, VM guest agents.
- Keep podman+quadlets, gcloud, gh, cloudflared, tailscale, cifs-utils,
  nautilus-open-any-terminal, codecs.
- Fonts: `maple-mono` + `nerd-fonts.jetbrains-mono` + google-fonts + noto-emoji.
- Firmware → `hardware.enableRedistributableFirmware`. Power → power-profiles-daemon.
- Zirconium profile lists are ~90% NixOS-base / bootc-gone — not a package-by-
  package slog. Real per-device leftovers: printing, NM-VPN-plugins, fprintd
  (Duo?), thermald + intel-media-driver (Intel only).
- ⚠️ **gws** = overlay source-build, NOT nixpkgs `gws` (different tool).

### harnessRPM ledger (complete)
- nixpkgs: atuin, cliphist, eza, lisgd, nwg-look, shpool, starship,
  wl-gammarelay-rs, bibata-cursors, kitty.
- overlay source-build: asr-rs, cliamp, mactahoe ✅.
- pi → pi.nix/llm-agents.nix. dropped: quickshellX, antigravity.
- ☑️ **microsandbox → microvm.nix** (nix-native).
- ⏸️ **DEFERRED until first boot (want both, revisit then):** **gws** (Google
  Workspace CLI — NOT nixpkgs `gws` which is a different tool; source-build vs
  prebuilt) · **fgp-browser** (overlay as-is vs own wrapper). Explicitly left out
  of the initial build; **get back to them once the system boots.**

### Open questions / research
- ⏳ Which bespoke tools become flake-modules now vs later.
- ⏳ Distribution model: personal-only vs published.
- ⏳ Secure-boot/TPM2 (lanzaboote) + `luks-tpm2-autounlock` — Phase 4, heaviest.
- ⏳ distrobox/toolbox — keep only if used for non-Nix envs.
- 🔬 **niri built-in screenshot vs grim/slurp/satty** — investigate what niri's
  native screenshot UI covers; `satty` (annotation) / grim+slurp (scripted
  capture) only where it doesn't. (Aside from 2026-06-19.)
- 🔬 **tailscale timer** — confirm none was needed (parity = `services.tailscale`).
- ⏳ Per-device: printing (cups+hplip nix-default), NM-VPN-plugins (all, additive),
  fprintd (all devices), thermald+intel-media (Intel only). cups/zram/plymouth keep.
- ⚠️ Verify NAS share name: harness uses `//10.42.0.2/G`; nix-test wrongly had `/LaCie`.
- 🔬 `99-no-nsresourced.preset` — confirm N/A on NixOS (likely drop).
- harness `docs/` renamed → `harness-legacy-docs/` (onboarding compresses via
  secrets; network-services has avenues; bluebuild-migration is historical).

---

## The per-item loop (mactahoe was the template)

pick item → I lay out the rungs + tradeoffs → I decide → prove it builds
(nixos/nix container) → record it here. A row isn't "decided" until it's proven.

## The sweep plan (forward path)

Systematic pass, in dependency order:

1. **`harness` repo** — the OS/system layer. Source: `comparison.yml` +
   nix-test audits (greetd→niri, router glue, pipewire, zram, NAS mount…).
   Sort each into GONE/SAME/NEW.
2. **`harnessRPM`** — likely collapses: most specs → already in nixpkgs (delete);
   a handful → overlay source-builds (mactahoe ✅ done); rest die.
3. **`dotfiles` + `skills/`** — home-manager port (SAME bucket) merged with the
   capability catalog (`skills/task-6.x`, microvm, remote-connection) that says
   what the setup must provide.

---

## Pointers
- Philosophy & per-tool nixpills: `notes/june18-nix-learnings.md`
- Harness item-by-item format: `harness/docs/bluebuild-migration/comparison.yml`
- Reference (don't build on): `nix-test/` (esp. `docs/DECISIONS.md`, `docs/audit/`)
  — fully swept → **`nix-test-compare.md`** (ADOPT / ALIGN / DIVERGE / WRONG + the
  checks/CI shape, mkOutOfStoreSymlink granularity, per-device findings, router +
  secrets-ACL references worth lifting).
- First proven item: `mactahoe-oled/`
- nvim migration plan (multi-agent, scrutinized): `nvim-sweep.md`
