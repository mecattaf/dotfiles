# 35 — Vicinae source inventory: builtins, providers, services, UI grammar, keys, theme, CLI

Reader note for the gpuix-shell overnight build (2026-10-20/21). Read-only inventory of the
Vicinae clone at `/home/tom/Downloads/vicinae` for a full GPUIX reimplementation of its
Linux/Wayland-facing feature set. Labels: **MEASURED** = read in the pinned source or in Tom's
dotfiles at the cited line; **REPORTED** = taken from a dotfiles doc, a wave-1 note or a commit
message; **INFERRED** = my reading. Nothing here was executed: Vicinae was not launched, no
socket was touched, no live Sway was involved. Paths under `src/` are relative to the clone;
`DF/` is this worktree (`/home/tom/.wt/dotfiles/gpuix-shell`).

---

## 1. What the source is

| Item | Value | Evidence |
|---|---|---|
| Clone | `/home/tom/Downloads/vicinae`, `git describe` = `v0.29.1-18-g8c63ae2ef` | MEASURED |
| HEAD | `8c63ae2ef` 2026-10-13 "feat(windows): add keyboard binding preference for "run as administration" action (#2078)" | MEASURED |
| Stack | C++23 + Qt 6 QtQuick/QML (QML is presentation only; C++ "view hosts" expose `Q_PROPERTY`/`Q_INVOKABLE`), React/TypeScript extension API run by a Node "extension-manager" over protobuf on stdio; own IPC generator `figura` | MEASURED `AGENTS.md:1-20`, `src/typescript/extension-manager/README.md:1-9` |
| Size of what matters | builtins 12 617 lines (`src/server/src/builtins/**`), root-search 2 089, services ≈ 48 k (window-manager 5 914, clipboard 3 573, app-service 3 612, files 2 127, global-shortcuts 1 999, builtin-icon 1 746, snippet 1 478, calculator 1 398, root-item-manager 1 281, tray + tray-host 2 134) | MEASURED `wc -l` |
| Docs | **No `docs/` directory in the clone** (docs live at docs.vicinae.com in another repo). The configuration reference is `extra/config.jsonc` (258 lines, fully commented) and the settings strings in `src/server/src/ui/qml/settings/*.qml`; the theme reference is `extra/theme-template.toml` | MEASURED (`find -name docs` empty) |
| Platforms | Linux (main target), macOS, Windows; many builtins are `#ifdef`-gated | MEASURED |
| Processes | `vicinae server` (Qt app) + helpers found via `findHelperProgram`: `vicinae-input-server` (setcap'd key injector), `data-control-server` (Wayland clipboard watcher), `file-indexer`, `vicinae-url-handler`, `vicinae-browser-link` (native-messaging host), Node extension-manager | MEASURED `services/input-server/linux-input-server.cpp:82-103`, `src/data-control-server/`, `src/file-indexer/`, `src/cli/src/url-handler-main.cpp`, browser-extension grep |
| Unit | `extra/vicinae.service`: `ExecStart=vicinae server --replace`, `ExecReload=kill -HUP`, `Restart=always`, `RestartSec=60`, `Requires=dbus.socket`, `PartOf=graphical-session.target` | MEASURED |
| HM module | `nix/home-manager-module.nix`: `programs.vicinae.{enable,package,enableSoulver,enableNumen,enableFirefoxIntegration,enableChromeIntegration,systemd.{enable,autoStart,environment,target},launchd.*,extensions,themes,settingOverrides,settings}` | MEASURED lines 58-130, 140-235 |

### 1.1 How Tom runs it today (the thing being replaced)

`DF/home/vicinae.nix` (172 lines, MEASURED):

- `programs.vicinae.enable` on `myDisplay.enable` hosts only; systemd target `sway-physical-session.target`; `QT_QPA_PLATFORM=wayland` (l.24-33).
- `font.normal = { family = "Anthropic Sans"; size = 12; }` with the comment `# Tom, 2026-10-12: "make the font larger than 11 (12 or 14, need to decide, start at 12)"` (l.35-38).
- `telemetry.system_info = false`; `tray.enabled = false` ("Search Tray still hosts other applications' tray menus"); `input_server.enabled = false` ("Copy works; no privileged input injection"); `pop_to_root_on_close = true`; `favicon_service = "none"` (l.39-43).
- `theme.dark.name = theme.light.name = "dotfiles-current"` → `~/.local/share/vicinae/themes/dotfiles-current.toml` is a `mkOutOfStoreSymlink` to `~/.config/theme/vicinae.toml`, i.e. the theme follows the `~/.config/theme` pointer like Kitty/Herdr; "`theme apply` rescans and reloads it without restarting Vicinae" (l.44-47, 94-97).
- `launcher_window = { opacity = 1; material = "none"; rounding = 0; client_side_decorations = { border_width = 1; shadow_size = 0; }; layer_shell = { enabled = true; layer = "overlay"; keyboard_interactivity = "exclusive"; }; }` (l.48-61). Window size is the default 770×480.
- Providers: `core.entrypoints.report-bug.enabled = false`, `core.entrypoints.sponsor.enabled = false` (Tom, 2026-10-12); `clipboard.preferences = { monitoring = true; ignorePasswords = true; evictionThreshold = "86400"; preserveTagged = true; }`; `files.preferences = { autoIndexing = true; indexingPaths = [ ~/Downloads ~/Documents ]; }` (l.62-83).
- Favorites, in order: `applications:herdr-picker`, `clipboard:history`, `browser-extension:browse-tabs`, `media:now-playing`, `core:search-tray` (l.84-90).
- Chrome native-messaging host installed from the package; `xdg-terminals.list = kitty.desktop`; ROG Control Center launcher hidden (l.98-109).
- mako: `font = "Anthropic Sans 11"`, `anchor = "top-center"` (`# Tom, 2026-10-11: "top and center not top right"`), width 390, margin 12, padding 14, border 1, radius 0, timeout 5000, max-visible 4, layer overlay, colours from `~/.config/theme/mako.conf` (l.111-143).
- Desktop entries that make dotfiles scripts searchable in the launcher: `herdr-picker` ("Herdr workspaces"), `sway-workspace new|restore|rename`, `makoctl dismiss|restore`, `kitty --class network-settings nmtui` (l.148-170).

Sway binds (MEASURED `DF/home/dot_config/sway/binds.conf:6-7,114`): `$mod+d exec vicinae toggle`, `$mod+space exec vicinae toggle`, `$mod+v exec vicinae cmd launch clipboard:history`. The herdr picker (`DF/home/dot_local/bin/herdr-picker:211-258`, 574 lines) drives Vicinae's **dmenu** over the IPC socket directly: JSON-RPC 2.0 `{"method":"Ipc/dmenu","params":{"req":{rawContent,placeholder,format:"Data",noSection,noQuickLook,noIcon,noMetadata,noFooter,password}}}` framed with a 4-byte native-endian length on `$XDG_RUNTIME_DIR/vicinae/vicinae.sock`, with a random high request id because "Upstream's CLI starts every connection at ID 1 ... A concurrent CLI/browser call can steal dmenu's reply".

---

## 2. Verbatim Tom rulings about the desktop shell and the launcher (dated)

Newest wins. Quotes are verbatim, typos included.

| Date | Tom | Source | Bearing |
|---|---|---|---|
| 2026-10-07 | "the concept of a spotlight menu sort of thing, along with all of the contextual information that it can hold at any given moment is probably the most underused item on the modern desktop and it should be really strengthened given that we're on swaywm (with its ipc) on linux, and the vicinae product is a great foundation to start" | REPORTED `wave1/06-transcript-cc-big-oct14-b.md:141` (`~/today/2026-10-14-computer-use-study/longrun/ambient-computer.md:113`) | The launcher must be contextual (Sway IPC, herdr state) |
| 2026-10-07 am | "herdr itself is becoming the true cornerstone of this setup. truely: herdr+kitty+chrome+claudecode + vicinae" | REPORTED `wave1/04-transcript-cc-look-pivot.md:168` | Vicinae was then part of the five-piece core |
| 2026-10-07 late | "i also push back completely on its "keep vicinae" framing.. i would like to fully supersede this." | MEASURED `/home/tom/today/dematerialized-2026-10-07/00-TOM-WORDS-AND-FRAME.md:5-7` | First "supersede Vicinae" |
| 2026-10-11 | mako "top and center not top right" | MEASURED `DF/home/vicinae.nix:115` | Toast anchor (conflicts with BRIEF §3 "toasts = overlay top-right"; see §6) |
| 2026-10-12 | "we keep vicinae actually.. i was getting a little carried away there when i said let's delete it. it's good fucntionality." | REPORTED `wave1/06:143` (dotfiles T-2) | Superseded 10-14 and 10-20 |
| 2026-10-12 | "make the font larger than 11 (12 or 14, need to decide, start at 12)" | MEASURED `DF/home/vicinae.nix:37` | Launcher UI font 12 |
| 2026-10-12 | "ROG control center, report vicinae bug, donate to vicinae, chatgpt, claude, Claude, gcloud, github (the chrome --app shortcut), GVim, openwebui, perplexity, photos, railway, soundcloud, whatsapp, youtube-music must all be gone" and "this goes for cross-nixosfleet not just on the client" | MEASURED commit `f7167e3b` message (`/home/tom/mecattaf/dotfiles`) | No vendor/self-promo rows in the root; launcher catalogue is curated |
| 2026-10-12 | "the blue color is not the same as the vicinae launcher. i prefer the latter's" | MEASURED `DF/home/themes/default.nix:125-126` | mako progress/accent takes Vicinae's selection blue (`t.selection.bg` #264F78 in noir) |
| 2026-10-13 | "the way we control brightness and volume should be keypress>sway>script execution, no need to tie in vicinae if we don't have to" | REPORTED `wave1/06:146` | Volume/brightness binds stay in Sway; the launcher's volume commands are secondary |
| 2026-10-13/14 00:16 | "whatever you just opened: i love it. this is good enough to also become a functional remplacement to waybar, vicinae and mako notifications." | REPORTED `wave1/03:76`, BRIEF §1 | Scope: the shell replaces Vicinae |
| 2026-10-14 00:17 | "functionality pull from quickshell NOT visuals" | BRIEF §1 | |
| 2026-10-14 | "for the launcher, feature parity at least with vicinae (already enjoyed on my setup) including how it interacts w google chrome tabs is very desirable" | REPORTED `wave1/06:151` (`~/today/2026-10-14-computer-use-study/BRIEF.md:43`) | **Acceptance bar: parity with Vicinae incl. Chrome tab search** |
| 2026-10-14 | "exposing selected functionality tot he user and watching my behavior and selfimproving from there can onyl happen bcz we have a tight grip on the actual keypresses: sway to gpuix shortcuts and fast typing." | REPORTED `wave1/06:152` | Keypress model matters; frecency/visit tracking is wanted |
| 2026-10-14 | "sway has a contextual launcher, a herdr leftbar that is disjinted and contol sway workspaces, clipboard history.. all that stuff that macos version doesn't have. this creates a clean sepaeation layer" | MEASURED transcript `56e498e4` [37] | Launcher, rail, clipboard history are the Sway-only personal shell |
| 2026-10-20 ~22:50 | "a mod+d menu (vicinae remplacement) that presents a given functionality" | BRIEF §1 | The order |
| 2026-10-20 23:20 | "the vicinae implementation is also of interest so make sure to capture that as well"; "a full implementation of the linux wayland sway facing https://github.com/vicinaehq/vicinae ... would be impressive to see. gpuix for the win." | BRIEF §5 | This note |
| 2026-10-20 23:20 | "i would like to have a navidrome music selection in the gpuix shell ... raycast+spotify level searching and playing control from within the launcher"; "this is NOT ONLY about navidrome.. but indeed a welcome set of utilities you can demo for me" | BRIEF §5 | Media provider is a first-class launcher view, not just MPRIS buttons |

Standing (BRIEF §1): Sway only; no blur/frost, flat opaque, hairlines; noir/claude-dark/claude-light via `~/.config/theme`; Anthropic Sans 12 UI; "performance is not really the thing i m looking for here".

---

## 3. Feature inventory

### 3.1 The complete builtin/provider table

Column "Linux mechanism" is what the C++ actually calls on Linux. "GPUIX notes" is how the same behaviour maps onto the `gpuix-shell launcher` process (BRIEF §3 decisions 2 and 4). Keybinds are given by their config id (`action.copy` …); defaults are in §3.4.

| Builtin / provider (id, title) | Commands (id → title) | Behaviour (exact) | Keys | Preferences | Linux-specific mechanism | GPUIX reimplementation notes |
|---|---|---|---|---|---|---|
| **root** (`builtins/root/`) | `root` (the launcher page) | Sections in order: update banner → news → **link** row when the query parses as a URL with scheme ≥ `MIN_SCHEME_LENGTH` ("Open in <default opener>") → **calculator** row (query starting with `=` always; otherwise only when no results and length ≥ `CALCULATOR_MIN_CHARS`) → **favorites** (empty query only) → **results** ("Suggestions" when empty, "Results (n)" otherwise) → **files** (only if `search_files_in_root`, debounced, async) → **fallback** ("Use "<query>" with..." listing `fallbacks`, hidden while file results are pending). An absolute path that exists replaces everything with one file row. `root-search-model.cpp:102-180`, `root-search-sources.cpp:326-482` | Return = primary; see §3.4 | `favorites[]`, `fallbacks[]`, `search_files_in_root`, `pop_to_root_on_close`, `escape_key_behavior`, `pop_on_backspace`, `close_on_focus_loss`, `consider_preedit`, `activate_on_single_click`, `wrap_navigation`, `keybinding` | None | Same section grammar; favorites from `gpuix-shell.json`; herdr workspace rows become a first-class section (Sway IPC + `herdr api snapshot`) |
| **generic root item actions** (`actions/root-search-actions.hpp:146-175`) | — | Every root row gets, after its own actions: Copy Deeplink (`vicinae://launch/<provider>/<entrypoint>`, HUD "Deeplink copied in clipboard"), Reset ranking (confirm), Add to/Remove from favorites, Move up/down in favorites, Set alias (form), Set Global Shortcut (record submenu; only if a hotkey backend exists), Open preferences, Copy ID, Disable item (confirm "You will need to go in the settings to manually re-enable it.") | favorites ctrl+shift+F; move `action.move-up/down`; alias `action.edit-secondary`; copy deeplink `action.copy`; disable `action.remove` | per-entrypoint `providers.<p>.entrypoints.<e>.{alias,enabled,shortcut,preferences}` | — | Keep all; "global shortcut" becomes "write a Sway bind" (the shell has no hotkey protocol) |
| **ranking** (`services/root-item-manager/`, `lib/fuzzy/`) | — | fzf-style weighted scorer: title 1.0, unlocalized title 1.0, subtitle 0.5, alias 1.0, keywords; `MIN_QUALITY = 60` filters; `score + 6 × frecency`; empty query ranks `100 − 6 + 6 × frecency`; `frecency = min(25, 5·ln(1+0.1·visits) + 10·e^(−days/30)) / 25`; rows whose alias prefix-matches the query sort first, shorter alias first; visits in `<dataDir>/metadata.json`; `baseScoreWeight` per item (browser tabs 1.1). `root-item-manager.cpp:144-200`, `fuzzy-searchable.hpp:19-49` | Space activates an aliased item when its alias starts with the typed text (`supportsAliasSpaceShortcut`) | aliases per entrypoint | — | **Port the formula verbatim** (pure TS, bun test); keep `metadata.json` shape |
| **applications** provider (`root-search/apps/`) | one row per desktop entry; id = `applications:<desktop-id without .desktop>` | Subtitle/accessory = category ("Application" fallback); actions: Open Application / Focus window (order depends on app pref), Pin to all workspaces, Bring to current workspace, Close window (when running), desktop-file Actions with `ctrl+alt+1..9`, Open location (`action.open`), Copy App ID, Copy App Location, Quit (`ctrl+q`), Force quit, Uninstall (`action.dangerous-remove`) `app-root-provider.cpp:55-140` | as listed | per-app prefs | xdgpp desktop-entry parser; `QProcess::startDetached`; terminal apps via `xdg-terminals.list` (`xdg-app-database.cpp:17,457-563`) | Reuse: desktop-entry scan in TS (or `xdgpp` semantics); launch via `swaymsg exec`; "running" = Sway tree `app_id` match |
| **scripts** provider (`root-search/scripts/`) | one row per script command | Raycast-compatible script commands with `@vicinae`/`@raycast` headers: `schemaVersion,title,mode(fullOutput|compact|inline|silent|terminal),packageName,icon,argument1..3 (text|password|dropdown),refreshTime,needsConfirmation,currentDirectoryPath,author,authorURL,description`; dirs = `dataSearchPaths("scripts")` (`~/.local/share/vicinae/scripts`, …) + pref "Custom directories"; watched for rescans; actions Run, Open script (`action.open`), Open script directory, Copy path to script | `action.open` | Custom directories | `QFileSystemWatcher`; `lib/script-command` parser | **Replace with the dotfiles script catalogue** (BRIEF: 20 commands) using the same header grammar so Raycast scripts stay usable |
| **shortcuts** provider + **manage-shortcuts** ("Shortcuts") | `create` → "Create Shortcut"; `manage` → "Manage Shortcuts" | Quicklinks: name, link with placeholders `{argument}` (free name → completer field), `{clipboard}`, `{selection}/{selected}`, `{uuid}`, `{date}`; app (default opener or chosen); icon (default/favicon). Row actions: Open, Open with… (`action.open` submenu), Copy, Edit (`action.edit`), Duplicate (`action.duplicate`), Remove (`action.dangerous-remove`). Root rows take arguments inline; fallback "Open shortcut" with the search text | as listed | — | sqlite store (`services/shortcut/`) | Keep (cheap); store as JSON |
| **extensions** provider | builtin + TS commands | Each builtin/TS command is a root item (`<provider>:<command>`), `disabledByDefault` honoured, fallback "Open command" | — | per-command prefs | — | Same registry pattern (`src/registry.ts`) |
| **browser-tabs** provider + **browser-extension** ("Browser Extension") | `browse-tabs` → "Search Browser Tabs"; `shortcut-active-tab` → "Create Shortcut from Active Tab" | Tabs of every connected browser appear **in the root** (weight 1.1, subtitle = title, keywords = URL, accessory "Tab" + 🔊/🔇) and in a dedicated list; guard shows empty view "No browser connected" + "Open documentation". Tab actions: Switch to tab (Enter), Convert to shortcut, Close tab (`action.remove`), Copy URL (`action.copy`), Copy Title, Copy ID | as listed | — | WebExtension (`src/browser-extension`, Chrome MV3 `chrome.tabs.*` + Firefox manifest) ↔ native-messaging host `com.vicinae.vicinae` (`vicinae-browser-link`) ↔ server socket | **Tom's acceptance bar.** Reuse the extension unchanged and write our own native host (Node/bun) speaking its JSON; Chrome policy install already in dotfiles |
| **clipboard** ("Clipboard") | `history` → "Clipboard History"; `clear` → "Clear Current Clipboard Data" (HUD "Clipboard cleared" 🤫); `clear-history` → "Clear Clipboard History" (confirm "Your clipboard history will be gone forever :(") | History view: placeholder "Browse clipboard history...", kind filter dropdown All/Text/Images/Links/Files (persisted `all|text|image|link|file`), Pause/Resume clipboard toggle, "%n Items" count, detail pane (text/image/file preview + metadata; states "Decryption failed", "Data unavailable", "Data is encrypted"). Row actions: Paste to active window / Copy (order by pref, Paste only if `supportsPaste`), Open / Open with (links, files; `action.open`, ctrl+shift+O), Save as (`action.save`), Pin (`action.pin`), Edit keywords (`action.edit`), Remove (`action.remove`), Remove all (`action.dangerous-remove`). Kinds Text/Image/File/Link/Unknown from mime (`text/uri-list` of local files → File). Drag-and-drop out of rows | as listed | provider: `monitoring`, `ignorePasswords` (non-mac), `preserveTagged`, `ignoredApps` (Apps picker), `evictionThreshold` (never/900/3600/86400/604800/2592000/31536000), `eraseOnStartup`; command: `defaultAction` paste/copy | `ext-data-control-v1` via helper `data-control-server`; fallbacks gnome/x11/qt/dummy; sqlite `selection`+`data_offer` tables with `fuzzy_trigram` FTS tokenizer, md5 dedupe, AES-256-GCM at rest (`encrypt_sensitive_data`), `x-kde-passwordManagerHint` → `isPassword` | **Replace** (BRIEF decision 4): `wl-paste --watch` + own store (JSON/SQLite via bun), keep kinds, pin, keywords, eviction, password-hint skip, Mod+V entry (`gpuix-shell launcher --view clipboard`) |
| **files** ("System files") | `search` → "Search Files" (**fallback by default**) | Placeholder "Search for files..."; category filter All/Other/Directories/Images/Videos/Audio/Archives/Documents/Applications; empty query → "Recently Accessed" (XBEL recent files) else "Recently Modified"; results debounced by the indexer's `queryDebounce`; typed absolute path → "Direct file path"; detail pane preview by mime (image/text) | `action.open` family via file actions | Linux: `autoIndexing`, `indexingPaths`, `excludedIndexingPaths` (Directories pickers) | separate `file-indexer` process: sqlite + fts5 trigram, inotify watcher, filesystem walker, incremental scanner, io pacer, periodic full sweeps; cache `~/.cache/vicinae/file-indexer` | Replace with `fd`/`plocate`-backed query or a bun watcher over ~/Downloads and ~/Documents (Tom's two dirs); keep categories and the recent-files section (XBEL `~/.local/share/recently-used.xbel`) |
| **calculator** ("Calculator") | `history` → "Calculator history"; `refresh-rates` → "Refresh Exchange Rates" | Inline in root (see root). Result row actions: Copy Result (primary, HUD "Answer copied to clipboard"), Copy Question And Answer, Copy unformatted answer (`action.copy`), Put answer in search bar, Open Calculator History. History: pin/unpin, copy answer/question/both, Delete entry, Delete all. "You need to copy the result of a calculation for it to be saved in history." | as listed | `backend` dropdown (`numen` default, `qalculate`, SoulverCore on macOS) | libqalculate or bundled Numen | New: a TS expression/unit evaluator (mathjs-class) or shell out to `qalc`; keep the `=` prefix and history semantics |
| **core** ("Vicinae") | `refresh-apps` → "Refresh Apps"; `manage-fallback` → "Configure Fallback Commands"; `search-emojis` → "Search Emojis & Symbols"; `search-tray` → "Search Tray" (Linux only; keywords status/notifier/indicator); `search-menu-bar` (macOS only); `report-bug` (URL; arg `title`; **disabled by Tom**); `settings` → "Open Vicinae Settings" (keywords preferences); `sponsor` → "Donate to Vicinae" (**disabled by Tom**); `store` → "Extension Store"; `list-extensions` → "Show Installed Extensions"; `open-config-file`; `open-default-config`; `reload-scripts`; `show-logs`; `forget-telemetry`; `search-builtin-icons`; `oauth-token-store`; `inspect-local-storage`; `join-discord-server` defined but not in the register list (`vicinae-extension.cpp:256-279`) | Emoji grid: 18 sections (9 emoji: Smileys & Emotion 171, People & Body 388, Animals & Nature 160, Food & Drink 131, Travel & Places 219, Activities 85, Objects 266, Symbols 224, Flags 270; 9 symbol: Math 694, Arrows 427, Currency 39, Punctuation 190, Shapes 344, Misc Symbols 967, Greek 129, Number Forms 108, Fancy Letters 247 = **5 059 glyphs**, `lib/glyph/src/glyph.cpp:40960-40978`), category dropdown, recently-used/pinned ordering by visits, actions Paste/Copy (order by pref), Copy name, Copy codepoint, Copy group, Edit keyword (`action.edit`), Reset ranking, Pin/Unpin, Skin tones submenu "Skin tones" with "Reset to preference". Search Tray: list of StatusNotifierItems with accessory "Attention" (NeedsAttention), actions Activate, Browse Menu (flattened dbusmenu, toggles shown as check icons, "Trigger"), secondary activate; `tray.enabled=false` only hides Vicinae's own icon | as listed | emoji: `defaultAction` paste/copy, `skinTone`; store: `alwaysShowIntro` | SNI: `org.kde.StatusNotifierWatcher` (own fallback watcher if no bar), `org.kde.StatusNotifierItem`, `com.canonical.dbusmenu` over session D-Bus (`services/tray-host/sni/`) | Emoji: **convert `glyph.cpp` to JSON** (script) and reuse; Tray: port the SNI host (dbus-next) — Tom's favourite `core:search-tray` keeps working with no bar |
| **media** ("Media") | `now-playing` → "Now Playing"; `play-pause` → "Play / Pause"; `next-track`; `previous-track`; `volume-up` (arg step "+5"); `volume-down` (arg "-5"); `volume-100/75/50/25/0` → "Set Volume to N%"; `toggle-mute` | Now Playing: placeholder "Search players...", section "Players", accessory Playing/Paused, actions Play/Pause, Next Track, Previous Track. Transport commands take an optional `player` argument (fuzzy over identities), show HUDs "Playing <title — artist>", "Paused", "Next Track", "Previous Track", "Muted"; failures as toasts | — | — | MPRIS `org.mpris.MediaPlayer2(.Player)` over session D-Bus; volume via `pactl` subprocess (JSON sink list) | Keep as the base of Tom's "raycast+spotify level" music provider: MPRIS via dbus-next, `wpctl` for volume (dotfiles `volume` script), Navidrome/OpenSubsonic search + mpv playback as a sibling provider |
| **power** ("Power Management") | `power-off`, `reboot`, `sleep` → "Put System to Sleep", `lock` → "Lock Session", `logout` → "Log Out", Linux: `suspend`, `hibernate`, `soft-reboot` | Each: optional confirm alert "Are you sure / High-impact operation, please confirm", closes window with `clearRootSearch`, runs `customProgram` if set else the D-Bus call; "System can't lock/…" and "Failed to …" toasts | — | per command: `confirm` (default on), `customProgram` (Linux) | `org.freedesktop.login1.Manager` PowerOff/Reboot/Suspend/Hibernate/LockSession/TerminateSession with `Can*` checks; DE session managers tried first for logout | Keep; add `swaymsg exit` for logout and `swaylock`/`loginctl lock-session` for lock; `gpuix-shell power` surface already planned |
| **wm** ("Window Management") | `switch-windows` → "Switch Windows"; `switch-workspaces` (only if backend `hasWorkspaces`); `toggle-fullscreen`, `toggle-floating`, `toggle-overview` by capability | Windows: placeholder "Search open window...", subtitle app, accessory workspace name or "WS n"; section "Window Actions": Focus window, Pin to all workspaces, Bring to current workspace, Close window (`ctrl+Q`), Quit app, Force quit. Workspaces: name, "%n window(s)"/"empty", app icons, "Switch to workspace" | ctrl+Q close | — | Backend selection order Hyprland → GNOME → (KDE) → X11 → Niri → **generic Wayland** (`zwlr_foreign_toplevel_management_v1`: titles/app_id/state, focus/close only, **no workspaces, no capabilities**) `window-manager.cpp:30-59`, `wayland/wayland.hpp` | **Big win**: Sway IPC gives workspaces, outputs, marks, urgency and container ids directly. The Mod+i switcher (PR #565) and herdr rows replace this view |
| **screenshots** ("Screenshots") | `browse` → "Search Screenshots"; `paste-last` → "Paste Last Screenshot" | Grid of screenshots/recordings; Refresh (`action.refresh`); actions Paste (primary), Copy (`action.copy`), Open, Open With, Reveal, Copy File Path, Move to Trash | as listed | — | watches the screenshots dir (INFERRED: XDG Pictures/Screenshots) | Keep as a grid over `~/Pictures/Screenshots` (dotfiles `screenshot` script output) |
| **snippets** ("Snippets") | `create` → "Create Snippet"; `manage` → "Manage Snippets" | Form: name (≥2 chars), content (placeholders `{cursor}` once, `{clipboard}`, `{date}`, `{argument}`, shell command), keyword, expand-as-word, app scope; "serverRunning" flag. Manage: Copy to clipboard, Edit, Duplicate, Remove. Expansion = keyword typed anywhere → delete keyword, paste expansion; undo on next backspace | `action.edit/duplicate/remove` | `enabled` (Expansion), `undo`, `layout` (Keyboard layout), `prePasteDelay` ms (0), `keyDelay` ms (2) | `vicinae-input-server` setcap helper (key monitoring + injection; NixOS caveat in `linux-input-server.cpp:86-89`), RPC over stdio | **Out** (Tom disabled the input server; "no privileged input injection"). Keep "Copy snippet" only |
| **font** ("Font") | `browse` → "Search Fonts" (keywords "browse fonts") | Grid of families; Preview (primary → demo view), Copy family (`action.copy`), Set app font | — | — | fontconfig via Qt | Low priority; a grid over `fc-list` |
| **theme** ("Theme") | `set` → "Set Theme" | List of themes with Set theme, Open theme file (`action.open`), Copy ID (`action.copy-name`), Copy path (`action.copy-path`) | — | — | TOML themes in search paths | Replace with the three dotfiles themes + `theme apply` (`~/.local/bin/theme`) |
| **system** ("System") | `run` → "Run Terminal Program" (arg `command`; keywords "shell command", "run program"); `browse-apps` → "Browse Apps"; `set-default-terminal`; `set-default-browser` | Run: with an argument, validates the program on PATH ("Not a valid executable") then Run in terminal / in terminal (hold) / directly per pref and closes; without argument pushes a run view listing programs with Copy path. Browse Apps: placeholder "Search apps...", accessory "Hidden" for `NoDisplay` entries, actions as the apps provider plus desktop Actions `control+shift+1..9` | as listed | run: `defaultAction`; browse: `sortAlphabetically`, `showHidden` | `ProgramDb` PATH scan; `xdg-terminal-exec` | Keep run-in-kitty; browse-apps merges into the apps provider |
| **developer** / **raycast-compat** / **internal** | `developer:create` "Create Extension"; `raycast-compat:store` "Raycast Store"; `internal:markdown-showcase` | Extension scaffolding, Raycast store browser, markdown test page | | `alwaysShowIntro` | | Out of scope (no extension store) |
| **dmenu** (`ui/views/dmenu-*`) | CLI `vicinae dmenu` / IPC `Ipc/dmenu` | Reads stdin lines, renders a list (optional navigation title, section title, placeholder, initial query, width/height, no-section, no-quick-look, no-metadata, no-footer, password mode); output format `data` (line) or `index`; actions Select entry (Enter), Pass search text, Select and copy entry (`action.copy`); reads all input before display (no streaming) | | | | **Keep the verb**: `gpuix-shell menu` with the same flags so `herdr-picker` and `sway-workspace rename` port by swapping the client (and the socket framing) |

### 3.2 Feature table (feature | exact behaviour | priority Tom gave | keep/replace/new | notes)

| Feature | Exact behaviour in Vicinae | Priority Tom gave | Keep/replace/new | Notes |
|---|---|---|---|---|
| Mod+d / Mod+space launcher toggle | `vicinae toggle` via Sway bind; layer-shell top/overlay, keyboard exclusive, centred on the active screen, 770×480 | 10-20 "a mod+d menu (vicinae remplacement)" | replace | `gpuix-shell launcher` toggle over `shell.sock`; geometry per BRIEF §3 (700×580, top margin 108) |
| Root search with favorites, suggestions, results, fallbacks | §3.1 root row | 10-07 "spotlight … most underused item" | keep grammar | add herdr/Sway context sections |
| Frecency ranking + aliases + visit tracking | §3.1 ranking | 10-14 "watching my behavior and selfimproving" | keep (port) | pure TS, tested |
| Apps | desktop entries, running-window awareness, desktop actions ctrl+alt+N | — | keep | Sway `app_id` match instead of foreign-toplevel |
| Chrome tabs in root and as a view | WebExtension + native host; Switch/Close/Copy | 10-14 "feature parity … including how it interacts w google chrome tabs" | keep (own host) | Mod+0 Chrome workspace focus after switch |
| Clipboard history (Mod+V) | §3.1 clipboard | 10-14 "clipboard history.. all that stuff" | replace (own store) | keep kinds/pin/keywords/eviction/password skip |
| File search | indexer + categories + recent | files pref limited to Downloads/Documents | replace (lighter) | fallback item by default |
| Calculator inline | `=` prefix, auto when no results | — | new (TS) | keep actions |
| Emoji & symbols | 5 059 glyphs, 18 sections, pin, skin tone, keywords | — | keep (data) | convert `glyph.cpp` → JSON |
| Search Tray (SNI) | items + flattened dbusmenu | favourite `core:search-tray` (vicinae.nix) | keep (port) | no bar needed; dbus-next |
| Now Playing / MPRIS / volume | §3.1 media | 10-20 navidrome "raycast+spotify level" | keep + new | volume binds stay in Sway (10-13 ruling) |
| Power | logind verbs with confirm | — | keep | `gpuix-shell power` |
| Window / workspace switcher | generic Wayland, no workspaces on Sway | 10-14 Mod+i switcher, herdr status | replace (Sway IPC) | PR #565 logic |
| Shortcuts (quicklinks) with `{argument}` completer | §3.1 shortcuts | — | keep | JSON store |
| Script commands (Raycast header grammar) | modes fullOutput/compact/inline/silent/terminal | dotfiles scripts are the catalogue | keep grammar | one catalogue (CUBS C4) |
| Snippets / text expansion | needs setcap input server | Tom disabled it | drop | copy-only |
| Screenshots grid | paste/copy/open/trash | — | keep (low) | over `~/Pictures/Screenshots` |
| Fonts grid | preview/copy/set | — | low | |
| Theme picker | TOML themes | dotfiles has 3 themes + `theme` | replace | `theme apply` |
| Settings window | General/Appearance/Extensions/Keybindings/Advanced/About | Nix-declared settings only ("not hidden GUI state") | drop | config is `gpuix-shell.json` from Nix |
| Action panel (ctrl+B) with filter and sections | §3.4 | — | keep | the shell's command palette inside the palette |
| HUD pill (1.5 s) and footer toast (2 s) | §3.3 | — | keep | HUD becomes the OSD surface |
| dmenu over socket | §3.1 dmenu | herdr-picker depends on it | keep verb | `gpuix-shell menu` |
| Deeplinks `vicinae://` | §3.5 | — | keep subset | `gpuix-shell://launch/...` or CLI only |
| CLI verbs | §3.5 | Sway binds call the CLI | keep subset | `toggle/open/close/cmd ls/cmd launch/menu/state` |
| Extensions store / Raycast compat | Node runtime, protobuf | out (BRIEF boundary) | drop | OpenUI programs are the extension story |
| Global hotkey protocols | `xx-hotkey-v1`, `vicinae-hotkey-v1`, X11 | Sway binds instead | drop | |
| Input server / paste-to-active-window | setcap helper | disabled by Tom | drop | |
| Telemetry, news, update banner, sponsor, bug report | root banners, URL rows | 10-12 "must all be gone" | drop | |
| Client-side decorations, blur, materials | CSD border/shadow/rounding; `material` auto/blur/liquid_glass | Tom: border 1, shadow 0, rounding 0, material none | keep Tom's values | hairline only |
| Compact mode | search-bar-only at root until typing | off in Tom's config | optional | cheap with layer-shell resize |
| Clock in footer | `hh:mm`, 60 s | enabled on Linux by default | optional | "no top bar on the Linux head" so the clock lives here or in the rail |

### 3.3 UI grammar (exact)

Window and surfaces (MEASURED `ui/qml/launcher/LauncherWindowLayerShell.qml:8-12`, `hud/HudWindowLayerShell.qml:7-11`, `launcher-window.cpp:919-1000`, `config/config.hpp`):

- Launcher: one `LayerShell.Window`, `anchors: AnchorNone` (compositor centres it), `scope "vicinae"`, `wantsToBeOnActiveScreen`, layer `top` (2) or `overlay` (3) from config, keyboard `exclusive` unless `close_on_focus_loss` (then `on_demand`). Default size 770×480; border 1 (Linux default 3, Tom 1); rounding 10 (mac 26, Tom 0); shadow 12 (Tom 0); opacity ≤1 with material `none|blur|liquid_glass|auto` (Tom `none`). Compact mode collapses to the search bar when: enabled, no unread news, no update, action panel closed, empty query, view stack size 1, no toast (`tryCompaction`).
- HUD: separate layer-**top** window `scope "vicinae-hud"`, no keyboard, a pill `row.width+30 × row.height+20`, radius = height/2, shown 1 500 ms (`hud-bridge.cpp:6`). Content = icon + text ("Copied to clipboard", "Muted", "Playing …").
- Settings and onboarding are ordinary windows.

Launcher page anatomy (top to bottom):

1. **Search bar** (height 60): back button when the view stack > 1; text input with placeholder per view ("Search for apps and commands..." at root, "Browse clipboard history...", "Search players...", "Search open window...", "Search apps...", "Search for files...", "Search tray items...", "Search menu...", "Search fonts"); inline **argument completer** fields (`ArgCompleter`) for commands with `arguments` (Tab moves between them; required ones gate the primary action); optional **search accessory** on the right (a searchable dropdown such as the clipboard kind filter, file category, emoji category, extension dropdown) opened with `open-search-filter` (ctrl+P); a horizontal loading bar under it while async work runs.
2. **Content** = one of: `GenericListView` (sections with `SectionHeader` 30 px; rows with icon, title, subtitle, alias badge, shortcut badge, accessories: text/icon/tag with semantic colour; row inset 6, radius 10, left/right padding 12, text spacing 6; `QuickAccessOverlay` paints ctrl+1..9/0 badges while Ctrl is held 250 ms), `DetailListView` (list + right `DetailPanel`: free content on top, `MetadataBar` below with rows of type `label {label,value,icon?,valueColor?}`, `link {label,value,url}`, `tags {label,tags[{text,color?,icon?}]}`), `GenericGridView` (columns 8, aspect 1.0, spacing 10, padding 20, optional titles, 2 px selection/hover outline), `MarkdownDetailView` (headings, paragraphs, lists, code blocks, tables, blockquotes, callouts, images, hr, html), `FormView` (text, textarea, text editor, password, checkbox, date, dropdown, searchable dropdown, app selector, file picker, shortcut recorder, separator, link accessory; inline errors "Required"), `EmptyView` (icon, title, description, actions), `DMenuView`, store detail, OAuth overlay, missing-preference view.
3. **Footer** (height 40, may float over content): left = navigation icon + title of the pushed view, or the clock at root; an inline **toast** replaces it for 2 000 ms (styles Success/Info/Warning/Danger/Dynamic; Dynamic = spinner for "Refreshing rates..."); right = primary action label + its shortcut tokens, a divider, "Actions" button with the toggle tokens, highlighted while the panel is open.
4. **Action panel**: popover anchored bottom-right over the footer; a filter input "Filter actions..." (debounced), sections with headers, rows showing title + icon + shortcut tokens; "No matching actions". Submenus (Open with…, Skin tones, Set Global Shortcut) push into the same popover.
5. **Alerts**: modal `AlertDialog` with title, message, confirm button (red for destructive: "Reset", "Disable"), cancel.

### 3.4 Keyboard model (exact)

MEASURED `services/keybinding/keybinding-service.hpp`, `internal/keyboard/keybind-manager.cpp:7-145`, `ui/windows/launcher-window.cpp:600-694`, `ui/qml/launcher/SearchBar.qml:138-330`, `ui/qml/actions/ActionPanelPopover.qml:42-80`.

- **Scheme** (`keybinding`: `default|vim|emacs`; `default` = vim on Linux, native on macOS): list navigation Up/Down/Left/Right always; vim adds ctrl+J/K (down/up) and ctrl+H/L (left/right); emacs adds ctrl+N/P and ctrl+alt+B/F plus emacs line editing in the search bar (ctrl+A/E/B/F/K/U, alt+B/F/Backspace/D). `wrap_navigation` wraps ends.
- **Return** = primary action of the selected row (the first action of its panel, or the one marked `setPrimary`). **Escape** = `navigate_back` (default) or `close_window`. **Backspace on an empty query** pops the view (`pop_on_backspace`). **Space** activates an alias-matched row. **Tab/Backtab** move between argument fields.
- **Reserved, never overridable by actions**: ctrl+A/C/V/Z (text editing). Modifier-only presses are ignored.
- **Ctrl held 250 ms** reveals quick-access badges; ctrl+1..9/0 trigger the nth visible row's shortcut (favorites, app desktop actions use `ctrl+alt+N`, Browse Apps actions use `control+shift+N`).
- **Keybind ids and Linux defaults** (user-overridable under `keybinds` with the serialized form `"control+shift+C"`, tokens `super|control|alt|shift|cmd|meta|opt`):

| id | default | id | default |
|---|---|---|---|
| `toggle-action-panel` | control+B (mac control+K) | `action.copy` | control+shift+C |
| `open-search-filter` | control+P | `action.copy-name` | control+shift+. |
| `open-settings` | control+, | `action.copy-path` | control+shift+, |
| `action.open` | control+O | `action.save` | control+S |
| `action.duplicate` | control+D | `action.new` | control+N |
| `action.move-up` | control+shift+Up | `action.move-down` | control+shift+Down |
| `action.refresh` | control+R | `action.pin` | control+shift+P |
| `action.remove` | control+X | `action.dangerous-remove` | control+shift+X |
| `action.edit` | control+E | `action.edit-secondary` | control+shift+E |
| `action.run-as-administrator` (Windows) | control+shift+Return | `PasteAction` | **no default in the manager** (MEASURED: only the enum entry `keybind.hpp:16`) |

- Hard-coded per-view shortcuts: close window ctrl+Q (window switcher), quit app ctrl+q (apps), open with ctrl+shift+O (clipboard), favorites toggle ctrl+shift+F, show details = Enter (stores).
- **Action panel popover**: Escape closes; Left closes a submenu; Up/Down (or scheme keys) move; Return/Enter executes; typing filters. While open, `capturesAllKeys` stops the launcher from handling keys.
- **Global**: `global_shortcuts.toggle` default `super+control+space` on Linux, `inhibit_apps[]` releases all hotkeys while a listed desktop-id is focused. Backends: `xx-hotkey-v1`, `vicinae-hotkey-v1` (own protocol), X11, dummy. Sway has none, so Tom binds the CLI.
- Mouse: hover highlights; click selects; double click (or single with `activate_on_single_click`) activates; rows are drag sources (files, clipboard entries, links).

### 3.5 CLI, IPC and deeplinks

`vicinae` CLI (MEASURED `src/cli/src/cli.cpp:136-538`, `theme.cpp`, `fs.cpp`, `script.hpp`, `config.hpp`, `state.hpp`): `version|ver`; `server` ("(Re)start the vicinae server", `--replace`); `ping`; `toggle [-q QUERY]`; `open [-q QUERY]`; `close`; `cmd ls|list [--json]`, `cmd launch <entrypoint> [args…] [--cwd DIR] [--query Q]`; `deeplink <link>`; `dmenu [-n title] [-s section] [-f data|index] [-p placeholder] [-q query] [-W px] [-H px] [--no-section] [--no-quick-look] [--no-metadata] [--no-footer] [--password]`; `theme set <id> | check <file> | template | paths`; `fs query <q> [-n limit≤10000] [-c category] [-j]`; `app launch <app_id> [args] [--new]` ("Focused existing window … Pass --new if you want to launch a new instance"); `config default`; `script template -t TITLE [-l bash] [-m mode] | check <file>`; `state open` (exit 0 if the window is open); `logs [-n N] [-f]`.

IPC: JSON-RPC 2.0 over `$XDG_RUNTIME_DIR/vicinae/vicinae.sock`, each frame prefixed by a 4-byte native-endian length; methods are generated from `figura`'s `ipc.fig` (e.g. `Ipc/dmenu`). The released CLI reuses id 1 per connection (REPORTED `DF/docs/vicinae-research.md:144-148`, `herdr-picker:213-217`).

Deeplinks `vicinae://<command>[/path]?query` (MEASURED `src/server/src/ipc/ipc-command-handler.cpp:46-270`): `kill`, `ping`, `toggle`, `settings/open?tab=…`, `settings/close`, `close?popToRoot=immediate|suspended&clearRootSearch=1`, `open?popToRoot=1&query=…`, `launch/<provider>` (opens a provider-only search) and `launch/<provider>/<entrypoint>?arguments=<json>&fallbackText=…&toggle=true&clearSearch=1`, `extensions/<author>/<name>` (also `raycast://`), `theme/set/<id>?openWindow=1`, `oauth?code&state`, `api?id=…`. Handler desktop file `extra/vicinae-url-handler.desktop`.

### 3.6 Extension API surface (for the boundary, not for reimplementation)

`@vicinae/api` (MEASURED `src/typescript/api/src/api/**`): components `List, Grid, Detail, Form, MenuBarExtra, ActionPanel, Action.{CopyToClipboard, Paste, Open, OpenInBrowser, OpenWith, Push, SubmitForm, Trash, ShowInFileBrowser, CreateQuicklink, PickDate, RunInTerminal}, Metadata, Dropdown, Tag/TagList, EmptyView`, services `Toast, Alert, HUD, Clipboard, LocalStorage, Cache, OAuth (PKCE), AI, Environment, Keyboard, WindowManagement, FileSearch, BrowserExtension, Wallpaper, Icon/Image/Color`. Manifest (`extra/schemas/extension.json`): `name,title,description,icon,author,owner,access(public|private),categories,keywords,license,platforms[Linux|macOS|Windows],preferences,commands[{name,title,subtitle,description,icon,mode(view|no-view|menu-bar),arguments,preferences,keywords,interval,disabledByDefault}],tools,ai,debug.reloadShortcut,dependencies[@vicinae/api]`. The runtime is a Node process spawned by the server, protobuf on stdout, logs on stderr. BRIEF §3.7/8 keeps extensions out: OpenUI programs through the adapter are the shell's extension story.

---

## 4. Design values worth carrying over (numbers)

| Value | Vicinae | Tom's override | Source |
|---|---|---|---|
| Launcher size | 770×480 | default kept; BRIEF plans 700×580 | `config.hpp:81-82` |
| Search bar height / footer height | 60 / 40 | — | `config.hpp:256,266`, `LauncherAppearance.qml:8` |
| Row inset / radius / padding / text gap / section header | 6 / 10 / 12 / 6 / 30 | — | `LauncherAppearance.qml:15-20` |
| Grid columns / aspect / spacing / padding / outline | 8 / 1.0 / 10 / 20 / 2 px | — | `GenericGridView.qml:21-27` |
| Border / rounding / shadow | 1 (Linux 3) / 10 / 12 | 1 / 0 / 0 | `config.hpp:91-99`, `vicinae.nix:51-55` |
| Material / opacity | auto / 1 | none / 1 | `vicinae.nix:49-50` |
| Font | bundled Inter, 10.5 pt Linux (13 mac), Qt distance-field rendering on Linux | Anthropic Sans 12 | `config.hpp:222-232`, `vicinae.nix:35-38` |
| Toast / HUD / Ctrl-hold / clock | 2 000 ms / 1 500 ms / 250 ms / 60 s | — | `toast-service.hpp:78`, `hud-bridge.cpp:6`, `launcher-window.cpp:64`, `config.jsonc` |
| Layer / keyboard | top / exclusive | overlay / exclusive | `vicinae.nix:56-60` |
| Theme palette roles | core {accent, accent_foreground, background, foreground, secondary_background, border}; accents ×8; text {default, muted, danger, success, placeholder, selection, links}; input {border, border_focus, border_error, background}; button.primary; list.item.{hover,selection}; grid.item; scrollbars; loading {bar, spinner}; tooltip; main_window {border, footer.background}; settings_window.border; shortcut.border; `opacity`; values may reference `colors.core.x` and lighten/darken (`light|lighter|dark|darker`) | Tom maps `t.ground.base/raised`, `t.fg`, `t.border.inactive`, `t.accent`, 7 accents, `t.comment` (muted/placeholder), `t.selection.{bg,fg}` for text and list selection, `t.brand` for the loading bar | `extra/theme-template.toml`, parser keys in `src/server/src/theme/*.cpp`, `DF/home/themes/default.nix:140-179` |
| noir values that end up in the launcher | background #000000, fg #EAECF0, border #373735, accent #70B8FF, selection #264F78/#EAECF0, muted #818898, brand #D97757 | | `DF/home/themes/noir.nix` |

The shell's `gpuix-shell.json` fragment (BRIEF §3.5) should expose at least these roles so the launcher, toasts and OSD read one file: `background, surface, foreground, muted, placeholder, border, accent, accentForeground, selectionBg, selectionFg, danger, success, warning, brand, accents{blue,green,magenta,orange,red,yellow,cyan}`.

---

## 5. Reusable code and data (paths)

| Asset | Path | Reuse plan | Label |
|---|---|---|---|
| Emoji + symbol dataset (5 059 glyphs, names, keywords, 18 categories, skin-tone flags) | `src/lib/glyph/src/glyph.cpp` (2.5 MB generated table), `emoji.cpp`, `emoji-properties.cpp` | one-off script → `pkgs/gpuix-shell/data/glyphs.json`; licence is Vicinae's (GPL per `LICENSE`) so credit it | MEASURED |
| Frecency and weighted-field scoring | `src/lib/fuzzy/include/fuzzy/fuzzy-searchable.hpp:19-49`, `root-item-manager.cpp:144-200` | port formula and ordering rules to `src/launcher/rank.ts` | MEASURED |
| Config reference (every setting, defaults, comments) | `extra/config.jsonc` | template for `gpuix-shell.json` and the HM option docs | MEASURED |
| Theme template + 32 palettes | `extra/theme-template.toml`, `extra/themes/*.toml` | role list for the shell theme fragment; palettes optional | MEASURED |
| Keybind catalogue (ids, names, descriptions, icons, defaults) | `src/server/src/internal/keyboard/keybind-manager.cpp:7-145`, `keyboard.cpp:91-144` (token parser) | same ids in `gpuix-shell.json.keybinds` | MEASURED |
| Browser WebExtension (Chrome MV3 + Firefox) | `src/browser-extension/{src,chrome,manifest.firefox.json}`; host name `com.vicinae.vicinae`; binary `vicinae-browser-link` | keep the extension; write a bun native-messaging host that relays tab lists/commands into `shell.sock`; dotfiles already declares the Chrome policy + host manifest (`vicinae.nix:98-99`) | MEASURED |
| Script-command header grammar | `src/lib/script-command/src/script-command.cpp`, CLI `script template/check` | reimplement the parser in TS for the dotfiles catalogue | MEASURED |
| dmenu request shape | `herdr-picker:221-227` (fields), `src/cli/src/cli.cpp:345-375` (flags), `ui/views/dmenu-model.cpp:96-120` (actions) | `gpuix-shell menu` keeps flags and the three actions | MEASURED |
| Deeplink grammar | `src/server/src/ipc/ipc-command-handler.cpp:46-270` | subset for `gpuix-shell` CLI | MEASURED |
| Desktop-entry + terminal-exec semantics | `src/lib/xdgpp/`, `services/app-service/xdg/xdg-app-database.cpp:415-563` | behaviour reference for the TS app provider (Exec field codes, `xdg-terminals.list`) | MEASURED |
| SNI tray host (watcher fallback, item props, dbusmenu flattening) | `services/tray-host/sni/*.cpp`, `builtins/vicinae/search-tray-view-host.hpp:36-170` | behaviour reference for a dbus-next port | MEASURED |
| MPRIS + pactl | `services/media-control/mpris/`, `services/audio-control/pactl/pactl-audio-control.cpp` | reference; dotfiles already has `volume`, `media`, `audio-route` scripts | MEASURED |
| logind power | `services/power-manager/systemd/*.cpp:21-72` | reference for `gpuix-shell power` | MEASURED |
| Clipboard schema (kinds, tables, password hint, eviction) | `services/clipboard/clipboard-db.cpp`, `clipboard-content.hpp`, `data-control-server/src/` | schema reference for the bun store; `wl-paste --watch` replaces ext-data-control | MEASURED |
| Standalone helpers that could be subprocessed as-is | `file-indexer` (sqlite/fts5/inotify), `data-control-server` | **not recommended**: their IPC/db formats are private and Qt-linked; REPORTED by their CMake layout | INFERRED |
| Markdown feature list | `ui/qml/markdown/Md*.qml`, `internal/markdown-showcase-command.hpp` | checklist for the launcher's detail renderer | MEASURED |
| Launcher geometry readme | `ui/qml/launcher/README.md` | scrolling/inset rules under an overlay search bar | MEASURED |

---

## 6. Gaps, conflicts and what was not verified

1. **Docs not in the clone.** The task asked for `docs/` (config, keybindings, themes, extensions, script commands, dmenu, deeplinks, CLI). The clone has none; I inventoried the same topics from `extra/config.jsonc`, the settings QML strings, the CLI sources, `ipc-command-handler.cpp`, `theme-template.toml` and the script parser. Docs.vicinae.com was not fetched (offline reader).
2. **Nothing was run.** "MEASURED" means read in source. Runtime claims (e.g. the dmenu id-1 misrouting) are REPORTED from `DF/docs/vicinae-research.md` and `herdr-picker`.
3. **No Sway backend exists upstream.** On Sway, Vicinae's window provider is the generic `zwlr_foreign_toplevel_management_v1` one: no workspaces, no fullscreen/floating toggles, transient ids. The GPUIX shell gets strictly more from Sway IPC; nothing to port there.
4. **Toast anchor conflict**: Tom 2026-10-11 "top and center not top right" (mako) vs BRIEF §3 "toasts = overlay top-right 390 wide max 4". Newer-wins says BRIEF, but BRIEF's value is the orchestrator's assumption, not a Tom quote. Logged for ASSUMPTIONS.md: default top-center 390 wide, max 4, make it a config key.
5. **`PasteAction` keybind has no default** in `keybind-manager.cpp` (only the enum entry); paste rows show no badge unless the user sets `action.paste`. Irrelevant for us (no input server) but do not copy the gap.
6. **Snippets/paste-to-window are out** because they need the setcap `vicinae-input-server`; Tom disabled it. Any "paste" verb in the shell must be "copy + HUD".
7. **Clipboard capture protocol**: Vicinae needs `ext-data-control-v1` (or wlr-data-control via the Qt backend). `@gpuix/native` exposes no Wayland data-control binding; the plan is `wl-paste --watch` (wl-clipboard is already a dotfiles dependency, INFERRED from `fzf-nmcli`/`colorpicker` usage; verify in the integrator pass).
8. **Global hotkeys**: upstream needs `xx-hotkey-v1`/`vicinae-hotkey-v1`; Sway offers neither, so "Set Global Shortcut" must become "write/inspect a Sway bind" or be dropped.
9. **KDE row in the backend order** (`window-manager.cpp:32,35-36`) was not read; order given as Hyprland → GNOME → (…) → X11 → Niri → Wayland.
10. **Screenshots directory**, **news/update services**, **wallpaper service** (swww/hyprpaper backends exist) were only skimmed; wallpaper is irrelevant (#000000 solid).
11. **Font grid, builtin icon browser, OAuth store, local-storage inspector, extension stores, developer scaffold**: inventoried, not worth porting; listed so the "complete table" is complete.
12. **Licence**: Vicinae is GPL (per `LICENSE`, not read in full). Reusing the glyph table or the WebExtension verbatim keeps that obligation inside Tom's private dotfiles; fine for a personal shell, note it in `pkgs/gpuix-shell/README`.

---

## What I did / could not do

Did: read BRIEF.md (all sections incl. §5), `AGENTS.md`, `README.md`, `extra/config.jsonc`, `extra/theme-template.toml`, every `*-extension.{hpp,cpp}` and `*-command.hpp` under `builtins/`, the root-search providers and `root-item-manager`, the fuzzy/frecency header, the keybinding scheme and keybind manager, the launcher window key forwarding and layer-shell setup, the QML launcher/footer/action-panel/list/grid/detail/metadata components, the clipboard, files, media, power, wm, tray, snippet, shortcut, browser-extension and app services at header level, the CLI, the deeplink handler, the extension manifest schema, Tom's `home/vicinae.nix`, `home/themes/{default,noir}.nix`, `docs/vicinae-research.md`, `docs/client-sway-vicinae.md`, `bin/herdr-picker`, `sway/binds.conf`, the wave-1 ruling tables and the 10-07 Tom-words file. Wrote only this file.

Could not: fetch docs.vicinae.com; run Vicinae or any socket test; read the full 5.9 k-line window-manager tree or the 2.5 MB glyph table beyond its section index.

---

## Appendix A — flat entrypoint ids (`provider:command`), Linux build

The serialized form used by `favorites`, `fallbacks`, `vicinae cmd launch`, deeplinks and
`providers.<p>.entrypoints.<e>`. Applications are `applications:<desktop-id>`; scripts, shortcuts
and browser tabs get provider-generated ids. MEASURED from the `id()` overrides cited in §3.1.

```
core:refresh-apps            Refresh Apps
core:manage-fallback         Configure Fallback Commands
core:search-emojis           Search Emojis & Symbols
core:search-tray             Search Tray                      (Linux only)
core:report-bug              Report a Vicinae Bug             (disabled by Tom 2026-10-12)
core:settings                Open Vicinae Settings
core:sponsor                 Donate to Vicinae                (disabled by Tom 2026-10-12)
core:store                   Extension Store
core:list-extensions         Show Installed Extensions
core:open-config-file        Open Config File
core:open-default-config     Open Default Config File
core:reload-scripts          Reload Script Directories
core:show-logs               Show Log File
core:forget-telemetry        Forget Past Vicinae Telemetry
core:search-builtin-icons    Search Builtin Icons
core:oauth-token-store       Manage OAuth Token Sets
core:inspect-local-storage   Inspect Local Storage
calculator:history           Calculator history
calculator:refresh-rates     Refresh Exchange Rates
clipboard:history            Clipboard History                (Tom favourite; Mod+V)
clipboard:clear              Clear Current Clipboard Data
clipboard:clear-history      Clear Clipboard History
files:search                 Search Files                     (default fallback)
system:run                   Run Terminal Program             (arg: command)
system:browse-apps           Browse Apps
system:set-default-terminal  Set Default Terminal
system:set-default-browser   Set Default Browser
wm:switch-windows            Switch Windows
wm:switch-workspaces         Switch Workspaces                (not registered on Sway: generic backend has no workspaces)
wm:toggle-fullscreen         Toggle Fullscreen                (capability-gated; absent on Sway)
wm:toggle-floating           Toggle Floating                  (capability-gated; absent on Sway)
wm:toggle-overview           Toggle Overview                  (capability-gated; absent on Sway)
media:now-playing            Now Playing                      (Tom favourite)
media:play-pause             Play / Pause                     (arg: player)
media:next-track             Next Track                       (arg: player)
media:previous-track         Previous Track                   (arg: player)
media:volume-up              Turn Volume Up                   (arg: step, "+5")
media:volume-down            Turn Volume Down                 (arg: step, "-5")
media:volume-100             Set Volume to 100%
media:volume-75              Set Volume to 75%
media:volume-50              Set Volume to 50%
media:volume-25              Set Volume to 25%
media:volume-0               Set Volume to 0%
media:toggle-mute            Toggle Mute
power:power-off              Power Off System
power:reboot                 Reboot System
power:sleep                  Put System to Sleep
power:lock                   Lock Session
power:logout                 Log Out
power:suspend                Suspend System                   (Linux)
power:hibernate              Hibernate System                 (Linux, Windows)
power:soft-reboot            Soft Reboot System               (Linux)
screenshots:browse           Search Screenshots
screenshots:paste-last       Paste Last Screenshot
manage-shortcuts:create      Create Shortcut
manage-shortcuts:manage      Manage Shortcuts
snippets:create              Create Snippet
snippets:manage              Manage Snippets
font:browse                  Search Fonts
theme:set                    Set Theme
browser-extension:browse-tabs           Search Browser Tabs   (Tom favourite)
browser-extension:shortcut-active-tab   Create Shortcut from Active Tab
developer:create             Create Extension
raycast-compat:store         Raycast Store
internal:markdown-showcase   Markdown Showcase
applications:herdr-picker    Herdr workspaces                 (dotfiles desktop entry; Tom favourite #1)
applications:sway-workspace-new / -restore / -rename, notifications-dismiss, notifications-history, network-settings  (dotfiles desktop entries)
```

Count: 66 builtin commands registered on Linux (5 of the `wm` ones are absent on Sway), plus the
dynamic providers (applications, scripts, shortcuts, browser-tabs, extensions).

## Appendix B — config keys with defaults (the settings surface to re-expose)

MEASURED from `config/config.hpp` and `extra/config.jsonc`. "Tom" = `home/vicinae.nix`.

| Key | Default | Tom | Shell equivalent |
|---|---|---|---|
| `imports[]` | [] | — | not needed (Nix renders one file) |
| `telemetry.system_info` | true | false | drop |
| `input_server.enabled` | true | false | drop |
| `tray.enabled` | true | false | n/a (no own tray icon) |
| `search_files_in_root` | false | — | `launcher.filesInRoot` |
| `activate_on_single_click` | false | — | keep |
| `escape_key_behavior` | `navigate_back` | — | keep both values |
| `pop_on_backspace` | true | — | keep |
| `close_on_focus_loss` | false | — | keep (forces keyboard on-demand) |
| `consider_preedit` | false | — | n/a |
| `pop_to_root_on_close` | false | true | keep, default true |
| `wrap_navigation` | false | — | keep |
| `encrypt_sensitive_data` | false (Linux) | — | drop (own store, no OAuth) |
| `favicon_service` | `twenty` | `none` | drop (no favicons; Tom "none") |
| `keybinding` | `default` (= vim on Linux) | — | keep `default|vim|emacs` |
| `language` | unset | — | n/a |
| `pixmap_cache_mb` | 50 | — | n/a |
| `font.rendering` | `qt` (Linux) | — | n/a |
| `font.normal.family` / `.size` | `auto` (Inter) / 10.5 pt | Anthropic Sans / 12 | theme fragment: `fontFamily`, `fontSize` |
| `theme.light|dark.name` / `.icon_theme` | vicinae-light/dark / auto | dotfiles-current | `~/.config/theme/gpuix-shell.json` |
| `launcher_window.opacity` | 1 | 1 | keep 1 |
| `launcher_window.material` | auto | none | none |
| `launcher_window.rounding` | 10 | 0 | 0 |
| `launcher_window.client_side_decorations.{enabled,border_width,shadow_size}` | true/1/12 | —/1/0 | hairline 1, no shadow |
| `launcher_window.compact_mode.enabled` | false | — | optional |
| `launcher_window.size.{width,height}` | 770/480 | — | 700/580 (BRIEF) |
| `launcher_window.clock.{enabled,format,interval}` | true (Linux)/`hh:mm`/60 | — | optional footer clock |
| `launcher_window.floating_status_bar` | true | — | keep |
| `launcher_window.layer_shell.{enabled,layer,keyboard_interactivity}` | true/top/exclusive | true/overlay/exclusive | overlay/exclusive (BRIEF) |
| `launcher_window.screen` | auto (X11 only) | — | n/a |
| `global_shortcuts.{toggle,inhibit_apps}` | super+control+space / [] | — | drop (Sway binds) |
| `keybinds.<id>` | §3.4 | — | keep ids |
| `favorites[]` | [`clipboard:history`] | 5 entries (§1.1) | keep |
| `fallbacks[]` | [`files:search`] | — | keep |
| `providers.<p>.{enabled,preferences,entrypoints.<e>.{enabled,alias,shortcut,preferences}}` | {} | core/clipboard/files (§1.1) | keep shape |

Settings-window strings that name behaviour not covered above (MEASURED `ui/qml/settings/*.qml`):
"Encrypt sensitive data … Requires a restart", "Floating status bar … content stays slightly visible under it", "Native font rendering … Disable for Qt distance-field rendering", "Use layer shell … May require reopening Vicinae", "Launcher hotkey / Record Shortcut", "Root file search … expect a slight delay", "Basic usage statistics", "IME handling". Pages: General, Appearance, Input & Navigation, Keybindings (Shortcuts), Extensions (Commands / Preferences per provider), Advanced (Security, Privacy), About.
