# Vicinae as the command surface for the Herdr desktop

**Vicinae can carry substantially more of this desktop than the first investigation established.** At released v0.29.1 it already supplies media controls, a searchable system tray that works without Waybar, browser-tab search, applications, scripts, calculator, files, clipboard and snippets. The useful next move is to make those capabilities consistently reachable, then add a few carefully chosen extensions. Herdr remains the owner of durable agent work; Sway owns the physical desktop; Kitty renders terminal sessions; Chrome owns web work; Mako delivers notifications. Vicinae selects and invokes them.

This is a source-grounded research report prepared alongside the separate implementation branch, not a claim that every capability has been tested on the Zenbook Duo. Research used tagged upstream source, current extension source and official documentation. It did not read live clipboard contents, browser profiles, account tokens or agent prompts, install extensions, or change the live desktop.

## The package decision is settled

The current main dotfiles nixpkgs revision supplies **0.23.1**; the separate fresh input supplies **0.27.1**. The newest published release observed is **0.29.1**, dated September 30. These are materially different baselines. Use `github:vicinaehq/vicinae/v0.29.1` and the Home Manager module exported by that same input. The tagged revision is `7f1d1d96ea7ca9b08130962c91d0469df24a1362`. ([Main nixpkgs package](https://github.com/NixOS/nixpkgs/blob/e2587caef70cea85dd97d7daab492899902dbf5d/pkgs/by-name/vi/vicinae/package.nix), [fresh package](https://github.com/NixOS/nixpkgs/blob/413a9b88e4284b6f118f8e565b3442ade07336ae/pkgs/by-name/vi/vicinae/package.nix), [release](https://github.com/vicinaehq/vicinae/releases/tag/v0.29.1))

The release is cached. Read-only evaluation resolved `/nix/store/pnqiyj8z8k5j38wfph95h055qz6sbnmx-vicinae-0.29.1`, and the official cache returned a signed narinfo for that exact output. Its compressed package archive is approximately 15.8 MB; this excludes dependencies. Keep upstream's own nixpkgs pin to preserve cache compatibility. ([Cache receipt](https://vicinae.cachix.org/pnqiyj8z8k5j38wfph95h055qz6sbnmx.narinfo), [Nix installation guidance](https://docs.vicinae.com/nixos))

Home Manager provides settings, themes, extension derivations, secret override files and a systemd user service. Its actual implementation wraps the executable with `VICINAE_OVERRIDES`; settings therefore override mutable GUI settings without making the ordinary settings file read-only. The module's prose mentioning `nix.json` does not accurately describe the implementation. Default calculator backend is bundled Numen; Soulver is separately optional. The module and configuration template are identical between this release and inspected main. ([Tagged Home Manager module](https://github.com/vicinaehq/vicinae/blob/v0.29.1/nix/home-manager-module.nix), [flake](https://github.com/vicinaehq/vicinae/blob/v0.29.1/flake.nix))

## A desktop with no Waybar still has a tray and media controls

**Search Tray is a particularly good fit for this decision.** It presents StatusNotifier tray items and their menu actions inside Vicinae. When no desktop bar supplies `org.kde.StatusNotifierWatcher`, Vicinae supplies its own fallback watcher. Turning `tray.enabled` off hides Vicinae's own tray icon; the tray host is initialized separately. Thus tray menus can remain reachable without creating a visible bar. ([Tray command/view](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/builtins/vicinae/search-tray-view-host.hpp), [fallback watcher](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/services/tray-host/sni/sni-watcher.cpp), [service setup](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/server.cpp))

Core media support also goes beyond the earlier report. It browses running MPRIS players, toggles playback, skips tracks, adjusts volume, mutes and offers volume presets. Playback uses session D-Bus directly; volume uses `pactl`, already included on PATH by the upstream Nix wrapper. Player Pilot is therefore an optional alternative interface, not a requirement for basic media control. ([Media commands](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/builtins/media/media-extension.hpp), [MPRIS implementation](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/services/media-control/mpris/mpris-media-control.cpp), [Nix wrapper](https://github.com/vicinaehq/vicinae/blob/v0.29.1/nix/vicinae.nix))

The practical division I recommend is:

| Surface | Responsibility |
|---|---|
| Sway workspaces 1–9 | One selected Herdr terminal view per slot; direct numbered navigation |
| Sway workspace 10 / Mod+0 | Chrome, with tabs found through Vicinae |
| Vicinae root | Apps, favorite commands, scripts, browser tabs, calculator |
| Herdr picker | Herdr identity/status joined to the slot actually shown on this client |
| Mako | Notifications, dismissal and restoration |
| Hardware keys | Immediate volume, media and brightness controls |
| Vicinae Search Tray | Less frequent application tray menus |

This table is an integration recommendation, not a claim that Vicinae natively understands Herdr slots. Its built-in clock is visible while its window is open. I found no general Linux battery dashboard or Mako-history provider in the inspected builtins. A battery script and Mako commands can fill those narrow gaps without turning Vicinae into another desktop shell. ([Root configuration](https://github.com/vicinaehq/vicinae/blob/v0.29.1/extra/config.jsonc), [builtins source](https://github.com/vicinaehq/vicinae/tree/v0.29.1/src/server/src/builtins))

## Make the useful commands easy to reach

The exact IDs matter. Application IDs in Vicinae strip the `.desktop` suffix; built-in provider IDs do not always match their visible names. These are source-verified for v0.29.1:

| Purpose | Entrypoint ID |
|---|---|
| Dotfiles Herdr picker desktop entry | `applications:herdr-picker` |
| Browser tabs | `browser-extension:browse-tabs` |
| Media players | `media:now-playing` |
| Tray items | `core:search-tray` |
| File search | `files:search` |
| Clipboard history | `clipboard:history` |

Use `vicinae cmd ls --json` on the running pilot to discover any remaining IDs. `vicinae cmd launch <entrypoint>` opens a particular command; `--query` and `--cwd` supply context. `toggle`, `open`, `close` and `deeplink` are supported CLI routes. Put a few high-value commands in favorites, keeping root file results optional so project filenames do not swamp agent and browser selection. ([App IDs](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/root-search/apps/app-root-provider.cpp), [browser IDs](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/builtins/browser/browser-extension.hpp), [browser command](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/builtins/browser/browser-extension.cpp), [core ID](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/builtins/vicinae/vicinae-extension.hpp), [CLI](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/cli/src/cli.cpp))

Three extension mechanisms serve different levels of need:

| Mechanism | Good use | Limit |
|---|---|---|
| Desktop entry or script command | Open Herdr picker, network settings, Mako actions, known URLs | Simple launch/action, limited live UI |
| `vicinae dmenu` | Snapshot of remote agent state with a selectable stable row | Reads all input before display; does not stream updates |
| React/TypeScript extension | Rich rows, status accessories, refresh while open, additional actions | Node code/dependencies and lifecycle to maintain |

Script commands support `fullOutput`, `compact`, `inline`, `silent` and `terminal` modes. Inline commands can refresh a small result, useful for a quick battery/network summary. Metadata accepts either `@vicinae` or `@raycast`, but not a mixture. `vicinae script check` validates that metadata. A dotfiles script is preferable to a separate custom-command database when reproducibility is the goal. ([Script parser](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/lib/script-command/src/script-command.cpp), [script CLI](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/cli/src/script.hpp))

## The Herdr boundary needs to stay explicit

Vicinae's generic Wayland backend can list, activate and close windows. It does not provide the Sway workspace membership or PIDs needed for the Herdr mapping. Its window IDs are transient internal identifiers, not Sway container IDs. The TypeScript API having `getWorkspaces()` does not create native Sway support. Use Sway IPC for the actual physical slot/container mapping. ([Wayland backend](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/services/window-manager/wayland/wayland.cpp), [WindowManagement API](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/typescript/api/src/api/window-management.ts))

For a snapshot picker, preserve authoritative Herdr IDs behind display rows, timestamp the observation, and distinguish unreachable or stale data from idle. Index-mode dmenu output still requires validation: the menu also exposes a “Pass search text” action. An arbitrary output string must never become a shell command or an unchecked array index. This follows directly from the CLI and view implementation. ([dmenu input](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/cli/src/cli.cpp), [dmenu actions](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/ui/views/dmenu-model.cpp))

My recommended future extension is a thin view over the same dotfiles bridge: execute an argv-safe JSON command with a timeout, refresh only while visible, keep the previous snapshot visibly stale on error, and cancel work when the view closes. Herdr remains responsible for session lifetime and agent state. This is a design recommendation; it does not replace the separate Herdr implementation's proof of attachment and focus behavior.

## Anthropic typography and one shared palette

`font.normal.family = "Anthropic Sans"` is a supported setting. The family must exist on the client, independently of its presence on Strix. Size is in points. Qt rendering is the Linux default, and upstream's configuration comments favor it under fractional scaling. Markdown code uses a separate monospace path; there is no documented `font.mono` equivalent in the inspected schema. Kitty retains control of its own terminal font. ([Font settings](https://github.com/vicinaehq/vicinae/blob/v0.29.1/extra/config.jsonc), [font service](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/services/font-service/font-service.cpp))

Vicinae theme files are native TOML. The smallest coherent theme inherits a built-in variant and sets core/semantic colors:

```toml
[meta]
name = "Herdr desktop"
variant = "dark"
inherits = "vicinae-dark"

[colors.core]
background = "#171717"
foreground = "#e5e5e5"
secondary_background = "#222222"
border = "#404040"
accent = "#d97757"
```

These example colors demonstrate syntax, not the chosen final palette. The implementation should generate Vicinae, Mako and Kitty formats from its existing palette source. Additional supported fields include accent foreground, eight accent hues, muted/success/danger text, input focus and list selection. Store under `~/.local/share/vicinae/themes/<id>.toml`; select with `theme.dark.name`. ([Complete theme template](https://github.com/vicinaehq/vicinae/blob/v0.29.1/extra/theme-template.toml))

A stable `dotfiles-current` theme ID pointing at the active palette is viable. `vicinae theme set dotfiles-current` explicitly rescans theme files and reloads even when the same theme ID is selected. This avoids restarting the launcher to apply the palette. Beware a misleading command name: `vicinae theme check` is unregistered in this release, so it is not a validator. ([Theme IPC](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/ipc/ipc-command-handler.cpp), [theme CLI](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/cli/src/theme.cpp))

On the Duo, test launcher placement on both displays and at the actual scaling. Layer-shell `exclusive` keyboard mode prevents `close_on_focus_loss` from working; Escape/toggle remains appropriate. `on_demand` enables that behavior. Upstream recommends the `top` layer because `overlay` may cover IME popovers, while overlay can be useful above fullscreen content. These are deliberate interaction choices, not interchangeable settings. ([Window configuration](https://github.com/vicinaehq/vicinae/blob/v0.29.1/extra/config.jsonc))

## Chrome needs two declarative pieces

The browser extension is `kcmipingpfbohfjckomimmahknoddnke`. Its permissions are `tabs` and `nativeMessaging`; the native host points to `vicinae-browser-link`. The tagged Nix package includes a manifest with the exact allowed extension origin. A Home Manager browser module can link it, or the pilot can explicitly link the package manifest into `~/.config/google-chrome/NativeMessagingHosts/`. ([Manifest](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/browser-extension/chrome/manifest.json), [Nix packaging](https://github.com/vicinaehq/vicinae/blob/v0.29.1/nix/vicinae.nix), [browser integration](https://docs.vicinae.com/browser-extension))

The extension itself is a separate installation. Proprietary Chrome on Linux reads external-extension declarations from system directories, including `/usr/share/google-chrome/extensions/` and `/opt/google/chrome/extensions/`. The ID-named JSON can reference the Chrome Web Store update URL. Use the repository's existing system browser policy pattern or a one-time store installation; a guessed per-user External Extensions directory is not the Linux Chrome route. ([Official Chrome installation method](https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions))

Selecting a tab requests that Chrome activate the tab and focus its owning window. Sway still controls physical placement and focus policy, so cross-workspace focus needs a real client test. Browser tabs are searchable at root already; the separate Chromium Bookmarks extension adds saved bookmarks. Main acquired mute-tab behavior after the tagged release, so do not promise that new feature for 0.29.1. ([Browser worker](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/browser-extension/chrome/background.js), [release-to-main changes](https://github.com/vicinaehq/vicinae/compare/v0.29.1...b66cc7241a33bf1b1181cbac6de4f9e00042d9cb))

## Indexing, history and input should have explicit defaults

File indexing defaults to the entire home directory. It skips common build/cache locations, but that is not a substitute for choosing search roots. A client pilot limited to Documents and Downloads is reasonable; project and notes roots can be added after checking what exists locally. `search_files_in_root` is independent of the indexer. Exact provider keys are camelCase: `autoIndexing`, `indexingPaths`, `excludedIndexingPaths`; top-level keys use snake_case. ([File preferences](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/services/files-service/file-preferences.hpp), [internal exclusions](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/file-indexer/src/entry-filter.cpp), [preference serialization](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/command/preference-schema.hpp))

Clipboard monitoring defaults on and retention defaults forever. A one-day setting is `evictionThreshold = "86400"`; `ignorePasswords = true` respects recognizable password hints, and `preserveTagged = true` exempts intentionally pinned/tagged items from bulk eviction. Linux `encrypt_sensitive_data` defaults false. Choose history behavior deliberately and do not mistake password hints for universal password detection. ([Clipboard preferences](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/builtins/clipboard/clipboard-preferences.hpp), [platform defaults](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/config/config.hpp))

The privileged input helper is separate. Disabling it leaves copying available while automatic paste falls back to copy and snippet expansion stops. The official NixOS input module enables a root-owned capability wrapper by default. The first pilot can use copy-only behavior and decide about text injection after the basic desktop has been tried. This does not restrict ordinary launcher commands. ([Input behavior](https://github.com/vicinaehq/vicinae/blob/v0.29.1/extra/config.jsonc), [NixOS helper](https://github.com/vicinaehq/vicinae/blob/v0.29.1/nix/nixos-module.nix))

## Extension expansion: useful candidates and concrete exclusions

The inspected catalog contains **96 manifests**, recorded at commit `413154812ffce610218c523b9c479febe46c5327`. The research audit recorded commands, preferences, dependencies and source links for all of them. Source review supports this order; it is not an end-to-end compatibility certificate.

| Extension | Added value and prerequisite | Recommendation |
|---|---|---|
| [PulseAudio](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/pulseaudio) | Per-app streams, device routing, inputs, card profiles; pactl and PulseAudio/PipeWire-Pulse | Strong next addition beyond core volume |
| [Power Profile](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/power-profile) | powerprofilesctl and power-profiles-daemon | Useful on the Duo if daemon already chosen |
| [Nix](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/nix) | Packages/options/flake lookup; network APIs | Good information lookup; does not own configuration |
| [Chromium Bookmarks](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/chromium-bookmarks) | Reads local bookmark files across Chromium browsers | Useful if saved bookmarks are part of workflow |
| [Player Pilot](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/player-pilot) | Grid/player filtering via playerctl | Try core Now Playing first |
| [SSH](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/ssh) | Basic Host-line parser plus visit history | Does not handle SSH Include graph; default argv launch preferable |
| [GitHub](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/github) | Issues, PRs, workflows, repository search; its own PAT | Optional; consider existing gh workflow before another credential |
| [Process Manager](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/process-manager) | Process inspection and termination | Useful tool, not agent status or identity |
| [Zoxide directories](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/zoxide-recent-directories) | Recent folders/git projects via local zoxide database | Optional folder navigation, not Herdr session selection |
| [Workspace](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/workspace) | Project folders, git branches/status and launchers | Name is misleading for this task; not Sway workspaces |
| [Wayland Explorer](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/wayland-explorer) | Protocol documentation search | Research utility, not window management |
| [KDE Connect](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/kde-connect) | Paired phone file/text transfer and actions | Later, when phone integration is actually chosen |
| [Timer](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/timer) | Transient systemd timers, notify-send | Fine for ad hoc timers; separate from remote routines |
| [Agenda](https://github.com/vicinaehq/extensions/tree/413154812ffce610218c523b9c479febe46c5327/extensions/agenda) | Read-only iCal URL agenda | Optional view; not a calendar/task source of truth |

Two concrete findings change installation choices:

1. **Bluetooth, D-Bus and systemd are explicitly excluded from the upstream extension flake's package outputs.** The reason recorded there is a dbus-next/usocket node-gyp failure. The Nix documentation's Bluetooth example is therefore not sufficient evidence that this catalog pin builds it. Keep existing tools until packaging is repaired. ([Extension flake](https://github.com/vicinaehq/extensions/blob/413154812ffce610218c523b9c479febe46c5327/flake.nix))
2. **Wi-Fi Commander should not be shipped unpatched.** Its connect form interpolates SSID/password into an argument list that is joined into a shell command and passed to `child_process.exec`. Password shell characters can alter interpretation; quoting the SSID with double quotes also leaves shell expansion possible. This is a static code finding, with no execution or exploit attempted. An `nmtui` launcher in Kitty is the appropriate immediate alternative. ([Connect form](https://github.com/vicinaehq/extensions/blob/413154812ffce610218c523b9c479febe46c5327/extensions/wifi-commander/src/components/ConnectFormNmcli.tsx), [command construction](https://github.com/vicinaehq/extensions/blob/413154812ffce610218c523b9c479febe46c5327/extensions/wifi-commander/src/utils/execute-nmcli.ts), [shell execution](https://github.com/vicinaehq/extensions/blob/413154812ffce610218c523b9c479febe46c5327/extensions/wifi-commander/src/utils/execute-command.ts))

GitHub's extension requests its own PAT with broad repository/account scopes rather than using `gh auth`. SSH's default path safely passes `['ssh', host]` to terminal launch, while its optional custom terminal string is interpolated. Those are reasons to scope adoption, not reasons to avoid Vicinae itself. ([GitHub manifest/client](https://github.com/vicinaehq/extensions/blob/413154812ffce610218c523b9c479febe46c5327/extensions/github/package.json), [SSH source](https://github.com/vicinaehq/extensions/blob/413154812ffce610218c523b9c479febe46c5327/extensions/ssh/src/ssh.tsx))

## Unknowns and proposed defaults

The first physical test should establish that numbered Herdr slots remain independent, Chrome stays on workspace 10, the picker shows actual Herdr status, and selecting a row focuses only the intended client view. Then test Anthropic rendering and palette reload on both screens, launcher placement, browser-tab focus, native media, tray menus, Mako delivery, audio routing and client sleep/reconnect. File indexing and clipboard behavior should be checked against the declared settings.

Research establishes the supported building blocks and catches several integration traps. The dedicated dotfiles branch and its validation receipts determine what is actually ready to pull. The next extension work should be driven by the first missing daily action: richer Herdr selection, audio routing or a narrow local status command, while session state stays in Herdr and configuration stays in dotfiles.

## Integration addendum: dmenu has a real concurrency bug

The separate isolated smoke test exposed a v0.29.1 problem that source review alone had not established. While dmenu waits for selection, another stock CLI call such as `state open` can produce `Failed to invoke dmenu: unknown_key`. The cause is a shared pending-reply map keyed only by request ID, while each new CLI connection starts at ID1. A synchronous reply from another connection can consume the pending dmenu route and send its differently shaped response to dmenu. Tagged source confirms this sequence; inspected main has the same code. ([Request numbering](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/lib/figura/src/codegen/glaze.hpp), [reply routing](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/lib/figura/src/codegen/glaze-qt.hpp), [pending replies](https://github.com/vicinaehq/vicinae/blob/v0.29.1/src/server/src/ipc/ipc-command-server.cpp))

The implementation uses a narrow compatibility bridge with the same native dmenu protocol, a high random request ID and response validation. Real selection and free-form entry passed in the isolated desktop while stock CLI queries ran concurrently. The long-term upstream fix must route pending replies by connection as well as request. This is why removing the smoke-test poll alone would not be sufficient. The branch's final verification receipts determine the tested workaround; the package cache and supported interface findings above remain valid.
