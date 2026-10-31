# 18 · Waybar / Mako / Vicinae replacement inventory

Wave-1 reader note for the overnight `gpuix-shell` build (2026-10-20/21). This is the
replacement inventory: everything the three programs the shell retires (the deleted Waybar,
Mako and Vicinae) do for Tom, and the scripts that lean on them. Each row says what exactly
Tom relies on, where it lives today (file:line), which gpuix-shell surface takes it, and a priority.

Reader: Claude (Opus 5.5), read-only, wrote this one file only. Nothing was run against the
live Sway, herdr, Mako, Vicinae or systemd. Line numbers are for the worktree
`/home/tom/.wt/dotfiles/gpuix-shell` (branch `experimental/gpuix-shell`, off `main` dadb1426)
unless a path says otherwise.

Labels:
- **MEASURED**: read in a file or binary tonight, or the output of a command I ran.
- **REPORTED**: stated in a doc, commit message or transcript, not re-checked tonight.
- **INFERRED**: my reading or recommendation.

Priorities: **must** (the shell cannot replace Mako/Vicinae without it), **should** (expected
within the first usable cut), **later** (inventory only).

---

## 1. What this source is

| # | Source | Path / ref | What it is |
|---|---|---|---|
| S1 | Old Waybar config (deleted 2026-09-11 in 1d926f2e) | `git -C /home/tom/mecattaf/dotfiles show 1d926f2e^:home/dot_config/waybar/{config,config-thinkpad,modules,style.css,mocha.css,pomodoro-bar.json,pomodoro-bar.css}` | The niri/scroll-era bar. Commit 1d926f2e says Home Manager **never linked** it in the last era ("not in home.nix's configDirs, so Home Manager never linked it and no niri startup ever spawned a bar"). REPORTED. It is a historical feature list, not current reliance. |
| S2 | Mako settings | `home/vicinae.nix:111-143` | `services.mako` settings plus a hand-written systemd unit on `sway-physical-session.target`. MEASURED. |
| S3 | Mako theme fragment | `home/themes/default.nix:125-138` | Per-theme colours and per-urgency overrides, included through `~/.config/theme/mako.conf`. MEASURED. |
| S4 | Vicinae HM config | `home/vicinae.nix:1-172` | Every Vicinae setting, provider preference, favourite, theme link, Chrome native-messaging host, desktop entries. MEASURED. |
| S5 | Vicinae research | `docs/vicinae-research.md` (148 lines) | Source-grounded report on Vicinae 0.29.1: tray, media, browser tabs, IDs, clipboard, files, dmenu concurrency bug. REPORTED. |
| S6 | Client Sway/Vicinae doc | `docs/client-sway-vicinae.md` (297 lines) | Keys, picker behaviour, Mako behaviour, rollout receipts 2026-10-07. REPORTED. |
| S7 | Vicinae smoke tests | `tests/sway-vicinae/{smoke.py,herdr_local.py,README.md}` | Isolated Sway + Vicinae + Mako + Herdr smoke under `runtime-test`. MEASURED (read, not run). |
| S8 | Sway binds | `home/dot_config/sway/binds.conf` (157 lines) | Lines 6, 7, 8, 12, 114 reach Vicinae; 139-157 reach the OSD scripts. MEASURED. |
| S9 | PR #571 | `/home/tom/.wt/dotfiles-sway-mod-o`, commit f14ada65 (2026-10-17 12:52 CEST) | Adds `bindsym $mod+o exec makoctl dismiss --all` after binds.conf:36. The PR is OPEN, not merged and not deployed ("Not deployed to the Zenbook", PR body). MEASURED via `gh pr view 571`. |
| S10 | OSD script and its callers | `home/dot_local/bin/osd` (38 lines), `volume`, `brightness`, `touchpad-toggle`, `audio-route` | One replaceable `notify-send` popup per key press. MEASURED. |
| S11 | Other notify-send callers | `record`, `pomodoro`, `pomo`, `music-download`, `herdr-picker`, `home/dot_config/herdr/config.toml:233` (tally pardon), and unmerged `herdr-attention` (branch `/home/tom/.wt/dotfiles/herdr-sway-context`) | The actual notification traffic the daemon must accept. MEASURED. |
| S12 | Mako 1.11.0 binary and man pages | `/nix/store/n17vf7d32lq4q36y8qd1i4b3m51bf3b0-mako-1.11.0/{bin/.mako-wrapped,share/man/man5/mako.5.gz,share/man/man1/makoctl.1.gz}` | Defaults Tom inherits without setting them; hints mako parses (string scan of the binary). MEASURED. |
| S13 | Vicinae upstream clone | `/home/tom/Downloads/vicinae` (HEAD 8c63ae2ef, newer than the pinned v0.29.1) | Clipboard semantics, browser-extension protocol, default window size. MEASURED, with the caveat that the clone is not the pinned tag. |
| S14 | Previous GPUIX notifications daemon | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/{notifications-daemon.ts,notifications.ts}` | Reusable D-Bus server and store, with gaps listed in §5. MEASURED. |
| S15 | Transcripts | see §2 for each quote | Tom's own words on Mako, Vicinae, Waybar, OSD and the left bar. |
| S16 | Tom's own pre-2026 mako, Waybar and SwayFX commits | `git -C /home/tom/mecattaf/dotfiles log -- dot_config/mako/config home/dot_config/mako/config`; `52dcb7bc^:home/dot_config/mako/config` | Tom's hand-set notification look 2024-05 → 2025-10 (top-center, radius 0, OLED black, accent = launcher). MEASURED. |
| S17 | Open GitHub issues from the Vicinae pause (2026-10-07) | mecattaf/dotfiles #508 clipboard paste, #509 Wi-Fi menu, #510 Bluetooth menu, #512 Herdr identity/navigation, #539 Navidrome music; #511 native volume HUD **closed, not planned** (Tom 10-13) | The acceptance criteria Tom's agents already wrote for these menus. MEASURED via `gh issue view`. |
| S18 | Downstream overnight docs that already cite this note | `docs/gpuix-shell/{DESIGN.md,SCOPE.md,KEYS.md,ASSUMPTIONS.md}`, `wave1/26-sway-ipc-and-system-integrations.md` | Checked for conflicts with this inventory; the divergences are §6 G1-G8, G24. MEASURED (read). |

---

## 2. Tom's rulings on the desktop shell, verbatim and dated

Times are UTC from the transcript (`Z`), with CEST in brackets. Typos are Tom's own.

| When | Where | Verbatim | Bears on |
|---|---|---|---|
| 2026-10-07 07:59Z (09:59 CEST) | `~/.claude/projects/-home-tom-today/b7646300-….jsonl` | "i have been using a bar-less setup for almost a year now. the only thing that would have been useful is a left sidebar, without the need for those complex tabs." | No top bar. The Waybar era is history; the rail is a left sidebar. |
| 2026-10-07 11:07:34Z (13:07 CEST) | Codex `~/.codex/sessions/2026/10/07/rollout-2026-10-07T13-06-33-01a1160b-….jsonl` | "i also wish to digress from the waybar+fzf decision, and move into: let's use Vicinae … let's check to see if it can support custom fonts (i want the anthropic font). herdr-in-kitty-in-swayworkspaces-in-vicinae ; with the "status" coming from herdr. this is the simplest setup i can conceive." | Why Vicinae was adopted: font, herdr status, simplicity. MEASURED tonight in the Codex rollout (also quoted in the b7646300 compaction summary). |
| 2026-10-07 11:13:08Z (13:13 CEST) | same Codex rollout | "so no waybar. however mako is still desirable, and so is using it with nice "herdr-like" colorsystem. mako also takes the anthropic font by the way. … herdr itself is becoming the true cornerstone of this setup. truely: herdr+kitty+chrome+claudecode + vicinae ; … all in their lanes. all controlled from dotfiles" | **The toast daemon keeps mako's role**: Anthropic Sans, the shared palette, configured from dotfiles. The mako block of `home/vicinae.nix` (bab72378) was committed 22 minutes later, 13:35 CEST. MEASURED. |
| 2026-10-07 20:50Z (22:50 CEST) | `~/.claude-work/projects/-home-tom-today/525b30aa-….jsonl` | "niri > scroll > sway and the associated tools: screenshots, what i had mapped to function row, what got rolled into vicinae as incomplete that we can bridge the gap to; the need to have a webapp launched in flating, pinned chrome --app for the left bar that is at the same time a herdr picker, and somehting that routes sway workspaces." … "i also push back completely on its "keep vicinae" framing.. i would like to fully supersede this." | Left bar = herdr picker + Sway workspace router. First "supersede Vicinae". |
| 2026-10-11 19:37Z (21:37 CEST) | `~/.claude-work/projects/-home-tom-today/b61fd73f-….jsonl` | "plz make the mako notifications be top and center not top right on the screen." | **Toast anchor = top-centre.** Applied in fc1474d6 (`home/vicinae.nix:115`). |
| 2026-10-11 19:38Z | same | "and yes include the sway volume and brightness edits plz also. they're all wante" | The OSD-through-notify-send edits of 10-10 are Tom's own (commit 524c66f7). |
| 2026-10-12 08:48Z (10:48 CEST) | `~/.claude/projects/-home-tom-today/1376398e-….jsonl` | "a) in mako notifications, the blue color is not the same as the vicinae launcher. i prefer the latter's blue color" | Toast progress/accent blue = the launcher's selection blue (`home/themes/default.nix:125-132`). |
| 2026-10-12 08:48Z | same | "b) in vicinae launcher, i see there are lots of apps that should not be there and require cleanup. ROG control center, report vicinae bug, donate to vicinae, chatgpt, claude, Claude, gcloud, github (the chrome --app shortcut), GVim, openwebui, perplexity, photos, railway, soundcloud, whatsapp, youtube-music must all be gone. … this goes for cross-nixosfleet not just on the client (zenbook)" | The app list must respect `NoDisplay`/`Hidden` and carry no launcher-branding items. |
| 2026-10-12 08:54Z | same | "i already have navidrome installed and the music.internal url ; but i found the default navidrome to be honestly horrendous ; and at the same time vicinae launcher (and its raycast ingegrations) should be ripe for us to perhaps do better" | Music in the launcher (separate music workflow tonight). |
| 2026-10-12 09:20Z (11:20 CEST) | same | "vicinae settings stuff, perhaps because i m on nix, don't seem to be "taking effect". i did try to hide those two settings before. and i also wanted to make the font larger than 11 (12 or 14, need to decide, start at 12). we keep vicinae actually.. i was getting a little carried away there when i said let's delete it. it's good fucntionality." | Launcher font 12 pt. Declared config must take effect, with no hidden GUI state. Vicinae's functionality is the bar to clear. |
| 2026-10-13 18:41Z (20:41 CEST) | `~/.claude/projects/-home-tom-mecattaf-dotfiles/7af325ec-….jsonl` | "1.6 sway and vicinae are indeed mainstay on the client (zenbook)." … "1.11 volume keys through viciane popup yes i roll back on that; the way we control brightness and volume should be keypress>sway>script execution, no need to tie in vicinae if we don't have to" | **Hardware keys stay keypress → Sway → script.** The launcher must not sit in that path. |
| 2026-10-13 22:16Z (10-14 00:16 CEST) | Codex `~/.codex/sessions/2026/10/13/rollout-…01a1370e-….jsonl` | "whatever you just opened: i love it. this is good enough to also become a functional remplacement to waybar, vicinae and mako notifications. drawing insporation from omarchy's implemetnatipn of wayshell in fact." | The mandate: replace all three. |
| 2026-10-13 22:16:59Z | same | "we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever" | Feature parity is the goal; looks come from the Claude/noir/Tacit line. |
| 2026-10-13 22:33Z | same | "one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status indicators. only for the top display (consult kanshi config …, and existing vicinae herdr wrkspaces item as well if needed." | Mod+i switcher, eDP-1 only; reuses the herdr-picker semantics. |
| 2026-10-13 22:34Z | same | "for ht left bar, i want you to copy the same proportions as the views c++ left tab bar that we saw from google chrome." | Rail proportions. |
| 2026-10-13 23:21Z | same | "i m not intersted in "native advantage" . performance is not really the thing i m looking for here. … vicinae (raycast clone) proves this theoretically ; we hae the sway ipc and omarchy's quickshell which you investigated a while back did exactly that." | Vicinae is the proof of concept for the launcher. |
| 2026-10-14 13:10Z | Codex `…/2026/10/14/rollout-…01a13a80-….jsonl` | "increase brightness on my asus zenbook to the max. this should become a shortcut like f1 f2 perpahs ; and a vicinae-remplacement-launcher" | Brightness presets as both a key and a launcher command. |
| 2026-10-14 16:08Z | `~/.claude/projects/-home-tom-today/56e498e4-….jsonl` | "sway has a contextual launcher, a herdr leftbar that is disjinted and contol sway workspaces, clipboard history.. all that stuff that macos version doesn't have." | Clipboard history and the launcher are Linux-shell features, owned here. |
| 2026-10-17 10:52Z (12:52 CEST) | Codex `…/2026/10/17/rollout-…01a1497d-….jsonl` | "in sway wm i wnt ot bering back the shortcot mod O "removes all notifiations" plz. atomic commit and PR" | **Mod+O = dismiss all notifications** (PR #571, open). |
| 2026-10-20 14:50Z | Codex `…/2026/10/20/rollout-…01a159bd-….jsonl` | "the only thing we can retain from before is the nautilus file picker (same as what google chrome uses)" | The file *picker* stays Nautilus/portal. The gpuix file explorer is separate. |
| 2026-10-20 20:52Z (22:52 CEST) | `~/.claude/projects/-home-tom-tuesday-oct20/94d008d7-….jsonl` | "the crux of it is that we write scripts and functionality that is either a bespoke swaywm shortcut ; or a mod+d menu (vicinae remplacement) that presents a given functionality. notify-send remplacement to mako ; a left bar with workspace switcher that remplaces waybar (not implemented in my setup but should exist in the past dotfiles config)" | The order for tonight. |
| 2026-10-20 20:57:18Z (22:57 CEST, queued message) | same session | "gpuix as the frontend all the way is desired. the rest, including scripts and other functionality, you can use what comes instinctively to you. for wifi menu, or bluetooth pairing menu; etc." | Wi-Fi and Bluetooth menus are named deliverables; their backends (D-Bus, nmcli, bluetoothctl) are the builder's choice. MEASURED. |
| 2026-10-20 20:57:18Z | same message | "more importantly however is the aesthetic that was acheived with this tacit os quickshell config: this is what i would like to remain close to (of course, different font than the one i want, but i like the vanilla-ness of it)." | The look target. It says nothing about corner radius (see §6 G2). MEASURED. |
| 2026-10-20 ~21:20Z | BRIEF §5 | "the vicinae implementation is also of interest so make sure to capture that as well" and "a full implementation of the linux wayland sway facing https://github.com/vicinaehq/vicinae … would be impressive to see. gpuix for the win." | Full Vicinae parity (another reader inventories the source). |

Rulings embedded in config comments (REPORTED; the transcript is not re-read here):
- `home/vicinae.nix:37` "Tom, 2026-10-12: make the font larger than 11 (12 or 14, need to decide, start at 12)".
- `home/vicinae.nix:63-65` hides the "Report Vicinae Bug" and "Donate to Vicinae" items (Tom, 2026-10-12).
- `home/vicinae.nix:101-102` asusd stays; only its ROG Control Center launcher entry is hidden (Tom, 2026-10-12).
- `home/themes/default.nix:125-126`: Mako's progress bar takes the Vicinae selection blue (Tom, 2026-10-12).

**Provenance of the mako geometry (MEASURED from git, both repos):** no transcript quote of Tom's sets
the radius, border or width. But Tom's **own mako config** (chezmoi era; commits under his account
`mecattaf <thomasmecattaf@gmail.com>` with no agent co-author trailer, so INFERRED hand-made; deleted
2026-03-05 in 52dcb7bc as "unused") already had
`anchor=top-center`, `border-radius=0`, `border-size=1` and `layer=overlay`. The agent commit bab72378
(2026-10-07 13:35 CEST) re-created exactly those four and added `width=390`, `margin=12`, `padding=14`,
`default-timeout=5000` and `max-visible=4`. So:

| Value today | Origin | Status |
|---|---|---|
| `anchor=top-center` | Tom's commit db35f95e "mako center" (2024-05-30, top-right → top-center); restated verbatim 2026-10-11 | **Tom ruling, twice** |
| `border-radius=0` | Tom's commits "disable rounded corners" 1-4 on 2024-11-10: 73b19714 (SwayFX `corner_radius 10` and blur commented out), e47b6d17 (mako 15 → 0, Waybar 10 → 0, wlogout), 982eb3aa and 6d6e40fb (Waybar); niri cd9c9cf1 "square corners" (2026-09-25, comment "(Tom): square corners"); Vicinae `rounding = 0` (`home/vicinae.nix:51`) | **Tom's standing preference** (commits, not a quote) |
| `border-size=1` | Tom's own config (unchanged since 2024) | Tom's choice (commit history) |
| `layer=overlay` | Tom's own config | Tom's choice (commit history) |
| progress/accent colour = the launcher's | Tom's 28cafe8f "purple accents for notifications, matching apps launcher" (2025-05-13: border #89b4fa → #cba6f7) and the 2026-10-12 "i prefer the latter's blue color" | **Tom ruling, twice**: toasts take the launcher accent |
| black toast ground on OLED | Tom's e191e4e9 "first attempt at optimizing colors for oled" (2025-01-01: #1e1e2e → #000000) | Tom's choice; noir `ground.raised` is still #000000 |
| font size | Tom's dedbf3ce (2025-07-06, 12 → 24 at 1x) and 802d7532 "going back to 2x scale" (2025-08-08, 24 → 12) | Tom sizes text for the scale he runs; today 11 pt at scale 2 |
| `width=390`, `margin=12`, `padding=14`, `max-visible=4`, `default-timeout=5000` | agent commit bab72378 (Tom's own were margin 15, padding 15,10,15, timeout 2500, `#max_visible=3` commented) | accepted look, not a ruling (INFERRED) |

Tom's pre-2026 mako colours (Catppuccin mocha on black): background #000000, text #cdd6f4, border #cba6f7,
progress `over #313244`, critical #f38ba8, low #fab387 (`git -C ~/mecattaf/dotfiles show 52dcb7bc^:home/dot_config/mako/config`).

---
## 3. Feature and behaviour inventory

Fate: **replace** (gpuix-shell takes it, the old program goes), **keep** (stays as it is and
gpuix-shell calls it), **new** (no current provider), **drop** (historical, no replacement).
Surface names follow BRIEF §3.2: `notifications` (D-Bus daemon + toasts + OSD window),
`launcher`, `rail`, `switcher`, `controls`, `files`, `power`, plus the `gpuix-shell` CLI on
`$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`.

### 3.0 Index: capability → provider today → surface → priority

One line per capability; the detail rows (exact behaviour, file:line, notes) are in §3.1-§3.11.
"Provider today": **W** = Waybar era (deleted, historical), **M** = mako, **V** = Vicinae,
**S** = a dotfiles script/Sway bind, **—** = nothing.

| Capability | Provider today | Exact behaviour Tom relies on (short) | gpuix-shell surface | Pri | Detail |
|---|---|---|---|---|---|
| Own `org.freedesktop.Notifications` | M | one daemon, `Type=dbus` unit on `sway-physical-session.target`, client only | `notifications` daemon | must | §3.1 |
| `notify-send -r` replace-id | M | live id updated in place; stale id → new id printed | daemon | must | §3.1 |
| `-h int:value:N` progress | M | full-card fill in `selection.bg` | toast + OSD renderer | must | §3.1 |
| urgency low/normal/critical | M | border inactive/active/red; critical never expires | daemon + toast | must | §3.1 |
| timeouts | M | default 5000 ms, `-t 0` never, explicit `-t` honoured | daemon | must | §3.1 |
| actions + `--wait` | M | body click = default action; stdout prints key | daemon + toast | must | §3.1 |
| app-name | M | routing key (`osd`, `Herdr`, Chrome) | daemon | must | §3.1 |
| body markup | M | Pango subset + entities; herdr-attention escapes its body | toast renderer | must | §3.1 |
| icons / image-data / image-path | M | 64 px icon at the left | toast renderer | should | §3.1 |
| stack: max 4, "(N more)", newest first | M | `max-visible=4`, `sort=-time` | toast surface | must | §3.1 |
| anchor top-centre, 390 wide, margin 12, padding 14, border 1, radius 0 | M | Tom 2024-05-30 + 2026-10-11 (anchor); Tom 2024-11-10 (radius 0) | toast surface | must | §3.1, §2 |
| focused-output placement | M | `output=""` | toast surface | must | §3.1, §6 G3 |
| click left/right/touch | M | left = default action, right = dismiss, touch = dismiss | toast surface | must | §3.1 |
| history + restore | M + V entry | 5 most recent, `makoctl restore` | daemon + launcher + centre | must | §3.1, §3.3 |
| dismiss / dismiss all (Mod+O) | M + V entry, PR #571 | newest / all, history kept | CLI + launcher | must | §3.3 |
| theme reload | M (`makoctl reload`), V (`vicinae theme set`) | live palette switch via `theme` | all surfaces watch `~/.config/theme` | must | §3.3, §3.10 |
| OSD volume/brightness/touchpad/mic | S (`osd` → notify-send) | one replaceable popup, 1500 ms, value bar | OSD window in `notifications` | must | §3.2 |
| launcher toggle (Mod+D, Mod+Space) | V | overlay, exclusive keyboard, 12 pt Anthropic Sans, pops to root | `launcher` | must | §3.4 |
| applications | V | visible `.desktop` set only, NoDisplay/Hidden honoured | launcher provider | must | §3.4 |
| dotfiles commands | V (desktop entries) | 7 entries: herdr picker, new/restore/rename workspace, dismiss/restore notification, network | launcher commands | must | §3.4 |
| favourites at root | V | herdr, clipboard, tabs, now playing, tray | launcher empty-query | must | §3.4 |
| clock while open | V | status-bar clock (only clock on screen) | launcher footer + rail | should | §3.4 |
| clipboard history (Mod+V) | V | 24 h eviction, password hint ignored, pinned survive, dedupe, FTS, copy-only | clipboard watcher + launcher lens | must | §3.5 |
| calculator | V | inline result at root; Enter copies; history | launcher inline provider | should | §3.6 |
| file search | V | Downloads + Documents index, fallback row | launcher provider (+ `files` window) | should | §3.6 |
| browser tabs | V + Chrome extension | list/activate Chrome tabs; tabs at root | launcher provider + own native host | should | §3.6, §5.4 |
| media / Now Playing | V; keys = S (`media` → playerctl) | MPRIS list, play/pause/next/prev/volume | launcher view + `controls`; keys unchanged | should | §3.6 |
| tray (StatusNotifier) | V (fallback watcher + Search Tray) | tray menus without a bar | launcher "Tray" + optional rail slot | later/should | §3.6 |
| power actions | V builtins | lock/suspend/reboot/power-off/logout (no hibernate on the client) | `power` + launcher | should | §3.6 |
| window/workspace switching | V `wm` (generic) | not Sway-aware | `switcher` + launcher "Windows" | should | §3.6 |
| dmenu (herdr picker, rename) | V dmenu IPC + `herdr-picker` | rows in, selection out; free text; concurrency-safe | `gpuix-shell dmenu` + native herdr provider | must | §3.7 |
| Mod+I top-display switcher | fuzzel (PR #565, open) | eDP-1 workspaces + herdr status at open | `switcher` | must | §3.7 |
| workspace strip | W (bottom of eDP-2, glyph per ws, urgent/focused) | — today | `rail` slots 1-9 + 10 | must | §3.8 |
| Claude capacity | W (`claude-capacity`, 300 s) | — today | rail chip + controls | should | §3.8 |
| volume / backlight / battery / clock | W | — today (battery shown nowhere) | rail footer + `controls` | should | §3.8 |
| pomodoro progress bar | W (10 px bar, HDMI-A-1) | — today; `pomodoro` = fzf + notifications | later strip / rail ring | later | §3.8 |
| Wi-Fi menu | — (`nmtui` entry; `fzf-nmcli` unbound) | issue #509; named by Tom 10-20 | `controls` Wi-Fi | should (named) | §3.9 |
| Bluetooth pairing menu | — (scripted `bluetoothctl`) | issue #510; named by Tom 10-20 | `controls` Bluetooth | should (named) | §3.9 |
| audio route, theme, monitors off, screenshots… | S (kitty + fzf prompts) | F2/F9/… prompts | launcher views over the same scripts | should/later | §3.9 |
| action echo (HUD) | V (`showHud` "Selection copied to clipboard") | brief confirmation after copy | toast/OSD echo (DESIGN U-09) | should | §3.4 |

### 3.1 Notification server: notify-send / org.freedesktop.Notifications compatibility

Mako owns `org.freedesktop.Notifications` today through a `Type=dbus` unit
(`home/vicinae.nix:127-143`; flake asserts at `flake.nix:1214-1219`). Every row below is
something a current caller sends or something mako does by default that Tom sees.

| Feature | Exact behaviour Tom relies on today | Lives today | Fate | gpuix-shell surface | Pri | Notes |
|---|---|---|---|---|---|---|
| Own the bus name | One daemon owns `org.freedesktop.Notifications` on the session bus. The unit is `Type=dbus`, `BusName=org.freedesktop.Notifications`, `PartOf`/`WantedBy` `sway-physical-session.target`, `ConditionEnvironment=WAYLAND_DISPLAY` | `home/vicinae.nix:127-143` | replace | `notifications` daemon unit (same target, `Type=dbus`) | must | "never both" (BRIEF §2, SHELLS-DIGEST Q6). The HM option must turn `services.mako.enable` off. The previous daemon refuses to start if the name is taken (`notifications-daemon.ts:12-13`), which is the right behaviour. |
| `Notify` signature | `susssasa{sv}i` → `u`; returns the id; `notify-send -p` prints it | libnotify 0.8.8 `notify-send` (`home/vicinae.nix:145`) | replace | daemon | must | MEASURED: `notify-send --help` on 0.8.8 lists `-u -t -a -i -n -c -e -h -p --id-fd -r -w -A --selected-action-fd --activation-token-fd`. |
| **replace-id** (`-r N`) | Replaces the content of live notification N in place and keeps id N. If N has expired, a **fresh** notification with a new id is created and printed. `bin/osd` depends on both cases ("When the popup has already expired, notify-send -r on the stale id simply creates a fresh one, verified against mako 1.11 on the client") | `home/dot_local/bin/osd:9-14,27-37` | replace | daemon | must | The previous store does both (`notifications.ts:26-29`) and moves a replaced item to newest (`:39-42`). Keep that. |
| **hint `int:value:N`** (progress) | Draws a progress bar across the whole popup, fill = N %, colour `progress-color=over <selection.bg>` | `bin/osd:32-34`; `home/themes/default.nix:132` | replace | toast and OSD renderers | must | **Missing in the previous daemon**, which reads only `urgency`, `resident` and `transient` (`notifications-daemon.ts:47-48`). The volume/brightness OSD is the most frequent notification Tom sees. mako's binary parses `value` (MEASURED string scan). |
| **urgency** (`-u low\|normal\|critical`, byte hint `urgency` 0/1/2) | low: border `border.inactive`. normal: border `border.active`. critical: border `red` and **never expires** (`[urgency=high] default-timeout=0`) | `home/themes/default.nix:133-137` | replace | daemon + toast style | must | Callers: `record:10,14,26` (`-u critical -t 0` "Screen Recording Started"), `record:19,24` (`-u low -t 0`), `herdr-attention` (`--urgency=normal`). mako accepts `high` as an alias in criteria (string `high` in the binary, MEASURED; INFERRED alias). |
| **timeouts** (`-t ms`) | `-1` (no `-t`) → 5000 ms (`default-timeout = 5000`). `0` → never. Explicit `-t N` is honoured (`ignore-timeout` default 0). Critical with no `-t` → never | `home/vicinae.nix:121`; mako(5) `ignore-timeout` default 0 | replace | daemon | must | The previous store uses 6000 for `-1` (`notifications.ts:45`): change it to **5000**. The previous store also forces every critical to 0 even with an explicit `-t`; mako honours an explicit `-t` on critical. Match mako (INFERRED from mako(5) semantics). Timings in use: osd 1500, pomodoro 1500/1000, herdr-attention 15000, record 0. |
| **actions** (`-A key=Label`, `--wait`) | Buttons; a left click on the body runs the **default** action (`on-button-left=invoke-default-action`); `notify-send --wait` prints the chosen key and exits 0; `ActionInvoked(id,key)` then `NotificationClosed(id,2)` | mako(5) defaults; caller `herdr-attention:258-273` on branch `herdr-sway-context` | replace | daemon + toast | must | herdr-attention sends `--app-name=Herdr --urgency=normal --expire-time=15000 --action=default=Open --wait` and expects stdout `default` (`:265-268`). That branch is unmerged; it is still the planned attention path. The previous store handles keys correctly (`notifications.ts:31-36,59-63`). |
| `ActivationToken` signal | mako emits `ActivationToken(id, token)` before `ActionInvoked` so the invoked app can raise itself (xdg-activation) | mako binary string `ActivationToken` (MEASURED) | replace | daemon | should | notify-send 0.8.8 has `--activation-token-fd`. On Sway, xdg-activation tokens let Chrome focus its own window when a web notification is clicked (INFERRED). |
| **app-name** (`-a`) | Text only (mako format `<b>%s</b>\n%b` does not print `%a`); usable for criteria and routing | mako(5) `format` default | replace | daemon | must | `bin/osd` sends `-a osd`, which lets the daemon route OSD traffic (§3.2). herdr-attention sends `Herdr`. Chrome sends its own name (INFERRED). |
| **body markup** | `markup=1`: Pango markup in the body (`<b> <i> <u> <a>`, entities `&amp; &lt;`). Capability `body-markup` is advertised | mako(5) `markup` default 1; binary strings `body-markup` | replace | toast renderer | must | herdr-attention **escapes** its body with `html.escape` (`herdr-attention:256`) on the assumption that markup is on. Without entity decoding Tom would read `&amp;` literally. The previous daemon advertises only `actions, body` (`notifications-daemon.ts:45`). Advertise mako's set: `actions, body, body-markup, icon-static` (MEASURED strings). GPUIX has no italic, so render `<i>` as plain (§6 G13). |
| **icons** (`-i name\|path`, `-n app-icon`, `image-data`/`image_data`/`icon_data`, `image-path`) | `icons=1`, `max-icon-size=64`, `icon-location=left`, `icon-border-radius=0`; icon names looked up in the icon theme (MacTahoe), paths loaded directly, raw pixel hints decoded | mako(5) defaults; binary strings `image-data image_data icon_data image-path` | replace | toast renderer | should | No script of Tom's sends `-i` today (MEASURED grep). Chrome web notifications (Gmail and Calendar `--app` windows, binds.conf:28-30) send favicons as `image-data` (INFERRED from Chromium). Without them toasts still work, just without the picture. |
| `category`, `desktop-entry` hints | Matched by mako criteria; not displayed | binary strings `category desktop-entry` | replace | daemon (store only) | later | Use `desktop-entry` to focus the sending app on a default action (INFERRED). |
| `x-canonical-private-synchronous`, `x-dunst-stack-tag` | A new notification carrying the same tag replaces the previous one (the volume-OSD idiom of other tools) | binary strings (MEASURED) | replace | daemon | should | Tom's scripts use `-r` instead, but third-party tools and future scripts use the tag. It is cheap to honour. |
| `transient` (`-e`), `resident` | transient: not kept in history; resident: stays after an action | previous store `notifications.ts:38,48,63` | replace | daemon | should | mako 1.11 has no explicit transient handling in its strings; the previous store does it. Keep. |
| **max-visible 4** | At most 4 toasts on screen; extra ones hidden behind a placeholder row `(%h more)` | `home/vicinae.nix:122`; binary string `(%h more)` | replace | toast surface | must | The kit agrees: "toasts 390 wide, at most 4" (SHELLS-DIGEST:181). A placeholder card "(N more)" is the mako behaviour Tom has seen. |
| **sort -time** | Newest first. With top-centre anchoring the newest is the top card | mako(5) `sort` default `-time` | replace | toast surface | must | |
| **anchor top-centre** | Stack hangs from the top edge, horizontally centred, 12 px from the edge (`margin=12`, `outer-margin=0`), 12 px between cards | `home/vicinae.nix:115-117` | replace | toast layer surface: `anchor:["top"]`, margin `[12,0,0,0]`, `layer:"overlay"`, `keyboardInteractivity:"none"`, `exclusiveZone:-1` | must | **Conflict with BRIEF §3.3 and SHELLS-DIGEST:68,181,251, which say top-right.** Tom's 10-11 ruling is explicit, repeats his own 2024-05-30 commit, and he never reversed it, so top-centre wins. The previous GPUIX shell already anchored its toasts `["top"]` only, i.e. top-centre (`/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/ui.tsx:1287-1291`). DESIGN.md §8.4 (A-15) keeps top-right as the default with a config key; §6 G1 asks the integrator to flip the default. |
| width 390, height ≤100, padding 14, border 1, radius 0 | Each card is 390 px wide and shrinks to fit its text up to a 100 px maximum (mako `height` default 100); 14 px inner padding; 1 px border; square corners | `home/vicinae.nix:116-120`; mako(5) `height` default 100 | replace | toast renderer | must | The kit's "fixed 140 px card, title one line, body two lines" (SHELLS-DIGEST:202) differs from mako's ≤100 px shrink-to-fit. Pick one and log it (§6 G5). |
| Font | `Anthropic Sans 11` (Pango **points**: 11 pt × 96/72 ≈ **14.7 logical px**) | `home/vicinae.nix:114`; asserted at `flake.nix:1229` | replace | toast renderer | must | Format `<b>%s</b>\n%b`: bold summary line, body below, both 11 pt (mako(5) `format` default). DESIGN.md's toast title 13 px / body 14 px is a little smaller than today (§6 G24). |
| Colours | bg `ground.raised`, text `fg`, border `border.active`, progress `selection.bg`; low → `border.inactive`; critical → `red` | `home/themes/default.nix:127-138` | replace | toast renderer reads `gpuix-shell.json` | must | Per-theme values in §4.3. |
| Layer and output | `layer=overlay` (above fullscreen); `output=""` = **the focused output** at the moment the card appears | `home/vicinae.nix:123`; mako(5) `output` default | replace | toast surface | must | GPUIX 0.11.0 `LayerShellOptions` has **no output field** (MEASURED `index.d.ts:685-721`). Sway places a new layer surface on the focused output, which matches mako at creation. A stack that stays open does not follow focus to the other panel (§6 G3). |
| Mouse and touch | left click → default action; right click → dismiss; middle → nothing; **touch → dismiss** | mako(5) `on-button-*`, `on-touch` defaults | replace | toast surface | must | The Duo has touch panels (`input type:touch map_to_output eDP-1`, `home/home.nix:155`). Whether GPUIX surfaces get touch as pointer events is unknown (§6 G14). |
| Close reasons | `NotificationClosed(id, reason)`: 1 expired, 2 dismissed by user, 3 `CloseNotification`, 4 undefined | spec; previous store uses 1 (`notifications.ts:46`), 2 (`:57-58,66`), 3 (`notifications-daemon.ts:51`), 4 (`notifications.ts:44`, overflow past 100) | replace | daemon | must | `notify-send --wait` exits when it sees NotificationClosed. |
| `GetServerInformation` | mako answers its own name and version | spec | replace | daemon | must | Return `gpuix-shell`, vendor, version, spec `1.2` (as the previous daemon does, `:46`). |
| Sound | None (`on-notify` default none) | mako(5) | keep none | — | later | The kit has `sound none\|done\|request` (SHELLS-DIGEST:515). Silent by default. |
| History buffer | Dismissed and expired notifications go to history (`history=1`), **max 5** (`max-history` default 5); `makoctl restore` brings back the newest | mako(5) `history`, `max-history`; desktop entry `notifications-history` (`home/vicinae.nix:164-166`) | replace | daemon store + launcher command + notification centre | must (restore) / should (centre) | The previous store keeps 100 history items but has **no restore verb** (command union `notifications.ts:9`, cap `:49`), and it writes every non-transient notification into history **at Notify time** (`:47-48`), not on expiry/dismissal as mako does. Add `restore`. Keep at least 5, and offer a browsable centre (kit: 500×650, SHELLS-DIGEST:181). |
| Do Not Disturb | Unused today: no `mode` criteria in the config | `home/themes/default.nix:127-138` | new | daemon + `controls` | should | mako has modes; the previous store has `dnd` (`notifications.ts:19,64`). A DND toggle in `controls` and the launcher is expected of a "complete" shell (INFERRED). |
| Chrome web-app notifications | Gmail and Notion Calendar `--app` windows (`binds.conf:29-30`) and claude.ai (`:28`) post web notifications through the same bus. Chrome reads `GetCapabilities` and adapts: with `body-markup` it escapes text, with `actions` it adds buttons (INFERRED from Chromium's Linux notification bridge, not read tonight); it sends an image as `image-path` or `image-data` and a `desktop-entry` hint (INFERRED) | Chrome 152 on the client (REPORTED, 1376398e summary) | replace | daemon + toast | must | The largest third-party sender. Capture one real Notify call with `dbus-monitor` before claiming parity (§6 G19). Clicking must raise the Chrome window: needs the default action plus `ActivationToken` (row above). |
| Flood and size limits | mako has none that Tom relies on | — | new | daemon | should | The previous store caps summary 1024, body 8192, app 256, 16 actions, 100 live items (`notifications.ts:33-44`). Keep these caps. |
| Strix and headless hosts | No daemon: `osd`, `pomodoro` and `pomo` guard with `command -v notify-send` and exit 0 | `bin/osd:16-17,25`; `bin/pomodoro:14-23`; flake asserts `!strixHome.services.mako.enable` `flake.nix:1222` | keep | — | must | The shell is client-only (`osConfig.myDisplay.enable`, `home/vicinae.nix:10`). |

### 3.2 OSD (volume, brightness, touchpad, mic)

| Feature | Exact behaviour today | Lives today | Fate | gpuix-shell surface | Pri | Notes |
|---|---|---|---|---|---|---|
| One replaceable OSD popup | `osd <title> <body> [percent]` → `notify-send -p -t 1500 -a osd [-r <last id>] [-h int:value:<pct>] title body`; the id is kept in `$XDG_RUNTIME_DIR/osd-notify.id`, so repeated presses update **one** popup | `home/dot_local/bin/osd:27-37` | keep the script; replace the renderer | `notifications` daemon routes `app-name == "osd"` to the OSD window, or leaves it as a toast (decide, §6 G4) | must | Tom 10-13: "keypress>sway>script execution, no need to tie in vicinae". The script stays the entry point, so it works unchanged with **any** compliant daemon. A `gpuix-shell osd` verb can come later, with `osd` as a thin wrapper that falls back to notify-send. |
| Volume | `volume up\|down` = `wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%±` then OSD "Volume" "N%" N; `mute` toggles → "Muted" "" 0 or "Volume"; `micmute` → "Microphone muted" / "Microphone on" "N%" (no bar) | `home/dot_local/bin/volume:15-35`; binds.conf:145-147,152-154; `sway-local.conf` XF86AudioMicMute (`home/home.nix:167`) | keep | OSD renders | must | Bound `--locked`, so it also works on a locked screen. |
| Brightness | `brightness up\|down [N%]`, `off`, `restore`, `toggle`; OSD "Brightness" "N%" N, or "Backlight off" "" 0 | `home/dot_local/bin/brightness:170-182`; `home/home.nix:158-166` (XF86MonBrightness, Shift = 2 % steps, F10 toggle) | keep | OSD renders | must | Tom 10-14: wants "max brightness" as a key and as a launcher command (§3.9). |
| Touchpad | Caps Lock / Menu → `touchpad-toggle` → OSD "Touchpad" "off"/"on" (no bar) + Caps LED | `home/dot_local/bin/touchpad-toggle:31-33`; binds.conf:141 | keep | OSD renders | must | PR #565 does **not** touch this bind: a two-dot `git diff main` shows it removed only because #565 branched before 7e082fbb added it; `git diff main...HEAD` is clean (MEASURED). |
| Audio route lift | After routing into a sink with a near-silent stored volume, OSD "Volume" N | `home/dot_local/bin/audio-route:231` | keep | OSD renders | must | |
| OSD look today | Since 2026-10-11 it is simply a **mako toast at top-centre**, 390 px, 1.5 s, with a full-card progress fill in `selection.bg` | as above | replace | — | must | BRIEF §3.3 places the OSD bottom-centre, 96 px margin. That position is a design choice, not a Tom ruling (§6 G4). |

### 3.3 Notification control verbs (makoctl equivalents) and binds

| Feature | Exact behaviour today | Lives today | Fate | gpuix-shell surface | Pri | Notes |
|---|---|---|---|---|---|---|
| Dismiss newest | `makoctl dismiss` (first notification) | desktop entry `notifications-dismiss` `home/vicinae.nix:161-163` | replace | `gpuix-shell notify dismiss` + launcher command "Dismiss notification" | must | |
| **Dismiss all (Mod+O)** | `makoctl dismiss --all`; dismissed items go to history | PR #571 adds `bindsym $mod+o exec makoctl dismiss --all` after `binds.conf:36` (open) | replace | `gpuix-shell notify dismiss --all` | must | Tom 10-17 verbatim. The previous store's `clear` also **wipes history** (`notifications.ts:65-68`). mako's `dismiss --all` keeps history. Make dismiss-all keep history and add a separate `clear-history`. |
| Dismiss without history | `makoctl dismiss -h/--no-history` | makoctl(1) | replace | `--no-history` flag | should | |
| Restore last | `makoctl restore` | desktop entry `notifications-history` `home/vicinae.nix:164-166` | replace | `gpuix-shell notify restore` + launcher command | must | |
| Invoke action | `makoctl invoke [-n id] [action]`, `makoctl menu -- <picker>` | makoctl(1) | replace | `gpuix-shell notify invoke`; toast actions also listed in the launcher (SHELLS-DIGEST:202, "Toast actions are also launcher commands") | should | |
| List / history JSON | `makoctl list [-j]`, `makoctl history [-j]` (the smoke test greps plain `makoctl list` for the summary: `tests/sway-vicinae/smoke.py:234-236`) | makoctl(1) | replace | `gpuix-shell notify list --json`, `history --json` | must (tests depend on it) | The smoke test asserts the delivered summary appears in `makoctl list`. The gpuix test needs the same probe. |
| Reload on theme switch | `theme` runs `makoctl reload` when `mako.service` is active | `home/dot_local/bin/theme:84-87` | replace | the daemon watches `~/.config/theme` (BRIEF §3.5), so `theme` needs only a guarded `gpuix-shell reload` (or nothing) | must | Also remove the `vicinae theme set` reload at `theme:88-91` when the shell is on. |
| makoctl shim | — | — | new (optional) | `makoctl` wrapper script → `gpuix-shell notify …` | later | INFERRED convenience: keeps PR #571, the `theme` script and Tom's muscle memory working if the option is flipped before every call site moves. Not needed if the call sites are rewired in the same commit. |

### 3.4 Launcher root (Vicinae today) — Mod+D / Mod+Space

Vicinae 0.29.1 from `github:vicinaehq/vicinae/v0.29.1` (`flake.nix:151`), run as a systemd user
service on `sway-physical-session.target` with `QT_QPA_PLATFORM=wayland` (`home/vicinae.nix:29-33`).

| Feature | Exact behaviour today | Lives today | Fate | gpuix-shell surface | Pri | Notes |
|---|---|---|---|---|---|---|
| Toggle | `vicinae toggle` on Mod+D and Mod+Space; a second press closes it | `binds.conf:6-7` | replace | `gpuix-shell launcher toggle` | must | Both chords. The launcher is a layer surface with keyboard `exclusive`, so `close_on_focus_loss` cannot fire; Esc or the chord closes it (`docs/vicinae-research.md:92`). |
| Window | Layer shell `overlay`, keyboard `exclusive`, opacity 1, material none (no blur), **rounding 0**, client-side border 1 px, shadow 0. Size is upstream's default **770×480** (not overridden), centred | `home/vicinae.nix:48-61`; default size `Downloads/vicinae/extra/config.jsonc:163-166` | replace | `launcher` layer surface | must | The kit says 700×580 at 108 px from the top with outer radius 16 (SHELLS-DIGEST:67,466-467). That conflicts with today's square 770×480 centred window (§6 G6). |
| Font | `Anthropic Sans` **12 pt** (Vicinae sizes are points, `docs/vicinae-research.md:70`) = **16 logical px** | `home/vicinae.nix:35-38`; asserted `flake.nix:1228` | replace | launcher typography | must | Tom 10-12 "make the font larger than 11 (12 or 14 …, start at 12)". DESIGN.md sets launcher input 14 px and rows 13 px, i.e. ≈10.5 pt and ≈9.75 pt: **smaller than what Tom asked for** (§6 G24). Toasts stay 11 pt (`flake.nix:1229`). |
| Theme | Theme id `dotfiles-current` → symlink to `~/.config/theme/vicinae.toml`; `theme` reloads it with `vicinae theme set dotfiles-current` | `home/vicinae.nix:44-47,94-97`; `home/themes/default.nix:140-177`; `bin/theme:88-91` | replace | launcher reads `gpuix-shell.json` and watches the symlink | must | Colour roles are in §4.3. Selection = `selection.bg/fg`, the "Vicinae blue" Tom prefers. |
| Apps | Every `.desktop` entry on `XDG_DATA_DIRS`, honouring `NoDisplay`/`Hidden`; id = file name without `.desktop` | Vicinae `applications` provider; hidden ROG entry `home/vicinae.nix:103-109` | replace | launcher "Applications" provider (freedesktop desktop-entry parser) | must | Tom 10-12 listed apps that "must all be gone" fleet-wide (done in f7167e3b). The launcher must show exactly the installed, visible set. `Terminal=true` entries open in kitty (`xdg-terminals.list` = `kitty.desktop`, `home/vicinae.nix:100`). |
| Dotfiles commands as desktop entries | "Herdr workspaces" (`herdr-picker`), "New Herdr workspace" (`sway-workspace new`), "Restore Herdr workspace" (`sway-workspace restore`), "Rename workspace" (`sway-workspace rename`), "Dismiss notification" (`makoctl dismiss`), "Restore notification" (`makoctl restore`), "Network settings" (`kitty --class network-settings nmtui`) | `home/vicinae.nix:146-170` (helper `command` at :13-19: `genericName` = subtitle, icon `utilities-terminal`, category Utility) | replace | native launcher commands (one command registry, SHELLS-DIGEST:18) | must | Keep them reachable by the same words. The two notification entries become native verbs; the others call the same scripts. |
| Favourites | Root shows, in order: Herdr workspaces, Clipboard history, Browser tabs, Now Playing, Search Tray | `home/vicinae.nix:84-90` (`applications:herdr-picker`, `clipboard:history`, `browser-extension:browse-tabs`, `media:now-playing`, `core:search-tray`) | replace | launcher empty-query section | must | Agent-chosen on 10-07, not changed by Tom since (REPORTED). |
| Hidden root items | Vicinae's "Report Vicinae Bug" and "Donate to Vicinae" disabled | `home/vicinae.nix:62-69` | drop | — | must | No launcher-branding items in the gpuix launcher. |
| Fallbacks | Upstream default `["files:search"]` (Tom sets none): when nothing matches, offer "search files for <query>" | `Downloads/vicinae/extra/config.jsonc:244-246` | replace | launcher fallback row | should | |
| Pop to root on close | Reopening starts at the root, not the last sub-view | `home/vicinae.nix:42` | replace | launcher state | must | Escape goes back one view, and Backspace on an empty query pops (`escape_key_behavior: navigate_back`, `pop_on_backspace: true`; `config.jsonc:47-50`). |
| Clock in the status bar | Vicinae's root status bar shows a clock (Linux default on) while the window is open. On a bar-less desktop this is Tom's **only on-screen clock** | `docs/vicinae-research.md:33`; `config.jsonc:124-135` | replace | launcher footer + rail clock (§3.8) | should | INFERRED reliance: no bar shows the time today. |
| Privacy | `telemetry.system_info=false`, `favicon_service="none"` | `home/vicinae.nix:39,43` | keep (the shell sends nothing) | — | must | No remote favicon fetches from the launcher. |
| Own tray icon | `tray.enabled=false` hides Vicinae's own icon; the tray *host* still runs | `home/vicinae.nix:40` | drop | — | — | |
| Input server | `input_server.enabled=false`: **copy works, auto-paste and snippet expansion do not** | `home/vicinae.nix:41`; `docs/vicinae-research.md:108` | keep the semantics | launcher | must | Clipboard "Paste" falls back to copy today (§3.5). |
| Settings take effect | Tom 10-12: Vicinae settings "don't seem to be "taking effect"" | transcript 1376398e 09:20Z | new guarantee | gpuix config = the generated JSON; no GUI-only state | must | Design value: declared config is authoritative and visible. |
| CLI surface used by Tom's scripts | `vicinae toggle`, `vicinae cmd launch clipboard:history`, `vicinae theme set dotfiles-current`, `vicinae state open`, `vicinae close`, `vicinae ping`, the dmenu IPC socket `$XDG_RUNTIME_DIR/vicinae/vicinae.sock` | binds.conf:6,7,114; `bin/theme:90`; `tests/sway-vicinae/smoke.py:127,195,199,232,239-240`; `herdr-picker:211-258` | replace | `gpuix-shell launcher {toggle,open <cmd>,close,state}`, `gpuix-shell ping`, `gpuix-shell dmenu` | must | The smoke tests need `state`/`ping` equivalents to wait on. |
| Browser tabs at root | Open Chrome tabs are searchable at root as well as in "Browse tabs" | `docs/vicinae-research.md:100` | replace | launcher provider (§3.6) | should | |
| Action echo (HUD) | After a copy, Vicinae closes and shows a small HUD "Selection copied to clipboard"; removing an entry shows a toast "Entry removed" | `Downloads/vicinae/src/server/src/builtins/clipboard/history/clipboard-history-actions.hpp:33,107-109` | replace | a short toast or OSD echo from the launcher process (DESIGN.md U-09 "acting is declared and echoed") | should | Do not route launcher echoes through `notify-send`: they would land in notification history. |

### 3.5 Clipboard history — Mod+V

| Feature | Exact behaviour today | Lives today | Fate | gpuix-shell surface | Pri | Notes |
|---|---|---|---|---|---|---|
| Open history | Mod+V → `vicinae cmd launch clipboard:history` opens the launcher straight into the history list | `binds.conf:114` (Mod+Ctrl+V = `splitv`, :115) | replace | `gpuix-shell launcher open clipboard` | must | Tom 10-14: clipboard history is a Linux-shell feature. |
| Single owner of capture | Vicinae watches the clipboard through wlr-data-control; **"Vicinae owns clipboard history; do not start a second cliphist watcher."** `cliphist` is installed but not run | `home/dot_config/sway/startup.conf:4`; `home/home.nix:451-452` | replace | `notifications`/`clipboard` daemon process (BRIEF §3.4: `wl-paste --watch` + own store) | must | Exactly one watcher. Stale comment to fix: `bin/screen-ocr-area:6` says "cliphist keeps the result". |
| Monitoring on | New selections are appended (`monitoring = true`) | `home/vicinae.nix:71` | replace | watcher | must | |
| **Ignore passwords** | Selections offering the MIME type `x-kde-passwordManagerHint` are dropped (`ignorePasswords = true`) | `home/vicinae.nix:72`; `Downloads/vicinae/src/lib/common/include/common/clipboard-formats.hpp:6`; `src/server/src/services/clipboard/clipboard-service.cpp:707-708` | replace | watcher: `wl-paste --list-types`; skip if the hint is present | must | Only password managers set this hint. A password copied from a terminal or a web page is **not** caught. That happened: a NAS password copied on the Asus landed in Vicinae's history and had to be deleted by hand ("Tom's Asus actions: delete the 11:55 vicinae clip", desk transcript, REPORTED). |
| **Eviction 24 h** | Unpinned entries older than 86 400 s are evicted (`evictionThreshold = "86400"`; upstream default "never") | `home/vicinae.nix:73`; enum `clipboard-preferences.hpp:14-21` | replace | store | must | Tom's chosen retention: one day. |
| **Preserve tagged** | Pinned entries and entries with a custom keyword survive eviction and "Remove all" (`preserveTagged = true`) | `home/vicinae.nix:74`; `clipboard-preferences.hpp:54,74` (upstream default is also true) | replace | store | must | |
| Kinds | Text, Link (URL with a scheme), File (`text/uri-list` of local files), Image (`image/*`; searchable as "image W×H"), Unknown | `clipboard-service.cpp:285-306,533-575` | replace | store + list renderer (image thumbnails) | must (text, image) / should (file, link) | Producers that make images: `bin/screenshot` (PNG to the clipboard), herdr's clipboard-image paste (`/tmp/herdr-clipboard-images-1000/client-*.png`, seen in Tom's 10-14 and 10-20 Codex turns). |
| Dedupe | Selections are hashed (MD5 over the offers); a re-copy bumps the existing entry rather than adding a duplicate | `clipboard-service.cpp:518-525,449` | replace | store | must | Matters because kitty has `copy_on_select clipboard` (`home/dot_config/kitty/kitty.conf:120`): every mouse selection in a terminal is a clipboard write. |
| Search | Full-text search over entries (Vicinae uses SQLite FTS with a `fuzzy_trigram` tokenizer) | REPORTED in the desk transcript (the tokenizer broke a Python cleanup of the DB) | replace | store (bun:sqlite FTS5 or an in-memory fuzzy index) | must | |
| Actions per entry | Default **Paste** (falls back to **Copy**, because `input_server` is off), Copy to clipboard, Open / Open with…, **Remove entry**, Pin / Unpin, Edit keywords, Remove all (confirm, red) | `Downloads/vicinae/src/server/src/builtins/clipboard/history/clipboard-history-actions.hpp:14-178`; default action `clipboard-preferences.hpp:108` | replace | launcher action panel | must (copy, remove, pin) / should (keywords, open with) | Enter = copy and close. Real paste would need `wtype` (used by the smoke test) and is out of scope until Tom asks (INFERRED). |
| Encryption at rest | Linux default `encrypt_sensitive_data = false` | `docs/vicinae-research.md:106` | replace | store file mode 0600 under `$XDG_STATE_HOME/gpuix-shell/` | should | INFERRED default. The secret incident argues for 0600 plus a visible "Remove" action and a "Pause capture" toggle. |
| Primary selection | Not part of history (Vicinae watches the regular clipboard) | INFERRED from the data-control server | keep out | — | — | kitty also writes primary (`clipboard_control write-primary`, `kitty.conf:131`). Do not record it. |
| Remote writes | Strix-side nvim yanks reach the seat via OSC 52 → kitty → Wayland clipboard; remote reads prompt | `kitty.conf:121-131` | keep | — | must | These appear in history like any other copy. Never add `read-clipboard`. |
| Consumers | `speak-clipboard` (Mod+Ctrl+R) reads text; `colorpicker` (Mod+C), `screen-ocr-area` (Mod+Ctrl+S) and `screenshot` write | `binds.conf:34,36,42-46`; `bin/speak-clipboard:10`; `bin/screen-ocr-area:12` | keep | — | — | Unchanged; they use `wl-copy`/`wl-paste`. |

### 3.6 Other launcher providers Tom has today (calculator, files, browser tabs, media, tray, power)

| Feature | Exact behaviour today | Lives today | Fate | gpuix-shell surface | Pri | Notes |
|---|---|---|---|---|---|---|
| **Calculator** | Typing an expression at root shows the result inline (Numen backend bundled; currency conversion with refreshable rates); copying a result saves it to "Calculator history" (`calculator:history`) | Vicinae builtin `calculator` (`Downloads/vicinae/src/server/src/builtins/calculator/calculator-extension.hpp:18-55`); backend note `docs/vicinae-research.md:13` | replace | launcher inline provider (pure TS evaluator: arithmetic, %, units; currency later) | should | Enter copies the result. No usage data exists (§6 G9). |
| **Files** | `files:search` over an index of `~/Downloads` and `~/Documents` only (`autoIndexing = true`); not mixed into root results (`search_files_in_root` default false); offered as the fallback | `home/vicinae.nix:76-82`; `docs/vicinae-research.md:104` | replace | launcher "Search files" (fd over the same two roots, results open with `xdg-open`) + `files` explorer window | should | The Pinax-like explorer is a separate surface (BRIEF §3.2). Tom 10-20 keeps the Nautilus *file picker*; Mod+E opens `nautilus` (`binds.conf:25`). Keep Mod+E until `files` passes its checks. |
| **Browser tabs** | "Browse tabs" lists every open Chrome tab (title, URL, window, active, audible, muted, pinned); Enter activates the tab and focuses its Chrome window; tabs are also root results | Chrome extension `kcmipingpfbohfjckomimmahknoddnke` force-installed by policy `modules/sway.nix:102-107`; native host manifest `home/vicinae.nix:98-99` → `vicinae-browser-link` | replace | launcher provider + a native-messaging host `com.vicinae.vicinae` reimplemented by gpuix-shell | should | **Reuse path, INFERRED:** keep the installed extension and point the same host name at a gpuix-shell bridge that speaks its protocol (§5.4). Sway then moves focus to workspace 10 (Chrome's slot). Cross-workspace focus was never tested (`docs/vicinae-research.md:100`). |
| **Media / Now Playing** | `media:now-playing` lists MPRIS players with play/pause, next, previous, volume ±5 and presets (volume via `pactl`); the F3-F5 and XF86Audio keys use `playerctl` on the default player | Vicinae builtin `media` (`Downloads/vicinae/src/server/src/builtins/media/media-extension.hpp:80-281`); `bin/media:6-11`; `binds.conf:142-144,155-157` | replace (launcher) / keep (keys) | launcher "Now Playing" + `controls` media card (MPRIS over `dbus-next`) | should | The keys stay script-driven (Tom 10-13). The music demo's daemon publishes its own MPRIS name `org.mpris.MediaPlayer2.gpuix_music` (ASSUMPTIONS.md, music (04)), so F3-F5 reach it through `playerctl`; which player `playerctl` picks when Chrome also plays is still open (§6 G10). |
| **Tray (StatusNotifier)** | "Search Tray" lists StatusNotifierItem apps and their menus. Vicinae also provides the fallback `org.kde.StatusNotifierWatcher` when no bar does | `home/vicinae.nix:89` (favourite); `docs/vicinae-research.md:17` | replace | launcher "Tray" provider: own `org.kde.StatusNotifierWatcher` + host + `com.canonical.dbusmenu` client; optional rail slot | later (should if any app on the client needs it) | Which tray apps run on the client is unknown (OBS is installed, `home/home.nix:395`). Measure before choosing (§6 G11). Without a watcher, some apps lose their tray icon or refuse to minimise to tray. |
| **Power actions** | Vicinae builtins `lock`, `suspend`, `sleep`, `hibernate`, `reboot`, `soft-reboot`, `power-off`, `logout` reachable from root | Vicinae `power-management` builtin (ids from `src/server/src/builtins/**`, MEASURED grep) | replace | `power` surface + launcher commands | should | The client has **no swap, so no hibernate** ("No swap partition → no hibernate", `hosts/client/default.nix:411-416`). Do not offer it. No lock-screen program is declared (MEASURED grep for swaylock/gtklock: none). "Lock" needs a decision (§6 G12). |
| Window / workspace switching | Vicinae `wm` builtins: switch-windows, switch-workspaces, toggle-fullscreen, toggle-floating | ids MEASURED; generic Wayland backend with no Sway workspace membership (`docs/vicinae-research.md:62`) | replace | `switcher` (Sway IPC) + launcher "Windows" provider | should | Use Sway IPC, never Vicinae's transient window ids. |
| Emoji, snippets, shortcuts, script commands, extensions | Present in Vicinae; no evidence Tom uses them; snippets need the input server, which is off | Vicinae builtins `search-emojis`, `snippet`, `shortcut`, `scripts`; `home/vicinae.nix:41` | replace later | launcher providers | later | Another reader inventories the full Vicinae surface for parity (BRIEF §5). |
| Network settings | Desktop entry opens `nmtui` in kitty (class `network-settings`) | `home/vicinae.nix:167-169` | replace | `controls` Wi-Fi menu (§3.9); keep the nmtui entry as "Advanced" | must (entry) / should (menu) | |

### 3.7 The dmenu bridge (Herdr picker and workspace rename) — Mod+Ctrl+Space, Mod+Shift+N

| Feature | Exact behaviour today | Lives today | Fate | gpuix-shell surface | Pri | Notes |
|---|---|---|---|---|---|---|
| Herdr picker | Mod+Ctrl+Space → `herdr-picker` builds rows from Sway's tree plus a read-only `herdr api snapshot` and shows them in Vicinae dmenu with the prompt "Workspaces and Herdr · status at open · Esc to dismiss". Rows: `Focus 3: name · assigned working · label · view 123`, `Reopen 5 · …` (parked), `Window …`, `Agent · blocked · claude · title · wXX:p1 · open navigator`, `Status unavailable · … · select to retry`, then New / Restore / Rename / Open Herdr / Refresh | `binds.conf:8`; `home/dot_local/bin/herdr-picker:466-498` (rows), `:501-571` (main loop) | keep the script; replace the menu backend | `gpuix-shell dmenu` (generic), and a native launcher "Herdr workspaces" provider fed by `herdr-picker --json` (`:505`) | must | Status is a **snapshot at open**; Refresh re-reads. Unreachable means "unavailable", never "idle" (`docs/client-sway-vicinae.md:88-94`). A native provider can show the status glyphs (blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○, BRIEF §2). |
| Vicinae dmenu wire protocol | Unix socket `$XDG_RUNTIME_DIR/vicinae/vicinae.sock`; frame = 4-byte native-endian length + JSON-RPC 2.0 `{"method":"Ipc/dmenu","params":{"req":{rawContent, placeholder, format:"Data", noSection:true, noQuickLook:true, noIcon:false, noMetadata:false, noFooter:false, password:false}}}`; reply `result.output` (string; empty = dismissed). A random high request id works around the 0.29.1 reply-routing bug | `herdr-picker:211-258`; bug write-up `docs/vicinae-research.md:144-148` | replace | `gpuix-shell dmenu [--prompt P] [--free-text] [--password]`: rows on stdin, selection on stdout, exit 1 when dismissed | must | Swap only `vicinae_menu()`/`dmenu()` (`herdr-picker:211-267`) to call the CLI. Keep the validation at `:261-267`: in list mode the result must equal one of the rows ("typed text is not a command"). |
| Free-text rename | Mod+Shift+N → `sway-workspace rename` → `herdr-picker --workspace rename` → dmenu with no rows, prompt "Name workspace N", free text; rejects control characters, U+2028/9, more than 100 characters, and `" \ $`; workspace 10 refused | `binds.conf:12`; `bin/sway-workspace:8`; `herdr-picker:402-416` (`quote_sway` at :108) | keep the script; replace the menu | `gpuix-shell dmenu --free-text` | must | The smoke test checks both paths: selected-row and empty-stdin free text (`tests/sway-vicinae/smoke.py:201-229`). |
| Concurrency | A picker that is waiting must survive concurrent `state`/`toggle`/`theme` CLI calls | `docs/vicinae-research.md:146-148`; smoke `:214-219` | replace | the CLI socket routes replies per connection | must | Design value: never key pending replies by request id alone. |
| Agent row → navigator | Selecting an agent focuses that slot's projector, sends the herdr prefix + `g` chord and posts `notify-send 'Herdr navigation' 'Select <pane> in the Herdr navigator.'` | `herdr-picker:543-561` | keep | — | must | One of the daemon's regular callers. Errors go to `notify-send 'Herdr / Sway' <error>` (`:567-572`). |
| Mod+I switcher (PR #565, unmerged) | `sway-workspace-switcher --output eDP-1` (fuzzel): live workspaces 1-9 plus whatever else is on eDP-1, herdr status read once at open; a second Mod+I closes only its own menu | `/home/tom/.wt/dotfiles/morning-shell` commit 7464298c (binds diff; tests in `tests/workspace-switcher/`) | replace | `switcher` surface | must | Tom 10-13 verbatim (§2). Its fixtures (`tests/workspace-switcher/fixtures/zenbook-0221-*.json`) are real Zenbook `get_tree`/`get_outputs`/`get_workspaces` captures: reuse them for the rail and switcher tests. |

### 3.8 The bar (Waybar era) → rail

The Waybar config was last linked in the scroll/niri era. Tom has been "bar-less for almost a
year" (10-07). These rows say what the bar *did*, so the rail can choose deliberately.

| Feature | Exact behaviour (Waybar era) | Lives (deleted) | Fate | gpuix-shell surface | Pri | Notes |
|---|---|---|---|---|---|---|
| Bar placement | One bar, `layer top`, `mode dock`, **bottom** of **eDP-2** (the lower Duo panel), `exclusive false`, `fixed-center`, `ipc true`; the ThinkPad variant has no `output` | `1d926f2e^:home/dot_config/waybar/config:5-14`, `config-thinkpad:5-13` | replace | `rail`: layer top, anchor left/top/bottom, exclusive 56 (BRIEF §3.3) | must | No top bar (BRIEF §2). The rail's output cannot be chosen through GPUIX 0.11.0 (§6 G3). Tom's slot model: 1-9 on eDP-1 (top), 10 on eDP-2 (`binds.conf:48-69`). |
| Workspaces | `sway/workspaces`, `all-outputs: true`, one glyph per workspace number (Nerd Font, 16 pt): 1 Chrome U+F268; 2 folder U+F07B (rosewater); 10 terminal U+E795; 11 comment U+F075 (green); 12 music U+F001 (peach); 13 U+F6EE (yellow); 14 U+F14A (blue); 15 U+F15C (sapphire); 16 U+F03D (lavender); 17 U+F5EC (teal); 19 U+F198 (mauve); 20 U+F0379 (maroon); default U+F111 ●; urgent U+F06A (red #f38ba8). Click switches; wheel switches with wraparound | `modules:64-91` (glyph codepoints MEASURED with a Python scan) | replace | `rail` slots 1-9 + 10 (Chrome), with herdr status per slot | must | The numbering scheme (10-20) is from the niri era. Today it is 1-9 herdr + 10 Chrome. Mod+wheel already switches (`binds.conf:85-90`). |
| Workspace states | Default text `surface0` (#313244); active `subtext0`; **focused** bg `maroon` (#eba0ac); **urgent** bg `green` (#a6e3a1) with `mantle` text; hover bg `mantle` | `style.css:46-79` | replace | rail states from the theme: focused / visible / urgent / empty | must | Sway urgency is live today: `client.urgent` red (`home/themes/default.nix:120`), and herdr-attention marks urgency (branch `herdr-sway-context`, `herdr-attention:179-246`). The rail must show urgent. |
| Claude capacity | `custom/claude-capacity`: `exec ~/.local/bin/claude-capacity` (JSON `{text, tooltip, class, percentage}`), every 300 s, signal 8; click drops the cache and refreshes; class `warning` ≥80 % or stale, `critical` ≥100 % (blinking red underline); colour `sky` | `modules:92-112`, `style.css:178-204`; script `home/dot_local/bin/claude-capacity:85-88,255-287` | replace | `rail` footer chip + `controls` row, polling `claude-capacity --json` | should | "the waybar half is Tom's, supplied verbatim 2026-09-02" (`claude-capacity:50`, REPORTED). The 60 s cache and 15-minute stale grace exist because `/api/oauth/usage` returns 429 when polled fast. **Poll ≥300 s.** |
| Volume | `pulseaudio`: "{icon} {volume}%", muted icon, click `amixer set Master toggle`, right click `pavucontrol`, wheel ±5 | `modules:44-63` | replace | `controls` volume slider (wpctl) + OSD on change | should | Today's keys step 3 % (`bin/volume:25-26`). pavucontrol is still floated by rule (`rules.conf:4-5`). |
| Backlight | `backlight` on `intel_backlight`, wheel ±1 % via brightnessctl | `modules:4-12` | replace | `controls` brightness slider via `bin/brightness` | later | The Duo daemon mirrors eDP-1's level to eDP-2 (`bin/brightness:167-168`, REPORTED). |
| Battery | States good 95 / warning 30 / critical 20; every 3 s; charging/plugged glyphs; click toggles to time remaining; critical and not charging → blinking red underline (0.5 s alternate) | `modules:13-26`, `style.css:141-167` | new on Sway (nothing shows battery today) | `rail` footer glyph + `controls` (UPower D-Bus) | should | UPower is on the client and powers off at 5 % (`hosts/client/default.nix:412-416`). Vicinae has no battery view (`docs/vicinae-research.md:33`). |
| Clock | " {:%R}" (24 h HH:MM); tooltip = month calendar | `modules:27-30` | replace | `rail` footer clock; calendar popover later | should | Today only Vicinae's status bar shows the time (§3.4). |
| Date (unused) | " {:%d/%m}" | `modules:31-34` | drop | — | — | Defined, never placed. |
| Network (unused) | Wi-Fi ESSID, signal tooltip, click toggles `nm-connection-editor` | `modules:35-43` | replace as the menu | `controls` Wi-Fi (§3.9) | should | Defined, never placed in the bar. |
| Pomodoro (unused in bar) | `custom/pomo/minutes/seconds` from hyprland-era scripts | `modules:114-136` | drop | — | — | |
| Pomodoro progress bar | A second Waybar, `bottom` of `HDMI-A-1`, 10 px tall, `exclusive true`, full width; the whole bar is a progress fill: **work** = `text` colour, **break** = `green`, **paused** = `peach`, base `red`, empty part `base`; classes `perc0..perc100`; every 1 s; click pauses | `pomodoro-bar.json:1-27`, `pomodoro-bar.css` (951 lines of `perc` classes) | later | a thin layer strip, or a rail progress ring | later | Today `pomodoro` is an fzf menu on Shift+F10 (`binds.conf:151`) with notifications. Its `waybar` output mode is gone with scroll. |
| Font and frame | JetBrainsMono / Iosevka Nerd Font 16 px; modules 0 10 px padding, 3 px vertical margin, 1 px border `mantle`; tooltips square with a 2 px border | `style.css:6-34,89-100` | drop (look) | — | — | The look is replaced by Anthropic Sans and the noir/Claude palette. |

### 3.9 Menus that are bespoke Sway shortcuts today (kitty + fzf) and the new menus Tom named

| Feature | Exact behaviour today | Lives today | Fate | gpuix-shell surface | Pri | Notes |
|---|---|---|---|---|---|---|
| Prompt tier | F2 theme, Shift+F2 accent, F9 audio route, Shift+F9 call record, F10 sleep monitors (the client overrides F10 to `brightness toggle`), Shift+F10 pomodoro: each opens `kitty --class <name>-prompt -e <script>`, floating, centred, 640×200 or 640×300, 2 px border | `binds.conf:139-151`; `rules.conf:10-13`; client F10 override `home/home.nix:158` | keep now; replace later | launcher sub-views calling the same scripts | should (theme, audio-route) / later (others) | Tom 10-20: "either a bespoke swaywm shortcut ; or a mod+d menu". The scripts stay the backends; the menus become native views. |
| **Wi-Fi menu** | None bound. `fzf-nmcli` exists unbound; the "Network settings" entry opens `nmtui` in kitty. 10-14: "no wifi?" on the Zenbook before a router change | `home/dot_local/bin/fzf-nmcli` (NM via GObject); `home/vicinae.nix:167-169`; Codex 2026-10-14 08:17Z | new | `controls` Wi-Fi list + connect form (NetworkManager D-Bus via `dbus-next`, or `nmcli` with argv only) | should | Tom 10-20 named it. **Never build a shell string from SSID or password.** The Vicinae Wi-Fi Commander extension was rejected for exactly that (`docs/vicinae-research.md:134`). Saved profiles come from `ensureProfiles` (`hosts/client/default.nix:135-136`). |
| **Bluetooth pairing menu** | None. Pairing was done with scripted `bluetoothctl` (NoInputNoOutput agent through a FIFO, 10-11 session summary). A `blueman-manager` float rule exists, but blueman is not installed | `rules.conf:6`; `modules/common.nix:269`; patched bluez for the Huion `hosts/client/huion.nix:185` | new | `controls` Bluetooth list: scan, pair, trust, connect, disconnect, remove (BlueZ D-Bus `org.bluez.Adapter1/Device1` + an `Agent1`) | should | Tom 10-20 named it. Keep the Huion Note's pairing untouched (custom bluez). Devices in use: Glove80 (BT profiles), Creative speaker (REPORTED 10-11). |
| Audio route | F9 → fzf of sinks/sources with exact PipeWire node names; lifts a near-silent stored volume | `home/dot_local/bin/audio-route` | keep backend | launcher "Audio output" view + `controls` | should | |
| Theme switch | F2 → `theme-prompt theme` → `theme <noir\|claude-dark\|claude-light>` | `binds.conf:139`; `bin/theme` | keep backend | launcher "Theme" command; the shell follows the `~/.config/theme` symlink | should | |
| Brightness max | Tom 10-14: "increase brightness … to the max. this should become a shortcut … and a vicinae-remplacement-launcher" | Codex 01a13a80 13:10Z | new | launcher command "Brightness 100 %" → `brightness up 100%` | should | MEASURED usage text: `brightness up\|down [focused] [N%]`, "N% overrides the 10% step" (`bin/brightness:6-8,185-186`); brightnessctl clamps at max (INFERRED). |
| Monitors off | Mod+Shift+P → `monitors-off` (one-shot swayidle resume) | `binds.conf:127` | keep | launcher command + `power` | later | |
| Screenshots, OCR, colour picker, speak clipboard, recording | Mod+S / Mod+Shift+S / Mod+Alt+S, Mod+Ctrl+S, Mod+C, Mod+Ctrl+R; `record` posts critical/low notifications | `binds.conf:34-46`; `bin/record:10-26` | keep | launcher commands mirroring the binds | later | Recording state could show in the rail (INFERRED). |

### 3.10 Plumbing the replacement must carry

| Item | Today | Lives | Action for the builder | Pri |
|---|---|---|---|---|
| HM option | `home/vicinae.nix` is gated only on `osConfig.myDisplay.enable` (`:10,24`) | `home/vicinae.nix` | `programs.gpuixShell.enable` turns off `programs.vicinae.enable`, `services.mako.enable` **and** the hand-written `systemd.user.services.mako` (`:127-143`). That unit embeds `${config.services.mako.package}/bin/mako` and would otherwise survive. Never both (BRIEF §2). | must |
| Things in vicinae.nix that are not Vicinae | `xdg-terminals.list` (`:100`), the hidden ROG entry (`:103-109`), `pkgs.libnotify` (`:145`), the seven desktop entries (`:148-170`), the Chrome native-host link (`:98-99`) | `home/vicinae.nix` | Keep or move them **out of** whatever the option disables. `notify-send` (libnotify) is the client API and must stay installed. | must |
| Flake assertions | `clientHome.programs.vicinae.enable`, `services.mako.enable`, the mako unit shape, the font asserts | `flake.nix:1213-1229` | Make them conditional on the option and add gpuix-shell equivalents (unit present, bus name, font). | must |
| Theme fragment | `mako.conf` and `vicinae.toml` rendered per theme | `home/themes/default.nix:125-177,281-290` | Add `gpuix-shell.json` to `render` (BRIEF §3.5); keep the mako/vicinae fragments while the option exists. | must |
| Theme reload | `theme` reloads mako and vicinae when their units are active | `home/dot_local/bin/theme:84-91` | Add a guarded `gpuix-shell reload` (or rely on the symlink watch). Keep the "do not D-Bus-activate tools of another desktop" guard. | must |
| Chrome policy and native host | Extension force-installed; host manifest from the Vicinae package | `modules/sway.nix:102-107`; `home/vicinae.nix:98-99` | Keep the policy if the gpuix bridge reuses the extension (§5.4); point the host manifest at the gpuix bridge. | should |
| Vicinae cache | `vicinae.cachix.org` substituter + key | `modules/sway.nix:108-113` | Remove only once Vicinae is gone from the flake. | later |
| Startup comment | "Vicinae owns clipboard history; do not start a second cliphist watcher." | `home/dot_config/sway/startup.conf:4` | Reword to name the gpuix-shell clipboard watcher. | should |
| Smoke test | Evaluates `programs.vicinae.settings`, `services.mako.package`, `xdg.configFile."mako/config"` | `tests/sway-vicinae/smoke.py:41-49` | Fork it into `tests/gpuix-shell/` rather than editing it (§5.6). | must |

### 3.11 Keybinding rewire (what each current call becomes)

| Chord | Today | Lives | Becomes | Pri |
|---|---|---|---|---|
| Mod+D, Mod+Space | `vicinae toggle` | `binds.conf:6-7` | `gpuix-shell launcher toggle` | must |
| Mod+V | `vicinae cmd launch clipboard:history` | `binds.conf:114` | `gpuix-shell launcher open clipboard` | must |
| Mod+Ctrl+Space | `herdr-picker` (Vicinae dmenu inside) | `binds.conf:8` | unchanged command; `herdr-picker` calls `gpuix-shell dmenu`, or `gpuix-shell launcher open herdr` once the native provider exists | must |
| Mod+Shift+N | `sway-workspace rename` (Vicinae dmenu free text) | `binds.conf:12` | unchanged command; the backend switches to `gpuix-shell dmenu --free-text` | must |
| Mod+O | `makoctl dismiss --all` (PR #571, open) | f14ada65 | `gpuix-shell notify dismiss --all` | must |
| Mod+I | `sway-workspace-switcher --output eDP-1` (PR #565, open) | 7464298c | `gpuix-shell switcher toggle` | must |
| Mod+E | `nautilus` | `binds.conf:25` | keep; `gpuix-shell files` beside it until Tom picks | later |
| F3-F8, XF86Audio*, XF86MonBrightness*, XF86AudioMicMute, Caps/Menu | `media`, `volume`, `brightness`, `touchpad-toggle` → `osd` → notify-send | `binds.conf:141-157`; `home/home.nix:158-167` | **unchanged** (Tom 10-13: keypress > Sway > script) | must |


---

## 4. Design values (sizes, colours, fonts, radii, timings)

### 4.1 Toasts as Tom sees them today (mako 1.11 on the Zenbook)

| Property | Value | Source | Label |
|---|---|---|---|
| anchor | `top-center` | `home/vicinae.nix:115` | MEASURED; Tom ruling (§2) |
| layer | `overlay` (above fullscreen) | `:123` | MEASURED |
| output | `""` = the focused output at creation | mako(5) default | MEASURED |
| width | 390 px | `:116` | MEASURED |
| height | ≤ 100 px, shrink to fit | mako(5) `height` default 100 | MEASURED |
| outer margin | 0 | mako(5) default | MEASURED |
| margin (per card) | 12 on every side, so 12 from the top edge and 12 between cards (mako does not collapse the two 12s between cards: they add to 24 between card borders, INFERRED from "applies to each individual notification") | `:117`; mako(5) `margin` | MEASURED value, INFERRED spacing |
| padding | 14 | `:118` | MEASURED |
| border | 1 px | `:119` | MEASURED |
| corner radius | 0 | `:120` | MEASURED; Tom's standing preference (§2) |
| font | Anthropic Sans 11 pt ≈ 14.7 logical px, summary bold, body regular | `:114`; format `<b>%s</b>\n%b` | MEASURED |
| text alignment | left | mako(5) default | MEASURED |
| icon | left, ≤ 64 px, radius 0 | mako(5) defaults | MEASURED |
| max visible | 4, then a "(N more)" card | `:122`; binary string `(%h more)` | MEASURED |
| order | newest first (`sort=-time`), so the newest is the top card under the top edge | mako(5) default | MEASURED |
| default timeout | 5000 ms | `:121` | MEASURED |
| critical | border `red`, never expires (`[urgency=high] default-timeout=0`) | `home/themes/default.nix:135-137` | MEASURED |
| low | border `border.inactive`, 5000 ms (no low-specific timeout) | `:133-134` | MEASURED |
| progress | `over selection.bg`: fill drawn over the card background across the whole card, width = value % | `:132`; mako(5) `progress-color` | MEASURED |
| history | on, 5 entries | mako(5) | MEASURED |
| pointer | left = default action, right = dismiss, middle = none; touch = dismiss | mako(5) | MEASURED |

### 4.2 OSD as Tom sees it today

The OSD **is** a mako toast (since 2026-10-10/11, commit 524c66f7): top-centre, 390 wide, title
"Volume"/"Brightness"/"Touchpad"/"Microphone muted"/"Backlight off", body "N%" or "on"/"off", a
full-card progress fill for volume and brightness, 1500 ms, replaced in place
(`home/dot_local/bin/osd:28-37`). Steps: volume 3 % (`bin/volume:25-26`), brightness 10 %, Shift 2 %
(`bin/brightness:3,6-8`; `home/home.nix:161-166`). MEASURED.

### 4.3 Colour roles per theme (resolved from `home/themes/*.nix`)

Toasts (mako fragment, `home/themes/default.nix:127-138`):

| Role | Palette key | noir | claude-dark | claude-light |
|---|---|---|---|---|
| background | `ground.raised` | #000000 | #20201F | #FFFFFF |
| text | `fg` | #EAECF0 | #EAECF0 | #131313 |
| border, normal | `border.active` | #555451 | #555451 | #A5A49A |
| border, low | `border.inactive` | #373735 | #373735 | #D2D1C7 |
| border, critical | `red` | #F47B85 | #F47B85 | #B80A18 |
| progress fill | `selection.bg` (Tom's "vicinae blue") | #264F78 | #264F78 | #CDE2FB |

Launcher (Vicinae fragment, `home/themes/default.nix:140-177`):

| Role | Palette key | noir | claude-dark | claude-light |
|---|---|---|---|---|
| background | `ground.base` | #000000 | #1A1A1A | #F9F9F7 |
| secondary background | `ground.raised` | #000000 | #20201F | #FFFFFF |
| foreground | `fg` | #EAECF0 | #EAECF0 | #131313 |
| border | `border.inactive` | #373735 | #373735 | #D2D1C7 |
| accent / accent fg | `accent` / `ground.base` | #70B8FF / #000000 | #70B8FF / #1A1A1A | #0051C2 / #F9F9F7 |
| list selection bg / fg | `selection.bg` / `selection.fg` | #264F78 / #EAECF0 | #264F78 / #EAECF0 | #CDE2FB / #131313 |
| muted, placeholder | `comment` | #818898 | #818898 | #6E7687 |
| danger / success | `red` / `green` | #F47B85 / #9BE963 | same | #B80A18 / #008000 |
| loading bar | `brand` | #D97757 | #D97757 | #D97757 |

Sway (`home/themes/default.nix:115-123`): `client.urgent` = `red`; desktop `output * bg #000000 solid_color` in
every theme. MEASURED.

Note for the builder: DESIGN.md gives noir `raised` = #101111 ("black lifted 7 % toward ink", A-01).
Today's noir toasts are pure #000000 with a #555451 hairline; the lift is a design change, not parity.

### 4.4 Launcher geometry and behaviour today (Vicinae 0.29.1 as configured)

| Property | Value | Source |
|---|---|---|
| size, position | 770 × 480, centred (upstream default, not overridden) | `Downloads/vicinae/extra/config.jsonc` `launcher_window.size` |
| rounding / border / shadow / opacity / material | 0 / 1 px / 0 / 1 / none | `home/vicinae.nix:48-55` (upstream defaults 10 / 1 / 12 / …) |
| layer / keyboard | overlay / exclusive | `:56-60` |
| font | Anthropic Sans 12 pt (16 px) | `:35-38` |
| Escape | navigate back one view; Backspace on empty query pops | upstream `escape_key_behavior: navigate_back`, `pop_on_backspace: true` |
| on close | pop to root | `:42` |
| clock | `hh:mm`, refreshed every 60 s, in the root status bar | upstream `launcher_window.clock` |
| file results at root | off (`search_files_in_root=false`); fallback "Search files" | upstream defaults |
| single-click activation | off | upstream default |

### 4.5 Timings in use

| What | Value | Where |
|---|---|---|
| default toast | 5000 ms | `home/vicinae.nix:121` |
| critical toast | never | theme fragment `[urgency=high]` |
| OSD | 1500 ms, one slot | `bin/osd:28` |
| pomodoro start / pause / resume / stop | 1500 / 1000 ms; break and focus prompts 5000 ms | `bin/pomodoro:30,38,53-59,115,121` |
| herdr-attention | 15000 ms toast, `--wait` up to 120 s, then terminate | `herdr-attention:258-273` (branch `herdr-sway-context`) |
| screen recording | `-t 0` critical "Started", `-t 0` low "Stopped" (a **low** toast that never expires) | `bin/record:10-26` |
| clipboard eviction | 86 400 s (enum: never, 900, 3600, 86400, 604800, 2592000, 31536000) | `home/vicinae.nix:73`; `clipboard-preferences.hpp:14-21` |
| Claude capacity poll | ≥ 300 s; cache 60 s; serve stale ≤ 15 min | waybar `modules:97-112`; `bin/claude-capacity:27-41` |
| battery poll (Waybar era) | 3 s | `modules:25` |
| Vicinae clock | 60 s | upstream default |
| UPower critical action | power off at 5 % | `hosts/client/default.nix:411-416` |

### 4.6 Waybar-era look (historical, for reference only)

- Bar: bottom of eDP-2, `layer top`, not exclusive, 16 px JetBrainsMono/Iosevka Nerd Font; modules padded
  0 10, margin 3 0, 1 px border in `mantle`; tooltips square with a 2 px border (`style.css:6-34,89-100`).
- Palette `mocha.css`: catppuccin mocha with **base, mantle and crust all #000000** (`mocha.css:8-10`), text
  #cdd6f4. This is the seed of today's noir.
- Workspaces: default `surface0` #313244, active `subtext0` #a6adc8, focused bg `maroon` #eba0ac, urgent bg
  `green` #a6e3a1 with black text, hover `mantle` (`style.css:46-79`).
- Module inks: clock `yellow`, volume `blue`, battery `green`, backlight `mauve`, Claude capacity `sky`
  (warning `peach`, critical: 2 px red underline blinking 0.5 s alternate) (`style.css:113-204`).
- Pomodoro bar: 10 px full-width strip; work fill `text`, break `green`, paused `peach`, empty `base`, base
  colour `red` (`pomodoro-bar.css:23-40,189-190,494-495,799-800`).

---

## 5. Reusable code and data (exact paths)

### 5.1 Notification daemon, store and client (prior GPUIX shell, 2026-10-14)

| File | Lines | Reuse | Change before reuse |
|---|---|---|---|
| `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/notifications-daemon.ts` | 79 | dbus-next server: `requestName(DO_NOT_QUEUE)` refusal (:12-13), `Notify` signature `susssasa{sv}i` (:47-55), signals (:52-55), Unix-socket subscribe/command protocol (:57-75), crash-backoff respawn of the toast process (:19-37), clean shutdown (:76-77) | Advertise `actions, body, body-markup, icon-static` (+ `persistence` once the centre exists) instead of `actions, body` (:45). Read hints `value`, `image-data`/`image_data`/`icon_data`, `image-path`, `desktop-entry`, `category`, `x-canonical-private-synchronous`, `x-dunst-stack-tag` (today only `urgency/resident/transient`, :48). Pass `app_icon`. Emit `ActivationToken`. Server info `gpuix-shell`. |
| `.../desktop-shell/notifications.ts` | 83 | Store with replace-in-place (:26-29), move-to-newest (:39-42), action key caps (:31-36), close reasons, `dismiss-latest`, `dnd` | `-1` → 5000 not 6000 and honour explicit `-t` on critical (:45); history on expiry/dismissal only, newest 5 visible to `restore` (:47-49); add `restore`, `dismiss --all` that keeps history, `clear-history`, `invoke [id] [key]`, `list/history --json`; keep `progress` (value) on the item. |
| `.../desktop-shell/notifications-client.ts` | 43 | Subscribe with reconnect backoff (:10-33), one-shot command (:34-43) | Socket path → `$XDG_RUNTIME_DIR/gpuix-shell/…` per BRIEF §3.2. |
| `.../desktop-shell/notifications.test.ts`, `notifications-client.test.ts`, `notifications-integration.test.ts` | 45 / 30 / 37 | Pure store tests; private-bus integration test (gated) | Add the cases in §5.2. |
| `.../desktop-shell/ui.tsx` | 1239-1300 | Toast layer surface sized to its rows (`toastCount*148-8`), anchor `["top"]` (= top-centre), `keyboardInteractivity none`, recreated when the count changes (GPUIX cannot resize or set an input region) | Opaque background (it uses `background + "e6"`, :1019, which breaks the no-translucency rule); radius per §6 G2; margin top 12 not 40. |

### 5.2 Conformance cases the daemon must pass (drawn from Tom's real callers)

Each line is a `notify-send` invocation from a file in this repo; a bun test can replay them against the
store, and a runtime-test smoke can replay them over a private bus (`dbus-run-session`, as
`tests/sway-vicinae/smoke.py:88-90,289` does).

1. `osd`: `notify-send -p -t 1500 -a osd -h int:value:45 Volume 45%` prints an id; the same with `-r <id>`
   while live keeps the id; after 1600 ms `-r <id>` prints a **new** id (`bin/osd:27-37`).
2. `osd` without a value: `notify-send -p -t 1500 -a osd Touchpad off` (no progress drawn).
3. `record`: `notify-send -u critical "Screen Recording Started" -t 0` stays until dismissed;
   `-u low … -t 0` also stays (explicit 0 beats the urgency).
4. `herdr-attention`: `notify-send --app-name=Herdr --urgency=normal --expire-time=15000 --action=default=Open --wait -- "Herdr · 3: x" "a &amp; b is waiting…"` renders "a & b", and a body click makes stdout `default` and exit 0 (`herdr-attention:258-273`).
5. `herdr-picker`: plain `notify-send 'Herdr navigation' 'Select … in the Herdr navigator.'` (`herdr-picker:561`).
6. `pomodoro`: options after positionals, `notify-send "Pomodoro Stopped" -t 1000` (`bin/pomodoro:38`).
7. `tests/sway-vicinae/smoke.py:234`: `notify-send -t 0 "Desktop smoke test" "Mako · Anthropic Sans · …\nSynthetic preview…"` then the list probe finds the summary.
8. Five more than `max-visible`: six live toasts show four cards and "(2 more)".
9. `CloseNotification(id)` emits `NotificationClosed(id, 3)`; right click emits reason 2; expiry reason 1.
10. Mod+O path: `gpuix-shell notify dismiss --all` then `gpuix-shell notify restore` brings back the newest.

### 5.3 OSD contract to keep

`home/dot_local/bin/osd` (38 lines) is the only interface the hardware-key scripts use. It needs
nothing but a spec-compliant daemon. If the OSD gets its own window, the daemon routes
`app_name == "osd"` there and keeps replace-id semantics, so `volume`, `brightness`, `touchpad-toggle`
and `audio-route` work unchanged and keep working if the shell is off. DESIGN.md §8.5 (P-10) has the
scripts call `gpuix-shell osd show <kind> <value>` instead; if that lands, keep `osd`'s notify-send path
as the fallback when the socket is absent.

### 5.4 Browser tabs: reuse the installed extension

- Extension `kcmipingpfbohfjckomimmahknoddnke`, force-installed by policy (`modules/sway.nix:104-106`).
  It **is** installed on the Zenbook: "The declared extension installed, its native-messaging process
  runs, and Vicinae exposes browser-tab search" (`docs/client-sway-vicinae.md:215-216`, 2026-10-07
  receipt). This answers note 36 §6 G4's "unknown".
- Host manifest `com.vicinae.vicinae` linked from the Vicinae package (`home/vicinae.nix:98-99`).
  Replace its `path` with a gpuix-shell native host; keep the name so the extension needs no change.
- Wire protocol (MEASURED in the main clone by note 36 §4.6 and note 35): native messaging (uint32 length
  + JSON) on stdin/stdout; the extension sends `browser/init` and `browser/tabs-changed` (full tab list:
  id, title, url, windowId, active, audible, muted, lastAccessed, pinned; debounced 50 ms) and accepts
  `browser/focus-tab {tabId}` and `browser/close-tab {tabId}`. Verify against the published extension
  version, since the clone is newer than v0.29.1 (§6 G18).

### 5.5 dmenu replacement contract

- Caller side to swap: `vicinae_menu()` and `dmenu()` in `home/dot_local/bin/herdr-picker:211-267`.
  Keep `dmenu()`'s validation: an empty result means dismissed; in list mode the result must equal a
  row ("typed text is not a command").
- New CLI: `gpuix-shell dmenu --prompt P [--free-text] [--password]`, rows on stdin, selection on stdout,
  exit 1 on dismiss; replies routed per connection (the Vicinae 0.29.1 bug, `docs/vicinae-research.md:144-148`).
- Native provider data: `herdr-picker --json` (`:505`) gives the rows and actions read-only, with no GUI.
- Test fixture to copy: `tests/sway-vicinae/smoke.py:201-229` (selected row; free text with empty stdin;
  concurrent CLI calls while the menu waits).

### 5.6 Smoke-test recipe to fork into `tests/gpuix-shell/`

- `tests/sway-vicinae/smoke.py:39-91` evaluates the **real** client config (`nix eval` of
  `nixosConfigurations.client`), copies the raw Sway config with inert session/startup fragments, and
  writes a private `dbus.conf` with no activation directories.
- `:262-290` refuses to run without `~/.local/bin/runtime-test` and bubblewrap, strips `HERDR_*`, and runs
  `runtime-test -- bwrap --unshare-net … dbus-run-session --config-file dbus.conf -- python smoke.py --inside`.
- Changes for GPUIX: `WLR_RENDERER=gles2` with the render node (`runtime-test --render-node
  /dev/dri/renderD128`), not `pixman` (`:282`), because pixman loses the Vulkan surface (BRIEF §5); the
  library path recipe from `docs/gpuix-shell/evidence/rail-probe/smoke.py`.
- Probes to replace: `vicinae ping` / `vicinae state open` / `vicinae close` (`:127,195,199,239-240`) →
  `gpuix-shell ping`, `gpuix-shell launcher state`, `gpuix-shell launcher close`; `makoctl list`
  (`:235`) → `gpuix-shell notify list --json`.
- Fixtures: `tests/workspace-switcher/fixtures/zenbook-0221-{get_tree,get_outputs,get_workspaces}.json` on
  branch `/home/tom/.wt/dotfiles/morning-shell` (7464298c) are real Zenbook captures for rail/switcher
  tests.
- A differential test is possible because mako 1.11 is in the store
  (`/nix/store/n17vf7d32lq4q36y8qd1i4b3m51bf3b0-mako-1.11.0`): replay §5.2 against mako, record
  `makoctl list -j` / `history -j`, then replay against the gpuix daemon and compare (one daemon per
  private bus at a time; INFERRED design, not built).

### 5.7 Launcher providers

| What | Path | Reuse |
|---|---|---|
| Desktop-entry parser + scoring | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/applications.ts:11-102` | copy; verify NoDisplay/Hidden and `Terminal=true` → kitty |
| Calculator (recursive descent: + − × ÷ % ^, parentheses, unicode operators, 14 significant digits) | `.../desktop-shell/providers.ts:176-225` (+ `providers.test.ts`) | copy as the inline provider; units/currency later |
| Bounded file search (names and mtime only, no contents) | `.../desktop-shell/providers.ts:133-163` | restrict roots to Downloads + Documents (Vicinae parity) |
| Command catalogue (record, monitors, media, mute, mic…) | `.../desktop-shell/providers.ts:1-68` | ids become launcher commands that call the same scripts |
| Explicit gap list | `.../desktop-shell/providers.ts:70-76` | the honest "not yet" list: Chrome tabs, tray, file index, unit/currency, clipboard retention |
| Clipboard via `cliphist` | `.../desktop-shell/providers.ts:108-131` | **do not reuse**: wrong owner (cliphist is installed but not running, `startup.conf:4`); the new watcher owns history |
| Dotfiles commands | `home/vicinae.nix:146-170` | port the seven entries 1:1 (names, subtitles, argv) |
| Theme renderer to extend | `home/themes/default.nix:125-177` (role maps), `:281-290` (`render`) | add `gpuix-shell.json` with the roles in §4.3 |

### 5.8 Clipboard semantics to reimplement (Vicinae source, main clone 8c63ae2ef)

- Password hint MIME `x-kde-passwordManagerHint`, concealed MIME `vicinae/concealed`, `text/uri-list`
  (`src/lib/common/include/common/clipboard-formats.hpp:5-8`).
- Ignore-password branch (`src/server/src/services/clipboard/clipboard-service.cpp:707-710`); main also
  has an ignored-source-apps list (`:712`), not checked against v0.29.1.
- Dedupe hash = MD5 over each offer's MD5 (`clipboard-service.cpp:518-525`).
- Eviction enum and default action Paste (`src/server/src/builtins/clipboard/clipboard-preferences.hpp:14-21,108`).
- Actions and HUD strings (`src/server/src/builtins/clipboard/history/clipboard-history-actions.hpp:14-178`).

### 5.9 Bar data that still exists

- `home/dot_local/bin/claude-capacity`: `--waybar` (default; JSON `{text, tooltip, class, percentage}`),
  `--json`, `--check` (exit 0/1/2) (`:9-15`). Poll ≥ 300 s.
- Workspace glyph map and colours: `git -C /home/tom/mecattaf/dotfiles show 1d926f2e^:home/dot_config/waybar/modules`
  lines 64-91 (Nerd Font private-use codepoints; read them with a byte-level tool, they do not print).
- Battery thresholds 95/30/20 (`modules:13-26`).

### 5.10 Menus and attention

- Wi-Fi: `home/dot_local/bin/fzf-nmcli` (libnm through GObject; based on networkmanager-dmenu); NM and BlueZ
  D-Bus members and the gpui-shell Rust references are in note 26 §5.
- herdr attention → Sway urgency + actionable toast: `/home/tom/.wt/dotfiles/herdr-sway-context/home/dot_local/bin/herdr-attention`
  (442 lines; urgency `:203-247`, toast `:249-281`), commit c1a49b99, unmerged.
- Open issue text with acceptance criteria: #508 (paste into Kitty/Herdr/Chrome; image paste), #509 (Wi-Fi:
  status, scan, known networks, connect/disconnect, SSID with punctuation, no shell interpolation), #510
  (Bluetooth: discovery, pair with confirm/PIN/passkey, connect, remove; real devices), #512 (durable
  Herdr identity per projector), #539 (Navidrome, now covered by the music workstream).

---

## 6. Gaps, conflicts and unknowns

Numbering is stable; other notes cite G1, G3, G4, G5.

- **G1 Toast anchor (conflict, decide for Tom's rulings).** Tom: top-centre (own commit db35f95e,
  2024-05-30; verbatim 2026-10-11 19:37Z "plz make the mako notifications be top and center not top
  right on the screen"). DESIGN.md §8.4 / A-15, BRIEF §3.3 and SHELLS-DIGEST say top-right. INFERRED
  recommendation: default `layout.toast.anchor = "top"` (top-centre), margin `[12,0,0,0]`; keep the key.
  The integrator should add this to ASSUMPTIONS.md.
- **G2 Corner radius (conflict).** Every corner Tom has set himself is square: 2024-11-10 commits
  (SwayFX, mako, Waybar, wlogout), niri 2026-09-25 "square corners", mako and Vicinae radius 0 kept since
  2026-10-07. DESIGN.md A-05 sets radius 12 on launcher, toasts, OSD, controls and power and rejects
  "Vicinae's 0", citing BRIEF §3.6's Tacit inference ("rounded 8/12 inner corners", which is the
  orchestrator's wording, not Tom's). Tom's 10-20 words are "i like the vanilla-ness of it"; they do not
  mention corners. INFERRED recommendation: one `radius.outer` token in `gpuix-shell.json`, flagged in
  MORNING.md as the first thing Tom will notice; if no one decides, square outer corners (0) match every
  explicit choice he has made.
- **G3 Output targeting.** GPUIX 0.11.0 `LayerShellOptions` has no `output` field
  (`@gpuix/native/index.d.ts:685-721`, MEASURED). A surface opens on the focused output. mako shows toasts
  on the focused output too, so Chrome toasts appear on eDP-2 when Tom is on workspace 10. DESIGN.md A-07
  pins every layer surface to eDP-1 (create while eDP-1 is focused, recreate on change): that differs from
  today for toasts. Rail and switcher must be eDP-1; toasts can follow focus.
- **G4 OSD placement and identity.** Today the OSD is a top-centre mako toast with a progress fill.
  DESIGN.md §8.5 puts it bottom-centre (margin 96), 280×56, radius 12, with scripts calling
  `gpuix-shell osd show`. Neither is a Tom ruling; Tom ruled only the path (10-13: "keypress>sway>script
  execution"). Keep `bin/osd` working against the daemon either way (§5.3).
- **G5 Toast card height.** mako shrinks each card to its text (≤ 100 px); DESIGN.md A-17 fixes 140 px
  because GPUIX cannot resize a surface (A-16). A fixed 140 px card is tall for "Volume 45%"; routing
  `app_name == "osd"` to the OSD window avoids that.
- **G6 Launcher size and position.** Today 770×480 centred, square, 1 px border. DESIGN.md: 700×580 at
  108 px from the top, radius 12. The 700×580/108 values come from the design kit; this reader found no
  Tom quote for them (note 20 attributes them to Tom; not re-checked here).
- **G7 Low-urgency timeout.** DESIGN.md §8.4 sets low 3000 ms. mako today gives low the default 5000 ms,
  and `record` sends a low toast with `-t 0` that must never expire. Explicit `-t` must win over any
  urgency default.
- **G8 Stack order.** mako: newest on top (closest to the anchor edge). DESIGN.md §8.4 / U-12: "packs
  newest at the bottom … new toasts enter below existing ones". That reverses what Tom sees today. Pick
  one and say so; parity says newest on top.
- **G9 Calculator usage.** No evidence Tom uses Vicinae's calculator or its currency rates (rate refresh
  is a network call). Ship arithmetic first.
- **G10 Which player the media keys drive.** `bin/media` calls `playerctl` with no `--player`. With Chrome
  and the gpuix music daemon both on the bus, playerctl picks one by its own rules. Decide whether the shell
  sets a preferred player (for example `playerctl --player=gpuix_music,%any`).
- **G11 Tray.** Which StatusNotifier apps run on the Zenbook is unknown (OBS is installed). Measure on the
  client (`busctl --user list | grep -i StatusNotifierItem`) before building the watcher. Not run tonight:
  this reader is on the strix and the Zenbook is live.
- **G12 Lock.** No locker is declared (no swaylock/gtklock/hyprlock in any `.nix`, MEASURED grep), so
  Vicinae's "Lock" and a `power` "Lock" have nothing to call. Decide: add swaylock or drop Lock.
- **G13 Body markup in GPUIX.** No Pango. Upstream GPUIX style supports `fontWeight` and
  `textDecoration: underline | line-through` (`/home/tom/Downloads/gpuix/packages/native/src/style.rs:234-240`)
  but no `fontStyle` (italic exists only in its markdown renderer, `markdown/render.rs:105`). Plan: parse
  `<b> <i> <u> <a>` and entities into spans; render `<i>` upright; strip unknown tags.
- **G14 Touch on toasts.** The Duo's panels are touch screens (`home/home.nix:155`). GPUIX exposes
  `touchPhase` only on scroll events (`index.d.ts:582-585`); whether a tap reaches `onClick` on a layer
  surface is untested.
- **G15 Clipboard capture details.** `wl-paste --watch` runs a command per change but hands it one MIME
  type; the watcher must then list types (`wl-paste --list-types`) to see the password hint and to pick
  image vs text, which races with a fast second copy. Size caps for images are not set by Tom; propose
  a cap (INFERRED: 20 MB per entry) and keep the store 0600.
- **G16 Paste.** Today is copy-only (`input_server.enabled = false`); #508 (real paste into Kitty/Herdr and
  Chrome) is open. Keep copy-only until Tom rules; `wtype` is installed for tests only.
- **G17 History migration.** Vicinae's clipboard DB is not imported (and a NAS password once landed in it).
  Start empty; the 24 h eviction makes the loss small.
- **G18 Browser protocol version.** The protocol in §5.4 was read in the main clone (8c63ae2ef), not at
  v0.29.1, and the extension in Chrome auto-updates from the Web Store. Verify the message names against
  the installed extension before relying on them.
- **G19 Chrome's notification hints.** Not captured. One `dbus-monitor --session
  "interface='org.freedesktop.Notifications'"` on the Zenbook (or a private bus with Chrome) would settle
  `image-path` vs `image-data`, `desktop-entry` and action keys.
- **G20 Issue bookkeeping.** #508, #509, #510, #512 and #539 are open against "Vicinae"; once the shell
  covers them, they should be re-pointed or closed. #511 is closed as not planned and must not be
  reopened by routing the volume keys through the launcher.
- **G21 Remote notifications.** Herdr runs on the strix and "does not … forward all remote toasts"
  (`docs/client-sway-vicinae.md:147-148`). Agent attention reaches the Zenbook only through
  `herdr-attention` on the unmerged `herdr-sway-context` branch.
- **G22 Waybar output field.** The old bar sat on eDP-2 (bottom panel); the rail goes on eDP-1. On the
  ThinkPad variant there was no output. Hosts other than the Zenbook have no second panel; nothing in the
  shell should assume eDP-2 exists.
- **G23 makoctl muscle memory.** PR #571 (Mod+O), `bin/theme:84-87` and the two desktop entries call
  `makoctl`. Either rewire all of them in the same commit that turns mako off, or ship a `makoctl` shim
  (§3.3).
- **G24 Type size.** Tom chose launcher text "larger than 11 … start at 12" (points) = 16 px; toasts are
  11 pt ≈ 14.7 px. DESIGN.md uses 14 px launcher input, 13 px rows and titles, 14 px toast body: every
  one is smaller than what Tom set. Check DESIGN's px against points before the first screenshot goes to
  Tom (INFERRED conversion at 96 dpi, the Qt/Pango convention on Wayland at integer scale).

---

## 7. What this reader did and did not do

- Read (MEASURED): BRIEF.md; the deleted Waybar files at `1d926f2e^` (config, config-thinkpad, modules,
  style.css, mocha.css, pomodoro-bar.json, pomodoro-bar.css); `home/vicinae.nix`;
  `home/themes/{default,noir,claude-dark,claude-light}.nix`; `docs/vicinae-research.md` and
  `docs/client-sway-vicinae.md` in full; `tests/sway-vicinae/{smoke.py,README.md,herdr_local.py}`;
  `home/dot_config/sway/{binds.conf,rules.conf,startup.conf}`; the OSD script and its callers; PR #571's
  branch (`git diff main`, `gh pr view 571`, OPEN); PR #565's branch (three-dot diff); mako 1.11 man pages
  and a byte scan of its binary; GPUIX 0.11.0 `index.d.ts`; the prior desktop-shell notification files;
  the Vicinae clone's clipboard, calculator and config files; GitHub issues #508-#512 and #539; Tom's
  2024-2025 mako commits; DESIGN.md, ASSUMPTIONS.md and note 26 for conflicts.
- Transcript quotes re-checked tonight: 10-07 11:07Z and 11:13Z (Codex 01a1160b), 10-11 19:37Z and
  19:38Z (b61fd73f), 10-12 08:48Z and 09:20Z (1376398e). The other quotes in §2 were carried from this
  note's first pass and not re-read.
- Not run: no notify-send, mako, Vicinae, Sway, herdr or systemd command; no D-Bus call; nothing on the
  Zenbook. Every behaviour of mako and Vicinae above comes from config, man pages, source or the 10-07
  receipts, not from a test tonight.
- Wrote only this file. The conflicts G1, G2, G7, G8 and G24 are for the integrator to record in
  ASSUMPTIONS.md.
