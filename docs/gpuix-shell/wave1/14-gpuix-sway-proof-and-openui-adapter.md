# 14 — GPUIX Sway proof (design/gpuix-comparison) and the OpenUI → GPUIX native adapter (shared-parity)

Wave-1 reader note for the overnight `gpuix-shell` build (2026-10-20/21). Read-only inventory of two
sources; nothing in them was run tonight. Labels: **MEASURED** = evidence on disk that I opened,
**REPORTED** = claimed by the source's own README/docs/logs, **INFERRED** = my reading.

Pointers are `path:line` into the files as they are tonight. Both sources are frozen snapshots:
`gpuix-comparison` is untracked (`??`) in the `hyprland-solid-shell` worktree (HEAD 2ac87891,
2026-10-13 22:45), files dated 2026-10-14 01:21–01:38; `shared-parity` is a tiny git repo with three
"Update Site source" commits at 2026-10-20 16:36 / 16:45 / 16:51 (+0200).

---

## 1. What these sources are

### 1a. `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/` — the GPUIX-on-Sway proof (Solid, 0.10.0)

Built by a Codex session in the night of 2026-10-13→14 (the "side by side implementations in gpuix … email
app and 'desktop'" order, see §2). Two ordinary xdg-toplevel GPUIX windows rendered through
`@gpuix/solid`'s custom renderer: `email.tsx` (a mail reader with fixtures + a live read-only mode) and
`desktop.tsx` (a "desktop" study: top bar with real Sway workspaces, 220-px sidebar, notes/terminal/browser
tabs, launcher, notifications, quick controls, calendar, three palettes). No webview, no DOM. The entry
refuses the WASI fallback (`main.ts:6`).

What matters for the shell is **not** the Solid UI (the brief picks React) but three things that are
framework-free and proven on this machine:

| Piece | File | Why it matters |
|---|---|---|
| Sway capability adapter | `platform.ts` (54 lines) + `platform.test.ts` (26 tests) | Read outputs/workspaces, filter to `eDP-1`, safe `workspace` switch with revalidation. Reuse as-is. |
| Isolated-compositor smoke recipe | `smoke-native.py`, `smoke-live.py`, `automation-native.ts` | Headless private Sway + grim + `@gpuix/native/automation`. The template for `tests/gpuix-shell/smoke_<surface>.py`. |
| Nix-less packaging recipe | `package-native.py`, `bundle/run`, `bundle/nix-closures.txt` | The exact `LD_LIBRARY_PATH` library set the 0.10.0 binding needs on NixOS (feeds `pkgs/gpuix-shell/default.nix`). |

Pins (README.md:5): `@gpuix/native` 0.10.0, `@gpuix/solid` 0.10.0, `solid-js` 1.9.15, TypeScript 5.9.3, Bun
1.4.2 (`/nix/store/216mr46yy8xspaydgapjhf4a21y643ji-bun-1.4.2`). `node_modules` is a symlink to
`../../pkgs/desktop-shell/node_modules` (the Hyprland desktop-shell's install, which also holds the only
installed native binding on this host: `@gpuix/{native,native-linux-x64-gnu,solid}` — **no `@gpuix/react`
is installed anywhere locally** (MEASURED, `ls pkgs/desktop-shell/node_modules/@gpuix/`).

MEASURED evidence still on disk (strix `/tmp`): `/tmp/gpuix-native-comparison-{1td9qwjs,6n5m0m2_,zbs9hz29,…}`
(9 dirs). `1td9qwjs/results.json` = `{"ok":true,"scope":"Native GPUIX mapped on isolated stock Sway; compositor
screenshots and native input/button automation passed."}`; `desktop-window.json` shows `app_id
gpuix-comparison-desktop`, title `GPUIX comparison — Desktop`, rect 720×900, `shell: xdg_shell`; `sway.conf`
there is `output HEADLESS-1 mode 720x900 bg #F9F9F7 solid_color`. The client-side bundle
`/home/tom/Downloads/gpuix-comparison-2026-10-14/` does **not** exist on strix (that copy lives on the
Zenbook per README.md:25; REPORTED).

### 1b. `/home/tom/tuesday-oct20/build/shared-parity/` — OpenUI contract + GPUIX MutationHost adapter (today, 2026-10-20)

Built this afternoon (Codex sessions 14:07–16:51) as the "parity engine" between a React web host (Cloudflare
Worker + R2) and a Linux GPUIX native host, both driven by one OpenUI component/action contract and one
typed command gateway. Domain is the *shared utilities* side of Tom's boundary (mail/CRM/projects fixtures,
fictional records) — **explicitly not the personal shell** (`docs/BUILD-MAP.md:13`: "Sway/Herdr placement,
personal desktop control and the user's shell remain outside it").

What matters for `gpuix-shell ask` (brief §3.7) is the framework-neutral seam it demonstrates:

| Piece | File | Why it matters |
|---|---|---|
| Core-only OpenUI library (no React) | `src/openui/contract.ts` | `defineComponent({... component: null})` + `createLibrary` from `@openuidev/lang-core` only. |
| Program validator / evaluator call | `src/openui/host.ts:28-80` | The exact `createParser` → `evaluateRoot` sequence and the refusal rules. Copy the shape. |
| OpenUI element tree → GPUIX mutation tuples | `src/native/adapter.ts:89-135` | The only existing lang-core → `applyBatch` renderer. Component switch at :103-127. |
| Native entry (binding load, window, tick, key events) | `src/native/main.ts` | How a raw `GpuixRenderer` is driven without a framework. |
| Local-model streaming call | `scripts/local-server.ts:88-108` + `src/model/stream.ts` | The exact `/v1/chat/completions` body against strix `127.0.0.1:8731`, SSE parsing, NDJSON relay. |
| Isolated compositor harness (GLES2 lesson) | `tests/native-compositor.py` | Same recipe as 1a but with `WLR_RENDER_DRM_DEVICE`, `TEST_WLR_RENDERER`, node+tsx entry. |
| Fake retained host for unit tests | `tests/native.test.ts:10-36` | `RetainedHost` validates mutation batches without a binding — reuse for bun tests. |

Pins (`docs/native.md:52`, `package.json`): OpenUI clone `9823ec05d4b29bc78d101676dc16b44fe17f1830`
(2026-10-19), installed `@openuidev/lang-core` 1.0.1 + `@openuidev/react-lang` 1.0.1, `zod` 4.3.6, React
19.2.3; GPUIX source snapshot `6a5c7c142ac32f9eb0caefe0121be995cfc18631`, loaded binary `@gpuix/native`
0.10.0 (sha256 `a907deb0…ea44d`, `evidence/native/manifest.json:7`), Node
`/nix/store/v6wsd9nyglmwh32yn7w8z11dq9cksg4m-nodejs-24.20.0`, pnpm 11.

MEASURED evidence on disk: `evidence/native/{pointer-local,keyboard-worker,keyboard-focus-worker,
model-worker,ordered-activity-worker,final-ordered-worker}` (before/after PNGs, `native-state.json`,
`result.json`), `evidence/native/failure-pixman/native.log` (the `ERROR_SURFACE_LOST_KHR` run),
`evidence/model/{generated.openui,probe.json}` (one real generation from `halogen-qwen3.8-flash-next`,
3271 ms, accepted, 2026-10-20T14:20:01Z).

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with timestamps)

All quotes are Tom's own words, pulled tonight from the Codex rollouts named in the brief with a user-turn
extractor (timestamps are UTC as stored in the rollouts; local = +2h). Typos preserved.

**2026-10-13, Codex `01a1370e` (the GPUIX pivot session)**

- 21:04:11Z — "revisit the chromium aura entire epoch historiically, and understandh how it will now be done on
  hyprland ; and https://gpuix.dev/ https://github.com/remorses/gpuix https://gpui-kit.com/docs/comparison/"
- 21:06:46Z — "this supersedes the whole aura requirement. it even fucking correesponds to the solidjsidea i had!!!"
- 21:11:34Z — "hyprland is just sway with animations and best in class blur. for terminal: herdr + kitty ;
  until superlogical releases their terminal. for browser, google chrome."
- 22:03:41Z — "the first task is to introspect into my existing claude ui, i tried replicating the claude managed
  agents ui , and tyhe claude calendar implementation. first step is finailzing the look and aesthetic. i want
  to use the claude anthropic font, the color scheme and selector, and the github primer react theme kit"
- 22:16:03Z — "whatever you just opened: i love it. this is good enough to also become a functional
  remplacement to waybar, vicinae and mako notifications. drawing insporation from omarchy's implemetnatipn
  of wayshell in fact."
- 22:16:59Z — "we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever"
- 22:25:30Z — "i digress on the hyprland parts, i m sorry. let s tick to sway window manager. less effort..
  but do list all the hyprland functionality that we're 'missing out on' in a way so i can decide if i want
  hat added potentially later or not..."
- 22:33:25Z — "one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status
  indicators. only for the top display (consult kanshi config to know which one i m talking about, and
  existing vicinae herdr wrkspaces item as well if needed." ← this is the order `platform.ts` answers
  (`targetOutput='eDP-1'`, `platform.ts:44`).
- 23:07:03Z — "i am expecitng it to be a react (solidjs compat) superset of github primer, cloudaflare kumo +
  cloudflare-os. that can do all the way from my desktop shell to the functional desktop that exists. the
  idea is to keep 'grinding' at a unified set of requirements that can outlast any coding language of
  framework, with react being the real world implementation of it"
- 23:17:17Z — "get 3 subagents to give me side by side implementations in gpuix so that i can see them side by
  side. let s do email app and 'desktop'" ← the origin of `design/gpuix-comparison`.
- 23:19:41Z — "explain more about why prier react components don't directly become native gpuix controls.
  what that means, and how that changes things for us. gpuix is a cool project but we can use it as
  stylistic inspiration if it's not adapted."
- 23:21:38Z — "i m not intersted in 'native advantage' . performance is not really the thing i m looking for
  here. 'supplies another renderer' is fine for something that' react plus generic compositor
  functionlaity... vicinae (raycast clone) proves this theoretically ; we hae the sway ipc and omarchy's
  quickshell which you investigated a while back did exactly that."
- 23:27:51Z — "it should be the 'same complexity' accessing cf-hosted data for gpuix 'native' windows as it is
  for chrome --app ones like what you showed me, right:?"
- 23:32:42Z — "i want a design kit (set of constraints) that is a good enough set in order for us to have a
  claude anthropic-maximalist look 'as if it was done by anthropic claude' but for desktop os ; in a way that
  we can use it in gpuix."
- 23:45:17Z — "one quick note on gpuix that is unfortunate is that it's not registering ctrl +\- for zooming ;
  was that explicitly disabled or what?" (REPORTED open question; never answered in the sources I read.)
- 23:46:43Z — "one more introspection in ~/notes on the ctrl k contextual menu idea … this is something that
  is interesting now that it may all be gpuix-controlled ; potentially giving control of my desktop to the ai"

**Tom's saved note `/home/tom/tuesday-oct20/desktop-ui.md:5-13` (undated file, quoted by
`docs/openui-method.md:9` on 2026-10-20)**

- "the GPUIX project was analyzed in the past and i found that it was the best possible tool to base my
  project on when it comes to building front-ends. it would make us completely agnostic to building native
  linux wayland (thomas); macos (marwan); AND web (frank)."
- "the only boundary being of course the desktop shell, which would be exclusive to wayland-on-sway wm."
- "the MASSIVE finding of the last few days: `https://github.com/thesysdev/openui` this openui project has
  the generative-ui philosophy that is exactly what i can use to have fully uniform deployments. extremely
  desirable, as i will have the same llm generate all the front-end tooling, starting from my desktop shell
  all the way to webapps like email etc."
- "we build it once and it can be exported everywhere."

**2026-10-20, Codex `01a15935` (the shared-parity session)**

- 13:47:28Z — "we drew the boundary of things that are my own versus things that we can all use are: the gpuix
  local shell. and that has been scoped very well previopusly"
- 13:58:10Z — "important: git clone and follow the methodloogy of openui which was referred to in the files i
  found. it's important that we stsett building the parity enfgine with real use cases freo mthe getgo"
- 14:12:30Z — "it is important that fron t end we buikld built from the ground up with openUI methodology AND
  thezhortcut driven method as well (so that my human clicks on the webUI is the same as an agwent's usage of
  the api with 'trailing clicks' happening by another aent thst just shows what is being worked through."
- 14:22:36Z — "we will 'find the ideal tool' to write gpuix plus cf workerd deployed as we go. react , solidjs
  (leaning towards react). what about the 'kb shortcut accessibility feautre' cha[ter?"

**2026-10-20, Codex `01a159bd` / `01a159c1` (herdr-web-ui ↔ terminal toggle)**

- 14:39:23Z — "on my own dotfiles sway implekentation, this switch is a little 'special' as we can toggle
  between a native termoinal and a gpuix based chat window. … i hope youo ll apreciate hwio cucrently swaywem
  workspaces have one to one with herdr and the kitty termianl carrying it. gpuix chat window based competely
  on the herdr-web-ui is unbuilt but should not be too difficult. … using shortcut-driven accessibility
  funcitonality plus openUI in order to achireve a parallel with the claude.ai web chat interface"
- 14:50:19Z — "we can in fact now come full circle with https://github.com/lcoutodemos/clui-cc … the gpuix
  implementation can enter flawlessly. the only thing we can retain from before is the nautilus file picker
  (same as what google chrome uses) ; and the clui-ccc behavior (using the 'unified' components collectin
  that i have. and it will intergrate with herdr-web-ui the same way."
- 14:50:54Z — "openUI as a starting point, the esthetic that exists in myown
  https://strix.tail8dd1.ts.net:8443/?ws=wHP-client-slot-7-695519&pane=wHP%3Ap1&view=chat implementation
  that s a good starting point - yet not yet 'dematerialized'"
- 14:53:57Z — "it s just the clui-cc reimplementation in gpuix really, with attention to herdr-centrality"

**2026-10-20 ~22:50–23:05 CEST (brief §1, the overnight order)** — "openUI for the desktop shell is not quite
known"; "gpuix as the frontend all the way is desired". INFERRED consequence for this note: OpenUI stays an
*exploratory* surface (brief §3.7), and everything the core shell needs from these two sources is the Sway
adapter, the harness recipe and the model-call shape.

---

## 3. Feature / behaviour inventory

Legend for "keep/replace/new": **keep** = reuse code as-is; **port** = reuse the behaviour, rewrite for
React/@gpuix/react; **replace** = different implementation in gpuix-shell; **new** = only exists as an
idea here; **n/a** = out of the shell's scope (mail/CRM).

| Feature | What exactly | Where it lives today | keep/port/replace | Notes |
|---|---|---|---|---|
| Sway output + workspace snapshot | `swaymsg -r -t get_outputs` ∥ `get_workspaces`, strict JSON validation, dedupe check, filter `output===eDP-1` and `!name.startsWith('__')`, sort by `num` then name; `availability:'unavailable'` + error text when eDP-1 inactive | `platform.ts:45-46` | **keep** | Framework-free (`node:child_process.execFile`, works under Bun). Brief §3.4 wants in-process i3-ipc subscribe; this is the polling baseline until that exists. No herdr status (by design, `:34`). |
| Safe workspace focus | single-flight; selection must be `output===eDP-1` and numeric id; `quotedName` rejects `" \ $ ; ,` control chars, `--` prefix, reserved words `number/next/prev/current/back_and_forth/next_on_output/prev_on_output`; revalidate (`sameWorkspace` on id+name+number+output) → `swaymsg -r -t command 'workspace --no-auto-back-and-forth "<name>"'` → verify `success:true` and focused-after; reports races, never compensates; no `move` | `platform.ts:29,47-52` | **keep** | Extends `herdr-picker`'s `quote_sway` (comment `:27-28`). Tests enumerate 5 stale cases + 10 unsafe names (`platform.test.ts:19,21`). |
| Adapter tests (mocked runner) | 26 bun tests: membership, missing output, malformed IPC, no-move, no-op when focused, stale selections, lower-output rejection, unsafe names, Unicode, duplicates, refusal, post-command change, single-flight | `platform.test.ts` | **keep** | Pure logic, `bun test`, no compositor. Drop into `pkgs/gpuix-shell/src/sway/`. |
| Top-bar workspace buttons | one `Button` per eDP-1 workspace, label = name (or number when `width<900`), `selected={w.visible}`, disabled while focusing/refreshing; status text when empty | `desktop.tsx:50` | **port** | Becomes the rail's 1..9 slots (brief §1 one-to-one herdr mapping); here it's a horizontal top bar (Tom: "no top bar on the Linux head"). |
| Launcher / command palette | `Ctrl/Cmd+K` toggles; `input role=searchbox autoFocus`; commands = apps + `Switch to <ws>` + `Toggle do not disturb` + `Open quick controls`; substring filter on `label detail`; ↑/↓ select, Enter runs `commands()[selected]`, Esc closes; hint line "↑ ↓ Navigate · Enter open · Escape close" | `desktop.tsx:42-43,61` | **port** | Vicinae replacement skeleton. Real sources (apps from .desktop, clipboard, herdr) are new. |
| Panel focus discipline | `open()` records `renderer.getFocusedElementId()`, `closePanel()` restores via `focusElement`; Tab/Shift-Tab inside an open panel use `focusNextWithin/focusPreviousWithin(panelElement.id)` | `desktop.tsx:39-40,43` | **port** | Matches A11Y-02 (menus own focus and return it). Same renderer API exists in 0.10 d.ts (`index.d.ts:111-121`). |
| Window-level keys | `onKeyDown` in `WindowOptions`: desktop dispatcher first, then Tab → `focusNext/focusPrevious` | `main.ts:7` | **port** | Solid wrapper feature; raw host equivalent is `setWindowKeyEvents(true,false,0)` + `windowKeyDown` events (`shared-parity/src/native/main.ts:41,27`). |
| Notifications panel (sample) | list with source·age, title, body; per-item Dismiss; `Clear all` → "You're all caught up." + reset; DND toggle | `desktop.tsx:62` | **replace** | Real daemon lives in `pkgs/desktop-shell/notifications-daemon.ts` (Hyprland shell, not read here). Visual shape reusable. |
| Quick controls (sample) | Wi-Fi/Bluetooth toggle buttons; Volume/Brightness `Range` rows (−/+ 10 steps, 5-px bar); Appearance = 3 palette buttons; Battery 82% text | `desktop.tsx:48,63` | **replace** | All sample state (`"Controls change this preview only."`). Real: `wpctl`, `brightnessctl`, NM/BlueZ via dbus-next (brief §3.4). |
| Palette switch at runtime | `setPalette('claude-light'|'claude-dark'|'noir')` recomputes a role map `t()` | `desktop.tsx:19-20` | **port** | Shell reads `~/.config/theme/gpuix-shell.json` instead; role mapping in §4 is the precedent. MEASURED: dark paint asserted pixel (5,5) == (32,32,31) = `#20201F` (`smoke-native.py:47`). |
| Calendar panel (sample) | Mon-first month grid, prev/next, fixed sample events on 14 Oct | `desktop.tsx:44,64` | **replace/new** | Nothing real behind it. |
| Clock | hardcoded `'Wed 14 Oct · 14:32'` | `desktop.tsx:50` | **replace** | Sample only. |
| Sidebar (220 px) | title=current workspace, "Search anything … Ctrl K", Notes/Mail/People/Calendar rows, "Open in this workspace" (Chrome, Herdr + kitty), "Pinned", footer "Appearance & controls"; Hide/Show | `desktop.tsx:52-53` | **port (shape)** | Closest existing GPUIX precedent to the brief's 220-expanded rail. Content is sample. |
| Status bar (30 px) | DND state left; error/message/status right | `desktop.tsx:58` | **port** | Useful as the rail's footer line. |
| Native text areas / inputs | `<textarea minRows maxRows onChange>` notes; `<input onChange onSubmit autoFocus>` search | `desktop.tsx:54,61`; `email.tsx:90,92,93` | **port** | Proves native text input on Linux (MEASURED by `automation-native.ts:20,23` fill()). |
| SVG icons | inline SVG string per icon, 16×16 stroke 1.2 `<svg source=…>` | `desktop.tsx:12,33`; Octicons in `email.tsx:32` | **port** | Brief wants the "Anthropicons" glyph font; SVG path icons are the proven fallback. |
| Window options | `appId`, `title`, `width/height`, `minWidth 500/minHeight 400`, `resizable`, `windowBackground:'opaque'` | `main.ts:7` | **port** | Layer-shell is **not** used anywhere in either source (README.md:11 "No layer-shell request"). |
| Build | `Bun.build({target:'bun', plugins:[solidPlugin, native-boundary external '@gpuix/native']})` | `build.ts` | **replace** | React build will not need the Solid plugin; the "native external" plugin idea stays. |
| Portable bundle | copy `dist` + the nix-store patched binding; `run` script exports the 10-lib `LD_LIBRARY_PATH`; `nix-closures.txt` for `nix copy` | `package-native.py`, `bundle/run` | **keep (data)** | See §5 for the library list; the Nix wrapper in `pkgs/desktop-shell/default.nix` is the real precedent (not read in this note). |
| Compositor smoke | private headless Sway, grim screenshot, automation driver, dark-pixel assert | `smoke-native.py` | **keep (template)** | §5 has the exact env. Uses `WLR_RENDERER=pixman` and **worked** on 10-14 (MEASURED evidence dirs). |
| Automation driver | `launch({command,args,env})` → `getByTestId().click()/fill()/press()/waitFor()/count()`, `getByType('input')`, `app.call('getAllText'|'getTree')`, `app.close()` | `automation-native.ts` | **keep (API)** | `@gpuix/native/automation`; needs `testId` props on controls. |
| Live-mode fetch mocking | Bun `--preload` replacing `globalThis.fetch`, request log to `TEST_REQUEST_LOG` | `mock-mail-preload.ts`, `smoke-live.py` | n/a (pattern keep) | Pattern for mocking `herdr api snapshot` / NM in smokes. |
| Mail reader (fixtures + live) | two-pane mail, folders, labels, pagination, search debounce 150 ms, abort on change | `email.tsx` | n/a | Shared-utility side; shell only launches mail. |
| OpenUI core-only library | `defineComponent({name,description,props:z.object, component:null})`, `defineAction`, `action()` prop type, `createLibrary({id,root,components,actions})` | `shared-parity/src/openui/contract.ts` | **port** | Define a *shell* vocabulary the same way (§6). |
| Program validation | parse → refuse empty/incomplete/errors/unresolved/orphaned; root must be complete `Reply`; no queries/mutations; forbid `ToAssistant/OpenUrl/Set/Reset/Run` and `Assign`; `evaluateRoot` with `store:null`; every `RunStep` has exactly one `ExecuteStep` whose ids resolve | `host.ts:28-80` | **port** | The "exactly one step per control" rule exists because upstream React does not await custom action callbacks (`docs/native.md:54`). |
| Host-owned action resolution | `resolveStep(event, allowedScenario, state)` rejects unknown names/extra params/other scenario; `stepCommandKey` idempotency key; `dispatchOpenUI` | `host.ts:82-112` | **port** | Shell analogue: resolve `@ShellAction(id)` to a catalog entry (Sway/herdr command), never run free-form. |
| OpenUI → GPUIX tree | `paint()` rebuilds the whole tree: `createElement/setStyle/appendChild/setText/setCustomProp/setEventListener/setRoot/destroyElement`; records as `div` cards with `text` lines; `RunStep` → `div` with `role:button`, `aria-label`, `tabIndex:0`, `autoFocus` when it was the focused label, listeners `click`+`keyDown` | `adapter.ts:89-135` | **port** | Styles hardcoded light (`#f6f5f1`, `#ffffff`, `#242424`, `#e5ebe1`, `#345c88`) — must be themed. Full rebuild per change (`docs/FRAMEWORK-EVALUATION.md:22`). |
| Native event handling | `windowKeyDown tab` ±shift cycles `controls[]` and `focusElement`; activation = `click` button 0 or `keyDown enter/space` not `isHeld`, no ctrl/alt/cmd; `pending` gate; receipts painted as "Host receipt"/"Command unavailable" cards | `adapter.ts:60-87` | **port** | |
| Activity presenter | passive ordered queue: ingest events, `advance()` ≤1 per 600 ms, human input pauses (`pause()` aborts in-flight), F7 single-next, F6 toggle follow; failure re-queues | `activity.ts`, `main.ts:66-78` | **n/a / idea** | For the shell: the same pattern could show "trailing clicks" of an agent (Tom 14:12:30Z). Not critical path. |
| Native entry | `GPUIX_BINDING` path → dynamic import, refuse non-native; `new GpuixRenderer(cb)`; `init({title,appId,width:960,height:900})`; `setWindowKeyEvents(true,false,0)`; `tick()` every 16 ms; evidence JSON dump incl. `getElementBounds`, `getAllText`, `getPaintedText`, `getFocusedElementId` | `main.ts:11-53` | **port** | Also shows the test hooks: `NATIVE_TEST_INPUT` (`simulateKeystrokes`/`simulateClick`), `NATIVE_TEST_COMMAND_FILE` mailbox polled at 100 ms. |
| HTTP gateway client | `createNativeGateway(baseURL, workspaceId, fetcher)` → GET `/api/workspace/snapshot`, POST `/api/workspace/commands`, header `X-Workspace-Id` | `adapter.ts:139-150` | n/a | Domain side; the shell talks to herdr/Sway, not the Worker. |
| Local-model bridge | `/api/model/status` (checks `/v1/models` lists the id), `/api/model/generate` (JSON `{scenarioId,request}` ≤8000 chars → health gate → single generation → NDJSON `{chunk}`/`{done,model}`/`{error}`) | `scripts/local-server.ts:53-116` | **port** | Shell must do this in-process (no local-server): §5.5. |
| SSE parser | `completionChunks(body)`: `data:` lines, skip `[DONE]`, `choices[0].delta.content` → chunk, `finish_reason` → finish, **throws if no finish**, ignores `reasoning_content`; `readEvents(body)`: NDJSON | `src/model/stream.ts` | **keep** | Framework-free, 43 lines, tested (`tests/model.test.ts:15-26`). |
| Model-driven render loop (web) | stream → accumulate `program` → `<Renderer response isStreaming>` → `validateProgram(full)` at end; replay fakes streaming at 35 chars/28 ms; localhost-only model check | `OpenUIChat.tsx:74-100,64-73` | **port (logic)** | React-DOM `Renderer` from react-lang is not usable natively (see §6). |
| Compositor harness v2 | same as 1a plus `WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128`, `WLR_RENDERER=${TEST_WLR_RENDERER:-pixman}`, `LD_LIBRARY_PATH` from `/nix/store/*-<lib>-*/lib` globs, asserts `WAYLAND_DISPLAY`/`SWAYSOCK` unset, node+tsx entry, `NATIVE_EVIDENCE` JSON polling instead of automation | `tests/native-compositor.py:21-36` | **keep (template)** | **The pixman default is a trap** (§6). Use `gles2`. |
| Fake retained host | `RetainedHost.applyBatch` validates op set, parent/child existence, element types ∈ {`div`,`text`}, root presence; tracks destroyed ids and text | `tests/native.test.ts:10-36` | **keep** | Perfect for `bun test` of a shell OpenUI renderer without a binding. |
| Keyboard/a11y chapter | A11Y-01..04 requirement IDs; command registry table (`commands.open` Ctrl/Cmd+K, next/previous, first/last Home/End, activate Enter, `surface.dismiss` Esc); native coverage listed as "unverified" per row | `docs/A11Y-CHAPTER.md:7-30` | **port (requirements)** | The shell's launcher/switcher should satisfy the same rows. |

---

## 4. Design values found (sizes, colours, fonts, radii, timings)

These are the values the 10-14 Solid proof actually painted (MEASURED in the sense that the code is exact; the
PNGs in `/tmp/gpuix-native-comparison-1td9qwjs/{desktop,desktop-dark-controls,mail}.png` show them). They
pre-date the Tacit/SHELLS-DIGEST aesthetic and are **not** the target; they are the proven-renderable baseline.

### 4a. Palette role mapping (`desktop.tsx:20`, source `design/claude-shell-study/src/palettes.json`)

```
canvas     = light ? ground.base : ground.desktop
surface    = ground.raised
subtle     = ground.dim
ink        = fg
muted      = light ? fgDim : comment
line       = border.inactive
accent     = accent
brand      = brand
primary    = light ? '#A74B2F' : brand
primaryInk = light ? '#FFFFFF' : '#131313'
```

Palette values (identical copies at `design/claude-shell-study/src/palettes.json` and
`design/claude-mail/src/palettes.json`, 3579 bytes each):

| role | noir | claude-dark | claude-light |
|---|---|---|---|
| ground.base / desktop / dim / raised | `#000000` ×4 | `#1A1A1A` / `#20201F` / `#151515` / `#20201F` | `#F9F9F7` / `#F0EFEC` / `#F3F3F0` / `#FFFFFF` |
| fg / fgDim / comment | `#EAECF0` / `#D3D7DE` / `#818898` | same | `#131313` / `#52514E` / `#6E7687` |
| border.inactive / active / urgent | `#373735` / `#555451` / `#F47B85` | same | `#D2D1C7` / `#A5A49A` / `#B80A18` |
| accent / brand | `#70B8FF` / `#D97757` | same | `#0051C2` / `#D97757` |
| selection bg / fg | `#264F78` / `#EAECF0` | same | `#CDE2FB` / `#131313` |
| muted (palette key) | `#45475a` | `#52514E` | `#A5A49A` |

The Hyprland desktop-shell's `theme.ts` (`pkgs/desktop-shell/theme.ts:31-49`, imported by `email.tsx:7`)
projects the same JSON into `{background,surface,subtle,foreground,secondary,muted,border,selection,
selectionText,error,accent,brand,primary,primaryText,hover}` with noir fallback `hover:'#37373555'`,
`primaryText:'#131313'`. `parsePalette` only accepts names `claude-light|claude-dark|noir` (`theme.ts:60`).

### 4b. Fonts

- `desktop.tsx:32`: `fontFamily:'Anthropic Sans'`; serif headings `'Anthropic Serif'` (`:54,56`); terminal
  sample `'Anthropic Mono'` (`:55`).
- `pkgs/desktop-shell/theme.ts:26-30`: `fonts = {sans:'Anthropic Sans', mono:'Anthropic Mono', serif:'Anthropic Serif'}`.
- **Discrepancy** with the brief (§1 look): brief names the mono family `"AnthropicMono Nerd Font"`. INFERRED:
  `'Anthropic Mono'` here either resolved through fontconfig aliasing on 10-14 or silently fell back. The
  shell should use the brief's family name and verify with `getPaintedText`/a screenshot.
- Fonts come from the system (fontconfig); `registerFont(bytes)` exists in the 0.11.0 d.ts
  (`/home/tom/Downloads/gpuix/packages/native/index.d.ts:178`) but is unused in both sources.

### 4c. Sizes / radii / type scale (`desktop.tsx`)

| Element | Value | Line |
|---|---|---|
| Top bar | height 44, padding-x 12, gap 14, 1-px bottom hairline, bg `surface` | :50 |
| Sidebar | width 220, padding 12, 1-px right hairline, bg `subtle`; header row 38 | :52 |
| Content tab row | height 42, padding-x 12, hairline | :53 |
| Status bar | height 30, padding-x 16, hairline top, text 11 muted | :58 |
| Button | height 30 (launcher rows 40), padding-x 8, gap 8, radius 8, border 1 (`line`; `accent` when focused; 0 when quiet), hover bg `subtle`, disabled opacity .5, selected weight 600 | :35-38 |
| AppRow | padding 12, radius 6, hover `subtle`, chevron trailing | :46 |
| Section label | padding-top 22, bottom 8, left 8, text 11 muted | :47 |
| Range row | padding-y 18, gap 12, bar height 5 radius 3 (`subtle` track, `brand` fill) | :48 |
| Panel (dialog) | absolute top 20 right 24, width 430, maxHeight `max(180, h-110)`, padding 20, gap 12, border 1, radius 10, bg `surface`, `overflowY:'scroll'`; scrim `#00000025` from y=44 to bottom-30 | :59 |
| Launcher input | height 40, padding 10, radius 6, border 1, bg `canvas`, text 14 | :61 |
| Notes textarea | text 14, lineHeight 24, minHeight 260, `minRows 12 maxRows 20` | :54 |
| Body text | 13 default; muted 11/12; panel title 18/600; page heading 26 serif; terminal 13 mono lineHeight 24 | :32-34 |
| Icons | 16×16 viewBox 16, stroke 1.2, round caps/joins, `currentColor = ink` | :12,33 |
| Narrow breakpoint | `width < 900` → number-only workspace labels, short clock | :17,50 |

Mail window (`email.tsx`): sidebar 220 (`:69`), list column 310 (`:78`), header rows 64/65, list row
min-height 117 (compact 92) padding 17 (`:81`), radius 6 buttons height 32 padding-x 10 (`:66`), reader
body 17 serif lineHeight 27 (`:88`), avatar 34 circle (`:88`), selected-row 3-px `brand` left bar.

### 4d. Window / timing

- Default window request 1000×900, min 500×400, resizable, `windowBackground:'opaque'` (`main.ts:7`);
  test sizes 1080×900 and 720×900 (README.md:21), Sway tiles them anyway.
- Solid proof pumps `native.tick()` every **500 ms** (`main.ts:10`); shared-parity pumps every **16 ms**
  (`src/native/main.ts:51`). INFERRED: on Linux `tick()` only reports liveness (d.ts:75-77), so the
  interval is a process-exit latency, not a frame rate.
- Launcher search debounce: none (filter is a memo). Mail live search debounce 150 ms (`email.tsx:55`).
- shared-parity adapter: snapshot poll 400 ms, activity advance 600 ms, test-command poll 100 ms
  (`main.ts:72,78,81`); replay typewriter 35 chars / 28 ms (`OpenUIChat.tsx:69-72`).
- shared-parity native window: 960×900, `appId 'shared-parity-openui'`, title `'Shared workspace — OpenUI / GPUIx'` (`main.ts:39`).
- Headless test outputs: `HEADLESS-1` 1080×900 (10-14) / 1080×1000 (10-20), bg `#F9F9F7` solid (10-14 only).

### 4e. Adapter (shared-parity) hardcoded colours — to be replaced by theme tokens

`adapter.ts:100-101,106,119`: page `#f6f5f1` padding 24 gap 12; record card `#ffffff` radius 8 padding 16
gap 8; text `#242424` 15 px; button `#e5ebe1` (pending `#dddddd`) radius 6 padding 12; focus border 2 px
`#345c88` + `focusVisible:{outlineWidth:2,outlineColor:'#345c88'}`.

---

## 5. Reusable code and data, with exact paths

### 5.1 Sway capability adapter — reuse as-is

- `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/platform.ts` (54 lines, framework-free).
  Public surface: `createSwayCapabilities({output?, run?}) → {snapshot(), focusWorkspace(selection)}`;
  types `WorkspaceSelection`, `DesktopWorkspace`, `DesktopOutput`, `DesktopSnapshot`,
  `DesktopCapabilities`, `DesktopCommandRunner` (`:4-15`).
- `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/platform.test.ts` (26 tests, `bun:test`,
  mocked `run`). Fixture at `:5-9` shows how to fake `swaymsg` replies including the `command` echo.
- Copy target (INFERRED from brief §4): `pkgs/gpuix-shell/src/sway/capabilities.ts` + `capabilities.test.ts`.
  Keep the `run` injection; the shell's rail will add a `swaymsg -t subscribe -m '["workspace","output"]'`
  stream later and call `snapshot()` on each event instead of polling.
- Known limits to carry into ASSUMPTIONS.md: no workspace creation, no `move`, no `Mod+0`/eDP-2 handling
  (the adapter *refuses* lower-display selections, `:48`), no herdr status, 4-s `execFile` timeout.

### 5.2 Isolated-compositor harness — exact recipe

Wrapper (required): `/home/tom/.wt/hyprland-solid-shell/home/dot_local/bin/runtime-test` (bwrap:
`--unshare-user --unshare-pid --unshare-ipc --bind / / --proc /proc --dev /dev --tmpfs /run/user`, unsets
`DBUS_SESSION_BUS_ADDRESS, DBUS_SESSION_BUS_PID, NOTIFY_SOCKET, WATCHDOG_*, WAYLAND_DISPLAY, DISPLAY, SWAYSOCK,
I3SOCK, HYPRLAND_*, SSH_AUTH_SOCK, PULSE_SERVER`; `--render-node /dev/dri/renderD128` dev-binds exactly that
node after checking it is a char device with major `0xe2` and minor ≥128, `:31-44`). The installed
`~/.local/bin/runtime-test` on strix has **no** `--render-node` (MEASURED: grep empty) — copy the worktree
version into this branch as the brief says.

Invocation (shared-parity, `docs/native.md:41-45`):

```sh
WORKSPACE_GATEWAY=http://127.0.0.1:4321 \
TEST_WLR_RENDERER=gles2 TEST_NATIVE_INPUT=keyboard \
/home/tom/.wt/hyprland-solid-shell/home/dot_local/bin/runtime-test \
  --render-node /dev/dri/renderD128 -- python3 tests/native-compositor.py
```

Inside the harness (`tests/native-compositor.py:21-36`, and `smoke-native.py:20-29` for the 10-14 variant):

| Step | Exact value |
|---|---|
| Preconditions asserted | `$XDG_RUNTIME_DIR/bus` absent; `/dev/input` absent; `WAYLAND_DISPLAY` and `SWAYSOCK` unset |
| Sway binary | `/nix/store/04g9x522ddd3hi77v013n97li9ccyrhd-sway-1.12/bin/sway --unsupported-gpu -c <conf>` (swaymsg beside it) |
| grim | `/nix/store/7scglgqhmxl5gj585y0h2nq699rspg4g-grim-1.5.0/bin/grim -o HEADLESS-1 out.png` |
| sway.conf | `output HEADLESS-1 mode 1080x1000` (10-14: `mode {w}x900 bg #F9F9F7 solid_color`) / `xwayland disable` / `seat seat0 fallback true` / `default_border none` |
| Env | `WLR_BACKENDS=headless` `WLR_HEADLESS_OUTPUTS=1` `WLR_RENDERER=<see below>` `WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128` `WLR_LIBINPUT_NO_DEVICES=1` `SWAY_DISABLE_SD_NOTIFY=1` `DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent-test-bus` `DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent-system-bus` `XDG_CURRENT_DESKTOP=sway` `VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json` `NODE_ENV=test` |
| LD_LIBRARY_PATH | globbed `/nix/store/*-{libxkbcommon,wayland,vulkan-loader,fontconfig,freetype,libGL,libX11,libxcb,openssl}-*/lib` (10-20); or the exact 10-lib list from `bundle/run` (10-14, §5.4) |
| Wait for | `$XDG_RUNTIME_DIR/sway-ipc*.sock` → `SWAYSOCK`; first `wayland-*` socket → `WAYLAND_DISPLAY` (150 × 0.1 s) |
| Launch app | 10-20: `node --import tsx src/native/main.ts` with `GPUIX_BINDING=/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/node_modules/@gpuix/native/index.js`; 10-14: `bundle/run <mode>` (bun + patched binding) |
| Mapped check | `swaymsg -r -t get_tree`, walk `nodes`+`floating_nodes`, find `app_id` |
| Screenshot | sleep 1–2 s then grim; dark-palette pixel assert `(5,5)==(32,32,31)` after `Claude Dark` click (`smoke-native.py:46-47`) |
| Input | 10-14: `@gpuix/native/automation` (`launch`, `getByTestId`); 10-20: in-process `renderer.simulateKeystrokes('tab'|'shift-tab'|'enter')` at 150 ms spacing or `simulateClick(cx,cy)` (`src/native/main.ts:56-64`), and a JSON "mailbox" file for later keys (`:81-84`) |
| Evidence | per-run `tempfile.mkdtemp(prefix=…)` with `sway.log`, app log, PNGs, window JSON, `result.json` |
| Cleanup | terminate app then sway, `wait(timeout=5)`; only own children |

**The WLR_RENDERER lesson (MEASURED both ways):**

- 10-14, `smoke-native.py:24`: `WLR_RENDERER='pixman'` — both windows painted and automation passed
  (`/tmp/gpuix-native-comparison-1td9qwjs/results.json ok:true`). The app log shows
  `libEGL warning: failed to get driver name for fd -1` / `MESA-LOADER: failed to retrieve device information`
  but the window mapped (`desktop.log:1-2`).
- 10-20, `tests/native-compositor.py:30` defaults to `pixman`: the native binding died at `renderer.init` with
  `wgpu_hal::vulkan::swapchain::native ERROR_SURFACE_LOST_KHR` → `Failed to open the GPUI window: No GPU
  adapter found that can configure the display surface` (`evidence/native/failure-pixman/native.log:1-9`).
  Re-run with `TEST_WLR_RENDERER=gles2` succeeded (`docs/native.md:35`; manifest scope "private Sway GLES2 +
  renderD128").
- INFERRED differences between the two pixman runs: 10-14 used Bun + the nix-store *autoPatchelf'd* binding
  from `desktop-shell-0.1.0` with the explicit 10-lib path; 10-20 used Node 24 + the raw `node_modules`
  binding with globbed libs and added `WLR_RENDER_DRM_DEVICE`. I cannot tell which factor flipped it.
  **Rule for tonight's harness: default `WLR_RENDERER=gles2` with `WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128`,
  keep `pixman` as an opt-in**, and record the renderer in `result.json`.
- Also retained: `failure-compositor-cursor` — injecting pointer motion through the compositor did not
  deliver input; the in-process `simulateClick` path did (`docs/native.md:33`). Don't spend time on
  compositor-side cursor injection.

### 5.3 OpenUI lang-core → GPUIX MutationHost mapping (what to copy)

Contract (`shared-parity/src/openui/contract.ts`): nine components, one action.

| OpenUI component | props | Native mapping today (`adapter.ts`) | Shell relevance |
|---|---|---|---|
| `Reply` (root) | `title`, `children: array(union of refs)` | `div` column, padding 24, gap 12, scroll; optional activity-status line; title text | Root container pattern. |
| `Note` | `text` | `text` | Prose. |
| `ContactRecord` / `MailRecord` / `ProjectWork` / `DraftRecord` / `RoutineRecord` / `ReportRecord` | `id` | record card: `div` + heading + lines looked up in host state; "not found" text when id unknown | Pattern: *host-resolved record by id*; shell analogue = `WorkspaceCard(id)`, `AgentCard(id)`, `NetworkCard(ssid)`. |
| `RunStep` | `label`, `action: action()` | `div` with `role:button`, `aria-label`, `tabIndex 0`, `autoFocus` if previously focused, listeners `click`/`keyDown`; events = `steps.map({type:name, params})` | The *only* interactive element; exactly one `@ExecuteStep(scenarioId, stepId)` per control. |
| action `ExecuteStep` | `{scenarioId, stepId}` | host resolves to a catalog step, dispatches a typed command, paints receipt | Shell analogue = `@ShellAction(actionId)` resolved against the command registry (`herdr workspace focus`, `swaymsg workspace`, `nmcli …`). |

Evaluator call to replicate (`host.ts:50-62` and `adapter.ts:91-92`):

```ts
const parsed = createParser(library.toJSONSchema(), library.root).parse(program);
const errors: OpenUIError[] = [];
const root = evaluateRoot(parsed, {
  library, store: null, errors,
  ctx: { getState: n => parsed.stateDeclarations[n] ?? null, resolveRef: () => null,
         actions: library.toJSONSchema().actions, functions: library.functions },
});
// root: {type:'element', typeName, props:{…, children?: Element[]}}; RunStep.props.action.steps[]
```

Mutation ABI (0.10, `index.d.ts:47-56`): `createElement(id,type)`, `destroyElement(id)`,
`appendChild(parent,child)`, `insertBefore(parent,child,before)`, `setStyle(id,{…})`, `setText(id,s)`,
`setEventListener(id,eventType,bool)`, `setRoot(id)`, `setKeyboardFocusDim(bool)`, `setCustomProp(id,key,v)`.
Event payloads seen: `click{button}`, `keyDown{key,isHeld,modifiers}`, `windowKeyDown` (needs
`setWindowKeyEvents(true,false,0)`). Element types used natively: `div`, `text`; GPUIX also documents
`input`, `textarea`, `svg`, `code`, `markdown`, `diff`, `virtual-list` (README.md:33 of gpuix-comparison;
tag counts in `/home/tom/Downloads/gpuix/README.md`).

Under React (brief §3.1) the adapter's `paint()` becomes a pure function `elementToJsx(root)` returning
`@gpuix/react` host elements (`<div style>`, `<text>`, `<input>`), with `RunStep` → a focusable `<div
role="button" tabIndex={0} onClick onKeyDown>` exactly as `desktop.tsx:37` does in Solid. The validation
(`validateProgram`) and resolution (`resolveStep`) stay framework-free and are reused verbatim. INFERRED;
not demonstrated anywhere yet — `docs/FRAMEWORK-EVALUATION.md:12` says explicitly "Today's new native proof
bypasses both framework adapters".

Streaming semantics to respect (`docs/openui-method.md:99-101,105`): at stream end the result must equal a
batch parse; no actions during streaming (custom controls must check `useIsStreaming()`/your own flag);
parser is permissive, so a visible card is not acceptance — run `validateProgram` on the final text.
Positional prop order is the ABI (`:119`); never reorder props of a shipped component.

### 5.4 Native binding, libraries, packaging data

- Only installed binding on strix: `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/node_modules/@gpuix/native/index.js`
  (0.10.0) + `@gpuix/native-linux-x64-gnu`; patched copy inside
  `/nix/store/pwp11p3rnmwygrykblk3rr3331mw4k4h-desktop-shell-0.1.0/lib/desktop-shell/node_modules/@gpuix`
  (`package-native.py:6,16`). 0.11.0 is on npm (brief) but **unproven here**.
- `LD_LIBRARY_PATH` the binding needs (from the Nix wrapper, `bundle/run`): openssl-3.6.3, libxcb-1.17.0,
  libx11-1.8.13, libglvnd-1.7.0, freetype-2.14.3, fontconfig-2.18.1-lib, vulkan-loader-1.4.350.0,
  wayland-1.26.0, libxkbcommon-1.13.2, gcc-15.3.0-lib — exact store paths in
  `design/gpuix-comparison/bundle/nix-closures.txt`. This is the `buildInputs`/wrapper list for
  `pkgs/gpuix-shell/default.nix` (brief §3.9 says model it on `pkgs/desktop-shell/default.nix`, which I did
  not read).
- Bun build: `design/gpuix-comparison/build.ts` (`target:'bun'`, `@gpuix/native` external).
- Known journal noise (REPORTED, README.md:31): `gpui_linux::linux::wayland::client` errors "failure to turn
  the loopback preview URL into a file path" and "relative URL without a base" on 10-14 01:35:08 client time,
  cause unknown; URL/drop handling never validated.

### 5.5 Local-model streaming call (exact shape)

`scripts/local-server.ts:88-98` (REPORTED working against strix; MEASURED one generation in
`evidence/model/probe.json`, 3271 ms, `halogen-qwen3.8-flash-next`):

```ts
await fetch(`${modelBase}/v1/chat/completions`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' /* + Bearer if apiKey */ },
  signal: controller.signal,                       // 90 s timeout, aborted when client disconnects
  body: JSON.stringify({
    model: 'halogen-qwen3.8-flash-next', stream: true, temperature: 0, max_tokens: 1800,
    enable_thinking: false, chat_template_kwargs: { enable_thinking: false },
    messages: [
      { role: 'system', content: workspacePrompt },             // library.prompt({preamble, additionalRules})
      { role: 'user',   content: `${generationContext(scenario)}\n\nCurrent request: ${input.request}` },
    ],
  }),
});
for await (const ev of completionChunks(upstream.body)) { /* ev.chunk | ev.finish */ }
if (finish !== 'stop') throw …; if (program.length > 32_000) throw …;
```

Guards worth keeping in-process in the shell: `GET /v1/models` must list the model id (`:56-58`);
`GET /health` → refuse (409) when `busy || in_flight>0 || queued>0` (`:73-80`) — "The existing model server
is busy. This example will not join its queue." (the strix model is shared with herdr agents); one
generation at a time; 8000-char request cap; `enable_thinking:false` both top-level and in
`chat_template_kwargs` (the test asserts the former, `tests/model.test.ts:52`).

Prompt construction: `library.prompt({preamble, additionalRules})` (`src/openui/library.tsx:112-120`) and
`generationContext()` = JSON of `{request, scenarioId, availableSteps:[{id,label,action}], records:{…},
example: exampleProgram(scenario)}` (`programs.ts:53-65`). The accepted program the model produced:

```
root = Reply("Ada's contact and correspondence", [
  ContactRecord("contact-ada"),
  MailRecord("mail-web-first"),
  RunStep("Read linked contact", @ExecuteStep("correspondence", "context"))
])
```
(`evidence/model/generated.openui`, 193 chars.)

Parsers to copy verbatim: `/home/tom/tuesday-oct20/build/shared-parity/src/model/stream.ts`
(`completionChunks`, `readEvents`).

### 5.6 Test fakes and automation

- `tests/native.test.ts:10-36` `RetainedHost` — copy into `pkgs/gpuix-shell/src/openui/host.test.ts`.
- `tests/native-activity.test.ts` — pattern for pause/abort tests if the shell ever shows agent "trailing clicks".
- `design/gpuix-comparison/automation-native.ts` — `@gpuix/native/automation` driver usage.

---

## 6. Gaps, unknowns and what is missing for a shell `ask` surface

### 6.1 Hard gaps (block or shape the build)

1. **No layer-shell precedent in either source.** Both proofs are xdg toplevels (README.md:11; pointer-local
   `result.json` `shell: xdg_shell`). The `LayerShellOptions` API exists in the 0.10/0.11 d.ts
   (`index.d.ts:678-714`: `namespace, layer, anchor[], exclusiveZone, exclusiveEdge, margin[4],
   keyboardInteractivity`) but nothing here has ever opened one under Sway. First smoke tonight must be a
   bare layer surface (`anchor:['left','top','bottom'], exclusiveZone:56, layer:'top'`) and a
   `get_tree`/`get_outputs` check that Sway reserved the zone.
2. **`@gpuix/react` is not installed anywhere on strix**; only 0.10.0 `native`/`solid`. React + 0.11.0 is a
   fresh `npm install` (registry reachable per brief) — expect the autoPatchelf step from
   `pkgs/desktop-shell/default.nix` to be required before any smoke runs.
3. **Pixman vs GLES2 is unresolved** (§5.2). Default the new harness to `gles2`; if it fails on the Zenbook
   (different GPU/ICD; `VK_ICD_FILENAMES` is the radeon ICD here), fall back to `pixman` and record which.
4. **Adapter is light-only and unthemed** (`adapter.ts:100-119`): everything must route through the
   `gpuix-shell.json` tokens (noir default).
5. **Mono font family name** mismatch (`'Anthropic Mono'` vs brief `"AnthropicMono Nerd Font"`); verify by
   paint.
6. **Sway adapter is top-display-only and polling**: no eDP-2 / workspace 10, no subscribe, no herdr status.
   Fine for Mod+i switcher; the rail needs a herdr snapshot merge (`herdr api snapshot`) that this source
   never had (`platform.ts:34` "No … inferred Herdr status").

### 6.2 What is missing for `gpuix-shell ask` (brief §3.7)

The shared-parity native proof renders *supplied* programs and actions; "a complete native chat
composer/navigation shell is not implemented" (`docs/native.md:48`). To get a shell "ask" surface:

| Missing piece | What exists | What to build (INFERRED, minimal) |
|---|---|---|
| Shell OpenUI vocabulary | workspace-domain library (contacts/mail/projects) | `shell.v1` library: `Reply(title, children)`, `Note(text)`, `WorkspaceList()`/`WorkspaceCard(name)`, `AgentCard(workspace)`, `NetworkList()`, `DeviceList()`, `Status(text)`, `RunAction(label, @ShellAction(id))`. Define with `component:null` core-only, exactly like `contract.ts`. |
| Host action catalog | `scenarios[].steps` fixtures + `resolveStep` | A typed registry `{id, label, run(): Promise<Receipt>}` of Sway/herdr/nmcli/bluetoothctl commands the shell already wraps (brief §2 scripts table). `validateProgram` keeps "exactly one `@ShellAction` per control", refuses `OpenUrl/ToAssistant/Set/Reset/Run` and `Assign`. |
| Prompt + context | `library.prompt({...})`, `generationContext()` with record ids | Context = current `snapshot()` of Sway workspaces, herdr workspace/agent list (names + statuses ◉◐●✓○), available action ids. Keep "never invent ids" rules. |
| Model transport in-process | `scripts/local-server.ts` (separate Node server) + `src/model/stream.ts` | Call `http://127.0.0.1:8731/v1/chat/completions` directly from the `ask` process with the §5.5 body; keep health/busy gate; cancel on Esc. |
| Streaming render natively | Web: `<Renderer isStreaming>`; native: `show()` only after full validation (`adapter.ts:38-44`) | Use `createStreamingParser(schema, root).push(chunk)` (lang-core d.ts:744) and render the partial `root` with controls disabled until `finish==='stop'` and `validateProgram(full)` passes (parity with OpenUI's "no actions while streaming" rule). Partial render is **not** demonstrated natively anywhere here. |
| Text input / composer | Native `<input>`/`<textarea>` proven in Solid (`desktop.tsx:61`, `email.tsx:93`); raw MutationHost path never created an input | Under `@gpuix/react` use `<input autoFocus onChange onSubmit>`; under raw host, `createElement(id,'input')` + `setEventListener('change'|'submit')` is UNVERIFIED. |
| Window | 960×900 xdg toplevel | Overlay layer surface, keyboard `exclusive`, Esc closes, same geometry family as the launcher (brief §3.3). |
| Receipts | "Host receipt"/"Command unavailable" cards | Same; plus a "Nothing was executed" line while streaming (A11Y: `role=status`). |
| react-lang in the shell | web `Renderer` auto-mounts a devtools widget and can load a CDN bundle in development (`docs/openui-method.md:130`) | Do **not** import `@openuidev/react-lang` in the shell; use `@openuidev/lang-core` + own React element mapping. Avoids DOM assumptions and the bootstrap side effect. |
| Union/strict-object validation | Measured limit: discriminated unions and strict-object extra fields can slip through the parser (`openui-method.md:111`) | Keep host-side `resolveStep`-style checks on every action param; never trust parser acceptance. |

Not critical path (brief §3.7): "the core shell must stand without it". Suggested order: shell vocabulary +
validator (bun tests with `RetainedHost`) → direct model call with the saved `generated.openui` as a replay
fixture (`OpenUIChat.tsx:64-73` replay pattern) → one compositor smoke rendering a fixed program in an
overlay layer surface → only then live generation.

### 6.3 Unknowns I could not settle from these sources

- Whether `@gpuix/react` 0.11.0's reconciler issues the same mutation tuples (it should by design,
  `FRAMEWORK-EVALUATION.md:8`), and whether `layerShell` works through it on Sway. Nobody has run it.
- Why Ctrl +/− zoom is not registered in GPUIX (Tom, 2026-10-13 23:45:17Z) — never investigated in these files.
- Whether `getAllText()`/`getPaintedText()` see text inside `<input>` (d.ts:343 says only `<text>` nodes for
  `getAllText`); the 10-14 automation used `getAllText` after `fill()` and passed, so inputs' *results*
  (filtered lists) are visible, the input value itself maybe not.
- Screen-reader/AT-SPI behaviour on Linux: "unverified" in every doc (`native.md:19`, `A11Y-CHAPTER.md`).
- The 10-14 client journal URL errors (§5.4) — origin unknown.
- Whether the 10-14 `/tmp` evidence survives a reboot (it is `/tmp`); the 10-20 evidence is inside the
  shared-parity repo and will survive.
- `pkgs/desktop-shell/default.nix`, `ui.tsx` (1300+ lines), `notifications-daemon.ts`, `singleton.ts`,
  `controller.ts` were **not** read for this note (another wave-1 reader owns `dig/05-gpuix-shell-state`);
  cross-check before deciding what the notifications daemon and theme loader already do.

### 6.4 What I did and did not do

- Read every file the task listed, plus: `platform.test.ts`, `automation-*.ts`, `smoke-live.py`,
  `mock-mail-preload.ts`, `package.json`/`tsconfig.json`, `palettes.json`, `pkgs/desktop-shell/theme.ts:1-80`,
  `scripts/local-server.ts`, `scripts/probe-model.ts`, `tests/model.test.ts`, `tests/native-activity.test.ts`,
  `docs/{VALIDATION,BUILD-MAP,A11Y-CHAPTER(head)}.md`, evidence manifests/logs, the runtime-test wrapper, the
  gpuix 0.11 `index.d.ts` (`GpuixRenderer`, `LayerShellOptions`, `WindowOptions`), lang-core's export list.
- Extracted Tom's verbatim turns from the Codex rollouts with a small script
  (`/tmp/claude-1000/…/scratchpad/codex-user.py`); the Claude-side transcripts named in the brief contained
  no additional user turns about OpenUI/GPUIX beyond the brief's own quotes.
- Ran nothing: no compositor, no bun/node, no model call. All MEASURED labels refer to files and evidence
  already on disk; all behaviour claims about running code are REPORTED from the sources' own docs/tests.
- Wrote only this file.
