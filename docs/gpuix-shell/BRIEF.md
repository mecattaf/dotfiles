# gpuix-shell — overnight build brief (2026-10-20/21)

Written by the orchestrator session (Claude, cc seat, herdr workspace wHW) for every agent
in the overnight run. Tom is offline until morning. Make healthy assumptions, write them down
in `docs/gpuix-shell/ASSUMPTIONS.md` (append a line, never block on Tom).

## 1. The order (Tom, 2026-10-20 ~22:50 and ~23:05 CEST, verbatim fragments)

- "oversee the creation of a gpuix + openUI project that will result in my shell being built"
- "staying on sway window manager (my wm of choice) ; and in my ~/dotfiles with an experimental branch"
- "the 'ultimate' gpuix-based shell ; that would be at the same level as quickshell as it was scoped
  for the desktop environment: in the case of dankmaterialshell ; noctalia ; and omarchy"
- "the crux of it is that we write scripts and functionality that is either a bespoke swaywm shortcut ;
  or a mod+d menu (vicinae remplacement) that presents a given functionality. notify-send remplacement
  to mako ; a left bar with workspace switcher that remplaces waybar"
- "there is a lot of herdr-web-ui centricity here especially on the left sidebar idea ; but having a
  comprehensive list of all the options is important."
- "keeping the anthropic font that i have ... is important. i m also expecting us to be close to the
  current minimal 'noir' colorscheme with the possibility to switch to claude 'light and dark'
  variants that are already in scope."
- "make sure that the work you do will set the foundation for my subsequent work on achieving the
  world's most complete linux desktop shell without using quickshell. gpuix as the frontend all the
  way is desired. the rest, including scripts and other functionality, you can use what comes
  instinctively to you. for wifi menu, or bluetooth pairing menu; etc."
- "lately i saw 'tacit' dotfiles ... in my case what is of interest is mainly the file explorer ...
  more importantly however is the aesthetic that was achieved with this tacit os quickshell config:
  this is what i would like to remain close to (of course, different font than the one i want, but
  i like the vanilla-ness of it). openUI for the desktop shell is not quite known"
- "do not block further overnight work on 'waiting on tom's input'"
- "the 'boundary' between personal desktop os shell versus common utilities (webui + macos native +
  wayland native; say for the email or crm utilities) should already be clear."

Standing rulings that bind (from MAP.md, dig reports, transcripts):
- Sway is the only compositor. Hyprland was tried 74 minutes on 10-14 and dropped ("let s stick to
  sway window manager. less effort").
- One herdr workspace = one kitty projector window = one Sway workspace; Mod+1..9 on the top display
  (eDP-1), Mod+0 = workspace 10 on the bottom display (eDP-2) = Chrome. Nine-slot cap is Tom's mental
  model ("one to one mapping, with a limit of 9 open workspaces at a time").
- herdr is "the centerpiece of dotfiles"; the shell reads herdr state (workspace list, agent status:
  blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○) read-only and acts through Sway.
- Look: Claude/Primer look is the baseline ("whatever you just opened: i love it. this is good enough
  to also become a functional remplacement to waybar, vicinae and mako"); "functionality pull from
  quickshell NOT visuals"; flat and opaque, hairlines not shadows, no blur, no frost, wallpaper is
  #000000 solid. Fonts: Anthropic Sans (UI), Anthropic Serif (documents), AnthropicMono Nerd Font (mono).
- Themes: noir (default, OLED black), claude-dark, claude-light, from `home/themes/*.nix`, switched at
  runtime by `~/.local/bin/theme` retargeting the `~/.config/theme` symlink. The shell must follow the
  same pointer (a new fragment in `home/themes/default.nix`, e.g. `gpuix-shell.json`).
- "performance is not really the thing i m looking for here"; "no top bar on the Linux head";
  "on the sway devices, the left bar of the ai chat is a waybar style workspace (1>9) launcher".
- Never restart herdr, the user manager, or the live Sway. Every compositor test runs under
  `runtime-test --render-node /dev/dri/renderD128 -- ...` (the version with `--render-node` is at
  `/home/tom/.wt/hyprland-solid-shell/home/dot_local/bin/runtime-test`; copy it into this branch).
- No cron/timers declared in dotfiles. No secrets in git. Fonts never in git (NAS requireFile).
- The Anthropic fonts cannot go public; this branch stays in Tom's private repo mecattaf/dotfiles.

## 2. Where things are

| What | Path |
|---|---|
| THIS branch (worktree) | `/home/tom/.wt/dotfiles/gpuix-shell` = branch `experimental/gpuix-shell` off `main` dadb1426 |
| Shell source (to create) | `pkgs/gpuix-shell/` (TypeScript, @gpuix/react, bun build, `default.nix` buildNpmPackage) |
| HM module (to create) | `home/gpuix-shell.nix` (systemd user units on `sway-physical-session.target`; option `programs.gpuixShell.enable`, never both it and vicinae/mako) |
| Docs (to create) | `docs/gpuix-shell/` |
| Tests (to create) | `tests/gpuix-shell/` |
| Main dotfiles checkout (do NOT edit) | `/home/tom/mecattaf/dotfiles` |
| Previous GPUIX shell (Hyprland, Solid, 0.10.0, uncommitted) | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/` (ui.tsx 1300+ lines: bar, launcher, controls, windows, notifications daemon over dbus-next, toasts, singleton, theme loader from kitty.conf) and `default.nix` (the Nix build precedent) |
| GPUIX Sway proof (Solid, Mail + Desktop windows, Sway IPC adapter) | `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/` |
| OpenUI + GPUIX native adapter (today, React web + framework-neutral MutationHost adapter) | `/home/tom/tuesday-oct20/build/shared-parity/` (src/native/adapter.ts, src/openui/*, docs/native.md, docs/FRAMEWORK-EVALUATION.md) |
| OpenUI upstream clone | `/home/tom/tuesday-oct20/build/shared-parity-reference/openui` (packages/lang-core is framework-agnostic) |
| gpuix upstream clone (source 6a5c7c1+) | `/home/tom/Downloads/gpuix` (packages/native/index.d.ts = the API; CHANGELOG.md) |
| Installed @gpuix/native 0.10.0 linux binary | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/node_modules/@gpuix/{native,native-linux-x64-gnu,solid}` |
| npm registry | reachable; `@gpuix/native` and `@gpuix/react` 0.11.0 published with `@gpuix/native-linux-x64-gnu`; 0.11.0 adds `registerFont(bytes)`; layerShell exists since 0.10.0 (`render(node,{layerShell:{namespace,layer,anchor,exclusiveZone,margin,keyboardInteractivity}})`) |
| bun 1.4.2 / node 24.18 / npm | `/home/tom/today/2026-10-14-convergence-soak/build/bun/bin/bun`, `/home/tom/today/2026-10-14-convergence-soak/build/node/bin/{node,npm,npx}` (not on PATH; or `nix shell nixpkgs#nodejs_24 nixpkgs#bun`) |
| Sway config | `home/dot_config/sway/{config,binds.conf,layout.conf,rules.conf,startup.conf,input.conf}`, `home/home.nix` (sway-local.conf per host) |
| Scripts the shell replaces or wraps | `home/dot_local/bin/{herdr-picker,herdr-chord,herdr-projector,sway-workspace,osd,volume,brightness,media,audio-route,screenshot,colorpicker,theme,theme-prompt,pomodoro,monitors-off,claude-capacity,fzf-nmcli,touchpad-toggle}` |
| Vicinae (to be replaced) | `home/vicinae.nix` (also hosts mako + desktop entries), `docs/vicinae-research.md`, `docs/client-sway-vicinae.md` |
| mako (to be replaced) | `home/vicinae.nix` services.mako; theme fragment in `home/themes/default.nix` (`mako = t: ...`) |
| Old waybar config (deleted 2026-09-11) | `git -C /home/tom/mecattaf/dotfiles show 1d926f2e^:home/dot_config/waybar/{config,modules,style.css}` |
| Unmerged Sway branches | `/home/tom/.wt/dotfiles/morning-shell` (PR #565: Mod+i top-display workspace switcher with herdr status, fuzzel; tests/workspace-switcher), `/home/tom/.wt/dotfiles/herdr-sway-context` (c1a49b99: Mod+grave kitty/Chrome swap, `herdr-attention` → Sway urgency + mako actions, 69 tests), `/home/tom/.wt/dotfiles-sway-mod-o` (PR #571 Mod+o dismiss notifications) |
| Theme system | `home/themes/{default,noir,claude-dark,claude-light}.nix`, `home/theme.nix`, `docs/theme-switcher-2026-09-17.md`, `home/dot_local/bin/theme` |
| Fonts | `pkgs/anthropic-ui.nix`, `pkgs/anthropic-mono-nerd.nix`, `docs/fonts/*.md`; installed system-wide via `modules/common.nix fonts.packages`; family names "Anthropic Sans", "Anthropic Serif", "AnthropicMono Nerd Font"; glyph font "Anthropicons" |
| Design kit handoff (the design rules U-01..U-19, surfaces table, tokens) | `/home/tom/today/2026-10-17-frank/design-handoff/{SHELLS-DIGEST.md,HANDOFF-B.md,VERIFICATION.md,dig/01-shells-overlaps.md,dig/02-quickshell.md,dig/05-gpuix-shell-state.md}` |
| Boundary personal shell vs shared utilities | `/home/tom/friday16oct-planning/{BOUNDARIES.md,PACKETS.md,SPEC.md,CONTRADICTIONS.md}` |
| CUBS (the earlier Chromium-Views shell scoping; the functionality list) | `/home/tom/mecattaf/cubs/{README.md,docs/architecture.md,docs/open-decisions.md,docs/compositor-adapters.md,cli/SPEC.md,schemas/*,examples/*/README.md,style/INVENTORY.md}` |
| Aura → Hyprland → GPUIX history | `/home/tom/mecattaf/dotfiles/reports/From Aura to Hyprland.md`, `/home/tom/mecattaf/dotfiles/research_notes/From Aura to Hyprland/*.md` |
| Tacit (the aesthetic to stay close to; Pinax file explorer) | `/home/tom/saturday-tacit/{README.md,TACIT-OVERVIEW.md,research/**,iso-files/usr/share/tacit/shell/**}` (QML: modules/common/{Appearance.qml,widgets,...}, modules/ii/{bar,files,island,notificationPopup,onScreenDisplay,overview,sidebarRight,bluetooth,...}) |
| herdr-web-ui fork (Tom's rail: 220/30/12/2/8, Noir + Claude palettes, DESIGN.md) | `/home/tom/mecattaf/herdr-web-ui/{DESIGN.md,src/styles.css,src/components/*}` |
| Other GPUI shells to mine for features | `/home/tom/Downloads/gpui-shell` (Rust GPUI shell: bar, launcher, control center, OSD, D-Bus integrations), `/home/tom/Downloads/herdr-bar`, `/home/tom/Downloads/herdr-gpui` |
| herdr CLI/API | `herdr workspace list`, `herdr agent list`, `herdr api snapshot`, `herdr api schema`, `herdr notification show`, `herdr workspace focus/create/close`; server socket on the strix; the client projects it with `herdr --remote strix` |
| Local model for generative UI | strix `http://127.0.0.1:8731` (OpenAI-compatible, model `halogen-qwen3.8-flash-next`); shared-parity `src/model/stream.ts` shows the call |
| Transcripts (what Tom said) | Claude: `/home/tom/.claude/projects/-home-tom-today/{f3cd04ae-...,56e498e4-...,683f84a0-...}.jsonl`, `/home/tom/.claude/projects/-home-tom-mecattaf-dotfiles/1a517fb2-....jsonl`, `/home/tom/.claude-work/projects/-home-tom-tuesday-oct20/4253a15b-....jsonl`; Codex: `/home/tom/.codex/sessions/2026/10/13/rollout-...01a1370e-....jsonl` (GPUIx pivot), `/home/tom/.codex/sessions/2026/10/14/rollout-...01a13780-{13dc,2ee4,5686}-....jsonl` (desktop-shell builds), `/home/tom/.codex/sessions/2026/10/20/rollout-...01a15935-...`, `...01a15938-{4949,6c51,89d0}-...`, `...01a159bd-...`, `...01a159c1-1f31-...` (today). Helper: `python3 /tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/transcript-text.py FILE [--user-only] [--grep REGEX] [--start I --end J] [--max N]` |
| Day map | `/home/tom/tuesday-oct20/MAP.md` (section 5 "The unified GPUIX workspaces" is the summary of record) |

## 3. Architecture decisions taken tonight (assume; record disagreements in ASSUMPTIONS.md)

1. Language/renderer: TypeScript + React 19 via `@gpuix/react` + `@gpuix/native` 0.11.0 (pin both exact).
   React, not Solid: Tom's leaning, Primer-shaped design kit, OpenUI's first-party runtime is React,
   shared-parity's web head is React. The MutationHost adapter path stays available for OpenUI programs.
2. One process per surface family, all launched by systemd user units bound to
   `sway-physical-session.target`, plus one `gpuix-shell` CLI that talks to a Unix socket at
   `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` (toggle launcher, show OSD, notify, etc.). Sway binds call
   the CLI. GPUIX has one window per renderer process, so: `gpuix-shell rail` (daemon), `gpuix-shell
   notifications` (daemon: org.freedesktop.Notifications D-Bus server + toasts + OSD window),
   `gpuix-shell launcher` (toggle, overlay), `gpuix-shell switcher` (Mod+i), `gpuix-shell controls`
   (quick settings), `gpuix-shell files` (Pinax-like explorer, ordinary window), `gpuix-shell power`.
3. Surfaces and layer-shell geometry follow SHELLS-DIGEST §4: rail = layer top, anchor left/top/bottom,
   exclusive zone 56 collapsed (220 expanded, X1 option), keyboard on-demand; launcher = overlay, top
   margin 108, 700×580, keyboard exclusive; toasts = overlay top-right 390 wide max 4; OSD = overlay
   bottom margin 96; switcher = overlay top margin 108.
4. Data: Sway IPC (`swaymsg -t subscribe` / i3-ipc socket in-process), herdr snapshot (`herdr api
   snapshot` polled + `herdr workspace list`), D-Bus (notifications server, UPower, NetworkManager,
   BlueZ, MPRIS, logind) via `dbus-next`, PipeWire via `wpctl`, brightness via `brightnessctl`/existing
   `brightness` script, clipboard history via `wl-paste --watch` + own store (Vicinae's goes away).
5. Theme: read `~/.config/theme/gpuix-shell.json` (new fragment rendered from `home/themes/default.nix`),
   watch the symlink, reload live; noir default; Anthropic Sans 12 UI, mono for figures.
6. Aesthetic: Tacit's vanilla-ness (generous padding, quiet type, restrained accents, rounded 8/12
   inner corners, hairline borders) on the Claude/noir palette; no blur, flat and opaque.
7. OpenUI: an exploratory, clearly-bounded surface (`gpuix-shell ask`: a prompt whose streamed OpenUI
   Lang output renders natively through the lang-core evaluator → GPUIX element mapping, reusing
   shared-parity's adapter design). Not on the critical path; the core shell must stand without it.
8. Boundary: everything compositor-bound (layer-shell surfaces, Sway IPC, herdr slots, notifications
   daemon, OSD, clipboard, power, wifi/bluetooth menus) is the personal shell and lives in dotfiles.
   Mail/CRM/projects/chat utilities are NOT built here; the shell only launches them (Chrome apps,
   herdr-web-ui desk, the agency kit) and may host their OpenUI programs through the same adapter.
9. Nix: `pkgs/gpuix-shell/default.nix` modeled on the desktop-shell precedent (buildNpmPackage,
   npmDepsHash, bun build, autoPatchelf, wrapper with LD_LIBRARY_PATH for wayland/vulkan/xkbcommon);
   wired in `flake.nix` overlay + client home packages; a flake check that builds it and runs `bun test`.
10. Deploy: nothing is activated tonight. The branch is committed and pushed; a draft PR is opened;
    `docs/gpuix-shell/MORNING.md` tells Tom how to deploy to the Zenbook (never the strix).

## 4. Working rules for agents

- Work only inside `/home/tom/.wt/dotfiles/gpuix-shell`. Never edit `/home/tom/mecattaf/dotfiles`.
- Use the bun/node paths above (absolute). `cd` into the worktree for every command.
- Prefer small files per surface under `pkgs/gpuix-shell/src/<area>/`; keep shared files
  (`package.json`, `src/main.ts`, `src/registry.ts`) owned by the agent the PLAN names as owner.
- Every surface ships: a pure-logic `*.test.ts` (bun test, no compositor), and a compositor smoke
  (`tests/gpuix-shell/smoke_<surface>.py`) that runs only under runtime-test --render-node.
- Write what you did and what you could not do at the end of your own file; never claim a test ran
  if it did not. Unverified = say so.
- Commit nothing yourself unless your prompt says so; the integrator commits.

## 5. Addendum 23:20 CEST (Tom's second and third messages, verbatim fragments)

- "logging off now, there will be no further inputs on my behalf. be proactive ... all-claude."
- "make sure that the work you do will set the foundation for my subsequent work on achieving the
  world's most complete linux desktop shell without using quickshell. gpuix as the frontend all the way"
- "lots of information in the ~/notes repo especially if you find a project that i had been scoping for
  months on a chromium shell ... as early as 6 months ago did i describe the 'ultimate desktop shell'
  with at one time a very detailed set of rulings with deeply annotated priorities list ... the spirit
  was very correct, even though i had not captured yet that i would be using herdr as centrally"
  → notes live in /home/tom/notes (git); candidates: references/devlogs/1h26/{cubs-steelman,pre-sync}/,
  references/continuity/2026-09-27-desk/2026-09-27/frontend/*, references/continuity/2026-09-07-sept7-working/sept7/scopes/agency-chromium.md
- "the vicinae implementation is also of interest so make sure to capture that as well" and "a full
  implementation of the linux wayland sway facing https://github.com/vicinaehq/vicinae ... would be
  impressive to see. gpuix for the win." → clone at /home/tom/Downloads/vicinae (v0.29.1-18); inventory
  every builtin/provider/command/setting/CLI verb/extension API and reproduce the Linux-relevant set.
- "i would like to have a navidrome music selection in the gpuix shell ; so a demo implementation of
  that would be very nice to have tomorrow morning ... raycast+spotify level searching and playing
  control from within the launcher" (refs: raycast mattisssa/spotify-player, thomas/spotify-controls,
  raycast/extensions navidrome at c33bf4cb; bjarneo/cliamp). Navidrome 0.63.2 (OpenSubsonic) answers at
  http://music.internal (Tailscale-gated, full access). Playback: mpv is installed (/etc/profiles/per-user/tom/bin/mpv).
- "this is NOT ONLY about navidrome.. but indeed a welcome set of utilities you can demo for me"
- "using https://github.com/thesysdev/openui fully with what's given ; following my own desired
  anthropic font and existing colorscheme" → the OpenUI native adapter should cover the full default
  component library, not a subset.

Toolchain facts measured 23:15: `@gpuix/native@0.11.0` + `@gpuix/react@0.11.0` + `react@19.2.0` install
with bun into /tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/probe011
(node_modules there has the Linux .node; reuse it for prototypes until the scaffold exists).
Sway for isolated tests: /nix/store/04g9x522ddd3hi77v013n97li9ccyrhd-sway-1.12/bin/{sway,swaymsg}; grim at
/nix/store/7scglgqhmxl5gj585y0h2nq699rspg4g-grim-1.5.0/bin/grim; render node /dev/dri/renderD128; use
WLR_RENDERER=gles2 (pixman loses the Vulkan surface); VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json.
32 CPUs on this box.

MEASURED 23:45 CEST by the orchestrator: the PUBLISHED @gpuix/native 0.11.0 Linux binary (no patch, no
Nix build) opens a wlr-layer-shell surface on an isolated headless Sway 1.12 (gles2): a 56 px left rail,
anchor left/top/bottom, exclusiveZone 56 → Sway reports workspace rect x=56 width=1384 on a 1440x900
output; Anthropic Sans text renders; grim screenshot in docs/gpuix-shell/evidence/rail-probe/shot.png.
The exact app and smoke script are docs/gpuix-shell/evidence/rail-probe/{rail.tsx,smoke.py}: copy that
recipe (LD_LIBRARY_PATH from /nix/store globs for libxkbcommon, wayland-1, vulkan-loader, fontconfig,
freetype, libglvnd, libx11, libxcb, openssl, gcc-15 lib dirs; WLR_RENDERER=gles2; run with bun directly
on the .tsx, no build step needed for prototypes).
