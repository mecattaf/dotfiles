# 36 — Vicinae's extension API, CLI, config, deeplinks, store, browser bridge and HM module, and how gpuix-shell can host Vicinae-style extensions

Reader note for the overnight gpuix-shell build (2026-10-20/21). Read-only on the Vicinae clone, the
dotfiles worktree and the transcripts; nothing was executed against a live Vicinae, Sway, herdr or
systemd. Labels: **MEASURED** = read in source or grepped tonight (file:line given);
**REPORTED** = read in a doc, comment, note or another reader's file; **INFERRED** = my reading or
recommendation. Build on an INFERRED line only after checking it.

Path shorthands used below:

- `V/` = `/home/tom/Downloads/vicinae` (git `v0.29.1-18-g8c63ae2ef`, HEAD `8c63ae2ef`, MEASURED)
- `TS/` = `V/src/typescript/api/src/api` (the `@vicinae/api` SDK)
- `EM/` = `V/src/typescript/extension-manager/src` (the Node runtime that hosts extensions)
- `RC/` = `V/src/typescript/raycast-api-compat/src` (the `@raycast/api` shim)
- `SV/` = `V/src/server/src` (the C++/Qt Quick server)
- `DF/` = `/home/tom/.wt/dotfiles/gpuix-shell` (this worktree)

Scope boundary: reader 35 covers Vicinae's builtins and root providers (clipboard, files,
calculator, media, tray, emoji, and so on). This note covers the extension SDK, the extension
runtime, the manifest, the CLI, script commands, config, deeplinks, the store and registry, the
browser bridge and the Nix module. It then proposes a provider/extension host for gpuix-shell and a
compatibility matrix. Builtins come up here only where an API depends on one.

---

## 0. Index

| § | What | Where to look first |
|---|---|---|
| 1 | Source map and process/IPC model | `V/AGENTS.md`, `V/figura/*.fig`, `EM/` |
| 2 | Tom's verbatim Vicinae and launcher rulings, dated | 17 quotes; newest wins: Vicinae is **replaced**, with Vicinae parity including Chrome tabs as the bar |
| 3.1 | Extension UI components: component, props, behaviour | `TS/components/*.tsx`, `V/src/typescript/api/types/jsx.d.ts` |
| 3.2 | Non-UI APIs: toast, HUD, clipboard, storage, AI, OAuth, environment, WM | `TS/*.ts` |
| 3.3 | Manifest schema (package.json) | `V/src/typescript/api/src/schemas/manifest.ts` |
| 3.4 | Runtime, lifecycle, `vici` dev CLI | `EM/*`, `V/src/typescript/api/src/commands/*` |
| 3.5 | Wire protocol (figura services) | `V/figura/{ipc,tsapi,manager,manager-extension}.fig` |
| 3.6 | `vicinae` CLI reference | `V/src/cli/src/*.cpp/.hpp` |
| 3.7 | Script commands | `V/src/lib/script-command/*`, `SV/script/*` |
| 3.8 | Config reference | `V/extra/config.jsonc`, `SV/config/config.hpp` |
| 3.9 | Deeplink grammar | `SV/ipc/ipc-command-handler.cpp` |
| 3.10 | Store and registry | `SV/services/{extension-store,raycast,extension-registry}` |
| 3.11 | Browser-tab bridge | `V/src/browser-extension/*`, `SV/services/browser-extension/*` |
| 3.12 | Nix HM module and extension builders | `V/nix/*.nix` |
| 3.13 | Every place Tom's dotfiles touch Vicinae today | `DF/home/vicinae.nix`, `binds.conf`, `herdr-picker`, `theme` |
| 4 | Design values, then the hosting design: interfaces, wire tree, element mapping, backends, CLI/socket, porting recipe, compat matrix | — |
| 5 | Reusable code and data, with paths | — |
| 6 | Gaps | — |

---

## 1. What the source is

**Vicinae** is "a focused launcher for your desktop — native, fast, extensible" (`V/src/cli/src/cli.cpp:23`), a
Raycast-style launcher for Linux, with macOS and Windows ports in progress. MEASURED structure:

- **Server** (`SV/`, ~1030 C++/QML files): Qt Quick UI, a C++ "view host" bridge per view
  (`V/AGENTS.md`: "QML is exclusively used for presentation"), root search, builtins, services
  (clipboard, tray host, MPRIS, window manager backends, OAuth, store, telemetry).
- **CLI** (`V/src/cli/`): the same `vicinae` binary. With no server running, `vicinae server`
  `execv`s the server binary (`V/src/cli/src/server.cpp:46-66`). Every other verb is a JSON-RPC
  client of `$XDG_RUNTIME_DIR/vicinae/vicinae.sock` (`V/figura/ipc.fig:1-2`,
  `V/src/typescript/api/src/utils/vicinae.ts:10-20`).
- **Extension runtime** (`V/src/typescript/`): three TypeScript packages bundled "inside a single
  javascript file which is then executed at startup" (`V/src/typescript/README.md`):
  - `@vicinae/api`: the SDK, published to npm and versioned like the binary
    (`V/src/typescript/api/README.md`). It also ships the `vici` build/dev CLI.
  - `extension-manager`: a Node process spawned by the server. It keeps a pool of
    `worker_threads` and runs **one worker per launched command** (`EM/index.ts:4,19-36`).
  - `@vicinae/raycast-api-compat`: a private package. Imports of `@raycast/api` are routed to it at
    runtime (`V/src/typescript/raycast-api-compat/README.md`).
- **IPC codegen**: `figura`, an in-tree generator. It produces the CLI↔server, server↔manager,
  manager↔worker and worker↔server (`tsapi`) RPC stubs from `.fig` files (`V/AGENTS.md`
  "Code generation"; `V/figura/*.fig`, 743 lines total).
- **Browser bridge**: a native-messaging host plus a Chrome/Firefox extension (`V/src/browser-extension/`).
- **Nix**: flake package, HM module, NixOS input-server module, `mkVicinaeExtension`,
  `mkRayCastExtension` (`V/nix/`).

Process/IPC model (MEASURED from the `.fig` headers and `EM/worker.tsx`):

```
vicinae CLI / browser native host ──JSON-RPC (Ipc service, ipc.fig)──► vicinae server (Qt)
                                                                         │ spawns
                                       Manager service (manager.fig) ◄───┘
                                       extension-manager (node)
                                         └─ worker_threads pool (one per running command)
                                              Lifecycle service (manager-extension.fig): launch/shutdown/send_message
                                              tsapi services (tsapi.fig), tunnelled as opaque payloads:
                                              UI.render(json) ─► server renders it natively in QML
                                              EventCore.handlerActivated(id,args) ◄─ user clicks / keys
```

Framing on `vicinae.sock` is MEASURED from Tom's own client (`DF/home/dot_local/bin/herdr-picker:211-258`):
a 4-byte native-endian length (`struct.pack('=I', n)`), then a JSON-RPC 2.0 object
`{"jsonrpc":"2.0","id":N,"method":"Ipc/dmenu","params":{"req":{...}}}`. Methods are named `<Service>/<fn>`.

Tom's flake pins **v0.29.1** (`DF/flake.nix:151`). The clone is 18 commits past it. The research doc
notes one such difference (mute-tab, `DF/docs/vicinae-research.md:100`); I did not diff the rest (§6).

Licensing (MEASURED; matters for copying): the repo root is GPL-3.0 (`V/LICENSE:1-2`). The three
TypeScript packages declare `"license": "ISC"` (`V/src/typescript/api/package.json:20`, same for
the other two). `V/src/server/LICENSE` is a BSD-style text. The icon SVGs live under `V/src/server/icons/`.

---

## 2. Tom's verbatim rulings on Vicinae, the launcher and the shell

Ordered by date. Tom's rule is "newer is truer".

| # | Date (time) | Verbatim | Source | Status |
|---|---|---|---|---|
| T1 | 2026-10-07 | "i also push back completely on its "keep vicinae" framing.. i would like to fully supersede this." | `/home/tom/today/dematerialized-2026-10-07/00-TOM-WORDS-AND-FRAME.md:6` (MEASURED grep) | stands (re-affirmed by T15) |
| T2 | 2026-10-07 | "I've been thinking a lot lately that raycast or just generally, the concept of a spotlight menu sort of thing, along with all of the contextual information that it can hold at any given moment is probably the most underused item on the modern desktop and it should be really strengthened given that we're on swaywm (with its ipc) on linux, and the vicinae product is a great foundation to start" | `~/today/2026-10-14-computer-use-study/longrun/ambient-computer.md:113`, citing `~/wednesday-today-evening.md:119` (REPORTED) | stands: the launcher must be **contextual** and Sway-IPC-aware |
| T3 | 2026-10-07 | "My point above is in the "predictability" that we can reach in the keystrokes. Like how notion had slashmenu, linear and superhuman have ctrl k you know?" | same file `:113`, citing `:210` (REPORTED) | stands: keystroke predictability |
| T4 | 2026-10-07 | "the universe of ctrl k "ambient" menu's like raycast or vicinae is also doable in a webapp" | `ambient-computer.md:201` (REPORTED) | context |
| T5 | 2026-10-11 | (mako) "top and center not top right" | `DF/home/vicinae.nix:115` (MEASURED) | **conflicts with BRIEF §3.3** "toasts = overlay top-right" (§6 G13) |
| T6 | 2026-10-12 | "we keep vicinae actually.. i was getting a little carried away there when i said let's delete it. it's good fucntionality." | `~/today/2026-10-14-computer-use-study/BRIEF.md:73` (short form, MEASURED grep); full form in `wave1/06-transcript-cc-big-oct14-b.md:143` (REPORTED) | **superseded** by T13 and T15 (10-20) |
| T7 | 2026-10-12 | "make the font larger than 11 (12 or 14, need to decide, start at 12)" | `DF/home/vicinae.nix:37` (MEASURED) | stands: launcher UI font 12 |
| T8 | 2026-10-12 | "the blue color is not the same as the vicinae launcher. i prefer the latter's" | `DF/home/themes/default.nix:125-126` (MEASURED) | stands: selection blue = `t.selection.bg`, as Vicinae renders it |
| T9 | 2026-10-12 | Vicinae's "Report Vicinae Bug" and "Donate to Vicinae" root items hidden; ROG Control Center launcher entry hidden (paraphrase in comments, not verbatim) | `DF/home/vicinae.nix:63-69,101-109` (MEASURED) | stands: no vendor or self-promotion items in the launcher |
| T10 | 2026-10-13 20:41 | "1.11 volume keys through viciane popup yes i roll back on that; the way we control brightness and volume should be keypress>sway>script execution, no need to tie in vicinae if we don't have to" | `/home/tom/today/crepuscule-2026-10-14/sessions/dotfiles-rulings.md:56` (MEASURED grep) | stands: the OSD only **displays**; the launcher is not in the volume path |
| T11 | 2026-10-13 22:16Z | "whatever you just opened: i love it.  this is good enough to also become a functional remplacement to waybar, vicinae and mako notifications. drawing insporation from omarchy's implemetnatipn of wayshell in fact." | Codex `rollout-2026-10-13T22-57-08-01a1370e-….jsonl` line 1486 (MEASURED) | stands |
| T12 | 2026-10-13 22:33Z | "… one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status indicators. only for the top display (consult kanshi config …, and existing vicinae herdr wrkspaces item as well if needed …)" | same transcript, line 2025 (MEASURED) | stands: the Vicinae "Herdr workspaces" item is a reference for Mod+i |
| T13 | 2026-10-13 23:21Z | "i m not intersted in "native advantage" . performance is not really the thing i m looking for here. "supplies another renderer" is fine for something that' react plus generic compositor functionlaity... vicinae (raycast clone) proves this theoretically ; we hae the sway ipc and omarchy's quickshell which you investigated a while back did exactly that." | same transcript, line 3453 (MEASURED) | stands: React plus compositor functionality is the model; Vicinae is the proof |
| T14 | 2026-10-14 ~01:26Z | "for the launcher, feature parity at least with vicinae (already enjoyed on my setup) including how it interacts w google chrome tabs is very desirable" | `~/today/2026-10-14-computer-use-study/BRIEF.md:43` (MEASURED grep) | **stands: the launcher acceptance bar; Chrome tab search is named explicitly** |
| T15 | 2026-10-20 ~22:50 | "the crux of it is that we write scripts and functionality that is either a bespoke swaywm shortcut ; or a mod+d menu (vicinae remplacement) that presents a given functionality. notify-send remplacement to mako ; a left bar with workspace switcher that remplaces waybar" | `DF/docs/gpuix-shell/BRIEF.md:13-15` (REPORTED verbatim fragment) | **stands: Vicinae is replaced by the GPUIX Mod+d menu** |
| T16 | 2026-10-20 ~22:50 | "gpuix as the frontend all the way is desired. the rest, including scripts and other functionality, you can use what comes instinctively to you. for wifi menu, or bluetooth pairing menu; etc." | `BRIEF.md:21-24` | stands |
| T17 | 2026-10-20 23:20 | "the vicinae implementation is also of interest so make sure to capture that as well" and "a full implementation of the linux wayland sway facing https://github.com/vicinaehq/vicinae ... would be impressive to see. gpuix for the win." | `BRIEF.md:154-156` | stands: reproduce the Linux-relevant Vicinae surface in GPUIX |
| T18 | 2026-10-20 23:20 | "i would like to have a navidrome music selection in the gpuix shell ; so a demo implementation of that would be very nice to have tomorrow morning ... raycast+spotify level searching and playing control from within the launcher"; "this is NOT ONLY about navidrome.. but indeed a welcome set of utilities you can demo for me" | `BRIEF.md:158-163` | stands: the launcher hosts rich, Raycast-grade extension views |

Also binding, REPORTED from `DF/AGENTS.md` ("Scheduled work (Tom, 2026-09-30)"): "No scheduled
agent work is declared in dotfiles." This bears on Vicinae's background `interval` commands and the
script `refreshTime` key (§4.5, §6 G8).

**Resolution (INFERRED; it follows Tom's own rule):** T1 (10-07) said supersede, T6 (10-12) said
keep, and T11, T13, T15 and T17 (10-13 to 10-20) say replace with GPUIX. Vicinae goes away. Its
**contract** (T14 parity, including Chrome tabs; T2/T3 contextual, keystroke-predictable Ctrl+K)
becomes the gpuix-shell launcher's acceptance bar. Keeping Vicinae's extension grammar keeps Tom's
`vicinae`-shaped habits and the Raycast extension ecosystem (T18 cites "raycast+spotify level").

---

## 3. Feature inventory

Disposition legend: **R** = reimplement in gpuix-shell with the same contract (Vicinae itself is
removed); **K** = keep the format, protocol or data as-is (reuse verbatim); **N** = new, not in
Vicinae; **D** = drop (not Linux-relevant or excluded by a ruling). "Tom prio" quotes a Tom priority
where one exists. Otherwise it is "—", and any tier in the notes is INFERRED (P0 = Mod+d parity
blocker, P1 = needed to port typical extensions, P2 = nice, P3 = later).

### 3.1 Extension UI components (the API table)

All MEASURED from `TS/components/*.tsx` and the wire vocabulary `V/src/typescript/api/types/jsx.d.ts:30-244`.
Each public component is a thin React wrapper. It serializes images and colors, generates stable
ids, wraps controlled values, and renders a lowercase **intrinsic element** (`<list>`,
`<list-item>`, …), which the server then renders natively.

| Component | Props (exact) | Behaviour | gpuix-shell | Pointer |
|---|---|---|---|---|
| `List` | `actions`, `children`, `filtering?`, `enableFiltering?` (deprecated → `filtering`), `isLoading?`, `isShowingDetail?`, `searchText?`, `searchBarPlaceholder?`, `navigationTitle?`, `searchBarAccessory?` (a `List.Dropdown` only), `throttle?` (default false), `onSearchTextChange?(text)`, `onSelectionChange?(id)`, `pagination?: {onLoadMore, hasMore}` | Builtin fuzzy filtering is on unless `onSearchTextChange` is passed. Sections stay grouped regardless of score. `isLoading` shows a bar under the search field. `navigationTitle` sits bottom-left in the status bar and defaults to the command name. `searchText` is sent as `{value, eventCount}` so the host can drop stale echoes. Pagination is flattened to `paginationHasMore` / `paginationOnLoadMore`, and a guard blocks re-entrant loads. Root `actions` apply when nothing matches. | **R**, P0 (T14) | `list.tsx:38-123,313-349`; event count `hooks/use-event-counted.ts:5-23`; pagination guard `components/pagination.ts:6-27` |
| `List.Section` | `title?`, `subtitle?`, `children` | Groups items. Loose items attach to an unnamed section. | R | `list.tsx:153-159,401-403` |
| `List.Item` | `title` (req), `id?` (auto `randomUUID`), `subtitle?` (dimmed), `keywords?: string[]` (ranked below title/subtitle), `icon?: ImageLike or {value, tooltip}`, `actions?`, `detail?`, `accessories?: Accessory[]`, `dragContent?: Clipboard.Content`, `active?` (dot under the icon) | Fixed-height row. Selection fires `onSelectionChange(id)`. The item's `ActionPanel` becomes the footer's primary action. | R, P0 | `list.tsx:164-219,351-392` |
| `List.Item.Accessory` | `{tag?: string or Date or {value, color?}}` or `{text?: string or Date or {value, color?}}`, plus `icon?`, `tooltip?` | Right-aligned chips/text. A `Date` renders as a date. `tag` takes any `ColorLike`; `text` takes a `Color`. | R | `list.tsx:249-311` |
| `List.Item.Detail` | `isLoading?`, `markdown?`, `metadata?` | Side panel, shown only when `List.isShowingDetail` and the selected item has a `detail`. | R, P1 | `list.tsx:228-247,394-399` |
| `List.EmptyView` / `Grid.EmptyView` | `title?`, `description?`, `icon?`, `actions?` | Shown when nothing matches. | R | `empty-view.tsx:4-22` |
| `List.Dropdown` / `Grid.Dropdown` | `tooltip?`, `defaultValue?`, `value?`, `onChange?(v)`, `filtering?`, `id?`, `isLoading?`, `placeholder?`, `storeValue?`, `throttle?`, `onSearchTextChange?`; children `Dropdown.Item {title, value, icon?, keywords?}` and `Dropdown.Section {title?, children}` | Search-bar accessory filter. **Note:** `Item` drops `keywords` when serializing. | R, P1 | `dropdown.tsx:10-53` (keywords dropped at `:41-44`) |
| `Grid` | Everything `List` takes, plus `columns?`, `itemSize?: small/medium/large` (sets columns to 8/5/3 when `columns` is unset), `inset?: zero/small/medium/large`, `fit?: contain/fill` (default `contain`), `aspectRatio?: "1","3/2","2/3","4/3","3/4","16/9","9/16","21/9","9/21","32/9","9/32"` (default `"1"`, sent as a number), `throttle?` | Cell grid with the same search, filter and pagination model as List. The intrinsic also carries `isShowingDetail`, but `Grid.Props` does not expose it. | R, P1 (T18 cover-art grids) | `grid.tsx:11-54,70-124,184-236,321-329` |
| `Grid.Section` | `title?`, `subtitle?`, `columns?`, `fit?`, `aspectRatio?`, `inset?`, `itemSize?` | A section can override the layout. | R | `grid.tsx:130-140,302-316` |
| `Grid.Item` | `content` (req): `ImageLike` or `{color}` or `{value, tooltip?}`; `title?`, `subtitle?`, `keywords?`, `icon?`, `id?`, `actions?`, `detail?`, `dragContent?`, `accessory?: {icon?, tooltip?}` | Image or color-swatch cell. The tooltip is lifted from `content.tooltip`. | R | `grid.tsx:159-181,238-300` |
| `Detail` | `markdown` (req), `navigationTitle?`, `metadata?`, `actions?`, `isLoading?` | Full markdown view, with an optional metadata column. | R, P0 (script fullOutput, AI answers) | `detail.tsx:24-54` |
| `Detail.Metadata` / `List.Item.Detail.Metadata` | children: `Label {title, text: string or {value, color?}, icon?}`, `Separator`, `Link {title, target, text}`, `TagList {title, children}` with `TagList.Item {text?, color?, icon?, onAction?}` | Key/value metadata block. A `TagList.Item` can be clickable. | R, P1 | `metadata.tsx:10-71`, `tag.tsx:5-38` |
| `Form` | `actions?`, `children`, `enableDrafts?` (default false), `isLoading?`, `navigationTitle?`, `searchBarAccessory?` | Vertical form. Submit is the first action, **Ctrl+Enter** (§4.1). `enableDrafts` is passed through; I did not trace whether drafts persist (§6). | R, P1 | `form.tsx:11-18,182-202` |
| Form field base (`FormItemProps<T>`) | `id` (req), `title?`, `info?`, `error?`, `storeValue?`, `autoFocus?`, `value?`, `defaultValue?`, `onChange?(v)`, `onBlur?(ev)`, `onFocus?(ev)`, `ref?` | `onFocus`/`onBlur` receive `{type, target:{id, value}}`. Controlled values are event-counted (TextField, PasswordField, TextArea). **`ref.focus()`/`ref.reset()` are no-ops: the bodies are commented out.** | R | `form.tsx:128-180`; `hooks/use-imperative-form-handle.ts:10-27` |
| `Form.TextField` / `PasswordField` / `TextArea` | base plus `placeholder?` | String inputs; the password field is masked. | R, P1 | `form.tsx:35-48,204-238,326-342` |
| `Form.Checkbox` | base(boolean) plus `label?` | | R | `form.tsx:50-53,277-281` |
| `Form.DatePicker` | base(Date or null) plus `min?`, `max?`, `type?: DatePicker.Type.DateTime ("dateTime") or Date ("date")`; static `isFullDay(d)` | Host sends an ISO string, wrapper parses it to a `Date`. | R, P2 | `form.tsx:55-62,240-275` |
| `Form.Dropdown` | base(string) plus `tooltip?`, `filtering?`, `isLoading?`, `placeholder?`, `throttle?`, `onSearchTextChange?`; `.Item`/`.Section` reuse `Dropdown` | | R, P1 | `form.tsx:64-75,285-301` |
| `Form.TagPicker` | base(string[]), children `TagPicker.Item {title, value, icon}` | Multi-select. | R, P2 | `form.tsx:77-88,303-324` |
| `Form.FilePicker` | base(string[]) plus `allowMultipleSelection?`, `canChooseDirectories?`, `canChooseFiles?`, `showHiddenFiles?` | File chooser (server side: `SV/services/file-chooser`). | R, P2 (could route to the Pinax-like `gpuix-shell files`, N) | `form.tsx:90-98,344-348` |
| `Form.Description` / `Separator` / `LinkAccessory` | `{text, title?}` / — / `{target, text}` | Static text, hairline, top-right link. | R | `form.tsx:100-112,350-371` |
| `Form.Values` | `{[id]: string, number, boolean, string[], number[], Date or null}` | Handed to `Action.SubmitForm.onSubmit`. | K | `form.tsx:114-125` |
| `ActionPanel` | `title?`, `children` | Gets a stable id. Opens with **Ctrl+B** on Linux (`V/extra/config.jsonc:213`). In List context the first action is **Enter** and the second **Shift+Enter**; in Form context the first is **Ctrl+Enter** (§4.1). | R, P0 | `action-pannel.tsx:10-51` |
| `ActionPanel.Section` | `title?`, `children` | | R | `action-pannel.tsx:16-21,53-65` |
| `ActionPanel.Submenu` | `title` (req), `icon?`, `shortcut?`, `onOpen?`, `children`; **`autoFocus`, `filtering`, `isLoading`, `throttle`, `onSearchTextChange` are commented out** of the public type but present in the intrinsic | Nested action list, loaded lazily via `onOpen`. | R | `action-pannel.tsx:23-36,67-87`; `jsx.d.ts:143-155` |
| `Action` | `title` (req), `onAction` (req), `icon?`, `shortcut?: Keyboard.Shortcut or Keyboard.Shortcut.Common.*`, `autoFocus?`, `style?: "regular" or "destructive"` (`Action.Style`) | Gets a stable id. The comment advises named shortcuts so user keybinds apply. | R, P0 | `actions.tsx:24-39,152-161,426-429` |
| `Action.CopyToClipboard` | `content` (string), `concealed?`, `onCopy?`, `title?` ("Copy to clipboard"), base | Copies (concealed copies are kept out of history), **closes the window**, then calls `onCopy`. Bug: the `icon` prop is ignored (always `Icon.CopyClipboard`). | R, P0 | `actions.tsx:49-56,163-183` |
| `Action.Paste` | `content`, `onPaste?`, `title?` ("Paste to active window") | Closes the window first so focus returns, then pastes. Falls back to copy when no input server is available (Tom runs with it **off**, `DF/home/vicinae.nix:41`). | R, P1 | `actions.tsx:87-92,185-204`; `TS/clipboard.ts:69-77` |
| `Action.Push` | `target: ReactNode`, base | Pushes a view onto the command's navigation stack. | R, P0 | `actions.tsx:58-62,311-322` |
| `Action.Open` | `target`, `app?: Application` | `open(target, app)`. | R, P0 | `actions.tsx:64-69,206-215` |
| `Action.OpenInBrowser` | `url`, `title?` ("Open in Browser") | Opens the URL, then closes the window. | R, P0 | `actions.tsx:94-98,276-291` |
| `Action.OpenWith` | `path`, `onOpen?`, `title?` ("Open with...") | A Submenu that fetches `getApplications(path)` on open, then lists one action per app. | R, P2 | `actions.tsx:71-76,217-259` |
| `Action.ShowInFinder` | `path`, `select?` (default true), `title?` ("Show in file browser"), `icon?`, `shortcut?`, `onShow?` | `showInFileBrowser`, then closes the window. | R (route to `gpuix-shell files`, N) | `actions.tsx:100-109,293-309` |
| `Action.Trash` | `paths: PathLike or PathLike[]`, `onTrash?`, `title?` | **Calls `trash()`, which is `fs.rm(p, {recursive:true})`: a permanent delete, not the freedesktop trash.** | R, but **fix it**: `gio trash` (N) | `actions.tsx:78-85,261-274`; `TS/utils.ts:11-16` |
| `Action.SubmitForm` | `onSubmit(values) => boolean, void or Promise`, `title?` ("Submit"), base | Renders an `<action>` whose `onSubmit` the host calls with the values. | R, P1 | `actions.tsx:111-118,324-341` |
| `Action.CreateQuicklink` | `quicklink: {link, name?, application?, icon?}`, `title?` | Host-side action `type:"create-quicklink"`. | R, P2 | `actions.tsx:120-125,145-150,348-376` |
| `Action.RunInTerminal` | `args: string[]`, `options?: {hold?, appId?, title?, workingDirectory?}`, base | `runInTerminal`, then closes the window. | R (kitty), P1 | `actions.tsx:137-142,378-393`; `TS/utils.ts:26-95` |
| `Action.PickDate` / `ToggleQuickLook` / `CreateSnippet` | — | **Stubs that return `null`** ("TODO"). | N later, P3 | `actions.tsx:127-132,343-346,395-403` |
| `MenuBarExtra` (+ `Item`, `Submenu`, `Section`, `Separator`) | `icon?`, `isLoading?`, `title?`, `tooltip?`; Item `{title, alternate?, icon?, shortcut?, subtitle?, tooltip?, onAction?}` | Renders empty intrinsics. The manifest accepts `mode: "menu-bar"`, but the registry **filters it out** (`supportedModes` = view, no-view). The Raycast shim maps it to a throwing stub. | D for now; candidate N: render as rail entries (INFERRED) | `menu-bar.tsx:5-51`; `SV/services/extension-registry/extension-manifest.cpp:12,65`; `RC/unsupported.ts` |

### 3.2 Hooks and non-UI APIs

All MEASURED in `TS/`. "RPC" names the figura service method the call goes through (§3.5).

| API | Exact surface | Behaviour / caveat | gpuix-shell | Pointer |
|---|---|---|---|---|
| `useNavigation()` | `{push(node), pop()}` | `push` calls `UI.pushView()` and appends to a React stack. `pop` calls `UI.popView()`; the host's `viewPoped` event shrinks the stack. When the stack empties after shutdown, the process exits. | R, P0 | `hooks/use-navigation.ts:9-14`; `EM/navigation-provider.tsx` |
| `showToast(init, title?, message?)` / `Toast` | `Toast.Options {title, message?, style?}`; `Toast.Style.Success, Failure, Animated`; `toast.title=`/`style=` re-send, `hide()` | RPC `UI.showToast(id, title, message, style)`. **Primary/secondary toast actions are commented out (not implemented). Setting `message` does not re-send.** Animated maps to proto "Dynamic". | R, and **add the actions** (the design kit allows 2 per toast, `wave1/11:202`), P0 | `toast.ts:26-151,222-226,282-295` |
| `showHUD(title, {clearRootSearch?, popToRootType?})` | — | RPC `UI.showHud`. | R → the OSD surface (BRIEF §3.3), P0 | `controls.ts:39-48` |
| `closeMainWindow({clearRootSearch?, popToRootType?})`, `popToRoot({clearSearchBar?})`, `clearSearchBar()`, `getSelectedText()` | `PopToRootType.Default` (follows the user setting), `Immediate`, `Suspended` | `getSelectedText` is RPC `UI.getSelectedText`. | R, P0; selected text via `wl-paste --primary` (INFERRED) | `controls.ts:7-93` |
| `confirmAlert(opts)` / `Alert` | `{title, message?, icon?, primaryAction?, dismissAction?, rememberUserChoice?}`; `Alert.ActionStyle.Default, Destructive, Cancel` | Resolves to a boolean and runs the matching `onAction`. **`icon` is not sent; `rememberUserChoice` is forced to false.** Default message is "Are you sure?". | R (GPUIX `Dialog`), P1 | `alert.ts:8-86` |
| `Clipboard` | `copy(content, {concealed?})`, `paste(content)`, `read()` → `{text?, html?, file?, urls?}`, `readText()`, `clear()`; `Content = {text} or {file} or {urls} or {html, text?}` | `concealed` keeps the copy out of history. A file is sent as a `file://` URL. `read` offset is not implemented. | R on the gpuix-shell clipboard store (BRIEF §3.4), P0 | `clipboard.ts:11-128` |
| `LocalStorage` | `getItem`, `setItem`, `removeItem`, `allItems`, `clear`; values string, number or boolean | Per-extension key/value store held by the server (RPC `Storage/*`). | R (per-extension JSON file), P0 | `local-storage.ts:8-37` |
| `Cache` | `new Cache({namespace?, capacity?, ttl?})`, `get`, `set(key, data, {ttl?})`, `has`, `remove`, `clear`, `subscribe`, `isEmpty`, `storageDirectory` | **Pure TypeScript**, file-backed under `environment.supportPath`. LRU index with revision, TTL sweep on construction. | **K: works unchanged** wherever `supportPath` is set | `cache.ts:15-160` |
| `getPreferenceValues<T>()`, `openExtensionPreferences()`, `openCommandPreferences()` | — | Preferences come from launch data (`preferenceValues`). The open calls also close the window. | R (values from Nix settings plus an override file), P1 | `preference.ts:5-25`; `EM/worker.tsx:90` |
| `environment` | `raycastVersion` ("1.0.0", meaningless), `ownerOrAuthorName`, `extensionName`, `commandName`, `commandMode` (`view`/`no-view`; never `menu-bar` at runtime), `assetsPath`, `supportPath`, `isDevelopment`, `appearance`/`theme` (**hard-coded "dark"**), `textSize` ("medium"), `launchType`, `canAccess(api)`, `vicinaeVersion {tag, commit}`, `isRaycast` | `canAccess` is true per capability bit for WindowManagement, BrowserExtension, Wallpaper and FileSearch. **AI is always false.** | R; set `appearance` from the theme pointer (claude-light → light) | `environment.ts:82-179`; `EM/worker.tsx:85-119` |
| `LaunchProps` / `LaunchType` | `{launchType, arguments, draftValues?, launchContext?, fallbackText?, cwd?}`; `UserInitiated` ("userInitiated"), `Background`, `CommandLine` | `cwd` is set by `vicinae cmd launch`. `fallbackText` holds the root query when launched as a fallback. | R, P0 | `environment.ts:8-72` |
| `launchCommand(opts)` | `{name, type, context?, arguments?, fallbackText?}` plus optional `{extensionName, ownerOrAuthorName}` for another extension | RPC `Command.launchCommand`. Note: `RC/unsupported.ts` also defines a throwing `launchCommand`, but `RC/index.ts` re-exports the real one from `@vicinae/api`. | R, P1 | `command.ts:19-76` |
| `updateCommandMetadata({subtitle})` | — | Changes the root-search subtitle of the running command. | R, P2 | `command.ts:11-17` |
| `AI.ask(prompt, {creativity?, model?, signal?})`, `AI.getModels()`, `AI.Model.*` | Model enum lists OpenAI, Anthropic, Mistral, Llama and Perplexity ids | **Both throw "not implemented"** (`@ignore - we don't support AI yet`). | **N**: route to the local `utility` model (Tom's resident text model on the strix, `DF/AGENTS.md` "utility slot"), P3, INFERRED | `ai.ts:4-142` |
| `OAuth.PKCEClient` | `new PKCEClient({redirectMethod: Web, App or AppURI, providerName, providerIcon?, providerId?, description?})`, `authorizationRequest()`, `authorize()`, `setTokens()`, `getTokens()`, `removeTokens()`; `OAuth.TokenSet` | S256 PKCE. Redirect URIs are **Raycast's**: `https://raycast.com/redirect?packageName=Extension`, `raycast://oauth?package_name=Extension`, `com.raycast:/oauth?…`. The server handles the `oauth` deeplink (§3.9). Tokens are stored by the server (`SV/services/oauth`). | R, P3; needs a scheme handler (§6 G9) | `oauth.ts:5-471` (redirect URIs `:300-309`) |
| `BrowserExtension.getTabs()` | `Tab {id, title?, url, active, browserId, lastAccessed, pinned, audible, focus(), close()}`; `closeTab(browserId, tabId)` | Comes from the native bridge (§3.11). | R, **P0 (T14 names Chrome tabs)** | `browser.ts:6-42` |
| `FileSearch.search(q, {limit?=100 (max 10000), filters?.category})` | Categories (from the CLI): image, video, audio, document, archive, application, directory, other | Fuzzy filename search over Vicinae's file index. | R, P2 (needs an index, §6 G6) | `file-search.ts:22-62`; `V/src/cli/src/fs.cpp:296-298` |
| `WindowManagement` | `getWindows(workspaceId?)`, `focusWindow(w)`, `getScreens()`, `getActiveWorkspace()`, `getWorkspaces()`, `getWindowsOnActiveWorkspace()`, `getActiveWindow()`; types `Window {id, title, active, bounds, workspaceId?, application?, focus()}`, `Workspace {id, name, monitorId?, active}`, `Screen {name, make, model, serial?, bounds, physicalResolution, active}` | Vicinae's generic Wayland backend has **no Sway workspace membership** and only transient ids (REPORTED `DF/docs/vicinae-research.md:62`). RPC also has `setWindowBounds` (not exported). | R **better** on Sway IPC (con_id, output names, workspace nums), P1 | `window-management.ts:54-221`; `V/figura/tsapi.fig:176-183` |
| `Wallpaper.set(path, {fit?, screen?})` | — | Backend chosen per desktop; throws when none exists. | **D**: Tom's wallpaper is solid `#000000` (BRIEF §1) → `canAccess(Wallpaper)=false` | `wallpaper.ts:4-37` |
| `open(target, app?)`, `getApplications(path?)`, `getDefaultApplication(path)`, `getFrontmostApplication()`, `showInFileBrowser(path, {select?})`, `runInTerminal(args, {hold?, appId?, title?, workingDirectory?})`, `trash(paths)`, `sendDesktopNotification({title, body, icon?, urgency?})` | `Application` from proto | `getFrontmostApplication` uses the active window's app. `sendDesktopNotification` goes to the system notification server. | R: XDG apps, kitty, own notifications daemon; P0/P1 | `utils.ts:11-193` |
| `Icon` | ~850 named ids (`Icon.CopyClipboard = "copy-clipboard"`, …) | Matches 854 SVGs at `V/src/server/icons/*.svg`. | K (ids) + R (glyph source), P0 | `icon.ts` (853 quoted lines); `V/src/server/icons/` |
| `Color` / `ColorLike` | `Blue, Green, Magenta, Orange, Purple, Red, Yellow, PrimaryText, SecondaryText`; raw string; `{light, dark, adjustContrast}` dynamic | Serialized as `{raw}` or `{dynamic}`. | R: map onto the dotfiles palette (§4.5) | `color.ts:6-45` |
| `Image` / `ImageLike` | URL, asset path, `Icon`, `{source, fallback?, tintColor?, mask?: Circle or RoundedRectangle}`, themed `{light, dark}`, `{fileIcon: path}` | A null `source` degrades to `QuestionMarkCircle`. | R, P0 | `image.ts:9-101` |
| `Keyboard` | `Shortcut {key: KeyEquivalent, modifiers: cmd, windows, meta, ctrl, opt, alt, shift}`; `Shortcut.Common`: Copy, CopyDeeplink, CopyName, CopyPath, Save, Duplicate, Edit, MoveDown, MoveUp, New, Open, OpenWith, Pin, Refresh, Remove, RemoveAll | Common names resolve against the user keybind map (`action.copy`, …; §3.8). | K, P0 | `keyboard.ts:4-124` |

### 3.3 Manifest schema (`package.json`), MEASURED `V/src/typescript/api/src/schemas/manifest.ts`

| Key | Constraint | Behaviour | gpuix-shell |
|---|---|---|---|
| `name` | `^(@workaround/)?[a-z0-9-~][a-z0-9-_~]*$`, 3–255 | Slug. The installed **directory name** becomes the extension id (`extension-manifest.cpp:39`); the provider id is `@<author>/<dirname>` (`SV/extension/extension.cpp:19`) | K |
| `title`, `description` (≥16), `icon` (512², `@dark` variant), `author`, `owner?`, `contributors?`, `pastContributors?`, `license` (`"MIT"` only), `access?` (public/private), `platforms?` (Linux, macOS, Windows), `categories?`, `keywords?` | `:254-570` | Store/preferences metadata | K |
| `commands[]` (1–100) | `name` `^[a-z0-9-~][a-zA-Z0-9-._~]*$` maps to `src/<name>.tsx` (view) or `.ts/.tsx` (no-view); `title`, `subtitle?`, `description`, `icon?`, `keywords?`, `mode: view, no-view or menu-bar`, `interval?` `^(\d+)(s,m,h,d)$` (min 10s; no-view/menu-bar only), `preferences?`, `arguments?`, `disabledByDefault?` | `:339-415`; built entry is `<dir>/<name>.js` (`extension-manifest.cpp:63`) | K; `menu-bar` dropped; `interval` **gated** (§4.5) |
| `preferences[]` (extension or command level; commands inherit and override by `name`) | discriminated `type`: `textfield {placeholder?, default?}`, `password`, `checkbox {label, default?}`, `dropdown {data:[{title,value}], default?}`, `appPicker {multiple? (Vicinae only)}`, `file`, `directory`; all `{name, title, description, required}`; `default` may be `{Linux, macOS, Windows}` | `:4-197` | K |
| `arguments[]` | `text`, `password`, `dropdown {data}`; `{name, placeholder, required?}` | `:200-252`; the JSON schema caps them at 3 (`V/extra/schemas/extension.json`) | K |
| `tools[]`, `ai {instructions, evals}` | Raycast AI-extension metadata; `functionalities: "AI attachment provider", "AI tool"` | `:416-505`; schema only, no runtime | D (or N later with the local model) |
| `dependencies`, `external?` | `@raycast/api` in `dependencies` sets `needsRaycastApi` (`extension-manifest.cpp:45`) | K |

### 3.4 Runtime and lifecycle (MEASURED)

| Feature | Exact behaviour | gpuix-shell | Pointer |
|---|---|---|---|
| Worker pool | Pre-provisions a production worker. `load()` takes a worker and sends `Lifecycle.launch(LaunchEventData)`. Statuses: awaiting_handshake, running, unloading. | R as a Bun `Worker` per command (INFERRED) | `EM/index.ts:19-124`; `V/figura/manager.fig:30-67` |
| Launch data | `{extension_name, command_name, mode View or NoView, entrypoint, asset_path, support_path, preferenceValues, argumentValues, launch_context, is_raycast, owner_or_author_name, launch_type User, Background or CommandLine, capabilities {browserExtension, windowManagement, wallpaper, fileSearch}, fallbackText?, cwd?}` | K (the same object) | `V/figura/manager-extension.fig:1-44` |
| Module routing | Overrides `Module.prototype.require` so `react`, `react/jsx-runtime`, `react-reconciler`, `@vicinae/api` and `@raycast/api` resolve to the bundled copies. `@raycast/api` is a Proxy: unknown symbols become a stub that throws "'X' from @raycast/api is not supported by Vicinae". `NODE_ENV` is set only while requiring, then deleted, so child processes don't inherit it. Injects `_jsx`/`_jsxs` globals that tolerate classic-runtime calls. | **K pattern** (alias to `@gpuix-shell/api`) | `EM/patch-require.ts:4-69` |
| View command | Imports the entrypoint, takes `default.default`, renders `<ErrorBoundary><Suspense><NavigationProvider root={<Cmd {...launchProps}/>}/>`; each render sends `UI.render(serializeViews(views))` | K pattern | `EM/loaders/load-view-command.tsx` |
| No-view command | Awaits `default(launchProps)`, then `emit_unload_requested` immediately | K | `EM/loaders/load-no-view-command.ts`; `EM/worker.tsx:29-35` |
| Reconciler | A custom `react-reconciler` host. Instance = `{$t: type, ...props, children}`. **Function props are swapped for handler ids** (`callbackManager.subscribe`). Removed handlers are freed one frame late (`deferRemoval`/`flushDeferredRemovals`). Each view root carries a dirty generation: only dirty views send a `root`. Renders are debounced to **60/s**. Text nodes are stripped from serialized children. A React element passed as a prop is ignored with an error. | **K design** (port ~440 lines) | `EM/reconciler.ts:26-117,338-398`; `EM/callback.ts` |
| Callbacks | Host → worker `EventCore.handlerActivated(id, args)`; stale ids are ignored | K | `EM/worker.tsx:70-72`; `V/figura/tsapi.fig:359-360` |
| Interval scheduler | Runs `interval` commands in the background, state in `stateDir/extension-intervals.json` | **Gate off by default** (T-rule 2026-09-30, INFERRED) | `SV/extension/extension-interval-scheduler.cpp:21-101` |
| `vici build -o out [-s src]` | esbuild per command: bundle, cjs, `jsx: automatic`, platform node, minify, `.node` as file. **externals: react, react/jsx-runtime, @vicinae/api, @raycast/api**. Copies `package.json` and `assets/` to the output. | K (same layout) | `V/src/typescript/api/src/commands/build/index.ts:20-30,60-120` |
| `vici develop [-i dir]` | Pings the server, builds into `dataDir/extensions/<name>`, tails stdout/stderr from `support/<id>/`, typechecks, watches `src`, `package.json` and `assets`; deeplinks `vicinae://api/extensions/develop/{start,refresh,stop}?id=` | R (`gpuix-shell ext dev`), P3 | `…/commands/develop/index.ts`; `…/utils/vicinae.ts:31-48` |
| `vici lint [-s dir]` | Validates `package.json` with the zod schema | K (reuse the schema) | `…/commands/lint/index.ts` |
| Boilerplate | `extra/extension-boilerplate`: 23 sample commands (list, list-detail, grid, form, nested-form, paginated, controlled-list, browser, window-switcher, wallpaper, launch-command, desktop-notif-interval, torture, …); scripts `vici build/develop/lint` | **K as the conformance suite** (§4.7) | `V/extra/extension-boilerplate/{package.json:152-157,src/*}` |

### 3.5 Wire protocol (figura services), MEASURED `V/figura/*.fig`

`ipc.fig` (CLI and browser host → server), `service Ipc` (`:117-133`):
`ping() → {version, pid}`, `deeplink({url}) → {error?}`, `describe() → {open, entrypoint}`,
`launchApp({appId, args[], newInstance}) → {error?, focusedWindowTitle}`, `listCommands() → {commands:[{id,name}]}`,
`launchCommand({entrypoint, args[], cwd?, query?}) → {error?}`, `dmenu(DMenuRequest) → {output}`,
`browserInit({id, name, engine})`, `browserTabsChanged(BrowserTabInfo[])`, `fsQuery(q, {limit, category?}) → FileResult[]`,
events `focusTab({tabId})`, `closeTab({tabId})`.
`DMenuRequest = {rawContent, navigationTitle?, placeholder?, format: Data or Index, sectionTitle?, noSection, noQuickLook, noIcon, noMetadata, query?, width?, height?, noFooter, password}` (`:58-73`).

`tsapi.fig` (worker → server, tunnelled through the manager) services: `Application {list, open, getDefault, showInFileBrowser, runInTerminal}` (`:19-24`);
`UI {render, showToast, updateToast, hideToast, showHud, closeMainWindow, popToRoot, confirmAlert, pushView, popView, setSearchText, getSelectedText, sendDesktopNotification; events viewPoped, viewPushed}` (`:111-131`);
`WindowManagement {focusWindow, getActiveWindow, getActiveWorkspace, getWindows, getScreens, getWorkspaces, setWindowBounds}` (`:176-183`);
`Clipboard {copy, paste, clear, readContent}` (`:198-202`); `Storage {get, set, remove, clear, list}` (`:207-212`);
`FileSearch {search}` (`:243-244`); `Command {launchCommand, updateCommandMetadata, openExtensionPreferences, openCommandPreferences}` (`:269-273`);
`OAuth {authorize, getTokens, setTokens, removeTokens}` (`:316-320`); `Wallpaper {set}` (`:336-337`);
`BrowserExtension {getTabs, focusTab, closeTab}` (`:351-354`); `EventCore {event handlerActivated(id, args)}` (`:359-360`).

**Known bug (REPORTED, `DF/docs/vicinae-research.md:144-148`; herdr-picker works around it):** every
CLI connection starts at request id 1, and the server routes pending async replies by id alone. A
concurrent `state open` can steal a pending `dmenu` reply ("Failed to invoke dmenu: unknown_key").
gpuix-shell must route replies **per connection** (§4.6).

### 3.6 `vicinae` CLI reference (MEASURED `V/src/cli/src/cli.cpp:464-541` and siblings)

| Verb | Flags and args | Behaviour | gpuix-shell equivalent (INFERRED) | Tom uses |
|---|---|---|---|---|
| `vicinae` (no args) | — | Prints help | same | — |
| `vicinae <scheme>://…` | a single argument | Sent as a deeplink when the scheme is `vicinae`, `raycast` or `com.raycast` (`:487-499`; `V/src/lib/common/src/common.cpp:22-26`) | `gpuix-shell <url>` | — |
| `server` | `--open`, `--replace` (SIGKILLs the pinged pid, waits 200 ms), `--config <path>`, `--no-extension-runtime` | `execv` of the server with JSON options; refuses when one is already running without `--replace` | `gpuix-shell launcher` daemon (BRIEF §3.2) | the unit (`DF/home/vicinae.nix:29-33`) |
| `version` / `ver` | — | tag, commit, build, provenance | same | — |
| `ping` | — | "Pinged successfully." | same | — |
| `toggle` | `-q, --query` | deeplink `vicinae://toggle?fallbackText=` | **`gpuix-shell toggle [-q]`, P0** | **Mod+d, Mod+space** (`DF/home/dot_config/sway/binds.conf:6-7`) |
| `open` | `-q, --query` | `vicinae://open` | same | — |
| `close` | — | `vicinae://close` | same | — |
| `cmd ls` / `cmd list` (alias `command`) | `-j, --json` | ids, or `[{id, name}]` | same | research (`vicinae-research.md:48`) |
| `cmd launch <entrypoint> [args…]` | `--cwd`, `-q, --query` | `provider:entrypoint` (split at the first `:`, `SV/common/entrypoint.hpp:25-29`). Positional args map to the manifest's declared arguments in order; extra args fail with a usage line (`SV/ipc/ipc-command-server.cpp:94-119`). `cwd` defaults to the shell's cwd. | **same, P0** | **Mod+v `cmd launch clipboard:history`** (`binds.conf:114`) |
| `deeplink <link>` / `link` | — | Ipc `deeplink` | same | — |
| `dmenu` | `-n --navigation-title`, `-s --section-title` (`{count}` placeholder), `-f --format data, index` (default data), `-p --placeholder`, `-q --query`, `-W --width`, `-H --height`, `--no-section`, `--no-quick-look`, `--no-metadata`, `--no-footer`, `--password` | Reads **all** of stdin, one row per line. A row starting with `/` shows the basename, plus the parent dir when quick-look applies. Fuzzy filter. Empty-result actions: "Pass search text", and "Pass and copy search text" (copy shortcut). Prints the selection (or its index) and exits 1 when empty. | **same flags, P0** (herdr-picker) | **`herdr-picker` speaks `Ipc/dmenu` directly** (`DF/home/dot_local/bin/herdr-picker:211-258`) |
| `theme set <id>` / `theme template` (`tmpl`) | — | `vicinae://theme/set/<id>`; prints the TOML template. `check`/`paths` are commented out. | D (gpuix-shell follows `~/.config/theme`, BRIEF §3.5) | `DF/home/dot_local/bin/theme:88-90` |
| `config default` | — | Prints the built-in `config.jsonc` | same | — |
| `script template` | `-t --title` (req), `-l --lang` (bash, python, javascript, typescript, ruby, perl, php, lua, go, swift; default bash), `-m --mode` (default fullOutput) | Prints a header template | same, P2 | — |
| `script check <file>` | — | Parses the metadata; exits 1 with the error | same, P1 | research |
| `state open` | — | Exits **0 if the window is open** | same | — |
| `fs query <q>` / `q` | `-n --limit` (100), `-c --category`, `-j --json` | Query must be **≥3 chars** | P2 | — |
| `app launch <app_id> [args…]` | `--new` | Launches the app, or focuses an existing window (prints its title) | P2 (Sway focus by app_id) | — |
| `logs` | `-n --lines` (50), `-f --follow` | Tails the server log | `journalctl --user -u gpuix-shell-*` | — |

### 3.7 Script commands (MEASURED `V/src/lib/script-command/*`, `SV/script/*`)

| Feature | Exact behaviour | gpuix-shell | Pointer |
|---|---|---|---|
| Header grammar | Lines starting with `//`, `--`, `#` or `;`, then `@vicinae.<key> <value>` or `@raycast.<key> <value>`. **Mixing scopes is an error.** The `#!` shebang is captured. | **K** (port the parser, ~150 lines) | `script-command.cpp:111-146,196-306` |
| Required | `schemaVersion 1`, `title` non-empty | K | `:308-309` |
| Keys | `mode`, `icon`, `iconDark`, `packageName`, `currentDirectoryPath`, `needsConfirmation true/false`, `author`, `authorURL`, `description`, `refreshTime <n>[s,m,h,d]` (**inline mode only**), `argument1..3` (JSON `{type: text, password or dropdown, placeholder?, optional?, percentEncoded?, data? (dropdown), secure? (legacy → password)}`), and **@vicinae-only** `keywords` (JSON array), `exec` (JSON argv), `terminal` (JSON `{hold?, title?, appId?, workingDirectory?}`) | K | `script-command.hpp:15-72`; `.cpp:232-305` |
| Interpreter | A shebang pointing at an existing file is used as-is. Otherwise `env [-S]` is unwrapped, falling back to the extension map (`.py`→python, `.js/.mjs/.cjs`→node, `.sh/.bash`→bash, `.ps1`→pwsh, `.rb`, `.pl`, `.lua`, `.php`). Aliases: python3→python, sh→bash, pwsh→powershell. PATH lookup. | K | `:317-389` |
| Modes | **fullOutput**: push an executor view that streams output, with ANSI colours and http(s) links tokenized. **compact**: toast with the last line (success or danger) and open the window. **silent**: HUD with the last line ("Script executed"), clear search; failure → toast. **terminal**: launch in the terminal with `hold=true` unless overridden, title defaults to the script title, cwd = `currentDirectoryPath`; close the window. **inline**: save the last line as the root item's subtitle (metadata store). | R: Detail view / toast / OSD / kitty / root subtitle | `SV/script/script-actions.cpp:55-150`; tokenizer `SV/script/script-output-tokenizer.cpp:10-94` |
| `needsConfirmation` | confirmAlert "Are you sure" before running | K | `script-actions.cpp:143-146` |
| `refreshTime` | **Parsed, but the server never schedules it** (grep: no use outside the lib) | Refresh only while the launcher is visible (INFERRED; see the scheduled-work rule) | MEASURED grep `SV/` |
| Discovery | `dataSearchPaths("scripts")` (user `$XDG_DATA_HOME/vicinae/scripts` plus `$XDG_DATA_DIRS/*/vicinae/scripts`), plus the provider preference `customDirs`. Skips dotfiles, `*.template*`, `.md/.svg/.txt` and binary files. Recursion is depth-limited; ids are dotted subdir paths. A file watcher plus a **15-minute rescan**. Entrypoint `scripts:<id>`. | R (watch `~/.local/share/gpuix-shell/scripts` plus dotfiles-declared dirs) | `SV/script/script-scanner.cpp:23-71`; `SV/services/script-command/script-command-service.cpp:10-65`; `SV/root-search/scripts/script-root-provider.hpp:116,129-173` |

### 3.8 Config reference (MEASURED `V/extra/config.jsonc:1-258`, `SV/config/config.hpp:19-420`, `config.cpp`)

The file is `~/.config/vicinae/settings.json` (`SV/server.cpp:243`; `config.hpp:427`). The default
config is embedded (`:config.jsonc`). Precedence: user file > `imports[]` (relative to the importing
file) > defaults (`config.cpp:262-280`), then **`VICINAE_OVERRIDES`** (colon-separated paths, set by
the HM wrapper) overrides everything (`config.cpp:67-73`). GUI edits rewrite the user file and lose
its comments (`config.cpp:18-27`). The file is watched and hot-reloaded (`config.cpp:83-85`). JSON
keys are snake_case (`config.hpp:440-460`).

| Key | Default | Tom's value (`DF/home/vicinae.nix`) | gpuix-shell |
|---|---|---|---|
| `imports` | `[]` | — | K (settings fragment imports) |
| `telemetry.system_info` | true | **false** (:39) | D (no telemetry) |
| `input_server.enabled` | true | **false** (:41) | D initially; paste = copy |
| `tray.enabled` | true | **false** (:40) | own tray host (reader 35) |
| `search_files_in_root` | false | — | K false |
| `activate_on_single_click` | false | — | K |
| `escape_key_behavior` | `navigate_back` (or `close_window`) | — | K |
| `pop_on_backspace` | true | — | K |
| `close_on_focus_loss` | false (no effect with layer shell plus exclusive keyboard) | — | K |
| `consider_preedit` | false | — | K |
| `pop_to_root_on_close` | false | **true** (:42) | K true |
| `favicon_service` | `twenty` (or `google`, `none`) | **none** (:43) | K none (privacy; INFERRED) |
| `keybinding` | `default` (or `vim`, `emacs`) | — | K |
| `font.rendering` | `qt` on Linux | — | n/a (GPUIX text) |
| `font.normal.{family,size}` | `auto` (Inter) / platform | **Anthropic Sans 12** (:35-38, T7) | K |
| `theme.{light,dark}.{name,icon_theme}` | vicinae-light/-dark, `auto` | `dotfiles-current` for both (:44-47) | R (theme pointer) |
| `launcher_window.opacity` | unset | **1** (:49) | flat, opaque (BRIEF) |
| `launcher_window.material` / `blur.enabled` | `auto` / true | **none** (:50) | D (no blur) |
| `launcher_window.rounding` | 10 (CSD struct: Linux 10, else 26) | **0** (:51) | **conflict** with the design kit's 16 (§6 G12) |
| `launcher_window.clock.{enabled,format,interval}` | Linux on, `hh:mm`, 60 s | — | R (status bar clock) |
| `launcher_window.client_side_decorations.{enabled,border_width,shadow_size}` | true, 1, 12 | border 1, **shadow 0** (:52-55) | hairline, no shadow |
| `launcher_window.compact_mode.enabled` | false | — | N option |
| `launcher_window.size.{width,height}` | **770×480** | — | BRIEF says **700×580** |
| `launcher_window.screen` | `auto` (X11 only) | — | output pinning via layer-shell output (INFERRED) |
| `launcher_window.layer_shell.{enabled,keyboard_interactivity,layer}` | true, `exclusive`, `top` | true, exclusive, **overlay** (:56-60) | K overlay + exclusive |
| `launcher_window.floating_status_bar` (hidden key) | true | — | — |
| `global_shortcuts.toggle` / `inhibit_apps` | "super+control+space" on Linux (comment) / `[]` | Sway binds instead | D (Sway owns keys) |
| `keybinds` | `open-search-filter` control+P, `open-settings` control+",", `toggle-action-panel` control+B, `action.copy` control+shift+C, `action.copy-name` control+shift+".", `action.copy-path` control+shift+",", `action.dangerous-remove` control+shift+X, `action.duplicate` control+D, `action.edit` control+E, `action.edit-secondary` control+shift+E, `action.move-down/up` control+shift+arrows, `action.new` control+N, `action.open` control+O, `action.pin` control+shift+P, `action.refresh` control+R, `action.remove` control+X, `action.save` control+S | — | **K** (map `Keyboard.Shortcut.Common`) |
| `favorites` | `["clipboard:history"]` | `applications:herdr-picker`, `clipboard:history`, `browser-extension:browse-tabs`, `media:now-playing`, `core:search-tray` (:84-90) | **K ids** |
| `fallbacks` | `["files:search"]` | — | K |
| `providers.<id>.{enabled, preferences, entrypoints.<id>.{alias, enabled, shortcut, preferences}}` | `{}` | `core.entrypoints.{report-bug,sponsor}.enabled=false`; clipboard `{monitoring, ignorePasswords, evictionThreshold "86400", preserveTagged}`; files `{autoIndexing, indexingPaths [~/Downloads, ~/Documents]}` (:62-83) | **K shape** |
| hidden: `wrap_navigation` false, `encrypt_sensitive_data` (Linux false), `language`, `pixmap_cache_mb` 50, `header.{height 60, margins}`, `footer.height 40` | | — | design values (§4.1) |

### 3.9 Deeplink grammar (MEASURED `SV/ipc/ipc-command-handler.cpp:33-312`)

Schemes are `vicinae`, `raycast` and `com.raycast` (`Omnicast::APP_SCHEMES`). The command is the
URL host, or the first path segment for `com.raycast:/…`. Query values are fully decoded.
Registered by `V/extra/vicinae-url-handler.desktop` (`MimeType=x-scheme-handler/vicinae;…/raycast;…/com.raycast`).

| Deeplink | Effect |
|---|---|
| `vicinae://ping` | no-op |
| `vicinae://kill` | `QCoreApplication::exit(1)` |
| `vicinae://toggle?fallbackText=` | toggle window, set search text |
| `vicinae://open?popToRoot=true&fallbackText=` | open |
| `vicinae://close?popToRootType=immediate,suspended&clearRootSearch=true` | close |
| `vicinae://settings/open?tab=` / `settings/close` | settings window |
| `vicinae://launch/<provider>` | **provider-scoped search view**, with the back button hidden (e.g. `launch/clipboard`) |
| `vicinae://launch/<provider>/<entrypoint>?arguments={json}&fallbackText=&toggle=true` | Activate the entrypoint. The split is at the **last** `/`, so extension providers like `@author/store.vicinae.x` work. `toggle=true` closes the window instead when it is open. |
| `vicinae://pop_current` / `pop_to_root?clearSearch=` | navigation |
| `vicinae://extensions/<author>/<name>` | **store detail page**: Vicinae store, or the Raycast store when scheme is `raycast`/`com.raycast`. Three segments are rejected. |
| `vicinae://theme/set/<id>?openWindow=` | rescan themes, set or reload |
| `vicinae://oauth?code=&state=` | complete PKCE |
| `vicinae://api/extensions/develop/{start,refresh,stop}?id=` | dev session (refresh re-launches the active command when it belongs to `id`) |

### 3.10 Store and registry (MEASURED)

| Feature | Exact behaviour | gpuix-shell | Pointer |
|---|---|---|---|
| Vicinae store | `GET {VICINAE_API_URL or https://api.vicinae.com/v1}/store/list?page&limit` (fetchAll limit 500), `/store/search?q=`, zip download by URL | **D at runtime** (reproducible Nix installs only; INFERRED) | `SV/services/extension-store/vicinae-store.cpp:41-82`; `SV/utils/environment.hpp:132-135` |
| Raycast store | `GET https://backend.raycast.com/api/v1/store_listings?page&per_page`, `/store_listings/search?q=`; ids `store.raycast.<name>`. Linux compatibility is not advertised by Raycast, so it is best-effort. A compat sheet comes from `{vicinae api}/raycast/get-compat`. | D at runtime; a **read-only browse** view is N P3 | `SV/services/raycast/raycast-store.cpp:7,18-97` |
| Install | Unzip to `dataDir/extensions/.staging-<id>` (strip 1), require `package.json`, rename to `<id>` | R via Nix (`mkVicinaeExtension`/`mkRayCastExtension` → `xdg.dataFile`) | `SV/services/extension-registry/extension-registry.cpp:36-86` |
| Discovery | `dataSearchPaths("extensions")` = `$XDG_DATA_HOME/vicinae/extensions` plus every `$XDG_DATA_DIRS/*/vicinae/extensions`. Watched, with a 100 ms debounced rescan. Provenance comes from the dir prefix `store.vicinae.`, `store.raycast.` or local. | R (own data dir; optionally also read Vicinae's) | `:20-33,117-140`; `SV/vicinae.cpp:96-108`; `extension-manifest.cpp:39-53` |
| Support dir | `dataDir/support/<id>`: `environment.supportPath`, plus `stdout.txt`, `stderr.txt` and `cli.pid` in dev | R | `extension-registry.cpp:119-121` |

### 3.11 Browser-tab bridge (MEASURED; T14's "how it interacts w google chrome tabs")

| Part | Exact behaviour | gpuix-shell |
|---|---|---|
| Browser extension | MV3, permissions `nativeMessaging` and `tabs`; Chrome id **`kcmipingpfbohfjckomimmahknoddnke`**, Firefox `firefox@vicinae.com` (`V/CMakeLists.txt:81-82`). Host name **`com.vicinae.vicinae`**. On connect it sends request `{id, method:"browser/init", data:{id: randomUUID, name: userAgent, engine:"chromium"}}`, then **notification `browser/tabs-changed`** with the full tab list (`{id, title, url, windowId, active, audible, muted, lastAccessed, pinned}`), debounced 50 ms, on created, updated, removed and activated. It handles notifications **`browser/focus-tab {tabId}`** (activate the tab and focus its window) and **`browser/close-tab {tabId}`**. Retries back off from 1 s to 60 s. | **K: reuse the published extension unchanged** by shipping our own native host under the same name (§4.6) |
| Native host | `vicinae-browser-link`: stdin/stdout native messaging (uint32 length + JSON, 64 MiB cap). Connects to `vicinae.sock` and forwards init/tabs as `Ipc.browserInit`/`browserTabsChanged`, and the `focusTab`/`closeTab` events back to the browser. Exits when the socket closes. | R (~150 lines TS/Bun) |
| Manifest install | The server writes per-user host manifests at startup for each detected browser (google-chrome{,-beta,-unstable}, chromium, Brave, Vivaldi, Edge, Mozilla, LibreWolf, Zen), with `allowed_origins chrome-extension://<id>/` or `allowed_extensions`. Packagers can opt out (`AUTO_INSTALL_BROWSER_MANIFESTS`). | R in Nix (declarative file; never self-writing) |
| Builtins | provider `browser-extension`: `browse-tabs` "Search Browser Tabs" (fuzzy over url 1.0, title 0.6), `shortcut-active-tab` "Create Shortcut from Active Tab" | R, **P0** |
| Tom's state | `enableChromeIntegration = false` in HM; instead the package's manifest is linked to `~/.config/google-chrome/NativeMessagingHosts/com.vicinae.vicinae.json` (`DF/home/vicinae.nix:27,98-99`). Whether the Chrome extension is actually installed on the Zenbook is **unknown** (§6 G4). | — |

Pointers: `V/src/browser-extension/chrome/background.js:1-8,40-110,196-235`; `V/src/browser-extension/src/browser.cpp:23-230`;
`SV/services/browser-extension/native-host-installer.cpp:30-247`; `SV/builtins/browser/browser-extension.cpp`, `browser-tabs-model.hpp:10`.

### 3.12 Nix HM module and builders (MEASURED `V/nix/*`)

| Option (`programs.vicinae.*`) | Default | Effect | gpuix-shell module (`programs.gpuixShell.*`, INFERRED) |
|---|---|---|---|
| `enable`, `package` (null → flake default or `with-soulver`) | — | `home.packages = [wrappedVicinae]` | same |
| `enableSoulver` / `enableNumen` | false / true (mutually exclusive, asserted) | sets `providers.calculator.preferences.backend` | calculator backend choice (reader 35) |
| `enableFirefoxIntegration`, `enableChromeIntegration` | true, true | `programs.{firefox,google-chrome}.nativeMessagingHosts = [pkg]` | `browserIntegration.chrome` → our host manifest |
| `systemd.{enable, autoStart, environment, target}` | –, true, {}, `graphical-session.target` | user unit `vicinae`: `ExecStart … server`, `Restart=always`, `RestartSec=5`, `KillMode=process`, `After`/`PartOf`/`WantedBy` the target | `sway-physical-session.target` (BRIEF §2) |
| `launchd.*` | — | macOS | D |
| `extensions` (list of packages) | `[]` | `xdg.dataFile."vicinae/extensions/${drv.name}".source = drv` | **K pattern** → `gpuix-shell/extensions/` |
| `themes` (attrs of TOML) | `{}` | `xdg.dataFile."vicinae/themes/<n>.toml"` | D (theme pointer) |
| `settings` (JSON) | `{}` | generated file, passed via **`VICINAE_OVERRIDES`** on a `wrapProgram` (the module's prose about `nix.json` is wrong, REPORTED `vicinae-research.md:13`) | **K pattern**: settings as an override layer above a mutable user file |
| `settingOverrides` (paths) | `[]` | appended to `VICINAE_OVERRIDES` (secrets, e.g. `/run/secrets/…`) | K (password preferences out of git) |
| Back-compat renames | `services.vicinae.*` → `programs.vicinae.*` | — | — |

Builders: `mkVicinaeExtension` = `buildNpmPackage` + `importNpmLock`, `buildPhase = "npm run build -- --out=$out"`
(`V/nix/mkVicinaeExtension.nix:1-21`). `mkRayCastExtension {name, rev, hash}` sparse-checks out
`raycast/extensions/extensions/<name>` and installs `$HOME/.config/raycast/extensions/*/.` into
`$out` (`V/nix/mkRayCastExtension.nix:1-49`). Both produce the runtime layout from §3.10, so
**gpuix-shell can consume them unchanged** (INFERRED; the layout check is in §4.7).

### 3.13 Every place Tom's dotfiles touch Vicinae today (MEASURED; the replacement must cover each)

| Touchpoint | Line | Replacement |
|---|---|---|
| `bindsym $mod+d exec vicinae toggle`; `bindsym $mod+space exec vicinae toggle` | `DF/home/dot_config/sway/binds.conf:6-7` | `gpuix-shell toggle` |
| `bindsym $mod+v exec vicinae cmd launch clipboard:history` | `binds.conf:114` | `gpuix-shell cmd launch clipboard:history` (keep the id) |
| `herdr-picker` → native `Ipc/dmenu` over `vicinae.sock`, random high request id, response validation | `DF/home/dot_local/bin/herdr-picker:211-258` (prompts `:407,531`) | gpuix-shell socket, same framing (§4.6), or the Mod+i switcher (BRIEF §3.2) |
| `theme` → `vicinae theme set dotfiles-current` when the unit is active | `DF/home/dot_local/bin/theme:88-90` | drop; gpuix-shell watches `~/.config/theme` |
| HM `programs.vicinae` settings, favorites, provider prefs, Chrome host link, theme symlink | `DF/home/vicinae.nix:22-99` | `home/gpuix-shell.nix`, never both (BRIEF §2) |
| 7 desktop entries shown in Vicinae app search (Herdr workspaces, New/Restore/Rename workspace, Dismiss/Restore notification, Network settings) | `DF/home/vicinae.nix:148-170` | first-party launcher commands (same argv) |
| `vicinae.toml` theme fragment (palette → Vicinae slots) | `DF/home/themes/default.nix:140-175,286` | `gpuix-shell.json` fragment (BRIEF §3.5); **reuse its slot mapping** |
| "Vicinae owns clipboard history; do not start a second cliphist watcher." | `DF/home/dot_config/sway/startup.conf:4` | gpuix-shell clipboard daemon owns it |
| Flake input `github:vicinaehq/vicinae/v0.29.1`; checks assert the client enables Vicinae, the strix does not, and the font is Anthropic Sans | `DF/flake.nix:151,1213-1228` | the swap must update these assertions (INFERRED) |

---

## 4. Design values

### 4.1 Numbers and defaults worth keeping (MEASURED unless marked)

- Render cadence: at most **60 view-tree frames/s**, debounced (`EM/reconciler.ts:365`). Only dirty views carry a `root`.
- Default list shortcuts: first action of the first section is **Enter**, the second **Shift+Enter**. Form: the first is **Ctrl+Enter** (`SV/ui/action-panel/action-panel-state.hpp:111-136`; `SV/internal/keyboard/keyboard.hpp:41`). A default shortcut wins, and the extension's own shortcut is kept as a secondary.
- Action panel: **Ctrl+B**; search filter: **Ctrl+P**; settings: **Ctrl+,** (`V/extra/config.jsonc:211-213`).
- Grid: itemSize small/medium/large = **8/5/3 columns**; 11 aspect ratios; insets zero, small, medium, large; fit contain (default) or fill (`grid.tsx:11-54,204-210`).
- Window: default **770×480** (`config.hpp:80-82`); header **60**, footer **40** (`config.hpp:255-270`); CSD Linux rounding 10, border 1, shadow 12. Tom overrides rounding 0, shadow 0, opacity 1, no material. BRIEF's launcher is **700×580, overlay, top margin 108, keyboard exclusive** (BRIEF §3.3).
- Font: Anthropic Sans **12** (T7).
- Clock: interval 60 s, `hh:mm` (`config.jsonc:126-136`).
- Arguments: at most 3 per command and per script (`script-command.cpp:297`; extension.json schema).
- Keywords: at most 12, each 1–25 chars, no commas (`V/extra/schemas/extension.json`).
- `interval`: minimum **10 s** (`manifest.ts:389-395`).
- File search: CLI min **3 chars**; API limit default **100**, max **10 000** (`fs.cpp:345`; `file-search.ts:27-30`).
- Browser bridge: tab debounce **50 ms**, retry 1 s → 60 s, message cap **64 MiB** (`background.js:2-4`; `browser.cpp:23`).
- Fuzzy weights: browser tabs url 1.0, title 0.6 (`browser-tabs-model.hpp:10`); dmenu single field 1.0, stable sort by score (`dmenu-model.cpp`); keywords score below title/subtitle (`list.tsx:169-175`).
- Clipboard (Tom): `evictionThreshold "86400"`, `ignorePasswords`, `preserveTagged`, `monitoring` (`DF/home/vicinae.nix:70-75`).
- Escape = navigate back; Backspace on an empty search pops; Tom sets `pop_to_root_on_close` true.
- Selection colour: Vicinae's list selection = `t.selection.bg/fg` (T8; `DF/home/themes/default.nix:166-170`). Loading bar = `t.brand` (`:171-172`).
- `Color` → palette slot (MEASURED mapping in Tom's fragment `default.nix:153-165`): blue→`t.blue`, green→`t.green`, magenta→`t.magenta`, orange→`t.orange`, red→`t.red`, yellow→`t.yellow`, purple→**`t.magenta`**, primary-text→`t.fg`, secondary-text→`t.comment`; muted/placeholder→`t.comment`; danger→`t.red`; success→`t.green`.

### 4.2 Hosting design: architecture (INFERRED recommendation)

Goal (T14, T17, T18): host Vicinae/Raycast-grammar extensions in GPUIX so that (a) first-party
features (herdr workspaces, Navidrome music, Wi-Fi, Bluetooth, clipboard, scripts) are written once
in `List/Grid/Detail/Form/ActionPanel/Action`, and (b) existing Raycast/Vicinae extension logic
ports with **no code change**: the module alias carries `@raycast/api` and `@vicinae/api`.

**Decision 1 (keep Vicinae's wire vocabulary):** the contract between extension code and the shell
is the **view tree**: intrinsic element names and props exactly as `V/src/typescript/api/types/jsx.d.ts:30-244`.
Reason: the public `@vicinae/api` component wrappers (`TS/components/*.tsx`) do nothing but
serialize into this vocabulary. We can reuse them (ISC-declared package; §6 G11), and any extension
that runs on Vicinae renders on gpuix-shell. Extensions get **no styling props**, as in Raycast. They
inherit the Anthropic/noir look automatically, which is what Tom wants (BRIEF §1 look rulings).

**Decision 2 (one renderer, two placements):** every command (first-party or third-party) is
reconciled into the same JSON view tree by a port of `EM/reconciler.ts`. The host renders that tree
with GPUIX React components. Placement is per provider:

- **in-process** (first-party, trusted, Nix-built, fast startup): the reconciler runs in the
  launcher process. Handlers are direct function references, with no serialization round-trip.
- **worker** (third-party Raycast/Vicinae extensions): a Bun `Worker` (or a `bun` child process
  when native modules or `process.exit` need isolation) runs the same reconciler. It posts
  `UI.render(json)`, and the host posts `EventCore.handlerActivated(id, args)` back. The worker is
  killed when the view closes, or right after a no-view command (`EM/worker.tsx:31-35`). A crash
  shows an error view (`SV/extension/views/extension-error-view-host.*`) and never takes down the
  launcher.

**Decision 3 (root search is a provider registry, not React):** the launcher's root list (apps,
commands, scripts, quicklinks, favorites, fallbacks, plus dynamic rows such as tabs, files, the
calculator and music tracks) is a pure-data registry. Pure data keeps it unit-testable with
`bun test` and keeps the first frame instant. That matches the prior `providers.ts`
(`/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/providers.ts:33-45`) and Vicinae's
`RootItemManager`. Activating a root item either runs a no-view action or opens a view command.

**Decision 4 (ids stay Vicinae's):** entrypoint ids are `provider:entrypoint`. Extension providers
are `@author/<dirname>`. Favorites, fallbacks, `cmd launch` and the `launch/<provider>/<entrypoint>`
deeplink all use them, so Tom's `clipboard:history`, `applications:herdr-picker` and
`browser-extension:browse-tabs` survive the swap verbatim.

```
 Sway bind ─► gpuix-shell CLI ─► $XDG_RUNTIME_DIR/gpuix-shell/shell.sock (figura-style JSON-RPC, per-connection reply routing)
                                         │
                       ┌─────────────────┴──────────────────┐
                       │  launcher process (@gpuix/react, layer-shell overlay 700×580)
                       │   RootRegistry ── providers: apps, scripts, herdr, clipboard, browser-tabs, music, wifi, bt, extensions…
                       │   NavStack ─ frames: ViewTree ← reconciler (in-process)  ← first-party commands
                       │                          ↑ UI.render(json) / handlerActivated ↓
                       │                       Bun Worker (one per running third-party command, @raycast/api → @gpuix-shell/api)
                       │   HostServices (tsapi.fig names): Application, UI, WindowManagement(Sway IPC), Clipboard,
                       │     Storage, FileSearch, Command, OAuth, BrowserExtension, EventCore
                       └── talks to: notifications daemon (toasts/HUD/OSD), clipboard store, Chrome native host, herdr, mpv/Navidrome
```

### 4.3 TypeScript interfaces (INFERRED; names proposed for `pkgs/gpuix-shell/src/ext/`)

```ts
// src/ext/api/index.ts : the "@gpuix-shell/api" module. Aliased at runtime as @vicinae/api and @raycast/api.
// UI components: re-export ports of TS/components/*.tsx unchanged (they only serialize to intrinsics).
export { List, Grid, Detail, Form, ActionPanel, Action, MenuBarExtra } from "./components";
export { Icon, Color, Image, Keyboard, Toast, Alert, Clipboard, LocalStorage, Cache, OAuth,
         BrowserExtension, FileSearch, WindowManagement, AI, LaunchType, PopToRootType, environment } from "./runtime";
export { showToast, showHUD, closeMainWindow, popToRoot, clearSearchBar, getSelectedText, confirmAlert,
         getPreferenceValues, openExtensionPreferences, openCommandPreferences, launchCommand,
         updateCommandMetadata, open, getApplications, getDefaultApplication, getFrontmostApplication,
         showInFileBrowser, runInTerminal, trash, sendDesktopNotification, useNavigation } from "./runtime";
export type { LaunchProps, Application } from "./runtime";

// src/ext/tree.ts : the wire contract (identical to Vicinae's serializeViews output).
export type Node = { $t: IntrinsicName; children?: Node[]; [prop: string]: unknown }; // function props → handler-id strings
export type ViewFrame = { dirty: boolean; root?: Node };
export type RenderMessage = { views: ViewFrame[] };            // UI.render(JSON.stringify(msg))
export type IntrinsicName =
  | "view" | "list" | "list-section" | "list-item" | "list-item-detail" | "list-item-detail-metadata"
  | "grid" | "grid-section" | "grid-item" | "detail" | "empty-view"
  | "metadata" | "metadata-label" | "metadata-separator" | "metadata-link" | "tag-list" | "tag-item"
  | "action-panel" | "action-panel-section" | "action-panel-submenu" | "action"
  | "form" | "text-field" | "password-field" | "text-area-field" | "checkbox-field" | "date-picker-field"
  | "dropdown-field" | "tag-picker-field" | "tag-picker-item" | "file-picker-field" | "form-description"
  | "link-accessory" | "separator" | "dropdown" | "dropdown-section" | "dropdown-item"
  | "menu-bar" | "menu-bar-item" | "menu-bar-submenu" | "menu-bar-section";

// src/ext/registry.ts : root search (pure data, bun-testable).
export type EntrypointId = `${string}:${string}`;              // provider:entrypoint (split at first ':')
export interface ArgumentSpec { name: string; type: "text" | "password" | "dropdown"; placeholder: string;
  required?: boolean; data?: { title: string; value: string }[] }
export interface PreferenceSpec { name: string; title: string; description: string; required: boolean;
  type: "textfield" | "password" | "checkbox" | "dropdown" | "appPicker" | "file" | "directory";
  default?: unknown; data?: { title: string; value: string }[]; label?: string; placeholder?: string; multiple?: boolean }

export interface RootItem {
  id: string;                                   // entrypoint part
  title: string; subtitle?: string; icon?: ImageLike; keywords?: string[];
  accessories?: List.Item.Accessory[];          // e.g. herdr ◉◐●✓○ status, "inline" script output
  arguments?: ArgumentSpec[];                   // root search shows ≤3 argument fields inline
  mode: "view" | "no-view";
  run(props: LaunchProps, host: HostServices): Promise<void> | React.ReactElement; // no-view: side effect; view: element to reconcile
}
export interface RootProvider {
  id: string;                                   // "applications" | "scripts" | "herdr" | "clipboard" | "browser-extension" | "music" | "@author/dir" …
  title: string;
  placement: "in-process" | "worker";
  preferences?: PreferenceSpec[];
  items(): RootItem[];                          // static entrypoints
  search?(query: string, signal: AbortSignal): Promise<RootResult[]>; // dynamic rows; cancelled on every keystroke
  subscribe?(onChange: () => void): () => void; // e.g. app dir watcher, herdr snapshot, tab list
}
export interface RootResult { id: string; title: string; subtitle?: string; icon?: ImageLike;
  accessories?: List.Item.Accessory[]; score?: number; actions: ResultAction[] } // actions[0] = Enter, [1] = Shift+Enter
export type ResultAction = { title: string; shortcut?: Keyboard.Shortcut; style?: "regular" | "destructive";
  run(host: HostServices): Promise<void> | React.ReactElement };

// src/ext/host.ts : host services, named after tsapi.fig so @vicinae/api's getClient() can be re-pointed 1:1.
export interface HostServices {
  Application: { list(target?: string): Promise<Application[]>; open(target: string, appId?: string): Promise<void>;
    getDefault(target: string): Promise<Application>; showInFileBrowser(target: string, select: boolean): Promise<void>;
    runInTerminal(o: { cmdline: string[]; hold: boolean; appId?: string; title?: string; workingDirectory?: string }): Promise<boolean> };
  UI: { render(json: string): void; showToast(id: string, title: string, message: string, style: "Success" | "Error" | "Dynamic",
      actions?: ToastActionSpec[]): void; hideToast(id: string): void;
    showHud(text: string, clearRoot: boolean, popToRoot: "Default" | "Immediate" | "Suspended"): void;
    closeMainWindow(clearRoot: boolean, popToRoot: "Default" | "Immediate" | "Suspended"): void;
    popToRoot(clearSearchBar: boolean): void; confirmAlert(p: ConfirmAlertPayload): Promise<boolean>;
    pushView(): void; popView(): void; setSearchText(t: string): void; getSelectedText(): Promise<string>;
    sendDesktopNotification(d: { title: string; body: string; icon?: unknown; urgency: "Low" | "Normal" | "Critical" }): void };
  WindowManagement: SwayWindowManagement;       // backed by Sway IPC (get_tree / get_workspaces / get_outputs)
  Clipboard: { copy(c: ClipboardContent, o: { concealed: boolean }): Promise<void>; paste(c: ClipboardContent): Promise<void>;
    clear(): Promise<void>; readContent(): Promise<ClipboardContent> };
  Storage: { get(k: string): Promise<unknown>; set(k: string, v: unknown): Promise<void>; remove(k: string): Promise<void>;
    clear(): Promise<void>; list(): Promise<Record<string, unknown>> };   // scoped per extension id
  FileSearch: { search(q: string, o: { limit: number; filters: { category?: string } }): Promise<FileInfo[]> };
  Command: { launchCommand(o: LaunchCommandOptions): Promise<void>; updateCommandMetadata(p: { subtitle?: string }): Promise<void>;
    openExtensionPreferences(): Promise<void>; openCommandPreferences(): Promise<void> };
  OAuth: { authorize(p: unknown): Promise<{ code: string }>; getTokens(id?: string): Promise<unknown>;
    setTokens(p: unknown): Promise<void>; removeTokens(id?: string): Promise<void> };
  BrowserExtension: { getTabs(): Promise<BrowserTab[]>; focusTab(browserId: string, tabId: number): Promise<void>;
    closeTab(browserId: string, tabId: number): Promise<void> };
  capabilities: { windowManagement: true; browserExtension: boolean; wallpaper: false; fileSearch: boolean; ai: boolean };
}
```

Porting a first-party feature: write `src/providers/herdr.tsx` with `items()` that returns
"Herdr workspaces" (`mode: "view"`). Its `run()` returns `<List>` rows with herdr status accessories
and `Action`s that call Sway. The same file could later run as a worker with no change.

### 4.4 Intrinsic node → GPUIX element mapping (INFERRED; @gpuix/react 0.11.0 primitives MEASURED in `…/probe011/node_modules/@gpuix/react/jsx-runtime.d.ts:32-45`: `div, text, img, svg, canvas, input, textarea, anchored, code, diff, markdown, virtual-list`; components `Select`, `Combobox`, `Dialog`, `Tooltip`, `DismissableLayer`)

| Node(s) | GPUIX rendering | Notes |
|---|---|---|
| `view` | one NavStack frame (back = Esc or Backspace on empty) | the frame's search text is kept per frame |
| `list` | search `input` (event-counted value) + `virtual-list` of rows; split pane when `isShowingDetail` | filtering: our fuzzy unless `onSearchTextChange` and not `filtering`; throttle 200 ms (INFERRED value); `paginationOnLoadMore` near the end |
| `list-section` | section caption row (muted, `t.comment`) | with `{count}` for dmenu |
| `list-item` | 30 px row (rail rhythm 220/30/12/2/8, `wave1/11`): icon 16 + title + dim subtitle + accessories right-aligned (tag = pill with colour, text = coloured text, Date = relative) + active dot | selection = `t.selection` (T8) |
| `list-item-detail`, `detail` | `markdown` + metadata column | Anthropic Serif for documents? (BRIEF fonts; INFERRED: Sans in the launcher) |
| `metadata*`, `tag-list`, `tag-item` | label/value grid, hairline separator, link (`xdg-open`), tag pills (clickable when `onAction`) | |
| `grid`, `grid-section`, `grid-item` | `div` flex-wrap; cell width = (W − insets)/columns, height via aspectRatio; `img` contain/fill; `{color}` swatch | music covers (T18), emoji, colors |
| `empty-view` | centered icon + title + description | |
| `dropdown*` (search-bar accessory) | `Select` at the right of the search bar | `storeValue` → per-command storage |
| `action-panel*`, `action` | footer: navigation title (left), primary action title + key tokens (right); Ctrl+B opens an `anchored` filterable `virtual-list` popover; submenus push inside it | first section shortcuts per §4.1; `style:"destructive"` in `t.red` |
| `form` + fields | label column + control column; `input`, masked `input`, `textarea`, checkbox (`div`), `Select`, `Combobox` multi (tag picker), date (gap), file picker → portal or `gpuix-shell files` | Ctrl+Enter submits; `error` under the field in `t.red`; `info` as `Tooltip` |
| `menu-bar*` | not rendered | candidate: rail entries (N) |
| toast / HUD / alert | gpuix-shell toast surface (top-right, or top-center per T5, §6 G13) / OSD surface / `Dialog` | |

### 4.5 Host-service backends on Sway/Linux (INFERRED)

| Service | Backend | Notes |
|---|---|---|
| `Application.list/open/getDefault` | XDG desktop entries (own parser, or GIO as in the prior `applications.ts`), `xdg-mime`, `gtk-launch`/`gio launch` | `open(url)` → Chrome on workspace 10 (Tom's model) |
| `Application.runInTerminal` | `kitty --class <appId> --title <title> --directory <cwd> [--hold] -- argv` | kitty is Tom's terminal (`DF/home/vicinae.nix:100`) |
| `Application.showInFileBrowser` | `gpuix-shell files --select <path>` (Pinax-like surface, BRIEF §3.2) | N |
| `UI.showToast/showHud` | gpuix-shell notifications daemon (toast stack) / OSD window | add toast actions (2 max) |
| `UI.getSelectedText` | `wl-paste --primary --no-newline` | |
| `UI.sendDesktopNotification` | own `org.freedesktop.Notifications` server | |
| `WindowManagement.*` | **Sway IPC**: windows = `get_tree` leaves (`con_id` as id, `app_id`/`window_properties.class`, `rect`), workspaces = `get_workspaces` (`num`, `output` → `monitorId`), screens = `get_outputs` (`make`, `model`, `serial`, `rect`, `current_mode`); `focus` = `[con_id=N] focus` | fixes Vicinae's Wayland gap (`vicinae-research.md:62`) |
| `Clipboard` | own store fed by `wl-paste --watch` (BRIEF §3.4); `concealed`/`x-kde-passwordManagerHint` → not indexed; `paste` = copy (input server off) or `wtype -M ctrl v` if Tom later allows injection | Tom's prefs: 86400 eviction, ignorePasswords, preserveTagged |
| `Storage` | `$XDG_DATA_HOME/gpuix-shell/storage/<extId>.json`, atomic writes | |
| `Cache` | unchanged TS (`TS/cache.ts`) under `support/<extId>/` | |
| `FileSearch` | `plocate`/`fd`-backed or own index over Tom's `indexingPaths` (~/Downloads, ~/Documents) | gap G6 |
| `OAuth` | PKCE with redirect `gpuix-shell://oauth` or loopback `http://127.0.0.1:<port>/`; tokens in the libsecret keyring | Raycast's redirect URIs point at raycast.com, so Raycast extensions with hard-coded providers need a proxy (G9) |
| `BrowserExtension` | own native host `com.vicinae.vicinae` (§4.6) | P0 (T14) |
| `AI` | `utility` slot, the resident text model on `strix:8731` (OpenAI-compatible; send the exact served id, `DF/AGENTS.md`) | N; `canAccess(AI)` true only when reachable |
| `interval` commands, script `refreshTime` | **off** by default; refresh while visible only | Tom 2026-09-30 scheduled-work rule (REPORTED) |
| `environment.appearance` | `light` iff `~/.config/theme` → claude-light | Vicinae hard-codes dark (`EM/worker.tsx:92-94`) |
| Icons | ids from `TS/icon.ts`; glyphs from `V/src/server/icons/*.svg` (license check, G11) or an Anthropicons/Nerd Font map with a fallback glyph | |

### 4.6 CLI, socket and deeplink design for gpuix-shell (INFERRED)

- **Socket**: `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` (BRIEF §3.2) speaks **the same framing as
  Vicinae**: a 4-byte native-endian length, then JSON-RPC 2.0 with methods `Ipc/<fn>` and the
  `ipc.fig` request shapes. `herdr-picker`'s `vicinae_menu()` then needs only a path change. Fix the
  upstream bug: key pending replies by **(connection, id)**.
- **Verbs**, mirroring §3.6: `toggle [-q]`, `open [-q]`, `close`, `cmd ls [--json]`,
  `cmd launch <provider:entrypoint> [args…] [--cwd] [-q]`, `dmenu` (all 13 flags, data/index output,
  exit 1 on empty), `deeplink <url>`, `state open` (exit 0 when open), `script check|template`,
  `config default`, `ping`, `version`, `fs query`, `app launch`. Plus the surfaces from BRIEF §3.2
  (`rail`, `notifications`, `launcher`, `switcher`, `controls`, `files`, `power`, `ask`). `theme set`
  is dropped.
- **Deeplinks**: accept the `gpuix-shell://` scheme with Vicinae's grammar (§3.9): `toggle`, `open`,
  `close`, `launch/<provider>[/<entrypoint>]?arguments=&fallbackText=&toggle=`, `pop_current`,
  `pop_to_root`, `oauth`. **Do not register `x-scheme-handler/vicinae|raycast`** while Vicinae is
  installed. With `programs.gpuixShell` exclusive of `programs.vicinae` (BRIEF §2), registering
  `raycast`/`com.raycast` becomes possible for OAuth and the Raycast deeplinks (G9).
- **Chrome tabs (P0, T14)**: ship a Bun native host and a declarative manifest at
  `~/.config/google-chrome/NativeMessagingHosts/com.vicinae.vicinae.json` with
  `allowed_origins: ["chrome-extension://kcmipingpfbohfjckomimmahknoddnke/"]`. The **already
  published** Vicinae Chrome extension then talks to gpuix-shell unchanged: `browser/init` →
  reply `{id, result}`; `browser/tabs-changed` → update the store; send `browser/focus-tab` /
  `browser/close-tab`. Tab selection must also focus Sway workspace 10 (`[app_id=google-chrome]`),
  because Chrome's `windows.update(focused)` doesn't move Sway focus across workspaces (REPORTED
  risk `vicinae-research.md:100`). The HM manifest path collides with `home/vicinae.nix:98-99`, so
  the module **must assert** that the two are exclusive.
- **Sway binds** (BRIEF: Sway calls the CLI): `$mod+d`/`$mod+space` → `gpuix-shell toggle`;
  `$mod+v` → `gpuix-shell cmd launch clipboard:history`. Volume and brightness stay
  `keypress → sway → script` (T10); the OSD only displays.

### 4.7 Porting recipe for a Raycast/Vicinae extension (INFERRED)

1. **Build**: reuse `vici build` semantics (esbuild cjs, externals `react`, `react/jsx-runtime`,
   `@vicinae/api`, `@raycast/api`; copy `package.json` and `assets/`), or take the outputs of
   `mkVicinaeExtension` / `mkRayCastExtension` unchanged.
2. **Install**: `programs.gpuixShell.extensions = [ drv … ]` → `xdg.dataFile."gpuix-shell/extensions/${drv.name}"`.
   The id is the dir name, the provider id is `@<author>/<dir>`, and each command is `<dir>/<name>.js`.
3. **Run**: the worker patches `require` (`EM/patch-require.ts:54-68`). `react`, `react/jsx-runtime`
   and `react-reconciler` get the shell's copies (React 19.2 in gpuix-shell vs 19.1.1 in
   `@vicinae/api`'s package.json, G10). `@vicinae/api` and `@raycast/api` resolve to
   `@gpuix-shell/api`. Unknown Raycast symbols resolve to a stub that throws
   "'X' from @raycast/api is not supported by gpuix-shell" (`RC/unsupported.ts`). `@raycast/utils`
   is bundled into the extension, so it works as far as its `@raycast/api` calls resolve
   (INFERRED, not tested).
4. **Preferences**: from `programs.gpuixShell.settings.providers.<id>.preferences`, with password
   preferences kept in an override file outside git (the `settingOverrides` pattern; "No secrets in git").
5. **Conformance**: run the 23 boilerplate commands (`V/extra/extension-boilerplate/src/*`) as the
   acceptance suite, especially `torture.tsx`, `action-panel-stress.tsx`, `paginated-*`,
   `controlled-list`, `nested-form`, `browser.tsx` and `window-switcher.tsx`. Then port the Raycast
   **Navidrome** extension (`raycast/extensions` at c33bf4cb, BRIEF §5) as a second route alongside
   the native music feature.

### 4.8 Compatibility matrix

✓ works · ◐ partial · S stub/throws · ✗ absent. "gpuix target" is the proposed v1. P-tiers are INFERRED except where T14 or T18 apply.
The Vicinae column is MEASURED from source. The **Raycast column is INFERRED** from the shape of
`RC/*` and general knowledge of `@raycast/api`; I did not check it against Raycast's own `.d.ts`.

| Surface | Raycast | Vicinae 0.29.1-18 | gpuix target | Tier / note |
|---|---|---|---|---|
| List (+Section, Item, accessories, EmptyView, Dropdown, pagination, throttle) | ✓ | ✓ | ✓ | P0 (T14) |
| List.Item.Detail + Metadata | ✓ | ✓ | ✓ | P1 |
| Grid (+Section, Item, Fit, Inset, ItemSize) | ✓ | ✓ (no `isShowingDetail` in Props) | ✓ | P1 (T18 covers) |
| Detail + Metadata (Label, Link, TagList, Separator) | ✓ | ✓ | ✓ | P0 |
| Form: TextField, PasswordField, TextArea, Checkbox, Dropdown, Description, Separator, LinkAccessory | ✓ | ✓ | ✓ | P1 |
| Form: DatePicker, TagPicker, FilePicker | ✓ | ✓ | ◐ (date widget gap; file picker → portal or files) | P2 |
| Form item `ref.focus()/reset()` | ✓ | S (no-op) | ✓ | P2 |
| Form `enableDrafts` / `LaunchProps.draftValues` | ✓ | ◐ (prop passed; persistence untraced) | ✓ (per-command storage) | P3 |
| ActionPanel, Section, Submenu | ✓ | ◐ (submenu filtering/loading props hidden) | ✓ | P0 |
| Action core: CopyToClipboard, Paste, Push, Open, OpenInBrowser, OpenWith, ShowInFinder, SubmitForm, RunInTerminal | ✓ | ✓ (Copy ignores `icon`; Paste → copy without input server) | ✓ | P0 |
| Action.Trash | ✓ (to Trash) | ◐ (**permanent `rm -r`**) | ✓ (`gio trash`) | P1 safety |
| Action.CreateQuicklink | ✓ | ✓ | ◐ (quicklink store) | P2 |
| Action.PickDate, ToggleQuickLook, CreateSnippet | ✓ | S (null) | ◐ later | P3 |
| MenuBarExtra / `mode: menu-bar` | ✓ (macOS) | S / filtered | ✗ (rail candidate) | — |
| useNavigation | ✓ | ✓ | ✓ | P0 |
| showToast / Toast (style, title updates) | ✓ | ✓ | ✓ | P0 |
| Toast primary/secondary actions | ✓ | ✗ (commented out) | ✓ | P1 |
| showHUD, closeMainWindow, popToRoot, clearSearchBar, PopToRootType | ✓ | ✓ | ✓ | P0 |
| getSelectedText | ✓ | ✓ | ✓ (primary selection) | P2 |
| confirmAlert / Alert | ✓ | ◐ (icon dropped, rememberUserChoice off) | ✓ | P1 |
| Clipboard copy, read, readText, clear | ✓ | ✓ (read offset ✗) | ✓ | P0 |
| Clipboard.paste | ✓ | ◐ (needs input server; Tom's is off) | ◐ copy fallback | P1 |
| LocalStorage | ✓ | ✓ | ✓ | P0 |
| Cache | ✓ | ✓ (pure TS) | ✓ (verbatim) | P0 |
| getPreferenceValues, open*Preferences, preference types (+appPicker multiple) | ✓ | ✓ | ✓ (Nix-declared + settings view) | P1 |
| environment (+canAccess) | ✓ | ◐ (appearance always dark) | ✓ | P1 |
| LaunchProps: arguments, launchContext, fallbackText, cwd | ✓ (no cwd) | ✓ | ✓ | P0 |
| launchCommand (intra/inter) | ✓ | ✓ | ✓ | P1 |
| updateCommandMetadata | ✓ | ✓ | ✓ | P2 |
| AI.ask, getModels | ✓ (Pro) | S (throws) | ◐ local `utility` model | P3, N |
| OAuth.PKCEClient | ✓ | ✓ (raycast redirect + scheme handler) | ◐ (own redirect; G9) | P3 |
| BrowserExtension.getTabs (+focus/close) | ✓ | ✓ | ✓ (same Chrome extension) | **P0 (T14)** |
| BrowserExtension.getContent | ✓ | S | ✗ (needs extension change) | P3 |
| FileSearch.search | ✗ (Vicinae-only) | ✓ | ◐ | P2 |
| WindowManagement | ✓ (macOS) | ◐ (generic Wayland: no Sway workspaces) | ✓ (Sway IPC) | P1 |
| Wallpaper.set | ✗ (Raycast has no such API; Vicinae-only) | ✓ | ✗ (black solid) | D |
| open, getApplications, getDefaultApplication, getFrontmostApplication, showInFileBrowser | ✓ | ✓ | ✓ | P0 |
| runInTerminal, sendDesktopNotification | ✗ (Vicinae-only) | ✓ | ✓ | P1 |
| getSelectedFinderItems | ✓ | S (throws) | ◐ (from the files surface) | P3 |
| captureException | ✓ | ◐ (console.error) | ◐ (journal) | — |
| Icon ids, Color, Image (mask, tint, themed, fileIcon), Keyboard | ✓ | ✓ | ✓ (glyph set G11) | P0 |
| Legacy pre-1.0 exports (ListItem, CopyToClipboardAction, …) | ✓ | ✓ (`RC/legacy.ts`) | ✓ (copy) | P2 |
| `@raycast/utils` (bundled by the extension) | ✓ | ◐ INFERRED | ◐ INFERRED | P1 test |
| Manifest arguments (≤3), preferences | ✓ | ✓ | ✓ | P0 |
| `interval` background commands | ✓ | ✓ (scheduler) | ✗ default (rule) | D/gated |
| AI tools (`tools`, `ai`) | ✓ | schema only | ✗ | D |
| Script commands (`@raycast.*` and `@vicinae.*`; fullOutput, compact, silent, terminal, inline) | ✓ (`@raycast`) | ✓ | ✓ | P1 |
| Script `refreshTime` | ✓ | ◐ (parsed, never scheduled) | ◐ (while visible) | P2 |
| dmenu | ✗ | ✓ (reply-steal bug) | ✓ (fixed) | **P0 (herdr-picker)** |
| Store browse/install at runtime | ✓ | ✓ (Vicinae + Raycast stores) | ✗ (Nix only) | D (INFERRED) |
| Dev loop (`vici develop`, hot refresh deeplink) | ✓ | ✓ | ◐ later | P3 |

---

## 5. Reusable code and data, with paths

| Asset | Path | Reuse how | Caveat |
|---|---|---|---|
| Wire vocabulary (intrinsic elements and props) | `V/src/typescript/api/types/jsx.d.ts:30-244` | the `IntrinsicName`/prop types for our tree (§4.3) | — |
| Public component wrappers (serialization only) | `TS/components/{list,grid,detail,form,actions,action-pannel,dropdown,metadata,tag,empty-view,pagination,menu-bar}.tsx` (~2.0 k lines) | port as-is into `@gpuix-shell/api`; fix `Action.Trash`, the CopyToClipboard icon, Dropdown.Item keywords | ISC-declared package inside a GPL repo (G11) |
| Hooks | `TS/hooks/use-event-counted.ts`, `use-navigation.ts` | verbatim | — |
| Non-UI API shims | `TS/{toast,controls,clipboard,local-storage,preference,command,alert,browser,environment,file-search,window-management,utils,keyboard,image,color,oauth}.ts` | re-point `getClient()` at `HostServices` | `AI`, `wallpaper` excluded |
| `Cache` | `TS/cache.ts` (353 lines) | verbatim | needs `environment.supportPath` |
| Icon id enum | `TS/icon.ts` (855 lines) + `V/src/server/icons/*.svg` (854) | ids verbatim; SVGs after a license check | G11 |
| Manifest zod schema | `V/src/typescript/api/src/schemas/manifest.ts` (584 lines) | validate extension `package.json` at install/build (`gpuix-shell ext lint`) | zod 4 |
| JSON schema for package.json | `V/extra/schemas/extension.json` | editor help, Nix check | — |
| Reconciler + callback manager + navigation provider + loaders | `EM/reconciler.ts` (443), `EM/callback.ts`, `EM/navigation-provider.tsx`, `EM/loaders/*` | port for in-process and Bun Worker placements | react-reconciler version must match React 19.2 |
| Require patch / Raycast proxy | `EM/patch-require.ts`, `RC/{index,unsupported,legacy,clipboard,browser,system,window-management}.ts` | port; rename the error string | — |
| Raycast legacy aliases | `RC/legacy.ts` | verbatim | — |
| figura protocol specs | `V/figura/{ipc,tsapi,manager,manager-extension}.fig` | the spec for `shell.sock` (§4.6) and the worker RPC | per-connection reply routing (fix) |
| Socket framing reference client | `DF/home/dot_local/bin/herdr-picker:211-258` | conformance test for `shell.sock` | — |
| CLI verb list + flags | `V/src/cli/src/{cli.cpp,server.cpp,theme.cpp,config.hpp,state.hpp,script.hpp,fs.cpp}` | mirror in `gpuix-shell` argv parsing; `bun test` the usage strings | — |
| Script-command parser + 7 test suites | `V/src/lib/script-command/{src/script-command.cpp,tests/*.cpp}` | port to TS; turn the C++ tests (argument-validation, comment-styles, edge-cases, fields, shebang, time-parsing, failure; ~1.2 k lines) into `bun test` fixtures | — |
| Script mode semantics | `SV/script/script-actions.cpp:55-150`, ANSI tokenizer `SV/script/script-output-tokenizer.cpp` | port | — |
| Default config with comments | `V/extra/config.jsonc` | document our settings; same key names where applicable | — |
| Config struct (hidden keys) | `SV/config/config.hpp:19-420` | — | — |
| Deeplink router | `SV/ipc/ipc-command-handler.cpp:33-312` | grammar for `gpuix-shell://` | — |
| Browser native protocol | `V/src/browser-extension/chrome/background.js`, `V/src/browser-extension/src/browser.cpp` | write the Bun native host against it | Chrome extension id fixed |
| Native host manifest set | `SV/services/browser-extension/native-host-installer.cpp:30-247` | browser → path table for the Nix module | Tom only needs google-chrome |
| Extension sample suite | `V/extra/extension-boilerplate/src/*.tsx` (23 commands) | conformance suite (§4.7) | — |
| Nix builders | `V/nix/mkVicinaeExtension.nix`, `V/nix/mkRayCastExtension.nix` | use directly from the flake input or vendor them | the input pin is v0.29.1 |
| HM module pattern | `V/nix/home-manager-module.nix:272-357` | `VICINAE_OVERRIDES`-style override layer, extension dataFiles, unit | — |
| Tom's palette → Vicinae slot mapping | `DF/home/themes/default.nix:140-175` | `Color.*` and selection mapping (§4.1) | — |
| Prior provider list and parity-gap list | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/providers.ts:33-76` | first-party root items (20 commands) + honest gap strings | — |

---

## 6. Gaps

- **G1 (live verification):** nothing here was run against a live Vicinae. Each runtime behaviour
  was read from source; none was observed. The research doc's isolated smoke test is the only
  REPORTED runtime evidence (`vicinae-research.md:144-148`; `client-sway-vicinae.md:282-288`).
- **G2 (version skew):** Tom runs v0.29.1. The clone is v0.29.1-18. I did not diff them. The
  mute-tab change is known (`vicinae-research.md:100`); others may touch the API.
- **G3 (draft persistence):** I did not trace where `enableDrafts` values are stored, or whether
  `draftValues` is ever filled. The server-side form model is `SV/extension/views/extension-form-model.cpp`.
- **G4 (Chrome extension state):** unknown whether the `kcmipingpfbohfjckomimmahknoddnke` extension
  is installed in Tom's Chrome on the Zenbook. The research doc says installation is separate and
  suggests a system external-extension JSON (`vicinae-research.md:98`). Without it, T14 parity
  fails regardless of the host.
- **G5 (Sway focus for tabs):** `browser/focus-tab` focuses Chrome's window, but whether Sway follows
  across workspaces is untested (REPORTED risk). The design adds an explicit Sway focus.
- **G6 (file index):** Vicinae's file indexer (`V/src/file-indexer`, `figura/file-indexer.fig`) is
  reader 35's scope. `FileSearch` and `fs query` parity need an index decision (plocate, fd or own).
- **G7 (selected text and paste):** Tom disabled the input server, so `Clipboard.paste` and
  `Action.Paste` degrade to copy. Whether Tom wants `wtype`-style injection later is undecided
  (`client-sway-vicinae.md:295` lists "Clipboard paste polish" as a parked issue).
- **G8 (background work):** Vicinae's `interval` scheduler and script `refreshTime` conflict with the
  spirit of "No scheduled agent work is declared in dotfiles" (REPORTED rule, 2026-09-30). My
  default is off and refresh-while-visible only. Tom has not ruled on in-app timers.
- **G9 (OAuth and URL schemes):** Raycast extensions use Raycast's redirect URIs. Vicinae handles
  them by registering `raycast://`/`com.raycast:`. gpuix-shell can do that only when Vicinae is
  uninstalled. The "Web" method returns to `raycast.com/redirect`, which needs Raycast's server.
  Untested.
- **G10 (React versions):** `@vicinae/api` pins React 19.1.1 and `@types/react` 19.1.17. The shell
  pins React 19.2.0 (BRIEF toolchain). Extensions treat react as external, so the shell's copy wins.
  Reconciler API drift between 19.1 and 19.2 is unchecked.
- **G11 (licensing):** the repo root is GPL-3.0, the TS packages say ISC, and `src/server/LICENSE`
  is BSD-style. Copying component wrappers or icon SVGs into Tom's private dotfiles is fine for
  private use (INFERRED). Check before any public release. The Anthropic fonts already keep this
  branch private (BRIEF §1).
- **G12 (window corners):** Tom's Vicinae has `rounding = 0` (`vicinae.nix:51`, no quote). The
  design kit says the launcher's outer radius is 16 (`wave1/11:197`) with a square-outer X1 option.
  This is unresolved; Tom has not ruled.
- **G13 (toast position):** T5 (2026-10-11, mako) says "top and center not top right", but BRIEF
  §3.3 places toasts top-right. This affects `showToast` placement. Newest-wins would take BRIEF,
  but BRIEF is the orchestrator's assumption, not a Tom quote. Record in ASSUMPTIONS.md.
- **G14 (builtin parity list):** this note does not enumerate builtins: clipboard, files,
  calculator, media, tray, emoji, snippets, shortcuts, power, system, screenshots, fonts, theme,
  wm, developer. Reader 35 does. The P0 bar is T14 "feature parity at least with vicinae".
- **G15 (store):** I recommend no runtime store (Nix-only installs, for reproducibility and the
  Wi-Fi Commander shell-injection finding in `vicinae-research.md:134`). Tom has not ruled. A
  read-only "browse Raycast store" view could come later.
- **G16 (`@raycast/utils`):** INFERRED to work because it is bundled per extension, but hooks such as
  `useForm` depend on `ref.focus()` (a no-op upstream) and `useCachedPromise` depends on `Cache`.
  Test with a real extension.
- **G17 (dmenu exit and empty semantics):** Vicinae exits 1 on an empty selection. herdr-picker
  tolerates that. Our implementation must keep the exit code, the "Pass search text" free-text
  path, and `{count}` in section titles.

### What I did / could not do

Done (MEASURED): read BRIEF.md fully. Read every `@vicinae/api` source file (components, hooks,
toast, controls, clipboard, storage, preferences, command, AI, alert, browser, environment, file
search, wallpaper, window management, utils, keyboard, image, color, cache and OAuth signatures),
the manifest zod schema, the `vici` CLI, the extension-manager (`patch-require`, worker, loaders,
reconciler, callback, navigation), the Raycast compat package, all four figura specs, the whole CLI,
the script-command library and server modes, the config sources, the deeplink router, the store and
registry services, the browser extension and native host, and all three Nix files. Then read every
Vicinae touchpoint in this worktree and verified Tom's quotes T1, T2, T6, T10, T11–T13 and T14
against their source files and transcripts.

Not done: no build, no run, no test. No live Vicinae, Sway or Chrome inspection. No diff from
v0.29.1 to HEAD. Server-side QML rendering details (exact paddings and row heights) were not read;
reader 35 or the design kit cover the look. Nothing outside this file was written.
