# 08 - Transcript read: today's OpenUI + GPUIx "shared parity" build (2026-10-20)

Reader note for the gpuix-shell overnight build. Written 2026-10-20/21 by one wave-1 reader (Claude, Fable 5.1). Read-only pass; nothing outside this file was written. Labels: MEASURED = I read the bytes myself (file, line, timestamp); REPORTED = an agent in the transcript said it and I did not re-run it; INFERRED = my reading of what it means for the shell builder.

All timestamps in the transcripts are UTC (`Z`). Paris on 2026-10-20 is CEST = UTC+2. Tom's "~22:50 CEST" order in BRIEF.md is therefore ~20:50Z, hours after everything read here.

---

## 1. What this source is

Three files were assigned. Two of them are the build; the third turned out to be unrelated.

| File | What it is | Span (MEASURED) | Relevance |
|---|---|---|---|
| `/home/tom/.codex/sessions/2026/10/20/rollout-2026-10-20T14-07-00-01a15935-302b-7df1-bd01-591deddb596c.jsonl` (18.1 MB, 4585 lines) | Codex 0.160.0 root session "GPT-6", cwd `/home/tom/tuesday-oct20`. Starts on Tencent memory models, drifts through "reusable toolkit / dematerialize", a 1-hour project-contracts assessment (4 investigators), then at 13:58Z Tom orders the 1-hour OpenUI + GPUIx parity build. 20 user turns (last at L3470, 14:22:36Z); final assistant report L4582 at 14:58:47Z. | 12:07:18Z to 14:58:47Z | The order and the architecture talk are here (root agent) |
| `/home/tom/.codex/sessions/2026/10/20/rollout-2026-10-20T14-10-23-01a15938-4949-7002-81ee-a5ed2bf233d3.jsonl` (17.4 MB, 3377 lines) | Codex subagent "Wegener" (`agent_path /root/notes_history`), forked from the root at 12:10Z with the first 3 user turns replayed. It did the OpenUI source inspection (L2203 onward) and the entire **native GPUIx lane** (L2654 to L3354). Its task payloads from the root are `encrypted_content` blobs (MEASURED, L2198, L2400 ...), so the exact orders it received are not readable; its tool calls and outputs are. | 12:10:23Z to 14:55:16Z | The native build: what ran, what failed, what worked |
| `/home/tom/.claude-work/projects/-home-tom-tuesday-oct20/4253a15b-0dde-4bf1-95c4-a1509cab048a.jsonl` (2.2 MB, 530 lines) | Claude Code session (cc2 seat) about **Frank's Mac SSH access, estate mapping and the overnight Frank kits**. Eleven user turns, none about the shell. The word "sway" occurs only as "open herdr sessions on my sway" (L5). "gpuix" occurs 29 times and "openui" 8 times, all inside tool outputs (`project memory show desk`, `start.md`, FRANK-NEXT-DAYS.md reads), never in a Tom turn of this session. | 14:26:13Z to 16:40:33Z (compaction summary at L513) | **Not a shell source.** BRIEF.md lists it under "Transcripts (what Tom said)"; the builder should not expect shell rulings in it. Its embedded second-hand quotes are listed in section 2.4 for completeness. |

Helper used: `python3 /tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/transcript-text.py` prints zero USER turns for the Codex 0.160 rollout shape (MEASURED: user text is `response_item` / `message` / `role:user`, not `event_msg` / `user_message`). I wrote a sibling `cx.py` in the same scratchpad that handles it (`--roles USER,ASSISTANT,AGENT,TOOL,CTOOL,TOUT,CTOUT --grep RE --from L --to L`). Next readers of Codex rollouts should use that one.

The build's own on-disk artefacts (all MEASURED, read directly):

- Prototype: `/home/tom/tuesday-oct20/build/shared-parity/` (git, last commit `3f4918b Update Site source`; `package.json` name `agency-shared-parity` 0.1.0; deps `@openuidev/lang-core` 1.0.1, `@openuidev/react-lang` 1.0.1, `react` 19.2.3, `zod` 4.3.6; dev `wrangler` 4.151.3, `@playwright/test`, `tsx`, `vite` 7, `esbuild` 0.25.12).
- OpenUI upstream clone: `/home/tom/tuesday-oct20/build/shared-parity-reference/openui` pinned `9823ec05d4b29bc78d101676dc16b44fe17f1830` (2026-10-19, MIT).
- Build report: `/home/tom/tuesday-oct20/reports/shared-parity-2026-10-20/BUILD.md` (hour ran 13:58:14Z to 14:58:34Z, 3620 s; 3 specialist agents + root).
- Tom's own note that triggered it: `/home/tom/tuesday-oct20/desktop-ui.md` (13 lines, mtime 2026-10-20 10:45:27 +0200 = 08:45Z).
- Hosted private demo (REPORTED): `https://agency-shared-workspace.civil-tick-1539.chatgpt.site` (owner-private OpenAI Sites deployment, `appgdep_6ad78018ecc48191b2cad4bf602dbb4d`). Not Cloudflare; not reachable without Tom's account.

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with dates)

### 2.1 The note that frames everything: `desktop-ui.md` (2026-10-20 08:45Z, MEASURED, lines 1 to 13)

```
https://github.com/remorses/gpuix#gpuix
and not sure if related:
https://github.com/khromov/gpuix-svelte

the GPUIX project was analyzed in the past and i found that it was the best possible tool to base my project on when it comes to building front-ends.
it would make us completely agnostic to building native linux wayland (thomas); macos (marwan); AND web (frank).

the only boundary being of course the desktop shell, which would be exclusive to wayland-on-sway wm.

the MASSIVE finding of the last few days:
`https://github.com/thesysdev/openui` this openui project has the generative-ui philosophy that is exactly what i can use to have fully uniform deployments. extremely desirable, as i will have the same llm generate all the front-end tooling, starting from my desktop shell all the way to webapps like email etc.

we build it once and it can be exported everywhere.
```

This is the source of "the three heads": **wayland/Sway native = Thomas, macOS native = Marwan, web/Chromium = Frank** (lines 6 to 8). The desktop shell is "exclusive to wayland-on-sway wm" (line 8) and is "the only boundary" to the agnostic build (INFERRED: everything else is shared). Line 11 is the strongest statement that OpenUI is meant to reach the shell too: "the same llm generate all the front-end tooling, starting from my desktop shell all the way to webapps".

### 2.2 The boundary ruling of record (desk thread T-38, two Tom messages, MEASURED in `/home/tom/tuesday-oct20/research_notes/Project contracts and implementation assessment/evidence-project-state/desk-T-38-2026-10-20.json`)

T-38 msg `01M51W9MQG4WEDAT30CTVXEYCP`, 2026-10-16T08:12:14Z (json line 36):

> "anyway, you are more high level than this. you see the specific integration point, we have a very clear separation of concerns being gpuix-specialized entire wayland shell and programs (email, crm, etc "a la Vesence") that are alos macos specific; all on the github+cloudflare+ai harness model. herdr-centril all the way, how hersr-web-ui is decomposed eg the leftbar becomes sway compatible. the nuance is that gpuix-shell is for ME and the substrate actual tooling is exported to macos native etc. by design. subagents must deliberte ont hius line (what goes in poersonal nixos dotfiles fleet vs external tooling that goes in agency gh org ; i already did that wiht email and crm i think)"

Same message, earlier sentence (shell-relevant inspiration list): "i really liked the claude explanaitpon ofhow the claude chrome extension works ... as well as the "CUA computer use" and the "recall / rewind" stuff that actually all contain some ideas that we can styletransfer. one of these oss projects was wayland specialize.d".

T-38 msg `01M5CK5ACW36T6N0XVWX2B7ZDF`, 2026-10-20T12:04:14Z, via Claude session `1a517fb2-dbee-4524-a95c-dd798bcc78b0` (json line 66):

> "now orthogonally to that, the agency.agency prject becomes something i have concwptiaalized for uqite some time now:
> a unified gppuix to linux program ; macos program ; AND browser webapps tjhat work on chromium ALLL IN ONE
>
> openui https://github.com/thesysdev/openui as the toolking that grows with us (instead of a prefactirated https://gpui-kit.com/ )
> this is a shared project on the frontend; and building with the same root will be desirtable
>
> for my own personal usahgge, on swaywm, we havwe a saister project that is a gpuix shell that is no-quickshell (yhet we benefit from all the fresearech we had done in previous attempts at b uilding my personal ultimate shell from quckshell omarhcy; noctalia;l dankmaterialshell etc) this is a SEPARATE project that uses the same kernel and has its learnngs feed into this project
>
> being shortcut-vased (as one of the latest chats would have had given us) is also important to xconsider from the get go on this unifidd deskotp os.
>
> we have 3+ users (thomass , marwan, frank) at minimum so building a high quality polished product that s repeatable is highly desired)"

Builder reading (INFERRED): "gpuix shell that is no-quickshell", "SEPARATE project", "uses the same kernel", "learnings feed into this project [agency.agency]", "shortcut-based from the get go". OpenUI is named over gpui-kit as the component toolkit "that grows with us".

### 2.3 Tom's turns in the Codex root session (MEASURED, file A, `L` = jsonl line)

| When (UTC) | Line | Verbatim |
|---|---|---|
| 13:44:01 | L2405 | "what ahould i show to frank" |
| 13:47:28 | L2484 | "right. we drew the boundary of things that are my own versus things that we can all use are: the gpuix local shell. and that has been scoped very well previopusly" |
| 13:58:10 | L2653 | "1 hour continuous time: i want to show him a simplified: chatui, crm, email, and many others> \|important: git clone and follow the methodloogy of openui which was referred to in the files i found / it's important that we stsett building the parity enfgine with real use cases freo mthe getgo" |
| 14:10:31 | L3030 | "talk to me while the subagents have their tasks: gpuix to cloudflare workers-compatible usage? mcp codemode through a dedicated server? i m thinking that the very same mcpcodemode tool that would gwet deployed would also be that unified web inerface. useful to go through the "old days" of cloudflre OS, the fgateway system, the "gadget" systenm" |
| 14:12:30 | L3126 | "understand again: it is important that fron t end we buikld built from the ground up with openUI methodology AND thezhortcut driven method as well (so that my human clicks on the webUI is the same as an agwent's usage of the api with "trailing clicks" happening by another aent thst just shows what is being worked through. / the above being the final desired design implementation. just building yet anoter email frontend now without accumulating these insights and making it parity between gpuix and cf worker (webui) accessible for frank has no use" |
| 14:22:36 | L3470 | "we will "find the ideal tool" to write gpuix plus cf workerd deployed as we go. react , solidjs (leaning towards react). what about the 'kb shortcut accessibility feautre" cha[ter?" |

Earlier turns in the same session that are context, not shell rulings (MEASURED): L9/L49 Tencent Hy-Memory and TencentDB-Agent-Memory; L97 "i explicityl decided not to use claude agent harness built in memroy ( it s disabled) opting for a "nightly harvest" nmodel"; L251 "right now the herdr workspaces on sway on clioent (read each to get a sense) all contain inforkmation; asks and prompts that will likely never be implemented"; L463 "encapsulate proctices i do over and over like "dematerialize/decoule" or styletransfer out some specific functiuonality that i see in a given agentiic harness and add it to my own toolkigt"; L561 spec.md per tool "like how terminal OZC sequences are explained"; L808 "deploy 1 hours worth of compute ... full spec sheets (inspired by terminal osc 99 for example) instead of having a stainless api"; L1473 "there are several other open herdr workspaces on my swaywm from client. those are all ongoing work, some of them mid-sessiob limit reset in 2hrs or so".

Standing rules the root agent re-read and applied (REPORTED, A L2656, L3236): preserve the personal-shell boundary, preserve ongoing Herdr sessions, run every compositor/runtime test under `runtime-test`.

### 2.4 Second-hand Tom quotes embedded in the Claude (Frank) session's tool outputs (REPORTED; they come from `project memory show desk` and desk thread reads, not from Tom in that session)

- 2026-10-14 (file C, L42, memory listing): Tom: "we did some prototyping aroudn gpuix and found that it can very well be the foundation we have been lookingfor" and "otto as inspiration, we remain on sway window manager however". Same line: "for the launcher, feature parity at least with vicinae (already enjoyed on my setup) including how it interacts w google chrome tabs is very desirable".
- 2026-10-17T00:45:54Z (file C, L137, desk thread): Tom: "we build for all : gpuix as the key and the code that it uses / a meta-heuristic on the latter point by the way is that ultimately the code iteslf is not that important and it can be regenerted in whatever framework etc. and how the goal is to "abstract out" the api actions that are unlocked and the actual tool use that is created. so the email and crm etc are nothing more than "applications of a spec" which i think is enough good quality to be deployed in standard on cloudflare".
- Agent summary, not Tom (file C, L137): "Boundary rule: compositor-bound = Tom's personal gpuix shell; GPU window without compositor = shared native head (Marwan kit); browser only = web head (Frank); else shared core deployed per owner." This is the clearest one-line test for "does X belong in dotfiles or in agency-agency", and it matches BRIEF.md decision 8. Treat as REPORTED paraphrase of 2.1/2.2.

### 2.5 What the agents told Tom about the boundary (REPORTED, A)

- L2489 13:47:43Z: "the personal shell versus shared product boundary was already scoped. I shouldn't have made it sound like that needed deciding again."
- L2528 13:48:25Z: quotes the 10-16 wording; "Your personal Sway/GPUIx shell is the separate sister project."
- L2682 13:58:57Z: "I found the exact reference: thesysdev/openui, in desktop-ui.md. Your note explicitly calls for one generative UI approach across the shared applications, with the Sway desktop shell as the personal boundary."
- L3109 14:12:01Z: mermaid of the target: Claude/Codex -> MCP Code Mode -> shared capability gateway <- unified web UI, <- GPUIx desktop client; gateway -> CRM / Email / Projects. "The portability contracts explicitly keep Sway and Herdr out of that shared core." (Source for that claim is `/home/tom/agency-agency/ultrabuild/design/claude-portability/src/core/contracts.ts` and `/home/tom/agency-agency/ultrabuild/design/claude-suite/UTILITY-ACCESS.md:11,19`, cited in `docs/history-gateway-gadgets.md:35-37`.)
- L3131 14:12:54Z (after Tom's L3126 correction): "A shortcut, a human click and an agent API call invoke the same command. That command produces the same state change and event trail. The web and GPUIx interfaces render that state through the OpenUI component contract. A separate presenter can follow the trail and show what is happening, without executing the command again." This is the "trailing clicks" design in one paragraph.
- L3508 14:23:34Z: the keyboard chapter already exists as A11Y-01..04 in `/home/tom/agency-agency/ultrabuild/design/claude-suite/REQUIREMENTS.md:72` plus "one command-ID registry with shortcuts mapped per host" in `COMPONENT-COVERAGE.md:48` and the Ctrl-K lineage in `CTRL-K-LINEAGE.md:19`.

---

## 3. Feature / behaviour inventory

Legend for "keep/replace/new" from the gpuix-shell builder's point of view: **keep** = reuse as is (copy or import); **adapt** = reuse the pattern, rewrite for the shell; **outside** = belongs to the shared product, the shell only launches/consumes it; **new** = the shell needs it and nothing here provides it.

### 3.1 What was built today (MEASURED unless marked)

| Feature | What exactly | Where it lives today | keep/adapt/outside/new | Notes |
|---|---|---|---|---|
| Framework-free OpenUI component contract | 9 components (`Reply` root, `Note`, `ContactRecord`, `MailRecord`, `ProjectWork`, `DraftRecord`, `RoutineRecord`, `ReportRecord`, `RunStep`) and exactly one action `ExecuteStep(scenarioId, stepId)`; `createLibrary({id:"agency.workspace.v1", root:"Reply", ...})`; imports only `@openuidev/lang-core` + zod | `build/shared-parity/src/openui/contract.ts:1-71` | adapt | The pattern (contract file with `component: null`, React file spreads `...XContract` and adds `component`) is exactly how a GPUIx-only renderer can share a vocabulary with a web renderer. Shell vocabulary would be different (WorkspaceRow, AgentStatus, NotificationCard, SliderRow ...). |
| React web renderer over the contract | `defineComponent({...NoteContract, component: ...})` per component; `WorkspaceData` React context supplies host state | `src/openui/library.tsx:1-40+` | outside | Web head only. |
| Strict final-program validator | `validateProgram(program, allowedScenario)`: refuses empty/incomplete/errored/unresolved/orphaned programs, non-`Reply` roots, queries/mutations, built-in actions `ToAssistant/OpenUrl/Set/Reset/Run`, state assignment; evaluates with `evaluateRoot`; requires every `RunStep` to carry exactly one `ExecuteStep` that resolves to a known host step | `src/openui/host.ts:28-80` | keep | The key lesson: "OpenUI parsing is permissive; its error list alone is not acceptance" (host.ts:25). A shell `ask` surface must validate the same way before any control is wired. |
| Host-owned action resolution | `resolveStep` rejects unknown params, cross-scenario steps; `stepCommandKey` builds the idempotency key `openui:<session>:<scenario>:<step>`; `dispatchOpenUI` turns an OpenUI custom action event into a typed domain command | `src/openui/host.ts:82-112` | adapt | Pattern for mapping generated buttons to Sway/herdr commands without letting the model invent commands. |
| Framework-neutral GPUIx adapter (the native proof) | `NativeWorkspace` evaluates the validated program and emits GPUIx 0.10 MutationHost tuples `createElement/appendChild/setText/setStyle/setCustomProp/setEventListener/setRoot/destroyElement` through `host.applyBatch(JSON.stringify(mutations))`; rebuilds the whole tree per paint and destroys the old root; keeps `controls[]` (elementId, label, events); Tab/Shift+Tab cycle, Enter/Space activate, held keys ignored, ctrl/alt/cmd ignored; logical focus restored by label after redraw via `host.focusElement` | `src/native/adapter.ts:19-136` | keep (as a reference) | Proves the "OpenUI Lang -> GPUIx element mapping" path BRIEF.md decision 7 wants, without `@gpuix/react` or `@gpuix/solid`. 150 lines. |
| Native HTTP gateway client | `createNativeGateway(baseURL, workspaceId)`; requires v4 UUID, http(s); GET `/api/workspace/snapshot`, POST `/api/workspace/commands`; header `X-Workspace-Id`; checks `protocol === 'shared-parity/1'` | `src/native/adapter.ts:139-150` | outside | Only needed if the shell talks to the shared Worker. |
| Native entry (window, input, evidence) | Loads `GPUIX_BINDING` (must be `__napiBindingTarget === 'native'`, WASI refused); `new binding.GpuixRenderer(cb)`; `renderer.init({title:'Shared workspace - OpenUI / GPUIx', appId:'shared-parity-openui', width:960, height:900})`; `renderer.setWindowKeyEvents(true,false,0)`; `renderer.tick()` every 16 ms; F6 toggles following, F7 presents next; writes `NATIVE_EVIDENCE` json with `getElementBounds`, `getFocusedElementId`, `getAllText`, `getPaintedText`; test-only `simulateKeystrokes` / `simulateClick`; file mailbox `NATIVE_TEST_COMMAND_FILE` polled every 100 ms | `src/native/main.ts:1-84` | adapt | Window, not layer-shell. The `renderer.*` calls are the 0.10.0 API surface actually exercised today. |
| Passive ordered activity presenter (native) | `NativeActivity` wraps the pure presenter: ingest events, advance at most one per 600 ms when following, pause on human input, `advance(true)` for single-next, AbortController cancels in-flight presentation, failed presentation requeues and pauses | `src/native/activity.ts:1-28`; pure core `src/parity/presenter.ts` (REPORTED) | adapt | Directly reusable idea for the shell: an agent's herdr events are *presented* (focus the row, show the toast) and never re-executed. |
| Private-compositor native harness | Starts its own Sway 1.12 (`/nix/store/04g9x522ddd3hi77v013n97li9ccyrhd-sway-1.12/bin/sway --unsupported-gpu -c <conf>`) with `WLR_BACKENDS=headless`, `WLR_RENDERER` (pixman default, gles2 used), `WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128`, `WLR_LIBINPUT_NO_DEVICES=1`, fake D-Bus addresses, `VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json`; `LD_LIBRARY_PATH` built from `/nix/store/*-{libxkbcommon,wayland,vulkan-loader,fontconfig,freetype,libGL,libX11,libxcb,openssl}-*/lib`; waits for `app_id=shared-parity-openui` in `swaymsg -t get_tree`; screenshots with `grim -o HEADLESS-1`; asserts `not (runtime/'bus').exists()` and no `/dev/input` | `tests/native-compositor.py:1-93` | keep | This is the compositor smoke the BRIEF asks every surface to ship (`tests/gpuix-shell/smoke_<surface>.py`). Copy and adapt. Sway conf: `output HEADLESS-1 mode 1080x1000`, `xwayland disable`, `seat seat0 fallback true`, `default_border none`. |
| Unit tests with a fake MutationHost | `RetainedHost` implements `applyBatch` by replaying the tuples into a Map, asserting undocumented ops throw, tree stays < 200 nodes, dispose empties it; schema identity test `workspaceLibrary.toJSONSchema() deepEqual workspaceContract.toJSONSchema()` | `tests/native.test.ts:10-45+`, `tests/native-activity.test.ts`, `tests/openui.test.ts` | keep | 49 native+openui tests (manifest `unitTests.count: 49`, REPORTED 49/49). Pattern for the BRIEF's "pure-logic *.test.ts, no compositor". |
| Host-independent shortcut catalogue | `shortcutCatalog` with ids `commands.open` (Ctrl+k / Meta+k), `surface.dismiss` (Escape), `commands.next/previous` (arrows), `commands.first/last` (Home/End), `commands.activate` (Enter); `matchesShortcut(id, keyIntent)` ignores composing/defaultPrevented | `src/ui/shortcuts.ts:1-21` | adapt | "application-local, never OS-global bindings" (line 1). The shell's Sway binds are the OS-global layer; this is the in-surface layer. |
| Keyboard/a11y chapter | Table of interaction IDs with focus and announcement contracts and per-host proof status; A11Y-01..04, PORT-01..07 recovered | `docs/A11Y-CHAPTER.md:1-75` | adapt | Native column says what is still unverified (palette, overlays, IME, AT-SPI). |
| Shared command gateway (Worker) | `/api/workspace/{contract,snapshot,commands,events}`, R2 conditional commit (ETag), `WorkspaceSession` serialized host, receipts `applied/replayed/conflict/rejected`, direct MCP on `/mcp` with 4 tools (`workspace_contract`, `read_workspace`, `execute_workspace_command`, `read_workspace_events`) | `src/worker/index.ts`, `src/gateway/{store,mcp}.ts`, `docs/GATEWAY.md`, `docs/PROTOCOL.md` (253 lines) | outside | Shared product. The shell could expose its own small socket with the same receipt discipline (BRIEF decision 2: `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`). |
| Local model generation probe | One real generation against `http://127.0.0.1:8731`, model `halogen-qwen3.8-flash-next`, 3271 ms, accepted; output program saved and rendered in both heads | `evidence/model/probe.json`, `evidence/model/generated.openui`, `src/model/stream.ts` (SSE `data:` chunk reader, `[DONE]` handling, finish_reason required) | keep | `stream.ts` is 43 lines, zero deps; usable as is for `gpuix-shell ask`. |
| React vs Solid evaluation | No decision; React has the shorter OpenUI path (`@openuidev/react-lang` exists, no Solid binding in the pinned tree); GPUIx has both adapters at 0.10.0 (`@gpuix/react` uses react-reconciler 0.33, peers React 19.2; `@gpuix/solid` uses `solid-js/universal`) | `docs/FRAMEWORK-EVALUATION.md:1-22` | keep | Consistent with BRIEF decision 1 (React). |
| Historical gateway/gadget review | Sept 22 "single worker mecattaf cfos instance ... universal mcp codemode"; Oct 10 "i will not be building on cloudflare-os"; Oct 12/13 "a single mcp codemode for all my cf worker-deployed utilities"; old CodeMode executor in `/home/tom/agency-agency/backlog/packages/worker/src/mcp-executor.ts` | `docs/history-gateway-gadgets.md`, `docs/GATEWAY.md:27-47` | outside | Shell irrelevant except: "local Sway/Herdr capabilities stay in a separate host adapter" (UTILITY-ACCESS.md:11,19). |
| Hosted demo + a11y audit | 119 unit, 18 browser cases vs local workerd; 428 text samples >= 4.5:1; 320 px reflow; hosted R2 retention and 409 on competing writes | `docs/VALIDATION.md`, `evidence/hosted/*`, `evidence/a11y-browser/*` | outside | Web head. |

### 3.2 What worked natively (MEASURED from `docs/native.md`, `evidence/native/manifest.json`, the harness, and B's tool log)

| Run | What happened | Evidence dir |
|---|---|---|
| First attempt, Pixman renderer | **Failed**: `wgpu_hal::vulkan::swapchain::native] get_physical_device_surface_capabilities: ERROR_SURFACE_LOST_KHR` then `Error: Failed to open the GPUI window: No GPU adapter found that can configure the display surface` at `main.ts` `renderer.init(...)` (14:18:59Z) | `evidence/native/failure-pixman/native.log` |
| Switch to `WLR_RENDERER=gles2` + `--render-node /dev/dri/renderD128` | Window mapped (`app_id shared-parity-openui`), pixels captured | all later dirs |
| `swaymsg seat seat0 cursor set/press/release` injection | **Did not deliver** the click to the window; retained as a failure | `evidence/native/failure-compositor-cursor/` |
| GPUIx's own `simulateClick(x,y)` through its hit-test pipeline | Click reached the control, host receipt painted | `evidence/native/pointer-local/` |
| `simulateKeystrokes("tab","tab","shift-tab","tab","enter")` against the local Worker on :4321 | Follow-up created; focus element id survived redraw; separate HTTP agent command opened a report and the native view projected it; Worker revision stayed 2 (no redispatch) | `evidence/native/keyboard-focus-worker/` |
| Ordered activity: human follow-up + two agent HTTP commands while paused; F7 then F6 | Projection order `[1,2,3]`, final revision 3, `redispatched: false` | `evidence/native/final-ordered-worker/activity-result.json` (earlier pass in `ordered-activity-worker/`) |
| The locally generated model program | Rendered contact then mail natively; Tab/Enter executed its one allowed action | `evidence/native/model-worker/` |

Binding used (MEASURED, harness line 30): `GPUIX_BINDING=/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/node_modules/@gpuix/native/index.js`, i.e. the **installed 0.10.0 linux-x64-gnu addon** from the previous shell attempt, sha256 `a907deb0...a44d` (manifest `nativeAddonSha256`). Loading it needed `LD_LIBRARY_PATH` with libxkbcommon at least (B L2811: `/nix/store/7lapmv280q2lfk2h7mxgf3490xbxw144-libxkbcommon-1.13.1/lib`), which the harness then generalised to the nine-library glob.

Vendored gpuix source consulted for the ABI: `/home/tom/agency-agency/ultrabuild/vendor/gpuix` at upstream `6a5c7c142ac32f9eb0caefe0121be995cfc18631` (inside ultrabuild checkout `9154ddd2...`), with six files byte-verified against GitHub (`evidence/native/upstream-source-check.json`). Note the BRIEF's `/home/tom/Downloads/gpuix` is a separate clone of the same upstream.

Node used: `/nix/store/v6wsd9nyglmwh32yn7w8z11dq9cksg4m-nodejs-24.20.0/bin/node --import tsx` (not bun). Every run was wrapped in `/home/tom/.wt/hyprland-solid-shell/home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- python3 tests/native-compositor.py` for the compositor, and `~/.local/bin/runtime-test -- node ...` for unit tests (MEASURED, B L2792, L2837, L2898, L3313).

Timeline of the native lane (MEASURED, B): 14:13:37Z start looking for a GPUIx renderer -> 14:15Z reads vendor gpuix `packages/native/js/{mutations,host,host-runtime}.ts` and `index.d.ts` -> 14:16Z finds the 0.10.0 binary and `design/gpuix-comparison/{smoke-native.py,package-native.py,automation-native.ts}` -> 14:17:11Z writes `src/native/adapter.ts` -> 14:18:57Z writes `src/native/main.ts` -> 14:19Z Pixman failure, GLES2 success -> 14:21Z keyboard path -> 14:23Z focus ring and Tab handling -> 14:28Z "one ExecuteStep per control" rule -> 14:30Z `activity.ts` -> 14:35Z final ordered run -> 14:36:14Z report "49 tests and typecheck pass".

### 3.3 What the adapter needs (for a shell builder who reuses it; MEASURED from the code, INFERRED where marked)

1. A `GpuixHost` with `applyBatch(json): number[]` and optionally `focusElement(id)` / `getFocusedElementId()` (adapter.ts:8). The real `GpuixRenderer` from `@gpuix/native` satisfies it; the unit-test `RetainedHost` fakes it.
2. The mutation vocabulary it emits is limited to element types `div` and `text` (the fake host asserts exactly that, native.test.ts:24). Styles used: `display:'flex'`, `flexDirection:'column'`, `gap`, `padding`, `backgroundColor`, `borderRadius`, `width/height:'100%'`, `overflow:'scroll'`, `color`, `fontSize`, `cursor`, `borderWidth/borderColor`, `focusVisible:{outlineWidth,outlineColor}`. Custom props: `role:'button'`, `aria-label`, `tabIndex:0`, `autoFocus:true`. Events: `click`, `keyDown` (adapter.ts:119-123). INFERRED: a shell renderer will need `img`, `svg`, `input`, `virtual-list` and the 0.11.0 `registerFont(bytes)` (`/home/tom/Downloads/gpuix/packages/native/index.d.ts:178,386`) for Anthropic Sans; none of that is exercised here.
3. It re-renders the full tree on every paint and relies on label-based focus restoration (adapter.ts:134). INFERRED: fine for a toast or an `ask` reply, wrong for a rail with live herdr status (use `@gpuix/react` reconciler there, as BRIEF decision 1 says).
4. It expects a validated program and a `state` snapshot from a gateway; it never reads DOM or the model directly. The shell equivalent: snapshot = herdr/Sway state, commands = Sway IPC / herdr CLI, receipts = the socket's reply (INFERRED).
5. Layer-shell is **not** used (window via `renderer.init`), even though the installed 0.10.0 `index.d.ts` already has `LayerShellOptions` (`exclusiveZone`, `keyboardInteractivity`, lines 625-660) and `WindowOptions.layerShell` (line 731) in `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/node_modules/@gpuix/native/index.d.ts`. MEASURED that the API exists; MEASURED that today's code never calls it.
6. Multi-step actions are refused by design because upstream OpenUI React does not await one custom-action callback before the next (FRAMEWORK-EVALUATION.md:16; B L3108 patch "exactly one supplied ExecuteStep"). INFERRED: keep this rule for any shell `ask` control.
7. The OpenUI parser's union validation leaks: unknown discriminator / missing branch field / extra strict field still produce executable steps (openui-method.md:109-111, `docs/openui-union-probe.{mjs,json}`). The host validator is mandatory.

### 3.4 Statements about the desktop shell boundary (collected)

| Date/time (UTC) | Who | Statement | Pointer |
|---|---|---|---|
| 2026-10-16 08:12 | Tom | "gpuix-shell is for ME and the substrate actual tooling is exported to macos native etc. by design" | T-38 json:36 |
| 2026-10-16 08:12 | Tom | "herdr-centril all the way, how hersr-web-ui is decomposed eg the leftbar becomes sway compatible" | T-38 json:36 |
| 2026-10-20 08:45 | Tom | "the only boundary being of course the desktop shell, which would be exclusive to wayland-on-sway wm" | desktop-ui.md:8 |
| 2026-10-20 08:45 | Tom | "the same llm generate all the front-end tooling, starting from my desktop shell all the way to webapps" | desktop-ui.md:11 |
| 2026-10-20 12:04 | Tom | "a saister project that is a gpuix shell that is no-quickshell ... SEPARATE project that uses the same kernel and has its learnngs feed into this project" | T-38 json:66 |
| 2026-10-20 13:47 | Tom | "the boundary of things that are my own versus things that we can all use are: the gpuix local shell. and that has been scoped very well previopusly" | A L2484 |
| 2026-10-20 13:58 | Codex | "I'll preserve the personal-shell boundary and the ongoing Herdr sessions." | A L2656 |
| 2026-10-20 14:12 | Codex | "The portability contracts explicitly keep Sway and Herdr out of that shared core." | A L3109 |
| 2026-10-20 (docs) | Codex | "The personal GPUIx/Sway shell stays outside this build." / "Sway/Herdr placement, personal desktop control and the user's shell remain outside it." | SHOWCASE.md:3, BUILD-MAP.md:13 |
| 2026-10-20 (docs) | Codex | "These are app-local bindings; nothing installs Sway, macOS or Windows global shortcuts." | A11Y-CHAPTER.md:37 |
| 2026-10-14 (older) | agent | "An ordinary native window is also separate from a commissioned shell surface using layer-shell, Sway IPC and notification protocols." | RENDERER-DECISION.md (section "The compatibility boundary") |
| 2026-10-14 (older) | agent | "Sway IPC supplies concrete operations behind a framework-independent desktop adapter ... Herdr supplies session identity/status through its own adapter. UI components consume capabilities rather than embedding compositor commands." | RENDERER-DECISION.md "Corrected steering" |

INFERRED consolidation: nothing in today's build contradicts BRIEF.md decision 8. Today's build sits entirely on the "shared" side; its contribution to the shell is method and code patterns, not surfaces.

---

## 4. Design values found (all MEASURED from code; none of these are Tom's rulings)

Native adapter palette and metrics, `src/native/adapter.ts:100-119` (this is a quick light-theme proof, not the noir look Tom wants):

| Token | Value | Where |
|---|---|---|
| Page background | `#f6f5f1` | adapter.ts:106 (Reply container) |
| Card background | `#ffffff` | adapter.ts:101 |
| Text colour | `#242424`, `fontSize: 15` | adapter.ts:100 |
| Button idle / pending | `#e5ebe1` / `#dddddd` | adapter.ts:119 |
| Focus ring | `#345c88`, 2 px border + `focusVisible.outlineWidth 2` | adapter.ts:119 |
| Radii | card 8, button 6 | adapter.ts:101,119 |
| Padding / gap | page 24 / 12; card 16 / 8; button 12 | adapter.ts:101,106,119 |
| Window | 960 x 900, title "Shared workspace - OpenUI / GPUIx", app_id `shared-parity-openui` | main.ts:39 |
| Test output | HEADLESS-1 1080 x 1000 | native-compositor.py:25 |

Timings: presenter advances at most one event per 600 ms (main.ts:78, native.md:21); gateway poll 400 ms (main.ts:72); renderer tick 16 ms (main.ts:51); test keystrokes 150 ms apart (main.ts:61); native input test fires 4000 ms after start (main.ts:56).

Keys: F6 toggle following, F7 next result (main.ts:27-28); Tab / Shift+Tab traverse, Enter / Space activate, held repeats ignored, ctrl/alt/cmd chords ignored (adapter.ts:61-67). Web palette: Ctrl+K / Meta+K, Escape, arrows, Home/End, Enter (shortcuts.ts:3-9).

Web composer focus outline measured `rgb(165,78,50)` 2 px solid, 3 px offset (A11Y-CHAPTER.md:67); minimum text contrast kept at 4.579:1 across 428 samples (A11Y-CHAPTER.md:66). The web UI "uses the existing Claude/Primer palette" (SHOWCASE.md:43).

Aesthetic rule the build applied (REPORTED B L2969, MEASURED skill file): `/home/tom/mecattaf/dotfiles/home/dot_claude/skills/design-references/uncodixfy/SKILL.md` ("Keep It Normal": sidebars 240-260 px solid with border-right, buttons 8-10 px radius max, cards 8-12 px, shadows <= 8 px blur, 1 px borders, transitions 100-200 ms, spacing scale 4/8/12/16/24/32, icons 16-20 px, body 14-16 px, no glass, no gradients, no pills). INFERRED: this agrees with the BRIEF's "flat and opaque, hairlines not shadows, no blur" and Tacit's "vanilla-ness"; it is a usable checklist for the shell's review.

Fonts: today's native run did not register any font (no `registerFont` in main.ts; 0.10.0 lacks it). Anthropic fonts appear only via the claude-portability DOM proof ("Core typography assets are copied from the existing accepted preview (Anthropic font package)", `/home/tom/agency-agency/ultrabuild/design/claude-portability/README.md:9`).

---

## 5. Reusable code or data, exact paths

Under `/home/tom/tuesday-oct20/build/shared-parity/` unless absolute:

| Reuse | Path | Lines | How to reuse in gpuix-shell |
|---|---|---|---|
| Framework-neutral OpenUI -> GPUIx MutationHost adapter | `src/native/adapter.ts` | 150 | Copy into `pkgs/gpuix-shell/src/ask/` as the base of the `gpuix-shell ask` renderer; swap the component switch for the shell vocabulary |
| Native entry with real `GpuixRenderer` usage (init, setWindowKeyEvents, tick, getElementBounds, getFocusedElementId, getAllText, getPaintedText, simulateKeystrokes, simulateClick) | `src/native/main.ts` | 84 | Reference for the 0.10/0.11 JS API calls that are known to work on this machine |
| Ordered passive presenter | `src/native/activity.ts` + `src/parity/presenter.ts` | 28 + (not read) | Pattern for "trailing clicks": agent events presented, never re-run |
| Program validator and host-owned action resolution | `src/openui/host.ts` | ~120 | Copy `validateProgram` shape; replace scenario registry with a shell command registry |
| Contract/React split | `src/openui/contract.ts`, `src/openui/library.tsx` | 71, ~150 | Pattern only |
| Program generators (`exampleProgram`, `focusProgram`, `generationContext`) | `src/openui/programs.ts` | ~80 | Shows how to derive a program from state + semantic focus rather than from clicks |
| SSE chat-completions reader for the local model | `src/model/stream.ts` | 43 | Drop in for `gpuix-shell ask` against `http://127.0.0.1:8731` model `halogen-qwen3.8-flash-next` (README.md:76-79 shows the env: `PARITY_MODEL_URL`, `PARITY_MODEL_ID`, `PARITY_MODEL_HEALTH_PATH=/health`) |
| Private-Sway compositor smoke harness | `tests/native-compositor.py` | 93 | Template for `tests/gpuix-shell/smoke_<surface>.py`; already asserts runtime isolation (no `bus`, no `/dev/input`, no live `SWAYSOCK`) |
| Fake MutationHost for unit tests | `tests/native.test.ts` (class `RetainedHost`) | 10-37 | Copy for every surface's `*.test.ts` |
| Shortcut catalogue + matcher | `src/ui/shortcuts.ts` | 21 | In-surface keys for launcher/switcher |
| OpenUI integration reference (API, pitfalls, pins) | `docs/openui-method.md` | 132 | Read before writing the `ask` surface; section "Compatibility is semantic, not just visual" has the prop-order ABI rule |
| Native proof write-up and repro line | `docs/native.md` | 54 | Repro: `WORKSPACE_GATEWAY=http://127.0.0.1:4321 TEST_WLR_RENDERER=gles2 TEST_NATIVE_INPUT=keyboard /home/tom/.wt/hyprland-solid-shell/home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- python3 tests/native-compositor.py` |
| Keyboard/a11y chapter | `docs/A11Y-CHAPTER.md` | 75 | Acceptance rows for the shell's palette/launcher |
| React vs Solid facts | `docs/FRAMEWORK-EVALUATION.md` | 22 | Cite in ASSUMPTIONS.md for decision 1 |
| Evidence manifest with hashes, pins, limits | `evidence/native/manifest.json` | json | Template for `tests/gpuix-shell/` receipts |
| OpenUI union-validation probe | `docs/openui-union-probe.mjs`, `.json` | - | Rerun if the lang-core version changes |
| OpenUI upstream clone, pinned | `/home/tom/tuesday-oct20/build/shared-parity-reference/openui` @ `9823ec05...` | - | `packages/lang-core` is the framework-agnostic part (README.md:29 of that package); `packages/react-lang/src/index.native.ts` exists but is React Native, not GPUIx |
| gpuix vendored source with the MutationHost ABI | `/home/tom/agency-agency/ultrabuild/vendor/gpuix/packages/native/js/{mutations.ts,host.ts,host-runtime.ts}`, `index.d.ts` | - | Same upstream as `/home/tom/Downloads/gpuix`; six files verified identical to `6a5c7c1` |
| Installed native addon that is known to open a window on this GPU | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/node_modules/@gpuix/native-linux-x64-gnu/gpuix-native.linux-x64-gnu.node` (0.10.0) | - | BRIEF pins 0.11.0 from npm; 0.10.0 is the one proven today |
| Earlier Solid native comparison and its Sway smoke | `/home/tom/agency-agency/ultrabuild/design/gpuix-comparison/{smoke-native.py,package-native.py,automation-native.ts,README.md}` | - | Consulted by B L2748; BRIEF already lists the `.wt` copy |
| Claude-suite requirements the shell inherits | `/home/tom/agency-agency/ultrabuild/design/claude-suite/REQUIREMENTS.md` (A11Y rows at :72-75, PORT rows :85-91, line 22 "Sway stays the window manager", :29 "workspace switcher toggles with Mod+I on the top display only"), `DESKTOP-REQUIREMENTS.md` (SH-01 launcher/menu/notifications/quick controls; SH-04..06 switcher; SH-07 launcher result kinds; SH-08 notifications/DND; SH-09 quick controls = real device state; AG-03 herdr status with explicit unknown), `RENDERER-DECISION.md`, `UTILITY-ACCESS.md:11,19`, `CTRL-K-LINEAGE.md:19`, `COMPONENT-COVERAGE.md:48` | - | These are the previously accepted shell requirements; the BRIEF's design-kit handoff pointers overlap |
| Historical CodeMode executor (if the shell ever exposes MCP) | `/home/tom/agency-agency/backlog/packages/worker/src/mcp-executor.ts`, `.../packages/mcp/src/protocol.ts` | - | Outside the shell |
| Local model server details | `README.md:73-80`, `evidence/model/probe.json` | - | Health path `/health`; one generation took 3.3 s |

Transcript tooling: `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/cx.py` (Codex 0.160 rollout dumper written for this read; scratchpad is session-temporary, copy it if wanted).

---

## 6. Gaps and unknowns

Unverified by me (light pass per the 2026-10-20 workflow rule; nothing was re-run):

- All test counts (49 native/openui unit, 119 total unit, 18 browser cases, 428 contrast samples) are REPORTED from the transcripts and `docs/VALIDATION.md`; I did not execute `tsx --test` or the compositor harness.
- The hosted demo URL and MCP provisioning are REPORTED; hosted MCP auth was admitted unverified by the build itself (VALIDATION.md:26, 401 at `/mcp`).
- The screenshots were viewed for one run only (`evidence/native/final-ordered-worker/agent-projection.png`: light beige page, two white cards, status line "Following activity · 0 queued · F6 pause/resume · F7 next result"); it matches adapter.ts values.

Unknowns that matter for the shell builder:

1. **No layer-shell run exists anywhere in today's material.** The 0.10.0 `index.d.ts` declares `LayerShellOptions` but today only an ordinary window was opened. Whether `layerShell` works on this GPU/compositor path (and in 0.11.0) is untested. Rail, toasts, OSD and launcher all need it (BRIEF decision 3).
2. **Pixman fails, GLES2 works** (`ERROR_SURFACE_LOST_KHR`). Every compositor smoke must set `TEST_WLR_RENDERER=gles2` and pass `--render-node /dev/dri/renderD128`; a CI without a GPU cannot run them.
3. **`swaymsg seat ... cursor` injection does not reach a GPUIx window**; tests must use `renderer.simulateClick/simulateKeystrokes`. INFERRED: physical pointer behaviour on the Zenbook is still unproven for GPUIx 0.10/0.11 windows.
4. **0.10.0 vs 0.11.0.** Today's proof is on 0.10.0 from the `.wt` node_modules. BRIEF pins 0.11.0 (adds `registerFont`). Nothing here shows 0.11.0 loading on this machine.
5. **Fonts.** No `registerFont`, no Anthropic Sans in any native run today. Font rendering of the Nerd Font glyphs (herdr status ◉ ◐ ● ✓ ○) in GPUIx is untested.
6. **Node, not bun.** Every run used nix Node 24.20.0 + `tsx`. The BRIEF plans `bun build` / `bun test`; no evidence either way for bun loading the napi addon.
7. **Subagent task payloads are encrypted** in file B (`encrypted_content`), so the exact instructions the native lane received from the root cannot be quoted; only its actions can.
8. **OpenUI is not a shell UI language.** The contract here is 9 record-ish components and one action. A shell vocabulary (rows, sliders, toggles, lists with status glyphs, OSD bars) and the host commands behind it (Sway IPC, `wpctl`, `brightnessctl`, `nmcli`, BlueZ) do not exist yet. BRIEF decision 7 keeps `ask` off the critical path; this read supports that.
9. **The "trailing clicks" presenter has no shell equivalent yet.** The idea maps well to "agent did X in workspace N -> rail highlights N, toast shows receipt" but no code here touches herdr events.
10. **The Claude session named in the task (4253a15b) contains no shell content** and should be dropped from the BRIEF's "what Tom said" list for shell purposes, or kept only for the second-hand 10-14 and 10-17 quotes in 2.4. The Claude session that carried the 2026-10-20 12:04Z boundary message is `1a517fb2-dbee-4524-a95c-dd798bcc78b0` (BRIEF already lists it under `-home-tom-mecattaf-dotfiles`); I did not read it.
11. **React vs Solid is explicitly undecided in the build docs**; BRIEF decision 1 decides React. The only measured facts are integration cost (React shorter for OpenUI) and that both GPUIx adapters exist at 0.10.0.
12. **Tacit aesthetic**: nothing in these three sources mentions Tacit; the aesthetic ruling comes from the ~22:50 CEST order in BRIEF.md, after all of this.

What I did not read: `src/parity/*` (engine, presenter, session, catalog), `src/worker/*`, `src/gateway/*`, `src/ui/*` beyond shortcuts.ts, `docs/PROTOCOL.md` beyond line 16, the a11y evidence JSONs, the 10-13/10-14 Codex rollouts and the other 10-20 rollouts (`01a15938-{6c51,89d0}`, `01a159bd`, `01a159c1`) listed in BRIEF.md.

---

## 7. Implications for the gpuix-shell builder (INFERRED, one line each)

1. Treat today's build as the **sister project's kernel**, not as shell code: copy patterns (contract/renderer split, strict validator, passive presenter, compositor harness, fake host tests), not surfaces.
2. First compositor experiment tonight should be the **layer-shell question** (`render(node,{layerShell:...})` on 0.11.0 under `runtime-test --render-node`, GLES2), because it is the one thing today's native proof did not touch and every shell surface depends on it.
3. Reuse `tests/native-compositor.py` as the smoke template; keep its isolation asserts; expect to use `simulateClick/simulateKeystrokes`, not `swaymsg seat cursor`.
4. Prove 0.11.0 + `registerFont(AnthropicSans)` early; 0.10.0 is the only addon proven on this GPU.
5. For `gpuix-shell ask`, start from `src/native/adapter.ts` + `src/openui/host.ts` + `src/model/stream.ts`; define a shell vocabulary with one host action per control; validate before wiring any control.
6. Map Tom's "trailing clicks" to herdr: agent events are presented (rail highlight, toast) and never re-executed; a human key or pointer pauses following. The pure presenter in `src/parity/presenter.ts` is the reference.
7. Record in ASSUMPTIONS.md that the build docs leave React vs Solid open and that BRIEF decision 1 (React) is taken on integration-cost grounds (`docs/FRAMEWORK-EVALUATION.md:7`).
8. Drop the Claude Frank session `4253a15b` from shell-reading lists; read `1a517fb2` (the 12:04Z boundary message) if a later wave needs the full context around it.
