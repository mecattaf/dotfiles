# Dotfiles sweep (preliminary) — chezmoi → home-manager

Synthesis of the 3-agent sweep of `dotfiles/home/` (chezmoi root). `skills/`
excluded (done together). Rungs: RAW (mkOutOfStoreSymlink, hot-reload) · TYPED
(generated from Nix options) · AS-IS (verbatim, Nix provides deps) · COPY
(activation copy — Claude Code can't follow symlinks) · GONE.

---

## Clear calls (low discussion)

### RAW (hot-reload configs, placed via symlink)
kitty · fish · starship · zathura · yt-dlp · asr-rs · shpool · kanshi · qt6ct
(or TYPED via `qt` module — minor) · bashrc/bash_profile.
- All plain text, no chezmoi templates, frequently hand-edited → RAW preserves
  live editing. Nix provides the binaries + PATH deps.
- Deps to provide: eza, zoxide, atuin, starship (fish init); maple-mono +
  jetbrains nerd (kitty font); shpool; etc.
- Notes: fish `desk`/`desk-resume` + starship + `new-terminal` hardcode
  `harness-desktop` SSH host (fine as functions); kitty hardcodes the
  kitty-scrollback.nvim lazy path; bashrc sources `~/.env` → **secrets (sops)**.

### TYPED
- **git** (`dot_gitconfig.tmpl`, the only chezmoi template) → `programs.git`
  (userName=mecattaf, userEmail=thomas@mecattaf.dev, gh credential helper).

### COPY (Claude Code)
- `dot_claude/settings.json` + `settings.local.json` → copied at activation.
  `settings.local.json` has Fedora-specific allow-entries (dnf/rpm) — prune for Nix.
- (skills/ handled separately.)

### AS-IS
- **nvim** — lazy.nvim lua placed verbatim + **lazy-nix-helper**. ⚠️ real work:
  it uses **mason** (won't work on Nix) and `treesitter.install` (network, fails
  in sandbox) → replace mason with Nix-provided LSPs (currently just **marksman**)
  and pre-seed tree-sitter parsers. Mostly mechanical once the LSP/tool list is set.
- **containers/** = the **asr-toolbox WhisperLiveKit quadlet** (ROCm ASR server).
  Not a home config → moves to **system quadlet-nix** (AMD-Strix host), pairing
  with native asr-rs. (Confirms the asr-rs-native + WLK-containerized split.)

### GONE
- **scroll/** — legacy sway/scroll compositor; scripts already migrated to
  niri/scripts (verify none missing, then delete).
- **waybar/** — bar-less decision.
- **abandoned shell UI trees** — delete outright.
- loose dated status, port, and handoff notes in dot_config/ — stale documents
  chezmoi happened to deploy. Drop (the "~/.config must not change" invariant in
  nix-test was itself a chezmoi artifact).
- **dot_config/.claude/settings.local.json** — WIP work-artifact (52 perms for
  niri/shell UI hacking), not a real dotfile.
- launcher **antigravity.desktop** (+icon) — antigravity dropped.

### Per-file RAW (NOT whole-dir — other tools write here)
- `~/.local/share/applications/*.desktop` (12 Chrome-PWA launchers) + matching
  icons. Verify URLs for open-webui/photos/gcloud; drop antigravity.

### bin/ (~31 scripts) — whole-dir RAW, except retired shell wrappers (see discussion)
- Viable now (niri-native + CLI tools): volume (wpctl), screenshot (niri native),
  record, recording-toggle, colorpicker (niri pick-color), clipboard (cliphist),
  fzf-shortcuts, wifi-menu, vpn-status, fzf-nmcli (python+pygobject), new-terminal,
  shpool-resume, resume-terminal, battery, powermenu, pomo, pomodoro, music-download.
- Big Nix dep set: niri, rofi, wpctl/pipewire, wf-recorder, slurp, cliphist,
  wl-clipboard, jq, fzf, glow, yt-dlp, aria2, networkmanager, iwmenu, acpi,
  python3+pygobject, kitty, fish, shpool.

---

## DISCUSSION (the non-mechanical calls)

### D1 — niri: RAW vs TYPED  ⬅ reversal candidate
All 3 agents independently recommend **RAW**. The config is 8+ KDL files
(config/binds/startup/input/layout/misc/window-rules/layer-rules) + scripts,
hand-edited constantly, hot-reloaded by niri on save. `programs.niri.settings`
(typed) is "more nix-native" but **loses hot-reload** (rebuild per change) and
the schema lags upstream niri. Your earlier "most-nix-native" was a general lean;
**niri is the one config where RAW is the better engineering call.** Recommend
making niri the explicit RAW exception. ← your call.

### D2 — retired shell UI + its dependent scripts  ⬅ tied to "my own shell"
The old shell project is abandoned and must not be deployed. Several bin scripts
call its IPC and die without it: **brightness, media,
launcher, dms-launcher, spotlight, dnd, control-center, settings, sigrid,
wallpaper, bar-toggle** (+ notch-toggle/launchpad). These are real functions.
Options:
- (a) **Interim native re-point**: brightness→brightnessctl, media→playerctl,
  launcher→rofi, wallpaper→swaybg, dnd/bar/control-center→drop (bar-less). Gets a
  working desktop now.
- (b) **Leave dead** (accept no brightness/media/launcher keys meanwhile).
Recommend (a) for the keys you actually press daily (brightness, media, launcher,
wallpaper); drop the bar/notification/panel ones (bar-less). ← your call.

### D3 — wallpaper mechanism
niri has no built-in; the old shell IPC bridge is dead. Pick:
**swaybg** spawned from niri startup pointing at the repo `wallpaper.jpg` (simple,
home-manager-managed) — recommended. ← confirm.

### D4 — secrets: `~/.env`
bashrc sources `~/.env` for secrets. Fold into the **sops** decision (materialize
keys to an env file or per-service). ← confirms the secrets layer feeds the shell.

### Minor
- kanshi profiles carry stale `scrollmsg` (sway IPC) lines — harmless on niri;
  modernize to `niri msg` later or accept layout-only.
- startup.kdl cleanup: delete the catppuccin gtk-theme lines, the dead shell UI
  spawn, the dangling wallpaper comment.

---

## RESOLVED / OPEN (2026-06-20) — most are OPEN, revisit next session

- ✅ **D3 wallpaper** — confirmed: swaybg from niri startup → repo `wallpaper.jpg`.
- ✅ **D1 niri** — **RAW for now** (ratified). All 9 niri `*.kdl` annotated with a
  `// NIX-MIGRATION:` note (candidate to port to typed `programs.niri.settings`
  later — not committed). Overrides the harness-sweep typed call.
- ✅ **D2 retired shell scripts** — **native interim re-point, NO rofi** (ratified
  2026-06-20). The IPC callers are dead, so:
  - **brightness → brightnessctl**, **media → playerctl**, **wallpaper → swaybg**
    (the daily keys — re-point these).
  - **launcher + every rofi-dependent script (dms-launcher, spotlight, …) → LEAVE
    DEAD.** No rofi wanted; not re-pointed.
  - **bar-toggle / notch-toggle / dnd / control-center / settings / sigrid /
    launchpad → drop** (bar-less, notification-less).
- ☑️ **D4 env secrets (`~/.env`)** — **intentionally deferred** to the sops layer
  (later phase); explicitly out of the dotfiles sweep.
- ✅ **nvim → Nix** — dedicated session **DONE → `nvim-sweep.md`** (high-scrutiny
  multi-agent plan, 27 findings/18 fixed; keeps lazy.nvim, zero functionality loss;
  `programs.neovim` + lazy-nix-helper store-resolution + mason→Nix + tree-sitter
  pre-seed). Plan only — not built.
- 🔄 **ASR correction** — **no more WhisperLiveKit.** asr-rs **v2 is a single Rust
  binary** (model: **parakeet**, WIP). So `containers/asr-toolbox` quadlet → **GONE**
  (no container), and nix-test's "WLK containerized + asr-rs native" split is
  obsolete → just the native asr-rs v2 binary.

**All D1–D4 resolved + nvim → Nix planned (`nvim-sweep.md`) 2026-06-20.** The
dotfiles sweep is **scope-complete**. Clear calls (RAW/TYPED/COPY/GONE table at
top) stand. `skills/` + secrets are POST-boot / their own sessions. Next is
**building** (Layer 0 flake skeleton → Layer 1 home-manager bridge).
