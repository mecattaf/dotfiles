# 15 — GPUIX 0.11.0 API reference for the gpuix-shell builders

Reader 15 of the overnight gpuix-shell build (Claude Opus 5.5 subagent), written 2026-10-21 ~12:15 CEST.
Read this file instead of `index.d.ts`. Every claim carries a label:

- **MEASURED**: run on this machine, on the published 0.11.0 Linux binary, under
  `runtime-test --render-node /dev/dri/renderD128` and a private headless Sway 1.12. Evidence IDs P1..P7 are listed in §5.4.
- **REPORTED**: the d.ts doc comment, README, or CHANGELOG says so. Not run here.
- **INFERRED**: read from the Rust/TS source, not run.

Path legend (all relative paths are relative to the worktree `/home/tom/.wt/dotfiles/gpuix-shell`):

| Short | Absolute path | What |
|---|---|---|
| `NM/` | `pkgs/gpuix-shell/node_modules/@gpuix/` | the installed 0.11.0 packages. MEASURED byte-identical (`diff -r`) to the npm tarballs `@gpuix/native@0.11.0`, `@gpuix/react@0.11.0` |
| `D.TS` | `NM/native/index.d.ts` (804 lines) | the napi surface: `GpuixRenderer`, `TestGpuixRenderer`, `WindowOptions`, `LayerShellOptions`, `EventPayload` |
| `HOST` | `NM/native/dist/host.d.ts` (587 lines) | `StyleDesc`, `HostProps`, element props, `GpuixTheme`, `NativeRenderer`, `KeyEvent` |
| `RX/` | `NM/react/dist/` | `@gpuix/react` build output (`index.d.ts`, `reconciler/renderer.d.ts`, `components/*.d.ts`) |
| `UP/` | `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/gpuix011/upstream/` | upstream checkout at the **0.11.0 release commit `2e31b47`** (2026-10-20 15:20 +0200). Session scratch: if it is gone, use `git -C /home/tom/Downloads/gpuix show 2e31b47:<path>` (the clone has the object; its HEAD `515df19` is 17 commits older) |
| `ZED/` | `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/gpuix011/zed/` | the GPUI fork `remorses/zed` at submodule pin `f77e5cfe` (2026-10-20). `/home/tom/Downloads/gpuix/zed/` is an **empty** submodule dir |
| `PROBE/` | `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/gpuix011/` | probe scripts, logs, screenshots (§5.4) |

---

## 1. What this source is

- **`@gpuix/native` 0.11.0** is a napi-rs addon (`gpuix-native.linux-x64-gnu.node`, 52,449,896 bytes, MEASURED `ls`) over a
  fork of Zed's GPUI. Linux target `x86_64-unknown-linux-gnu`, renderer Vulkan via wgpu (REPORTED `UP/CHANGELOG.md:670`).
  It also ships the framework-neutral JS runtime as subpath exports: `./host`, `./testing`, `./automation`, `./runtime`,
  `./idle-gc`, `./cpu-throttle` (`NM/native/package.json` `exports`).
- **`@gpuix/react` 0.11.0** is a React 19 reconciler (`react-reconciler ^0.33.0`, peer `react ^19.2.0`). Subpath exports:
  `.`, `./jsx-runtime`, `./jsx-dev-runtime`, `./testing`, `./select`, `./combobox`, `./button`, `./dialog`, `./tooltip`,
  `./floating`, `./automation` (`NM/react/package.json`). JSX via `"jsxImportSource": "@gpuix/react"` (already set in
  `pkgs/gpuix-shell/tsconfig.json`). There is no separate React README; the documentation is `UP/README.md` (4046 lines).
- **0.11.0 vs the clone**: `diff /home/tom/Downloads/gpuix/packages/native/index.d.ts NM/native/index.d.ts` shows only two
  additions: `isTerminal()` (`D.TS:675`) and `WindowOptions.terminal` (`D.TS:798`). `registerFont` (`D.TS:178`) was already in
  the clone's source but first ships in a published binary with 0.11.0 (CHANGELOG 0.11 item 9). MEASURED.
- **How it runs on Linux** (INFERRED from `UP/packages/native/src/renderer.rs:1364-1484`): every `GpuixRenderer.init()`
  spawns its own Rust thread named `gpuix-ui` that creates **its own GPUI `Application`** (own Wayland connection, own
  text system, `QuitMode::LastWindowClosed`) and opens **exactly one window**. JS talks to it by
  `applyBatch(json)` (one mutex, one FFI call per React commit) and by an unbounded command channel (`UiCommand`,
  `renderer.rs:436-520`). Events come back through the napi threadsafe callback passed to `new GpuixRenderer(cb)`.
  On Linux `tick()` does no pumping; it only reports whether the UI thread is still inside `Platform::run`
  (`renderer.rs:1532-1560`).
- **Layer shell is older than the BRIEF says.** `WindowOptions.layerShell` landed in **0.8.0** (CHANGELOG `UP/CHANGELOG.md:396-414`,
  commit `bbaa202`, 2026-09-10), not 0.10.0. REPORTED.
- The only other GPUIX docs: `UP/docs/{custom-elements-plan,native-test-renderer-plan,native-text-components-plan,serialization-benchmark,terminal-renderer,visual-screenshot-plan}.md`
  (design plans, not API) and `UP/website/src/guides/{hermes,solid}.mdx` (Hermes runtime packaging and the Solid adapter; not
  used by the React shell).

## 2. Tom's rulings that bind the GPUIX layer (verbatim)

| When | Verbatim | Source | Consequence for API use |
|---|---|---|---|
| 2026-10-13 23:04:11 (Codex rollout time) | "revisit the chromium aura entire epoch historiically, and understandh how it will now be done on hyprland ; and https://gpuix.dev/ https://github.com/remorses/gpuix https://gpui-kit.com/docs/comparison/" | `wave1/03-transcript-codex-desktop-shell-builds.md:71` | origin of the GPUIX direction |
| 2026-10-13 23:06:46 | "this supersedes the whole aura requirement. it even fucking correesponds to the solidjsidea i had!!!" | `wave1/03...md:72` | GPUIX replaces Aura/Views (React chosen tonight, BRIEF §3.1) |
| 2026-10-13 23:21:38Z | "i m not intersted in 'native advantage' . performance is not really the thing i m looking for here. 'supplies another renderer' is fine for something that' react plus generic compositor functionlaity... vicinae (raycast clone) proves this theoretically ; we hae the sway ipc and omarchy's quickshell which you investigated a while back did exactly that." | `wave1/14-gpuix-sway-proof-and-openui-adapter.md:117-120`, `wave1/02...md:120` | cold-start latency and RSS (§4) are not adoption gates; correctness and coverage are |
| 2026-10-13 23:45:17Z | "one quick note on gpuix that is unfortunate is that it's not registering ctrl +\- for zooming ; was that explicitly disabled or what?" | `wave1/14...md:126-127` | GPUIX has **no zoom API** (no rem/scale setter in `D.TS`). The shell must implement Ctrl+= / Ctrl+- / Ctrl+0 itself (recipe §5.2 G) |
| 2026-10-14 00:33:25 | "one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status indicators. only for the top display" | `wave1/03...md:81` | needs output pinning, which GPUIX does not expose (§3.16) |
| 2026-10-14T13:37:43Z | "the major breakthrough is the recent gpuix react products plus terminal that can be \"mirrored to a front end\"" | `wave1/04-transcript-cc-look-pivot.md:188` | 0.11's `terminal: true` (kitty graphics) is a second GPUIX head worth knowing (§3.1) |
| file `~/tuesday-oct20/desktop-ui.md`, mtime 2026-10-20 10:45 CEST | "the GPUIX project was analyzed in the past and i found that it was the best possible tool to base my project on when it comes to building front-ends. it would make us completely agnostic to building native linux wayland (thomas); macos (marwan); AND web (frank). the only boundary being of course the desktop shell, which would be exclusive to wayland-on-sway wm." | `/home/tom/tuesday-oct20/desktop-ui.md:5-8` | layer-shell code paths are Linux-only by design; everything else should stay portable GPUIX |
| 2026-10-20 ~23:05 CEST | "make sure that the work you do will set the foundation for my subsequent work on achieving the world's most complete linux desktop shell without using quickshell. gpuix as the frontend all the way is desired." | BRIEF §1 | no Chrome/web fallback for shell surfaces; gaps below need GPUIX patches, not another toolkit |
| 2026-10-20 ~23:20 CEST | "a full implementation of the linux wayland sway facing https://github.com/vicinaehq/vicinae ... would be impressive to see. gpuix for the win." | BRIEF §5 | launcher surface needs keyboard-exclusive overlay + fast show (§3.3, §4) |
| 2026-10-20 | "keeping the anthropic font that i have ... is important." | BRIEF §1 | `fontFamily: "Anthropic Sans"` works; **bold does not** without a workaround (§3.8) |
| standing (BRIEF §1) | "functionality pull from quickshell NOT visuals"; flat and opaque, hairlines not shadows, no blur, wallpaper `#000000` | BRIEF §1 | use `windowBackground: "opaque"` except where rounded corners need alpha (§3.2); never `"blurred"` |

## 3. Feature / behaviour inventory

Column 4 vocabulary for an API: **keep** = use as shipped; **replace** = do not rely on it, the shell does it another way;
**new** = missing, needs shell-side code or an upstream/forked GPUIX patch.

### 3.1 Entry points and lifecycle

| Feature | What exactly | Where it lives today | K/R/N | Notes |
|---|---|---|---|---|
| `render(node, options?)` | Creates one `GpuixRenderer`, `init(windowOptions)`, mounts a concurrent React root, starts the frame loop, returns `Root`. **Process singleton** stored on `globalThis.__gpuixRenderHost`: a second `render()` call only remounts React on the same window and ignores new window options. When its window closes, `process.exit(0)` | `RX/reconciler/renderer.d.ts` (`render`, `RenderOptions`); source `UP/packages/react/src/reconciler/renderer.ts:365-426` | keep (one per process, for the primary surface) | INFERRED from source; MEASURED working with layer shell (rail-probe, P5, P7) |
| `RenderOptions` | `WindowOptions` + `onEvent`, `renderer` (inject an existing renderer: then **no init and no frame loop** are done for you), `debugFrameOverlay`, window key handlers `onKeyDown`, `onKeyUp`, `onSelectionChange`, `tabNavigation`, `keyboardFocusDim` | `renderer.ts:346-351`, `HOST:559-578` | keep | |
| Runtime error overlay | `render()` installs process-wide `uncaughtException`/`unhandledRejection` handlers that keep the process alive and replace the tree with a red "Uncaught runtime errors" overlay + Reload button (`#e83b46`, 32 px) | `renderer.ts:22-56, 167-334` | replace for daemons | A rail stuck on a red overlay is worse than a crash+`Restart=on-failure`. Add your own `process.on('uncaughtException', () => process.exit(1))` **after** `render()`, or use the custom host (§5.2 A). INFERRED |
| `resetRender()` | stops the loop, unmounts, drops the singleton | `renderer.ts:353-362` | keep (tests) | does not close the native window (§3.4) |
| `createRenderer(onEvent?)` | `new GpuixRenderer(cb)` wired to the shared event dispatcher (`createNativeRenderer`) | `RX/reconciler/renderer.d.ts`, `UP/packages/native/js/runtime.ts:25-48` | keep (2nd..nth surface in a process) | **auto-enables stdio automation when `process.stdin` is not a TTY** (`runtime.ts:40-46`), i.e. under systemd (`/dev/null`) and under `launch()` (pipe). Harmless with `/dev/null`; never give a GUI process a stdin pipe you do not control |
| `createRoot(renderer, handlers?)` | React root on an initialized renderer. **One root per renderer**; throws if one is mounted | `RX/reconciler/index.d.ts`; README "One renderer drives one root" `UP/README.md:798-802` | keep | MEASURED P5: second root on a second renderer works |
| `startFrameLoop(renderer, {frameMs?, onTerminated?})` | Linux: `setTimeout` poll of `tick()` every `frameMs` (default **8 ms**); calls `onTerminated` once `tick()` returns false (window closed) | `UP/packages/native/js/runtime.ts:13, 50-95` | keep, with `frameMs` ≥ 100 for daemons | On Linux frames are **not** driven by this loop (GPUI renders on its own thread); the poll only detects termination. `render()` hard-codes 8 ms = 125 JS wakeups/s forever. MEASURED P5: `frameMs: 250` on a second window renders and updates normally |
| `setFrameWakeCallback` | macOS display-link wake; returns **false** on Linux | `D.TS:71` | ignore | MEASURED P1 probe.out |
| `flushSync(fn)` | forces React commit down to one `applyBatch`; paint is still next frame | `RX/index.d.ts:1`, README `UP/README.md:1081-1100` | keep | |
| `createPortal(children, target)` | mount children under an already-mounted host element (toast layer, drag preview) | `RX/reconciler/portal.d.ts` | keep | same window only |
| `isTerminal()` / `WindowOptions.terminal` / `GPUIX_TERMINAL=1` | render the app **inside a kitty-graphics terminal** (kitty, Ghostty) instead of a window; shm frames locally, zlib inline over SSH; ctrl-c quits | `D.TS:675, 798`; `UP/CHANGELOG.md:5-11`; `UP/docs/terminal-renderer.md` | new option (not for shell surfaces) | Linux path uses `WgpuRenderer::new_offscreen` + cosmic-text; doc says "no app ran there yet" on Linux (`terminal-renderer.md:198`). Possible later use: Pinax file explorer or `gpuix-shell ask` inside a herdr kitty pane. UNVERIFIED on Linux |
| `GpuixContext`, `useGpuix()`, `useGpuixRequired()` | the renderer of the root this component is in | `RX/hooks/use-gpuix.d.ts` | keep | MEASURED P5: each root sees its own renderer (`getWindowSize` 120x800 vs 360x120) |
| `collectGarbageWhenIdle(opts?)` | one `Bun.gc(true)` after 2 quiet 5 s checks under 0.5 core | `NM/native/dist/idle-gc.d.ts:1-35` | keep for daemons (rail, notifications) | REPORTED |
| `checkUpdate` / `AvailableUpdate` | signed self-update feed | `D.TS:12-33, 459-475` | replace (Nix) | never call |

### 3.2 `WindowOptions` (`D.TS:746-799`) on Linux

| Field | What exactly | Linux behaviour | K/R/N | Notes |
|---|---|---|---|---|
| `title` | window title (default `"GPUIX"`) | xdg toplevel title; meaningless on a layer surface | keep for `files` window | `setWindowTitle()` changes it later |
| `appName` | macOS menu text | ignored | — | |
| `width`, `height` | initial logical size (default 800x600) | on a layer surface: the requested size; **0 on an anchored-both-edges axis = stretch** (§3.3) | keep | MEASURED P2/P7 |
| `minWidth`, `minHeight`, `resizable`, `fullscreen` | normal-window constraints | toplevel only | keep for `files` | |
| `transparent` / `windowBackground` | `"opaque"` (default) / `"transparent"` / `"blurred"` | `"transparent"` gives a real alpha surface on Sway: MEASURED P7, a 420x220 overlay with root `borderRadius: 24` shows the `#202020` wallpaper in its corners (`p7.../auto-grim.png`). `"blurred"` = macOS vibrancy / KDE blur; nothing on stock Sway | keep `"opaque"` for rail; `"transparent"` only for rounded overlays (launcher, toasts, OSD) | BRIEF: flat, no blur |
| `titlebarTransparent`, `trafficLightX/Y` | macOS chrome | ignored | — | |
| `focus` | take key focus on open | d.ts: "Ignored on Linux"; code still skips `cx.activate()` when false (`renderer.rs:1375`) | ignore | layer-surface keyboard focus is decided by `keyboardInteractivity` |
| `show` | open hidden | **ignored on Linux** (README table `UP/README.md:975-979`) | — | there is no way to open, or later hide, a window without mapping it |
| `appId` | Wayland `app_id` / X11 `WM_CLASS` | forwarded (`renderer.rs:7659`, unit test `app_id_is_forwarded`) | keep | use `gpuix-shell-<surface>`; Sway `for_window [app_id=...]` rules apply to ordinary windows only; Sway has no layer-surface rules |
| `layerShell` | open as `zwlr_layer_shell_v1` surface | §3.3 | keep | error `"Compositor doesn't support zwlr_layer_shell_v1"` if absent (`ZED/crates/gpui/src/platform/layer_shell.rs:79-83`) |
| `terminal` | kitty-graphics head | §3.1 | — | |
| *(absent)* output / display | — | **no field**; GPUI has `display_id` but GPUIX never sets it (`renderer.rs:7618-7672`) | new | §3.16 |

### 3.3 `LayerShellOptions` (`D.TS:685-721`)

| Field | Values / default | MEASURED behaviour on Sway 1.12 | K/R/N | Notes |
|---|---|---|---|---|
| `namespace` | string, default `""`; immutable after creation | accepted; not visible in Sway IPC (layer surfaces are not in `get_tree`) | keep (`gpuix-shell-rail`, ...) | |
| `layer` | `"background"` / `"bottom"` / `"top"` (default) / `"overlay"` | `top` rail and `overlay` popups both map (P1, P2, P7) | keep | rail = `top`, launcher/switcher/OSD/toasts = `overlay` (BRIEF §3.3) |
| `anchor` | any of `top/bottom/left/right`, default `["top","left","right"]` | `["top"]` only: surface centred horizontally at the top margin (P7: x 430..849 on a 1280 output for width 420) | keep | |
| size vs anchor | d.ts says width/height "only constrain the axis the surface is not stretched along" | **Wrong on Sway.** With `anchor: left/top/bottom` and `height: 100` the surface stays 56x100 and is **centred** (P7 red bbox y 350..449). With `height: 0` it stretches to 56x800 (P2, P7 `stretch0`). `getWindowSize()` reads `56x0` right after `init()` and `56x800` once configured | keep, pass **0** on every axis you want stretched | wlr-layer-shell protocol semantics: non-zero size + opposite anchors = centred |
| `exclusiveZone` | logical px; `0` = compositor decides; negative = reserve nothing | `56` → Sway workspace rect `x=56 width=1224` on 1280 (P1, P2, P7); still reserved when the surface is a centred 100 px stub (P7 `one`). `-1` on an overlay reserved nothing (P2) | keep | rail 56 (collapsed); expanding to 220 needs a **new surface** (no setter) |
| `exclusiveEdge` | one anchor name, for multi-edge anchors | not exercised | keep | INFERRED applied via `apply_exclusive_edge` (`ZED/crates/gpui_linux/src/linux/wayland/window.rs:189-191`) |
| `margin` | `[top, right, bottom, left]`, exactly 4 entries or ignored | `[108,0,0,0]` on a top-anchored overlay → y=108 (P2, P7) | keep | launcher/switcher top margin 108 (BRIEF §3.3) |
| `keyboardInteractivity` | `"none"` (default) / `"on-demand"` / `"exclusive"` | `"exclusive"` overlay receives typing, Enter, Escape (P3, P7) | keep | `on-demand` (rail) UNVERIFIED |
| placement output | — | **the surface opens on the focused output at creation time** (P2: same app opened on HEADLESS-1 or HEADLESS-2 depending on `swaymsg focus output`) | new | §3.16 |
| after creation | — | no API to resize, re-anchor, change layer/keyboard mode, set an input region, unmap or close | new | §6 |

### 3.4 Several windows / layer surfaces per process

| Feature | What exactly | Where | K/R/N | Notes |
|---|---|---|---|---|
| windows per renderer | exactly **one** | `renderer.rs:1427-1452` | keep | README Status lists "[ ] Multiple windows" (`UP/README.md:4033`): that means one renderer cannot open a second window |
| renderers per process | **several work** | MEASURED P1 (`two`: 56 px `top` rail + 300x200 transparent `overlay`, both alive after 2.5 s, rail exclusive zone applied), P2 (`stretch0`: stretched rail + overlay), P5 (two React roots: `render()` rail 120 px + `createRenderer()`/`createRoot()` toast 360x120 top-right, both painted, both updating every 250 ms, each `useGpuixRequired().getWindowSize()` correct) | keep, with care | each renderer = own GPUI `Application` on its own `gpuix-ui` thread with its own Wayland connection (INFERRED). GPUI was written for one app per process: long-run stability of two apps in one process is **UNVERIFIED** (probes lived 4-6 s) |
| memory | RSS | MEASURED: one renderer 148.5 MiB (P7, gles2) / 199.6 MiB (P1, pixman); two renderers 163.4 MiB (P7) / 233.5 MiB (P1) | — | a second surface in the same process costs ~15-34 MiB, a second process ~150-200 MiB |
| close one window | — | **no API.** Dropping the JS renderer only drops the command sender; the UI thread and window stay (`renderer.rs:3627-3641`, `555-560`). `root.unmount()` empties the tree; the surface stays mapped (and keeps taking pointer input in its rectangle) | new | a toggled surface therefore ends by **process exit**, or needs a GPUIX patch (`UiCommand::CloseWindow` → `window.remove_window()`) |
| process exit on close | `render()`: `process.exit(0)` when its window closes; custom hosts: your `onTerminated` | `renderer.ts:394-400` | keep | the compositor closes a layer surface when its output disappears (protocol `closed`): handle by exiting and letting systemd restart. INFERRED |

### 3.5 Live window and renderer methods (`GpuixRenderer`, `D.TS:36-217`)

| Method | Linux behaviour | K/R/N | Notes |
|---|---|---|---|
| `getWindowSize()` → `{width,height}` logical px | UI round trip; throws before `init()` ("GPUI application is not initialized", MEASURED P1) | keep | `useWindowSize()` polls it every 100 ms (`RX/hooks/use-window-size.d.ts`) |
| `getWindowInsets()` → `{safeArea, ime, effective}` | zeros expected on Linux | ignore | INFERRED |
| `activateWindow()`, `minimizeWindow()`, `zoomWindow()`, `toggleFullscreen()` | forwarded to GPUI; meaningful on the `files` toplevel only | keep for `files` | REPORTED (CHANGELOG 0.10 item 4) |
| `setWindowTitle(s)` | toplevel title | keep | |
| `promptForPaths({files,directories,multiple,prompt})` | **xdg-desktop-portal FileChooser** via `ashpd`; rejects with a "portal missing" error when no portal; one kind per prompt on Linux | replace in Pinax (own UI); keep for "Open with…" | `ZED/crates/gpui_linux/src/linux/platform.rs:401-440`. Portal availability on Tom's Sway UNVERIFIED |
| `setDebugFrameOverlay("hidden"/"minimal"/"full")`, `cycleDebugFrameOverlay()`, `getDebugFrameOverlayStats()` | on-screen draw-time overlay and p90/p99/max stats | keep (debug flag) | `debugFrameOverlay` in `render()` |
| `registerFont(buf)` | §3.8 | keep | per renderer |
| `getAllText()`, `getPaintedText()`, `getAutomationTree()`, `getElementBounds(id)`, `getElementsAt(x,y)`, `getPaintedHighlights()` | live inspection; work on Linux (P7 through automation) | keep for smokes | `getElementsAt` = DOM `elementsFromPoint` (0.11) |
| `simulate*` (click, mouse down/up/move, wheel, keystrokes, keyDown/Up) | inject through the live GPUI pipeline; used by automation | keep for smokes | MEASURED P7 |
| `clockPause/Set/FastForward/Resume` | freeze the **motion** clock only | keep for animation smokes | |
| `captureScreenshot(path)` | **throws on Linux**: "captureScreenshot needs a test-support build on macOS or Windows" (MEASURED P1, P7) | replace with `grim -o <output>` | |
| `TestGpuixRenderer`, `hasTestGpuixRenderer()` | **unavailable on Linux**: constructor throws "TestGpuixRenderer is macOS and Windows only..."; `hasTestGpuixRenderer() === false` (MEASURED P1) | replace | `createTestRoot()` from `@gpuix/react/testing` therefore cannot run here; unit tests are pure logic |

### 3.6 Host elements and headless components

JSX intrinsic elements (`NM/react/jsx-runtime.d.ts:167-180`; types `HOST:163`):

| Element | What exactly | Props beyond `HostProps` (`HOST`) | K/R/N | Notes |
|---|---|---|---|---|
| `div` | **block** box by default; flex/grid only with `display` | — | keep | README pitfalls `UP/README.md:3379-3398` |
| `text` | text run, selectable by default | — | keep | adjacent `<text>` siblings merge into one line; do not nest `<text>` in `<text>` |
| `input` | native single-line editor: caret, selection, IME, clipboard, undo/redo | `value`, `placeholder`, `readOnly`, `theme` (`HOST:386-392`) | keep | needs `autoFocus` or a click to get keys; **no inner padding** by default; clips to its own `borderRadius`. Enter → `onSubmit` always |
| `textarea` | multiline, auto-growing | + `minRows`, `maxRows` (`HOST:393-396`) | keep | Enter = newline unless `onSubmit` is set; Shift+Enter newline |
| `img` | path, data URL, or http(s) URL; PNG JPEG WebP GIF SVG BMP TIFF ICO Netpbm | `src`, `objectFit` (`fill/contain/cover/scaleDown/none`), `alt` (`HOST:425-430`); ref `setImage(bytes)`, `setImagePixels(w,h,buf,{format: "rgba" or "bgra"})` (`RX/types/host.d.ts:78-82`) | keep | http `src` fetched by GPUI in background; music notes rule: never feed token URLs (ASSUMPTIONS) |
| `svg` | **monochrome** icon tinted by `style.color` | `src` (path or `data:` URL), `source` (raw markup) | keep | `style.color` **required** or nothing paints; `currentColor` ≠ `style.color`. Bun: `import x from './i.svg' with { type: 'text' }` |
| `canvas` | declared, "Custom drawing (planned)" | — | new | README Status "[ ] Canvas element"; do not use |
| `anchored` | positioned overlay inside the window (GPUI deferred layer) | `position`, `side`, `align`, `gap`, `anchor`, `offset`, `fit` (`switch/snap`), `snapMargin`, `deferred`, `priority`, `occlude`, `fill: "window"` (`HOST:495-516`) | keep | **cannot draw outside its window's surface**: a tooltip from the 56 px rail is clipped to 56 px (§6) |
| `code` | syntax-highlighted block, no surface of its own | `code`, `language`, `path`, `showLineNumbers`, `theme` (`HOST:455-464`) | keep (OpenUI code blocks, clipboard preview) | rows fixed height, never wrap, own horizontal scroller |
| `diff` | unified-diff viewer | `patch`, `wordDiff`, `collapsedPaths`, `scroll`, `maxLines`, `theme`, `onToggleFile`, `onShowMore`, `onLineClick` | keep (herdr/agent views later) | |
| `markdown` | GFM: tables, strikethrough, task lists | `source`, `theme`, `onLinkClick` (`event.value` = URL) | keep (notification bodies, `ask`) | links do nothing unless you handle `onLinkClick` |
| `virtual-list` | variable-height list building only rows near the viewport | `estimatedItemHeight`, `itemCount` + `windowStart` (windowed mode), `alignment`, `followTail`, `overdraw`, `onVisibleRange`; **no `hover`/`active` style** (`HOST:397-424`) | keep (launcher results, clipboard history, Pinax) | wrap rows in `div` for hover; `scrollToItem(id, index, offset?)`, `getListScrollTop(id)` |

Headless components (`RX/index.d.ts`), all unstyled, Base UI / shadcn shaped:

| Component | Import | What | Notes |
|---|---|---|---|
| `motion.div` | `@gpuix/react` | native tweens of `width height opacity top right bottom left borderRadius` only (`HOST:7-31`); `transition {duration (s), delay (s), ease}` | no JS frames; clock-controllable |
| `AnimatePresence` | `@gpuix/react` | exit animations; unique `key` per child | toasts in/out |
| `Select`, `Combobox`, `Tooltip` | `@gpuix/react` or `/select`, `/combobox`, `/tooltip` | in-window floating layers (`collisionPadding` 8, `sideOffset` 0, Tooltip `delayDuration` 0, `skipDelayDuration` 300 — `UP/packages/react/src/components/{floating,tooltip}.tsx`) | in-window only |
| `Dialog.*` (Root, Trigger, Portal, Backdrop, Popup, Title, Description, Close) | `@gpuix/react/dialog` | full-window deferred layer; modal traps Tab; `initialFocus`/`finalFocus` | 0.11 |
| `Button`, `buttonProps()` | `@gpuix/react/button` | tab stop, `role="button"`, click on press / Enter down / Space up; `disabled`, `focusableWhenDisabled` | use for every clickable row/control |
| `DismissableLayer`, `pushDismissLayer(renderer, layer)` | `@gpuix/react`, `@gpuix/native/host` | per-window Escape stack: Escape closes only the top layer | custom popovers inside a surface |
| `FloatingLayer`, `floatingRootStyle`, `mergeStyles`, `renderSlot`, `resolveStyle`, `setRefs` | `@gpuix/react/floating` | building blocks for your own floating parts | |
| `useTextSearch`, `findRanges`, `createTextSearchController` | `@gpuix/react` | find-in-page over `highlight` | launcher match highlighting |

### 3.7 Style props (`StyleDesc`, `HOST:58-162`; README `UP/README.md:3359-3560`)

| Group | Props and accepted values | K/R/N | Notes |
|---|---|---|---|
| layout | `display` **only `"flex"` or `"grid"`** (anything else, incl. `"none"`, is ignored; `renderer.rs:6295-6300`); `flexDirection` (`row`/`column`), `flexWrap` (`wrap`/`wrap-reverse`/`nowrap`), `flexGrow`, `flexShrink`, `flexBasis` (number), `alignItems`/`alignSelf` (`start`/`flex-start`, `center`, `end`/`flex-end`, `stretch`, `baseline`), `alignContent` (+ `between/around/evenly/stretch/normal`), `justifyContent` (`start center end space-between space-around space-evenly`), `gap`, `rowGap`, `columnGap`; grid: `gridTemplateColumns`/`Rows` are **counts** (numbers), `gridColumnMin`/`gridRowMin` (`zero/min-content/max-content`) | keep | `div` is block until `display:"flex"`; flex children that must shrink need `minWidth: 0`. Hide with conditional rendering or `visibility:"hidden"` (keeps its box) |
| sizing | `width height minWidth minHeight maxWidth maxHeight`: number (px) or `"NN%"` or `"auto"`; `aspectRatio` | keep | no `calc()`, no `vh` |
| spacing | `padding`, `paddingTop/Right/Bottom/Left`, `margin*`: **numbers only** | keep | no CSS shorthands (`"0 16px"` ignored) |
| position | `position` `relative`/`absolute`/`fixed` (fixed = absolute), `top right bottom left` | keep | no `zIndex` (paint order = tree order; `anchored deferred` for overlays) |
| colour | `color`, `backgroundColor`, `background` (colour or `{type:"linear-gradient", angle, stops:[2], colorSpace}`), `opacity`, `borderColor`, `outlineColor`, `scrollbarColor`, `selectionColor`: any CSS colour via csscolorparser 0.8.3 (hex 3/4/6/8 with or without `#`, `rgb/rgba hsl/hsla hwb hsv lab lch oklab oklch`, named, `transparent`) | keep | invalid string = that one property ignored (`UP/packages/native/src/color.rs:3-11`) |
| border | `borderWidth`, `border{Top,Right,Bottom,Left}Width`, `borderColor` (one colour for all sides), `borderStyle` `solid`/`dashed`, `borderRadius` + 4 per-corner radii | keep | hairline = `borderWidth: 1` (`borderLeftWidth: 1` etc. for a single side) |
| shadow / outline | `boxShadow` object or array `{offsetX, offsetY, blurRadius, spreadRadius, color, inset?}`; `outlineWidth` (default 1), `outlineColor`, `outlineOffset` (no layout space, follows radius) | keep outline for focus rings; avoid shadows (BRIEF "hairlines not shadows") | |
| text | `fontSize`, `fontFamily`, `fontWeight` (number 1..1000 or `thin extralight light normal medium semibold bold extrabold black`, unknown → 400; `renderer.rs:63-88`), `textAlign` (`center`...), `lineHeight` (px), `whiteSpace` `normal`/`nowrap`, `textOverflow` `ellipsis`/`ellipsis-start`, `lineClamp`, `textDecoration` `underline`/`line-through`/`none` | keep | **absent**: italic/`fontStyle`, `letterSpacing`, `textTransform`, tabular-nums/font features. Inheritance §3.8 |
| overflow | `overflow`, `overflowX`, `overflowY`: `hidden`/`scroll`(/`visible`); `scrollbarColor` + `scrollbarWidth` (default 6) paint a non-interactive thumb | keep | thumb takes no pointer input (cannot be dragged) |
| interaction | `cursor` (§3.15), `pointerEvents` `auto`/`none` (unset: blocks clicks when it paints a fill or is positioned, lets wheel through), `userSelect` `text`/`none`/`auto` (inherited) | keep | set `userSelect: "none"` on rail/launcher chrome |
| state styles | `hover`, `active`, `focusVisible` (keyboard focus only, like `:focus-visible`; needs a focusable element) take a nested `StateStyleDesc`; `keyboardFocusDim: false` per element | keep | MEASURED P7: `hover.backgroundColor` applied natively (`#00cc00` under the pointer after a click) |
| visibility | `visibility: "hidden"` (not painted, keeps layout; `onLayout` silent while hidden) | keep | |

### 3.8 Fonts

| Feature | What exactly | MEASURED / source | K/R/N | Notes |
|---|---|---|---|---|
| system families | fontconfig families resolve by exact name | "Anthropic Sans", "Anthropic Serif", "AnthropicMono Nerd Font" all render (P1, P3, P6, rail-probe, P7) | keep | widths of "Hamburgefonstiv 0123" at 24 px: Sans 252 px, Serif 258, Mono 288, DejaVu Sans 276 (P1/P6 `onLayout`) |
| inheritance | `color`, `fontFamily`, `fontWeight` set on a `div` reach descendant `<text>` and `<input>` | P6 row A: magenta serif text under a styled div; P7: whole overlay in Anthropic Sans from the root div | keep | the example-app comment "GPUI does not inherit `color`" (`UP/example-app/app.tsx:28-29`) is **contradicted** by P6/P7 |
| defaults | no `color` anywhere → **black** text (invisible on noir); no `fontFamily` → an unidentified system face 249 px wide (not DejaVu, not Anthropic) | P6 rows B, D | — | always set `fontFamily` + `color` on every surface root |
| unknown family | falls back through `.ZedMono, .ZedSans, Helvetica, Segoe UI, Ubuntu, Adwaita Sans, Cantarell, Noto Sans, DejaVu Sans, Arial`; on this box `"NoSuchFontXYZ"` rendered monospace (288 px) | P1 | — | a typo in a family name gives a **mono** face, not sans |
| no font at all | if neither the family nor any fallback resolves, the `gpuix-ui` thread **panics** ("failed to resolve font 'Anthropic Sans' or any of the fallbacks") and the window dies; `registerFont` does not save it if the panicking family was not registered | P1 `fonts-emptyfc-*` (`FONTCONFIG_FILE` pointing at an empty dir) | — | the Nix wrapper must keep a working fontconfig (`FONTCONFIG_FILE`/`/etc/fonts`) in the unit environment |
| `fontWeight` with Anthropic Sans/Serif | the installed `AnthropicSans-Roman.ttf` / `AnthropicSerif-Roman.ttf` are **variable fonts** (fc-list shows named instances "Text Extrabold", "Display Bold"...). GPUI does not apply variable axes: weights 300/400/700 render **identically** | P4 ink counts 1585/1585, P1 widths 252/252/252; crop `PROBE/probe/gpuix011-probe4-l0i0tp00/static-family-crop.png` rows 5-6 | new | **bold UI text is impossible with the system Anthropic Sans as installed** |
| bold workaround | register a **static instance** of the variable font (e.g. fontTools `varLib.instancer` at wght 700) whose family name is `"Anthropic Sans"`: then `fontWeight: 700` picks it | P4 `same-family-bold`: rows "Anthropic Sans" 400/700 = 252/264 px, ink 1585/2359 | new (build step) | files used: `PROBE/fonts/AnthropicSans{Static-Regular,Static-Bold,Same-Bold}.ttf` (made by the orchestrator; never commit fonts — generate in the Nix build from `pkgs/anthropic-ui.nix` output, or at runtime into `$XDG_RUNTIME_DIR`) |
| mono weights | AnthropicMono Nerd Font ships static Regular/Bold/... files: `fontWeight: 700` works | P4 ink 1653/2347 | keep | |
| `registerFont(bytes)` | TTF/OTF (or collection) bytes; family names come from the file; requires family, full and PostScript names and a glyph for `m`; rejects anything else (`renderer.rs:8309-8331`); WOFF unsupported | P4: garbage rejected with "not a TrueType or OpenType font: unknown magic" | keep | **per renderer** (it adds to that window's text system: `renderer.rs:4053-4067`): register on every surface; text already laid out picks the family up next frame (README) |
| `GpuixTheme.fontSans` / `fontMono` | family for `<code>`, `<markdown>`, `<diff>`, input defaults; Linux defaults **"DejaVu Sans" / "DejaVu Sans Mono"** (`UP/packages/native/src/theme.rs:615-637`) | INFERRED | keep, always override | pass `theme={{fontSans:"Anthropic Sans", fontMono:"AnthropicMono Nerd Font", ...}}` |

### 3.9 Events (`HostProps` `HOST:303-385`; payload `D.TS:510-637`; table `UP/README.md:3243-3355`)

| Event prop | Payload fields | K/R/N | Notes |
|---|---|---|---|
| `onClick` | `x y button clickCount isRightClick modifiers`, **primary button only** | keep | MEASURED P7 |
| `onAuxClick` | non-primary clicks (`isRightClick`) | keep | rail middle-click / right-click |
| `onMouseDown`, `onMouseUp` | all buttons (`button` 0 left, 1 middle, 2 right) | keep | `onMouseDown` + `onMouseMove` on one node = pointer capture (left only) |
| `onMouseEnter`, `onMouseLeave` | `hovered`; leave also fires when the pointer leaves the window (0.11) | keep | |
| `onMouseMove` | `x y pressedButton modifiers` | keep | |
| `onMouseDownOutside` | press outside this element | keep | inside the same surface only: a click on another app/surface is not seen (Wayland) |
| `onScroll` | wheel input before it is applied: `deltaX deltaY precise touchPhase` | keep | volume/brightness wheel on the rail |
| `onScrollChange` | `scrollX scrollY` after any scroll movement | keep | not for `virtual-list` (use `onVisibleRange`) |
| `onLayout` | border box `width height x y`, after first paint and on each size change; `div` and `text` only | keep | MEASURED P1/P7; also a good "first paint" signal |
| `onFileDrop` | `paths x y` | keep (Pinax) | Wayland DnD via `wl_data_device` in GPUI (`ZED/.../wayland/client.rs:31`); UNVERIFIED on Linux |
| `onChange`, `onSubmit` | `value` | keep | MEASURED P7: `fill()` → one `change` per character; Enter → `submit:hello` |
| `onKeyDown`, `onKeyUp` | `KeyEvent`: `key keyChar isHeld modifiers keystrokeId` + `preventDefault() stopPropagation() defaultPrevented` (`HOST:548-556`) | keep | §3.10; keys are lowercase names: `enter escape tab space up down left right home end backspace delete f1`...; `modifiers {shift ctrl alt cmd}` where **Super/Logo = `cmd`** on Linux (P3: super-k → `cmd: true`) |
| `onFocus`, `onBlur` | — | keep | adding key/focus listeners creates a GPUI FocusHandle |
| `onHighlight`, `onVisibleRange`, `onMotionComplete`, `onLinkClick`, `onToggleFile`, `onShowMore`, `onLineClick` | element-specific (`matchCount`, `startIndex/endIndex`, `motionGeneration`, `value`, `oldLine/newLine`) | keep | |
| window `onKeyDown`/`onKeyUp` (in `render()`/`createRoot()` handlers) | fires after element handlers for keys no GPUI action consumed; gets `(event, renderer)` | keep | global shortcuts inside a surface (Ctrl+= zoom, Escape) |
| window `onSelectionChange` | `value` = joined selected text | keep | |
| `testId` | stable automation locator | keep | put on every interactive node (`<surface>.<part>.<id>`) |
| `role`, `aria-*` | AccessKit node needs `role`; `<text>` → Label, `<input>` → TextInput by default | keep | Linux AT-SPI exposure UNVERIFIED |

### 3.10 Focus, Tab, Escape

| Feature | What exactly | K/R/N | Notes |
|---|---|---|---|
| `tabIndex` | `0` = in order, `n` = explicit order, `-1` = focusable but skipped | keep | inputs/textareas are tab stops automatically |
| `autoFocus` | take focus once when the focus handle is created; **required** for an `<input>` to get keys without a click | keep | MEASURED P3/P7 (`focused: 2` after init) |
| dispatch order | keystroke → GPUI key actions (input editing keymap, §3.11) → element `onKeyDown` focused→ancestors → window `onKeyDown` → default (Tab focus move) | keep | an action that consumes a key means **no `onKeyDown`** (e.g. Enter/Home/End/ctrl-a/ctrl-c/ctrl-v inside an input) |
| Tab default | Tab/Shift+Tab move focus (0.11 default); cancel with `preventDefault()`; window-wide `tabNavigation: false` | keep | single-field launcher: either `tabNavigation: false` or use Tab for completion with `preventDefault()` |
| renderer focus API | `focusElement(id)` (waits until the element exists, 0.11), `focusNext/Previous()`, `focusNextWithin/PreviousWithin(id)`, `getFocusedElementId()`, `blur()` | keep | ids come from host refs (`ref.current.id`) |
| `focusVisible` style + `keyboardFocusDim` | while a control has keyboard focus, **every other focusable element renders at 40 %** (`KEYBOARD_FOCUS_DIM = 0.4`, `renderer.rs:4383`); a focused text field dims nothing; pointer jitter < 8 px keeps focus styles | replace default | pass `keyboardFocusDim: false` and draw Tacit-style rings with `focusVisible: {outlineWidth: 1 or 2, outlineColor, outlineOffset}` |
| Escape layer stack | one stack per window; Dialog/Select/Combobox/Tooltip/`DismissableLayer` push layers; Escape closes the top one unless `preventDefault()` | keep | a surface-level "Escape closes the launcher" goes in the window `onKeyDown` (runs only if no layer consumed it). MEASURED P7: `press('escape')` reaches element `keyDown` then `windowKeyDown` |

### 3.11 Text input, editing keymap, IME

| Feature | What exactly | K/R/N | Notes |
|---|---|---|---|
| editing keymap (both `ctrl-` and `cmd-`, i.e. Ctrl and Super) | `enter`=Submit (input) / Newline (textarea), `shift-enter` newline, `backspace delete left right home end shift-*`, `cmd-left/right` = Home/End, `cmd-up/down` = doc start/end, word moves `ctrl-left/right/backspace/delete` (or `alt-` per platform), `ctrl-a` select all, `ctrl-c` copy, `ctrl-x` cut, `ctrl-z` undo, `shift-ctrl-z` redo, `ctrl-v` paste; multiline adds `up down shift-up shift-down` | keep | `UP/packages/native/src/custom_elements/input.rs:192-270`. **Single-line `<input>` does not bind `up`/`down`**: they reach `onKeyDown` (launcher list navigation works without stealing) |
| `value` | external value; native edits apply first and report via `onChange`; same prop value does not reject edits (not a controlled input) | keep | |
| caret | line-height tall, solid while typing, blinks every **500 ms** idle; colour `theme.caret` | keep | set `theme={{caret: accent}}` |
| IME | Wayland `zwp_text_input_v3` is bound by GPUI (`ZED/crates/gpui_linux/src/linux/wayland/client.rs:50-54,141`) | keep | composition with fcitx5 on Sway UNVERIFIED; `wtype 'é'` produced no `change` in P3 (keymap-upload artifact, see §3.13) |
| paste fallthrough | when the clipboard has no text, Ctrl+V reaches `onKeyDown` (image/file clipboard handled by the app) | keep | 0.10 item 7 |
| no inner padding | `<input>` paints text at the top-left of its box; single-line centres vertically if taller | keep | P7: `height: 32, padding: 6` looks right (`p7.../auto-grim.png`) |

### 3.12 Clipboard and selection

| Feature | What exactly | MEASURED | K/R/N | Notes |
|---|---|---|---|---|
| JS clipboard API | **none** (no read/write method in `D.TS`) | grep | replace | shell actions call `wl-copy` (bytes on stdin) / `wl-paste`; clipboard history = `wl-paste --watch` + own store (BRIEF §3.4) |
| input copy → Wayland clipboard | `ctrl-a` + `ctrl-c` inside an `<input>` puts the text on the Wayland clipboard | P7: `wtype -M ctrl a c -m ctrl` → `wl-paste` printed `bc` | keep | P3/P7 runs that sent ctrl-a and ctrl-c as **separate** wtype processes copied nothing: wtype artifact (§3.13) |
| paste from Wayland clipboard | `ctrl-v` in `<input>` inserts `wl-copy` content | P3: `change` value `PASTED` | keep | |
| read-only text selection copy | drag-select `<text>`; Ctrl+C or Super+C copies the selection (`UP/packages/native/src/text/paint.rs:641-660`) | INFERRED | keep | `getSelectedText()`, `clearSelection()`, window `onSelectionChange`; disable with `userSelect: "none"` |
| primary selection | GPUI binds `zwp_primary_selection_device_manager_v1` | INFERRED | — | middle-click paste behaviour UNVERIFIED |

### 3.13 Automation and testing

| Feature | What exactly | MEASURED | K/R/N | Notes |
|---|---|---|---|---|
| `launch({command, args, cwd, env})` | spawns the app with piped stdio; the app (any `createRenderer`/`render`) serves the automation protocol (SSE `data:` lines on stdin/stdout, protocol v1) | **P7: works on Linux.** launch→ready 1.26 s (cold), `waitFor` 29 ms, then each step 30-55 ms | keep | `@gpuix/react/automation` = `@gpuix/native/automation` (`NM/native/dist/automation/client.d.ts:219`) |
| Locators | `app.getByTestId/getByText/getByType`, chain, `.all() .count() .element() .bounds() .center() .click() .hover() .wheel() .dragTo() .dragBy() .fill(text) .press(key) .textContent() .waitFor({timeoutMs})` | P7: `bounds` (`{x:16,y:16,width:388,height:32}`), `fill('hello')`, `press('enter')` → onSubmit, `press('escape')` → keyDown, `click()` → onClick, `textContent()`, `getByText().count()` all OK | keep | `client.d.ts:91-127` |
| raw input | `app.mouse.{move,down,up,click,wheel,drag}`, `app.clock.{pause,set,fastForward,resume}`, `app.captureFrames(dir, times)` | — | keep | `captureFrames` needs screenshots → Linux no |
| `app.screenshot({path})` | **fails on Linux** ("captureScreenshot needs a test-support build...") | P7 | replace | `grim -o HEADLESS-1 file.png` from the harness or the driver (P7 driver does both) |
| protocol methods | `initialize cancel click mouseDown mouseUp mouseMove scrollWheel keystrokes keyDown keyUp focus blur scrollTo getScrollOffset getTree getPaintedText getAllText getBounds getSelectedText clearSelection screenshot clockPause clockSet clockFastForward clockResume` | — | keep | `NM/native/dist/automation/protocol.d.ts:30-255`; errors `Timeout NotFound Ambiguous Protocol Closed Unsupported Security Cancelled` |
| `createTestRoot`, `TestRenderer`, `connectTest` | GPU test renderer | not on Linux | replace | pure-logic `bun test` + compositor smokes |
| wtype pitfalls | each `wtype` process creates a new virtual keyboard + keymap; **its first key event is lost** by the GPUIX window | P7: `wtype abc` typed `bc`; lone `wtype -k Escape`, `-k Down`, `-M ctrl a -m ctrl` produced nothing; a combined `wtype -M ctrl a c -m ctrl` worked | replace | in smokes prefer automation `press()`/`fill()`; if wtype is needed, chain keys in one invocation or send a throwaway first key (`-k Shift_L`) |
| layer surfaces in Sway IPC | not listed by `get_tree` | — | — | assert via workspace `rect` (exclusive zone) and grim pixels |

### 3.14 Timers, frame loop, motion

| Feature | What exactly | K/R/N | Notes |
|---|---|---|---|
| app timers | plain JS `setTimeout`/`setInterval`; no GPUIX timer API | keep | Bun/Node event loop is never blocked by GPUI (separate thread) |
| frame pacing | GPUI repaints on its own thread when a batch changes something drawn (`applyBatch` invalidates only if dirty, 0.11 item 22); caret blink and motion repaint natively | keep | |
| JS poll | `startFrameLoop` 8 ms default (`render()`); custom hosts choose `frameMs` | replace for daemons | §5.2 A |
| motion clock | `clockPause/Set/FastForward/Resume` affect native motion only | keep | |
| `motion.div` | `initial`/`animate`/`exit`/`transition{duration,delay,ease}`, eases `linear ease easeIn easeOut easeInOut [x1,y1,x2,y2]` | keep | OSD fade, toast slide via `top`/`opacity` |

### 3.15 Cursor

| Feature | What exactly | K/R/N | Notes |
|---|---|---|---|
| `style.cursor` | `default auto pointer text vertical-text crosshair grab grabbing move all-scroll col-resize row-resize ew-resize ns-resize nwse-resize nesw-resize n/e/s/w-resize ne/nw/se/sw-resize not-allowed no-drop alias copy context-menu` (`UP/packages/native/src/style.rs:374-394`) | keep | `hover: {cursor}` / `active: {cursor}` work |
| Wayland mechanism | `wp_cursor_shape_v1` when the compositor offers it, else xcursor theme | keep | INFERRED (`ZED/.../wayland/client.rs:66,212,252`); cursor theme/size env (`XCURSOR_THEME/SIZE`) only matters on fallback |

### 3.16 Output / monitor selection

| Feature | What exactly | K/R/N | Notes |
|---|---|---|---|
| choose output at creation | **not exposed.** GPUI's Wayland client maps `WindowOptions.display_id` to a `wl_output` and passes it to `get_layer_surface` (`ZED/crates/gpui_linux/src/linux/wayland/client.rs:1070-1092`, `window.rs:149-160`), but GPUIX never sets `display_id` (`UP/packages/native/src/renderer.rs:7618-7672`) | new (small patch) | patch sketch: add `WindowOptions.displayName?: string` → resolve `cx.displays()` by name → `gpui_options.display_id` |
| what happens today | compositor picks: **the focused output at surface creation** | — | MEASURED P2 (`place-after-focus-HEADLESS-1/2`) |
| list outputs | no API (no `displays()` in `D.TS`) | replace | use Sway IPC `get_outputs` |
| shell workaround (no patch) | for a one-shot overlay that must land on eDP-1 (Mod+i switcher, SH-04): `swaymsg focus output eDP-1`, spawn the surface, wait for first `onLayout`, then restore focus; for persistent per-output surfaces (rail on each display): spawn one per output after focusing it | new (shell) | INFERRED; racy under user input; the rail is wanted on eDP-1 only (BRIEF) so one focused-output dance at startup suffices. Must be proven with two headless outputs |

### 3.17 Theme for the native text components (`GpuixTheme`, `HOST:237-256`)

| Token | Linux default | K/R/N | Notes |
|---|---|---|---|
| `appearance` | `"dark"` (Comet dark) or `"light"` | keep | map noir/claude-dark → dark, claude-light → light |
| `bg border text textMuted textFaint textDim accent caret` | dark: bg `grey(6)`, border white 8 %, text 92 %, accent/caret **indigo `oklch(0.673 0.182 276.9)`** (`theme.rs:481-500`) | replace all | the default indigo selection/caret clashes with noir; feed the shell palette |
| `codeText codeWash diffAdd diffDel diffHunkBg syntax.*` | Comet palette | replace as needed | |
| `fontSans fontMono` | `DejaVu Sans` / `DejaVu Sans Mono` | replace | §3.8 |
| `metrics.*` | code/diff/markdown row heights, heading sizes, table padding | keep defaults first | `HOST:197-232` |
| `selectionColor` (style) | default theme accent at 35 % | replace | |

## 4. Design values (GPUIX defaults and measured numbers)

| Value | Number | Label / source |
|---|---|---|
| default window size | 800 x 600 (test renderer 1280 x 800) | `renderer.rs:1370-1371`; `testing.d.ts:5` |
| `render()` JS poll | 8 ms (≈125 Hz) | `runtime.ts:13` |
| macOS wake fallback | 100 ms | `runtime.ts:14` |
| `useWindowSize`/`useWindowInsets` poll | 100 ms | `RX/hooks/use-window-size.d.ts` |
| caret blink | 500 ms | `input.rs:73` |
| keyboard-focus dim | 40 % opacity on other focusables | `renderer.rs:4383` |
| focus-style pointer jitter tolerance | < 8 px | CHANGELOG 0.11 item 4 |
| scrollbar thumb | 6 px default width, min length 20 px, fully rounded, no pointer input | README `UP/README.md:1922-1945` |
| highlight wash | radius 2; colour accent 30 %, active accent 65 % | `HOST:279-301` |
| selection wash | accent 35 % | `HOST:151` |
| floating content | `collisionPadding` 8, `sideOffset` 0 | `floating.tsx:280-283` |
| tooltip delays | `delayDuration` 0, `skipDelayDuration` 300 ms | `tooltip.tsx:47-48` |
| idle GC | check every 5000 ms, 2 quiet checks, busy above 0.5 core | `idle-gc.d.ts` |
| text box at `fontSize: 24`, no `lineHeight` | 39 px tall (≈1.62 x) for Anthropic Sans/Serif/Mono | MEASURED P1 `onLayout` |
| "Hamburgefonstiv 0123" @24 px width | Sans 252 · Serif 258 · Mono 288 · DejaVu Sans 276 · unset 249 | MEASURED P1/P6 |
| `init()` duration (layer surface, headless Sway) | 92-177 ms | MEASURED P1/P2/P7 `initMs` |
| spawn → first `onLayout` (React overlay, warm caches) | node 291 ms, bun 289 ms; first-ever runs 549 ms (node) / 625 ms (bun) | MEASURED P7 `cold` |
| `launch()` (automation) → first locator ready | 1262 ms then 29 ms `waitFor` | MEASURED P7 |
| RSS one surface / two surfaces in one process | 148.5 / 163.4 MiB (gles2, P7); 199.6 / 233.5 MiB (pixman, P1) | MEASURED |
| native addon size | 52.4 MB | MEASURED |
| rail probe geometry that worked | 56 px wide, `exclusiveZone: 56`, anchor left/top/bottom, height 0 or output height | MEASURED rail-probe (BRIEF §5), P2, P7 |
| overlay geometry that worked | `anchor: ["top"]`, `margin: [108,0,0,0]`, 420x220 / 300x200, `keyboardInteractivity: "exclusive"` | MEASURED P2, P7 |

## 5. Reusable code, data and recipes

### 5.1 Paths

| What | Path | Use |
|---|---|---|
| napi surface | `NM/native/index.d.ts` (804 lines): `GpuixRenderer` 36-217, `TestGpuixRenderer` 232-451, `EventPayload` 510-637, `isTerminal` 675, `LayerShellOptions` 685-721, `WindowOptions` 746-799 | jump table |
| style/element types | `NM/native/dist/host.d.ts`: `MotionProps` 25, `CursorValue` 36, `StyleDesc` 58-161, `ElementType` 163, `GpuixTheme` 237, `HighlightSpec` 258, `HostProps` 303-385, `InputProps` 386, `VirtualListProps` 416, `ImgProps` 425, `SvgProps` 437, `CodeProps` 455, `DiffProps` 465, `MarkdownProps` 488, `AnchoredProps` 495, `NativeRenderer` 522, `MutationRenderer` 524, `KeyEvent` 548, `WindowKeyEventHandlers` 559 | |
| framework-neutral runtime | `NM/native/dist/runtime.d.ts:11-18` (`createNativeRenderer`, `startFrameLoop`, `enableAutomation`); `host-runtime.d.ts:16-52` (`readWindowSize`, `observeWindowSize`, `findRanges`, `createTextSearchController`); `renderer-state.d.ts:25-60` (`DismissLayer`, `pushDismissLayer`); `mutations.d.ts:14-37` (`createMutationQueue`, `EVENT_PROPS`, `sameMutationValue`) | the OpenUI MutationHost adapter (BRIEF §3.7) builds on these |
| React exports | `NM/react/dist/index.d.ts:1-34` | |
| automation client | `NM/native/dist/automation/client.d.ts` (`Locator` 91, `App` 128, `launch` 219) | smoke drivers |
| render() source | `UP/packages/react/src/reconciler/renderer.ts:271-426` | read before writing a custom host |
| Linux init / tick / window options | `UP/packages/native/src/renderer.rs:1364-1484`, `1532-1560`, `7467-7672` | patch points (§6) |
| GPUI layer surface creation | `ZED/crates/gpui_linux/src/linux/wayland/window.rs:146-195`; display→output `client.rs:1070-1092` | output-pinning patch |
| input keymap | `UP/packages/native/src/custom_elements/input.rs:156-270` | |
| default themes | `UP/packages/native/src/theme.rs:480-633` | |
| example app (tokens, svg icons, `virtual-list`, `motion.div`, testIds) | `UP/example-app/app.tsx` (572 lines), `screenshot.ts` (launch + screenshot pattern) | style reference only; its `FONT`/inheritance comments do not hold on Linux |
| rail probe that renders on headless Sway | `docs/gpuix-shell/evidence/rail-probe/{rail.tsx,smoke.py,shot.png}` | template for `tests/gpuix-shell/smoke_rail.py` |
| raw-batch probe app (multi-surface, fonts, kbd) | `PROBE/probe/measure.mjs` + `harness{,2,3,4,6}.py` | template for multi-surface and font smokes |
| React probes | `PROBE/probe-react/multi.mjs` (2 roots), `app7.mjs` (overlay with input/button/status + file logging), `driver7.mjs` (**automation driver: launch, fill, press, click, textContent, grim**), `harness7.py` (headless Sway gles2 harness: automation, wtype, cold start, stretch) | copy `driver7.mjs` + `harness7.py` shape into `tests/gpuix-shell/` |
| LD_LIBRARY_PATH that works | `PROBE/probe/harness.py:11` (`LIBS`: openssl, libxcb, libx11, libglvnd, freetype, fontconfig-lib, vulkan-loader, wayland, libxkbcommon, gcc-lib) + env `WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128 VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json` | the addon dlopens `libvulkan.so.1 libwayland-client.so libwayland-egl.so libEGL.so.1 libxkbcommon.so.0 libxcb.so.1` (MEASURED string scan) |
| static Anthropic Sans instances (probe only, never commit) | `PROBE/fonts/AnthropicSansStatic-{Regular,Bold}.ttf`, `AnthropicSansSame-Bold.ttf` | shows the bold workaround works |

### 5.2 Recipes (all INFERRED from the API unless marked)

**A. Daemon surface with a slow poll and crash-to-systemd** (rail, notifications):

```tsx
import { createRenderer, render, startFrameLoop } from '@gpuix/react'
const r = createRenderer()
r.init({ appId: 'gpuix-shell-rail', width: 56, height: 0, windowBackground: 'opaque',
  layerShell: { namespace: 'gpuix-shell-rail', layer: 'top', anchor: ['left', 'top', 'bottom'],
                exclusiveZone: 56, keyboardInteractivity: 'on-demand' } })
for (const f of fontFiles) r.registerFont(readFileSync(f))   // only if bundling static instances
render(<Rail />, { renderer: r, keyboardFocusDim: false })   // injected: render() starts no loop
startFrameLoop(r, { frameMs: 250, onTerminated: () => process.exit(0) })
process.on('uncaughtException', (e) => { console.error(e); process.exit(1) })  // after render()
```

**B. Second surface in the same process** (MEASURED P5 shape): `const s = createRenderer(); s.init({...layerShell});
const root = createRoot(s, { onKeyDown }); root.render(<Toasts />); startFrameLoop(s, { frameMs: 250 })`. The surface
cannot be closed again (§3.4); size it once (toast stack height = rows × row height at creation) or keep it for the process
lifetime. Register fonts on `s` too.

**C. Stretch an axis**: pass `0` for that dimension and anchor both opposite edges (MEASURED). A non-zero value gives a
centred fixed-size surface.

**D. Toggled overlay (launcher, switcher, power, OSD)**: one short-lived process per show: spawn → `render()` with
`layer: 'overlay'`, `keyboardInteractivity: 'exclusive'` → act → `process.exit(0)`. Cost ≈ 0.3 s warm to first paint
(MEASURED P7). Toggle = the CLI asks the running instance over the control socket to exit; Escape handled in the window
`onKeyDown` (MEASURED delivered). Keeping it alive between shows is impossible without a hide/close patch.

**E. Fonts on every surface root**: `style={{ fontFamily: 'Anthropic Sans', color: tokens.fg, fontSize: 12 }}` on the root
`div` (inherits, MEASURED); figures in `'AnthropicMono Nerd Font'` (bold works). For Sans bold, ship generated static
instances (§3.8) or design without bold (Tacit's quiet type mostly needs 400/500, and 500 has the same problem).

**F. Compositor smoke** (MEASURED P7 shape): headless Sway gles2 under `runtime-test --render-node`, then
`launch({ command: bun, args: [entry, '<surface>'] })`, drive with `getByTestId(...).fill/press/click/textContent`,
screenshot with `grim -o HEADLESS-1`, assert exclusive zone via `swaymsg -t get_workspaces` rect.

**G. Interface zoom (Tom 2026-10-13 23:45Z)**: GPUIX has no zoom. Put `scale` in a React context, derive every size
token (`fontSize`, padding, radii, row heights) as `Math.round(base * scale)`, handle `ctrl-=`/`ctrl--`/`ctrl-0` in the
window `onKeyDown`, persist per surface. Layer surface size cannot follow (no resize): the rail would need a respawn at
the new width.

**H. Launcher input**: `<input autoFocus value onChange onSubmit>`; arrow keys come through `onKeyDown` on the input
(single-line binds no up/down); Enter arrives as `onSubmit`, not `onKeyDown`; use `tabNavigation: false` or
`preventDefault()` on Tab.

### 5.3 Correction list for other notes and the BRIEF

1. "layerShell exists since 0.10.0" → since **0.8.0** (`UP/CHANGELOG.md:396`).
2. "GPUIX has one window per renderer process" (BRIEF §3.2) → one window per **renderer**; several renderers per process
   work (MEASURED P1/P2/P5). One-process-per-surface remains a valid choice for isolation, at ~150-200 MiB each.
3. d.ts `LayerShellOptions` comment on width/height → wrong for Sway; pass 0 to stretch (MEASURED).
4. "GPUI does not inherit `color`" (example app) → it does on Linux 0.11 (MEASURED P6/P7).
5. `wave1/21-nix-packaging-and-checks.md:124` "`registerFont` not needed" → needed if bold Anthropic Sans is wanted (§3.8).

### 5.4 Evidence index

| ID | When (CEST) | Who | Dir under `PROBE/` | What |
|---|---|---|---|---|
| P1 | 2026-10-20 23:15 | orchestrator | `probe/gpuix011-probe-s6nmn_ya/` (`harness.py`, pixman, 2 outputs) | two surfaces in one process; focusout; fonts; empty-fontconfig panic |
| P2 | 23:18 | orchestrator | `probe/gpuix011-probe2-aa5bbvzg/` (`harness2.py`) | height-0 stretch, exclusiveZone −1, placement follows focused output |
| P3 | 23:19 | orchestrator | `probe/gpuix011-probe3-0zp2_tho/` (`harness3.py`) | keyboard via wtype, paste, Super = cmd |
| P4 | 23:21 | orchestrator | `probe/gpuix011-probe4-l0i0tp00/` (`harness4.py`) | font weights, static-instance workaround |
| P5 | 23:22 | orchestrator | `probe-react/gpuix011-react-kscot5it/` (`harness5.py`, `multi.mjs`) | two React roots/surfaces in one process |
| P6 | 23:24 | orchestrator | `probe/gpuix011-probe6-l5a0g30t/` (`harness6.py`) | style inheritance, default colour/face |
| P7 | 2026-10-21 12:10 | this reader | `probe-react/p7/p7-h5usxziv/` (`harness7.py`, `app7.mjs`, `driver7.mjs`; gles2) | automation `launch()` on Linux, Escape/Enter, clipboard copy, cold start, stretch, transparent rounded overlay |

All ran as `~/.wt/dotfiles/gpuix-shell/home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- python3 harnessN.py`
against `/nix/store/04g9x522...-sway-1.12` headless; none touched the live session.

## 6. Gaps and unknowns

Ranked by how much they shape the shell. "Patch" = a change to `remorses/gpuix` (Rust, needs the zed submodule and a
native build; see `wave1/21` for the Nix side).

| # | Gap | Impact | Label | Options |
|---|---|---|---|---|
| G1 | **No window close/hide/unmap** for a renderer's window | toggled surfaces must be processes (§5.2 D); multi-surface daemons cannot drop a surface | INFERRED (code) | patch: `UiCommand::CloseWindow` / `Hide` (GPUI `window.remove_window()`); or accept spawn-per-show |
| G2 | **No output selection** | Mod+i switcher and rail must land on eDP-1 (SH-04, Tom 2026-10-14 00:33) | MEASURED (follows focus) + INFERRED (GPUI supports `display_id`) | patch ~20 lines (§3.16); interim focus-output dance |
| G3 | **No layer-surface reconfigure** (size, exclusive zone, layer, keyboard mode, margin) and **no input region** | rail 56↔220 expand, toast stack growth, keyboard on-demand switching | REPORTED + INFERRED | respawn surface on change; patch setters on `WaylandLayerSurfaceState` |
| G4 | **No popups outside the surface** | rail tooltips/menus are clipped to 56 px; `anchored` is in-window only | INFERRED | separate overlay surface per popover (positioned by margin from the rail), or patch to expose GPUI's `WindowKind::AnchoredPopup` (xdg_popup parented to the layer surface, already in the fork: `window.rs:197-230`) |
| G5 | **Variable Anthropic fonts lose weights** | no bold/medium Sans or Serif | MEASURED P1/P4 | static instances generated at build time and `registerFont` per surface (not in git); or a fontconfig-visible static family. Italic: `AnthropicSans-Italic.ttf` is variable too; no `fontStyle` prop exists anyway |
| G6 | **No JS clipboard API** | copy actions, clipboard history | MEASURED (absent) | `wl-copy`/`wl-paste` subprocesses (BRIEF §3.4) |
| G7 | **No screenshot / test renderer on Linux** | visual regression | MEASURED | grim in smokes; pixel asserts by colour bbox (P2/P7 `bbox`) |
| G8 | **No zoom** | Tom's 10-13 complaint | REPORTED (absent) | §5.2 G |
| G9 | `display: none`, `zIndex`, `fontStyle`, `letterSpacing`, `textTransform`, font features absent | Tacit-like small caps / tracking impossible | INFERRED | conditional render; tree order; design without tracking |
| G10 | Two GPUI apps in one process: long-run stability | daemon design (rail + toasts + OSD in one process) | MEASURED short (≤6 s) only | soak test before committing to it; one-process-per-surface is the safe default |
| G11 | `keyboardInteractivity: "on-demand"` (rail search/rename) | rail keyboard focus | UNVERIFIED | smoke it |
| G12 | IME (fcitx5 via text-input-v3), primary selection, `onFileDrop` from a file manager, `promptForPaths` portal on Tom's Sway | Pinax, text entry | UNVERIFIED | smoke each on the Zenbook |
| G13 | AccessKit on Linux (AT-SPI) | a11y | UNVERIFIED | `role`/`aria-*` cost nothing; keep them |
| G14 | What the compositor does to an unclosable layer surface when its output is unplugged (eDP-2 off on the Duo) | rail on the bottom screen | UNVERIFIED | exit on `tick()` false; systemd restarts |
| G15 | `render()` runtime-error overlay keeps a broken daemon alive | silent half-broken rail | INFERRED | §5.2 A |
| G16 | Automation auto-enables whenever stdin is not a TTY | a parent holding a stdin pipe can drive the GUI | INFERRED (`runtime.ts:40-46`) | spawn surfaces with `stdin: 'ignore'` (`/dev/null`: EOF, harmless) |
| G17 | `terminal: true` head on Linux | possible in-kitty Pinax/ask | UNVERIFIED ("no app ran there yet") | later |
| G18 | Real-hardware timings (Zenbook eDP-1/eDP-2, scale factors, fractional scale) | perceived launcher latency | UNVERIFIED (all numbers are headless) | measure on the client with `runtime-test`-isolated nested Sway or after deploy |

What this note did **not** verify: anything on the live Sway or on the Zenbook; `on-demand` keyboard mode; real keyboards
(only wtype and automation); IME; DnD; portals; multi-hour stability of multi-renderer processes; light/dark `GpuixTheme`
rendering of `<code>/<markdown>`; `motion.div` on Linux. The probes P1-P6 were run by the orchestrator; this reader
re-read their scripts, logs and screenshots and ran P7 itself.
