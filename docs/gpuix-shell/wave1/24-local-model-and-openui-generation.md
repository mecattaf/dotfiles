# 24 — Local model + OpenUI generation for gpuix-shell (`ask`, generated summaries, generated controls)

Reader 24 of the overnight gpuix-shell build, written 2026-10-20 23:25–00:15 CEST on the strix (Claude, cc2
seat). Scope: how the shell can call the local model to produce generative UI and power an "ask" surface.
Labels: **MEASURED** = I ran it or read it from a live log/file tonight; **REPORTED** = written in a source
file or another note, not re-checked live; **INFERRED** = my reasoning, untested. `SP` = 
`/home/tom/tuesday-oct20/build/shared-parity`, `OU` = `/home/tom/tuesday-oct20/build/shared-parity-reference/openui`
(pinned `9823ec05d4b29bc78d101676dc16b44fe17f1830`, 2026-10-19), `DF` = this worktree
`/home/tom/.wt/dotfiles/gpuix-shell` (same files as main `dadb1426` for everything cited here), `GF` =
`/home/tom/mecattaf/gufo` (`ae26ca4a13f252a0424c23e4bd7662167f23b436`, the commit `flake.nix:204` pins).

**Revision 2 (2026-10-21 12:00–12:40 CEST, re-run of reader 24, Claude Opus on the strix).** Section numbers
are unchanged because SCOPE.md, DESIGN.md, KEYS.md and BOUNDARY.md cite them (`[w1-24 §3]`, `§5.8` …).
What this pass added, all without one generation request (only `GET /v1/models`):
- token counts **MEASURED with the model's own tokenizer**
  (`/var/lib/local-models/halogen-qwen38-flash-next/tokenizer/tokenizer.json`), replacing the
  chars/4 estimates (§5.5, §5.7);
- the curated-subset prompt trick, tried: it works only if the child unions inside signatures are pruned
  too (§5.5);
- a React-free way to put **shell host components and a `ShellAction` custom action into the full default
  library spec**. It was tried end to end: prompt, parse, `evaluateRoot`, and action steps (§5.5a);
- streaming-parser behaviour measured frame by frame: transient errors, prefix-typed names in
  `unresolved`, labels that grow one character at a time, about 0.035 ms per re-parse (§5.6);
- Halogen journal through 2026-10-21 12:02: prefill rates by prompt-size band, the SP generation's exact
  token split, the prefix-cache reuse seen overnight, and the server's status since the §0 incident (§0, §5.7);
- the upstream playground route that makes the request the shell needs (`OU/docs/app/api/playground/stream/route.ts:12-45`).
The main dotfiles have not moved since revision 1 (`f501e856` only adds an agent rule on top of `dadb1426`), so the module pointers still hold.

---

## 0. Read this first: Halogen restarted after one of my requests (operational incident)

**MEASURED** (`journalctl -u podman-halogen.service`, `systemctl show`, `/proc/pressure/memory`, curl):

| Time (CEST) | Event |
|---|---|
| 23:27:57 | My three read-only `GET /v1/models` probes: 200, ~1 ms each. |
| 23:30:46 | My **one** generation request: 23-token prompt, `max_tokens` 40, thinking off, streaming. Before sending it I checked `/health`: `busy:false`, `in_flight:0`, `queued:0`. |
| 23:31:17 | `/health` → **503**. Halogen: "the engine has not answered PING for 45s". |
| 23:32:15 | Halogen: "the kernel is compacting host memory (compact_stall +150 since the last probe) … Free host memory, or give this server a machine of its own." |
| 23:35:31 | Halogen's 180 s watchdog took the container down: `status=137`, unit `Failed`, "Triggering OnFailure= dependencies", `NRestarts` 5 → 6. |
| 23:36:02 | Restart. Startup warning: "11.8 GiB of host RAM is in use before this server starts … Expect every prompt to read the table from disk, prefill to run several times slower than published, and pauses of a minute or more." |
| 23:36:37 / 23:36:57 | Model ready after 32.6 s; engine listening after 52 s. Weights were still in page cache, so this was a warm restart. |
| 23:37:00 | `/health` reports `engine.responds:true`. Outage from first 503 to healthy: about 6 min. |

- Memory pressure at 23:35 was PSI `full avg10=1.35 avg60=7.07 avg300=12.53`, with 113 GiB "available"
  (mostly page cache). The cause looks like tonight's host load (19 `claude`, several `codex`, `workerd`,
  bun jobs) evicting the 47.7 GiB n-gram lookup table that Halogen reads through the file cache. My
  request was the last one before the stall. Halogen's own log blames compaction, not the request.
- One failure marker was written: `/var/lib/failure-markers/88ada2f5…-22a582203be7b408`. It belongs to
  the podman healthcheck transient unit of the new container, whose probes failed during its start
  period (23:36:02 and 23:36:32) before it turned healthy at 23:37:04. **I did not clear it, restart
  anything or touch any unit.** `failure-marker-reconcile` (D41) or Tom decides what happens to it.
- After this I sent **no further generation requests**. All latency numbers below come from the
  server's own journal lines (other clients' traffic since 2026-10-17), SP's saved probe, and my
  `/v1/models` timings.
- **Rule for builders tonight (INFERRED, strongly recommended):** do not run live-generation probes
  against `strix:8731` while the overnight agent load runs. Use the saved replay fixtures (§5.11). The
  shell must treat the model as *unreliable by design*: it can be absent for minutes.

**Status at revision 2 (MEASURED 2026-10-21 12:01–12:02 CEST):**
- `podman-halogen.service` has been `active running` since 2026-10-20 23:36:02 with `NRestarts=6`, so there
  was no further restart overnight (`systemctl show`). The journal (read from 23:40) shows **no generation traffic from 23:40 to
  08:15**: the overnight agents did not call the model.
- Since 08:15 there have been five small think-off requests from `10.42.0.2`, the strix's own LAN address (prompts of
  1,257–1,835 tokens, 48–54 output tokens each), and then a 206,577-token agent-lane request whose prefill ran
  from 12:00:03 to 12:02:10 (127.4 s, 1,621 tok/s).
- My three `GET /v1/models` at 12:01:50 answered **200 in 1.2–2.5 ms** *during* that 206k-token prefill.
  `/v1/models` evidently does not wait on the engine (INFERRED from that timing), so it is a safe liveness and discovery probe even under load. `/health`
  does touch it (§5.7).
- Rev 2 sent no POST of any kind to `:8731`. Token counts were taken offline with the tokenizer file.

---

## 1. What this source is

This reader covers the model-and-generation slice of the shell. Sources read:

| Source | What it gave | Label |
|---|---|---|
| `SP/src/model/stream.ts` (43 lines) | A renderer-independent SSE parser for chat completions (`completionChunks`) and an NDJSON reader (`readEvents`). | read in full |
| `SP/scripts/local-server.ts` (144 lines) | The **only working model call** in the OpenUI work: localhost bridge → `POST {base}/v1/chat/completions`, `stream:true`, thinking off, temperature 0, `max_tokens` 1800, system prompt = `workspaceLibrary.prompt(...)`. | read in full |
| `SP/src/openui/{contract.ts,host.ts,library.tsx,programs.ts,OpenUIChat.tsx,openui.css}` | The OpenUI library (core-only contracts plus React bindings), prompt construction, generation context, validation, action resolution, and the web chat client. | read in full |
| `SP/src/native/adapter.ts` (150 lines) | The OpenUI → GPUIX MutationHost renderer (`NativeWorkspace.paint`). Note 14 covers it in depth. | read in full |
| `SP/evidence/model/{probe.json,generated.openui,web-render.png}`, `SP/evidence/native/model-worker/after.png` | One real generation (2026-10-20T14:20:01Z, 3,271 ms, accepted) rendered on the web and natively. | MEASURED by that build; files read by me |
| `SP/README.md:72-84`, `SP/docs/native.md:21,30,48`, `SP/docs/openui-method.md` | Run recipe for the model companion; native proof scope; OpenUI method and its measured parser limits. | read |
| `OU/packages/lang-core/README.md` + `src/parser/{parser.ts,types.ts}` + `src/library.ts` | Parser, streaming parser, prompt generation, `ParseResult`, `PromptOptions`. | read; APIs exercised with bun (MEASURED, §5.5–5.6) |
| `OU/docs/content/docs/openui-lang/{system-prompts,syntax,specification/index,architecture,benchmarks,reliability}.mdx` | Prompt flags, grammar, action and error semantics, streaming rules, token-efficiency numbers. | read |
| `OU/docs/generated/{playground,chat}-library.spec.json` | **Pre-generated specs of the full default component library** (82 and 84 components). Usable with `generateSystemPrompt` without importing React. | MEASURED prompt sizes |
| `OU/packages/react-lang/{package.json,src/index.native.ts,src/Renderer.tsx}` | react-lang has a `react-native` export condition without the devtools/DOM bootstrap: a possible route to run the real OpenUI `Renderer` under `@gpuix/react`. | read; untested |
| `DF/modules/halogen.nix` (633), `DF/modules/strix.nix:39-135`, `DF/modules/gufo.nix` (468), `DF/modules/local-models.nix` (skim), `DF/modules/strix-ai.nix` (83), `DF/hosts/strix/default.nix:145`, `DF/flake.nix:2256-2310` | Endpoint, port, model id, firewall door, serving defaults, the Gufo cutover contract. | read |
| `DF/home/pi.nix:45-46,182-231`, `~/.config/substrate/models.toml`, `DF/docs/local-ai/seats.md` (grep) | How other fleet clients address the model; model ids as runtime data. | read |
| `DF/home/dot_local/bin/{screen-ocr,screen-ocr-area}`, `DF/pkgs/utility-model/utility_model.py` (grep) | The two existing desktop-side model callers (OCR over ssh; non-streaming `utility-model`). | read |
| `GF/docs/SERVER.md`, `GF/src/cli/serve/{http_server.cpp,openai_chat.cpp}` (grep) | What changes for a caller after the Gufo cutover (model id 404, `/ready`, thinking controls, `Server-Timing`, errors). | read |
| Live: `curl http://127.0.0.1:8731/v1/models`, `/health`; Halogen journal since 2026-10-17 | Endpoint shape, capabilities, and real per-request timing lines (`serve_api: …`). | MEASURED |
| Other wave-1 notes 01, 08, 14, 22, 27–30 (grep) and the notes repo `ANNOTATED-feature-matrix.md` | Tom's rulings on AI in the shell. | quotes re-read at source where a line is given |
| **Rev 2:** `/var/lib/local-models/halogen-qwen38-flash-next/tokenizer/tokenizer.json`, via nixpkgs `python3.13-tokenizers-0.22.2` (store path in §5.11) | Exact Qwen3.8 token counts for every prompt variant (§5.5). | MEASURED, offline |
| **Rev 2:** Halogen journal 2026-10-17 → 2026-10-21 12:02 (202 parseable `serve_api` lines) | Prefill rates by size band; decode rates; the SP probe's own line (16:20:01); prefix-cache reuse. | MEASURED |
| **Rev 2:** `OU/docs/app/api/playground/stream/route.ts`, `OU/docs/package.json:6`, `OU/packages/react-ui/src/genui-lib/*/schema.ts` | Upstream's own call: full spec + `openuiExamples` → `/chat/completions` `stream:true`. How the specs are generated. Why the default schemas cannot be imported without React (they reference `X.ref` from the `.tsx` modules). | read |
| **Rev 2:** `docs/gpuix-shell/{SCOPE.md §20 (S-200, S-201), DESIGN.md §8.9, KEYS.md:185,388, BOUNDARY.md:164-167,299}` | What the synthesis already took from rev 1 (the `ask` geometry, `$mod+a` reserved, the P2 scope). | read |

---

## 2. Verbatim Tom rulings relevant to the desktop shell

| Date | Verbatim | Where | Bearing on the shell |
|---|---|---|---|
| 2026-10-20 ~10:45 CEST | "the MASSIVE finding of the last few days: `https://github.com/thesysdev/openui` this openui project has the generative-ui philosophy that is exactly what i can use to have fully uniform deployments. extremely desirable, as i will have the same llm generate all the front-end tooling, starting from my desktop shell all the way to webapps like email etc." / "we build it once and it can be exported everywhere." | `/home/tom/tuesday-oct20/desktop-ui.md:10-13` (MEASURED, file read) | OpenUI generation is meant to reach the desktop shell. The `ask` surface is the first concrete place. |
| same file | "the only boundary being of course the desktop shell, which would be exclusive to wayland-on-sway wm." | `desktop-ui.md:8` | The shell, including its `ask` window, stays personal and Sway-only. |
| 2026-10-20 12:04:14Z (desk T-38) | "openui https://github.com/thesysdev/openui as the toolking that grows with us (instead of a prefactirated https://gpui-kit.com/ )" | note 08 §2.2 (REPORTED from `desk-T-38-2026-10-20.json` line 66) | OpenUI, not a prefab kit, is the component vocabulary. |
| 2026-10-20 14:12:30Z | "it is important that fron t end we buikld built from the ground up with openUI methodology AND thezhortcut driven method as well (so that my human clicks on the webUI is the same as an agwent's usage of the api with "trailing clicks" happening by another aent thst just shows what is being worked through." | note 08 §2.3 (Codex root L3126, REPORTED) | Generated controls must dispatch the same typed actions a human keybind or click does (the `ExecuteStep` / host-catalog pattern). |
| 2026-10-20 ~22:50–23:05 CEST | "openUI for the desktop shell is not quite known" | BRIEF §1 | Exploratory and bounded (BRIEF decision 7). |
| 2026-10-20 23:20 CEST | "using https://github.com/thesysdev/openui fully with what's given ; following my own desired anthropic font and existing colorscheme" | BRIEF §5 | Cover the default library and render it with Anthropic fonts and noir/claude palettes. This pulls against prompt size (§5.7): the full library prompt is 28–53k characters. |
| 2026-10-20 (overnight order) | "performance is not really the thing i m looking for here" | BRIEF §1 standing rulings | A 5–10 s generation is acceptable for an exploratory surface. |
| 2026-03 (annotated feature matrix, #247 "AI assistant integration") | "COULD but much later down the line. i do not need an ai integration the way it is done in the reference qml shells. i have some ideas here so not marking this as won't" | `/home/tom/notes/references/devlogs/1h26/april-webshell-refs/ANNOTATED-feature-matrix.md:554` (MEASURED) | No Ambxst/II-style chat sidebar with providers. `ask` must be something else: generated native UI over the shell's own data and actions. |
| 2026-03 (#51 "AI button") | "COULD, same as 50 equora has it but i never use it" | same file `:123` (MEASURED) | No bar button. Entry is keybind or launcher only. |
| 2026-03 (#238 OCR) | "SHOULD but with a twist. … i do NOT want the ocr to be handled by tesseract: it will be handled with qwen 3.5 opensource multimodal llm model which comes with phenomenal ocr from screenshots; and i confirmed it runs on my machine. Backend: HTTP call to llama.cpp server running in a local toolbox container." | same file `:536` (MEASURED) | Already realised as `screen-ocr-area` → Flash-Next vision (Mod+Ctrl+S). Precedent for the shell sending screen content to the local model. |
| 2026-10-13 | "i said let  move to gufo!! not halogen!!!!" and "use that as the full collection of modles that we use" | `DF/modules/gufo.nix:9-10`, AGENTS.md | Code must survive the Halogen → Gufo cutover: discover the model id; no Halogen-only fields. |
| 2026-10-13 | (AGENTS.md paraphrase) "Do no Halogen-specific work" | AGENTS.md "Until the cutover" (REPORTED) | Same as above. |
| 2026-10-10 | "i dnt think it s a g ood idea to have things like that tied to nixos dotfiles" (model ids) | AGENTS.md "Model catalog" (REPORTED) | The shell must not pin a model id in Nix. Read it from `/v1/models` or a runtime file. |
| 2026-09-30 | (AGENTS.md) "No scheduled agent work is declared in dotfiles … Reactive triggers … are fine." | AGENTS.md "Scheduled work" (REPORTED) | Notification summaries etc. run on demand or on an event, never on a timer. |
| 2026-09-30 | (AGENTS.md) "Speech input is OUT … Do not reintroduce a wake detector, a resident transcription service or a dictation patch without Tom." | AGENTS.md (REPORTED) | `ask` is typed only: no microphone and no ASR. |
| 2026-03-27 | "I dont like the two-mode structure kf morphdom / Only ai generated code. Possibly even html css raw. But incorporate the linear learnings." | note 30 (`chat.md:735-736`, REPORTED) | History of the "LLM writes the UI" idea. OpenUI is its 2026 form. |
| 2026-03-23 | "pi generative ui with glimpse is also incredible in its novelty." | note 30 (`frontends-reference-goldmine.md:157-158`, REPORTED) | Same lineage. |
| design rule (not Tom's words) | "An LLM must not guess operational status" (herdr stays the status producer) | note 01 F12 (`design/claude-suite/TITLE-LINEAGE.md`, REPORTED, attribution unverified) | Generated UI may *place* status components, but the host fills in the facts (§5.8). |

---

## 3. Feature / behaviour inventory

| # | Feature | What exactly | Where it lives today | keep / replace / new | Notes |
|---|---|---|---|---|---|
| M1 | Model discovery | `GET {base}/v1/models` → pick the text model id. SP's bridge reports `available` only if the configured id is listed. | `SP/scripts/local-server.ts:53-61` | **keep (port)** | Gufo returns 404 for a request naming another id (`GF/docs/SERVER.md:884-892`). Halogen serves any id (`DF/modules/halogen.nix:293`). Always send the discovered id. |
| M2 | Streaming chat completions | `POST /v1/chat/completions` with `stream:true`; SSE `data:` lines; `choices[0].delta.content`; terminal `finish_reason`; `[DONE]`. | `SP/scripts/local-server.ts:88-108`; parser `SP/src/model/stream.ts:2-27` | **keep (copy `completionChunks`)** | Ignores `delta.reasoning_content` (tested `SP/tests/model.test.ts:15-21`). Throws if the stream ends without a finish receipt. |
| M3 | Request profile for UI generation | temperature 0, thinking off, explicit `max_tokens`. | `local-server.ts:91-92`; `screen-ocr:22-26`; `utility_model.py:126-138` | **keep; adjust fields for Gufo** | Halogen's defaults are thinking on at `xhigh` with a shared budget: an unset budget can come back with **empty content** and `finish_reason:"length"` (`halogen.nix:408-424`, `strix.nix:44-58`). |
| M4 | Busy gate | Before generating, `GET {base}/health`; refuse if `busy`, `in_flight>0` or `queued>0` (409). | `local-server.ts:73-80` | **replace with a softer UX** | `/health` itself takes ~1.0 s on Halogen because it PINGs the engine (MEASURED, `probe_s 1.001`). Use it for a status hint, not as a blocking gate. |
| M5 | Single-flight and timeout | One generation at a time; 90 s abort; client disconnect cancels. | `local-server.ts:26,64,81-86,114` | **keep** | Halogen 0.16.0: "a cancel during a long prompt stops it within ~1 s" (`halogen.nix:277`). Gufo: "socket closure propagates cancellation" (`GF/docs/SERVER.md:32-33`). |
| M6 | Output caps | Program >32,000 chars → error; `finish !== "stop"` → error; request ≤8,000 chars; body ≤20,000 bytes. | `local-server.ts:67,104,107,132` | **keep** | |
| O1 | Core-only OpenUI library | `defineComponent({…, component:null})` + `defineAction` + `createLibrary({id, root, components, actions})`. No React import. | `SP/src/openui/contract.ts:1-71` | **keep pattern; new vocabulary** | The `ExecuteStep(scenarioId, stepId)` action (`contract.ts:4-8`) becomes the shell's host catalog action (§5.8). |
| O2 | System prompt generation | `library.prompt({preamble, additionalRules})`, or `generateSystemPrompt({library: spec, promptOptions})` from a `.spec.json`. | `SP/src/openui/library.tsx:112-120`; `OU/packages/lang-core/README.md:63-79` | **keep** | Full default library spec ships pre-generated: `OU/docs/generated/playground-library.spec.json` (82 components, root `Stack`). |
| O3 | Generation context | JSON user message: request, exact ids of records and steps, plus one example program. | `SP/src/openui/programs.ts:53-65` | **keep pattern** | The shell context is a snapshot of Sway, herdr, devices and notifications, with ids (§5.8). |
| O4 | Streaming parse | `createStreamingParser(schema, root)` → `push(chunk)` / `set(full, complete)` / `getResult()` → `ParseResult`. | `OU/packages/lang-core/src/parser/parser.ts:478-488,667-680,770-772` | **new in native** | The web uses `<Renderer isStreaming>`. **No native partial render exists anywhere yet** (note 14 §6.2). |
| O5 | Final validation | Complete root; no unresolved, orphaned or error statements; no Query/Mutation; forbidden built-in actions; state assignment refused; every control has exactly one allowed action, and its params resolve in the host catalog. | `SP/src/openui/host.ts:28-80` | **keep (adapt)** | The parser is permissive. Unions and strict-object extras slip through (`SP/docs/openui-method.md:109-111`). The host re-checks every action param. |
| O6 | Action resolution | `resolveStep(event)` accepts only `{type:"ExecuteStep", params:{scenarioId, stepId}}` and looks up the real input from a host registry. | `host.ts:82-99`, `dispatchOpenUI` `:106-112` | **keep pattern** | This is Tom's "human click = agent API call" parity (§2, 14:12:30Z). |
| O7 | Native render | Evaluated tree → GPUIX `createElement/setStyle/appendChild/setText/setCustomProp/setEventListener/setRoot/destroyElement` via `applyBatch`. | `SP/src/native/adapter.ts:89-135` | **replace with a @gpuix/react mapper** (or keep the MutationHost path for parity tests) | Hard-coded light colours (§4). Note 14 owns the full mapping. |
| O8 | Replay | Re-stream a saved program 35 chars per 28 ms tick. Works with no model. | `SP/src/openui/OpenUIChat.tsx:64-73` | **keep** | Use it for tests, demos and model-down fallback. |
| O9 | Web chat client | Composer; `/api/model/status` probe; NDJSON events; `validateProgram` after `done`; actions disabled while streaming; "How this response works" panel showing the program and prompt. | `OpenUIChat.tsx:33-41,74-100,114-118,130-152` | **reference only** | Shows the full UX loop the native `ask` must reproduce. |
| A1 | `gpuix-shell ask` | Prompt → stream → progressive native render → validated actions → receipts. | not built | **new (exploratory, BRIEF §3.7)** | Design in §5.8. Off the critical path: the core shell stands without it. |
| A2 | Notification summary | On-demand grouping and headline of unread notifications by the local model. | not built | **new (exploratory)** | §5.9. JSON-schema output, not OpenUI. No timer. |
| A3 | Quick controls, generated | "Make me a panel with X, Y, Z" → OpenUI program over shell components and actions; pin it; re-render live with **no further model calls**. | not built | **new (exploratory)** | §5.10. OpenUI's generate-once/execute-many split (`OU/docs/content/docs/openui-lang/architecture.mdx`). |
| A4 | Screen OCR | slurp → grim → `ssh strix ~/.local/bin/screen-ocr` → Flash-Next vision → `wl-copy`. | `DF/home/dot_local/bin/screen-ocr-area:9-12`, `screen-ocr:12-36`, `DF/home/dot_config/sway/binds.conf:46` | **keep script; launcher entry; optional toast with result** | Hard-codes `halogen-qwen3.8-flash-next` (`screen-ocr:22`). Breaks at the Gufo cutover (404). Not shell-owned, but flag it. |
| A5 | "Ask about my screen" | grim region → image part in the `ask` request. | not built | **new (exploratory)** | Halogen vision is on: data URLs only, `max_pixels` 3,686,400, size multiple 32 (MEASURED `/health`). Gufo: projector loaded (`gufo.nix:331`). |
| A6 | Session titles from a small model | First exchange → title → herdr-web-ui and rail. | note 01 F12 (design only) | **later** | No timer and no new resident model (note 01). The rail must never take *status* from an LLM. |
| A7 | `utility-model` wrapper | Non-streaming, one request, strix-only. | `DF/pkgs/utility-model/utility_model.py:97-98`; `halogen.nix:210-219` | **not used by the shell** | Refuses `stream:true`. Wrong tool for progressive UI. |
| A8 | pi provider row | `halogen` provider at `http://strix:8731/v1`, id from `halogen.modelId`. | `DF/home/pi.nix:45-46,197-229` | **unrelated** | Shows the fleet convention `http://strix:8731`. |
| M7 | Liveness + discovery probe | `GET /v1/models` (no engine round-trip): 1–2.5 ms even during a 206k-token prefill. `/health` takes ~1 s because it PINGs the engine | rev 2 measurement (§0, §5.7) | **new (use for the status word)** | Poll at most when the ask window opens; never on a timer (no-timers rule). |
| O10 | Merged ask spec | Default playground spec + host components (`WorkspaceSlot`, `AgentRow`, `Battery`, `AudioSink`, `NotificationRef`) + `ShellAction` through `createLibrary(...).toSpec()`; React-free | §5.5a (code ran as written) | **new** | Parse schema = full merged; prompt = subset (O11) or full behind a flag. |
| O11 | Pruned subset prompt | Keep N components, rewrite their `(A \| B)[]` child unions to kept members, drop group notes, ship own examples | §5.5 (MEASURED 1,477–2,503 tokens vs 9,189 full) | **new** | Unit-test that the final prompt never names a dropped component (gap 12). |
| O12 | Streaming render rules | Ignore `meta.errors` and `unresolved` until `set(full,true)`; render partial nodes inert; key by `statementId` else index | §5.6 table (MEASURED) | **new** | Port into the GPUIX mapper; covered by frame-prefix unit tests. |

---

## 4. Design values (sizes, colours, fonts, radii, timings)

None of the visual values below are Tom's. They are the shared-parity prototype's light, Claude-web-ish
defaults. **Replace them with the `gpuix-shell.json` theme tokens** (noir default; notes 17 and 25).
The numbers are listed so a builder can see what the adapter hard-codes and must lose.

| Value | Where | Label |
|---|---|---|
| Native `Reply` container: `flexDirection column, gap 12, padding 24, bg #f6f5f1, width/height 100%, overflow scroll` | `SP/src/native/adapter.ts:106` | MEASURED (code); replace |
| Native text: `color #242424, fontSize 15` | `adapter.ts:100` | replace |
| Native record card: `gap 8, padding 16, bg #ffffff, borderRadius 8` | `adapter.ts:101` | replace; radius 8 matches BRIEF §3.6 "rounded 8/12 inner corners" |
| Native action button: `padding 12, bg #e5ebe1 (pending #dddddd), borderRadius 6, focus border 2 #345c88, focusVisible outline 2 #345c88`; `role=button`, `aria-label`, `tabIndex 0`, `autoFocus` on the last-focused label | `adapter.ts:119-120` | replace colours; keep the a11y props |
| Web: chat column max 850 px, padding 32/32/48; reply `h2` 21 px Georgia; note 14 px/1.7; record left rule 2 px `#d4cec2`; action button radius 6, padding 9×13, 13 px; composer radius 10; user bubble radius `12 12 3 12` | `SP/src/openui/openui.css:1-36` | reference only. Fonts must be Anthropic Sans/Serif/Mono (BRIEF), not Georgia. |
| Replay pacing: 35 characters every 28 ms (~1,250 chars/s) | `OpenUIChat.tsx:69-72` | MEASURED (code) |
| Native activity presenter: at most one event every 600 ms | `SP/docs/native.md:21` | REPORTED |
| Generation timeout 90 s; status/health timeout 3 s; probe client 100 s | `local-server.ts:56,74,84`; `scripts/probe-model.ts:12` | MEASURED (code) |
| `max_tokens` 1800 (SP); Halogen default 16,384 on the strix; cap 65,536; Halogen engine `max_tok` 32,768 | `local-server.ts:91`; `strix.nix:58`; `/health` `max_tokens_cap`; journal 23:36:55 | MEASURED |
| Context: Halogen 262,144 (`/v1/models` `context_length`), 4 slots over one 262,144-position KV pool on the strix; Gufo default 131,072 per session, 2 sessions | `/v1/models`, journal; `gufo.nix:326-337` | MEASURED / REPORTED |
| Vision input: data URL or bare base64 only, `http(s)` refused, ≤3,686,400 px, side multiple of 32 | `/health` `vision` | MEASURED |
| Overlay geometry for `ask` (suggested): launcher family, `overlay` layer, top margin 108, 700×580, keyboard exclusive, Esc closes | BRIEF §3.3 (launcher) | INFERRED reuse |
| **Adopted by the synthesis (rev 2 pointer):** ask = 700×580 at top 108, keyboard exclusive. Header 46 high: clay mark 22 (`brand.mark` `#D97757`), title 16 "Ask", status word 12 `ink.muted` on the right ("thinking on strix…", "ready", "model unavailable"). Input row 48 at the **bottom**. Reply prose in Anthropic Serif 15/25, code in AnthropicMono 13/21. OpenUI buttons 34 high, drawn with `state.disabled` inks until validated. `brand.muted` field behind a streaming reply. The model id is never drawn | `docs/gpuix-shell/DESIGN.md` §8.9 (lines 945-967), type scale lines 315-322, tokens 150-153, geometry 254 and 469 | wave-1 synthesis, not Tom's words |
| Keybind: `$mod+a` → `gpuix-shell toggle ask`, **reserved, not activated** | `KEYS.md:185` | INFERRED by the synthesis |
| Streaming render cadence (rev 2 suggestion): re-parse on every SSE chunk (0.035 ms each, §5.6). Repaint at most every 50 ms. Bring each newly resolved child in **without animation** (Tacit/flat look) | §5.6 measurement | INFERRED |

---

## 5. Reusable code and data, with the technical spec

### 5.1 Endpoint

| Where the caller runs | Base URL | Status |
|---|---|---|
| strix (headless; agents, tests) | `http://127.0.0.1:8731` | **MEASURED** serving: `podman-halogen.service` active, listening on `0.0.0.0:8731` (`ss -ltn`), engine on loopback `:8730` (never admitted). |
| Zenbook client (where the shell runs) | `http://strix:8731` (= `10.42.0.2:8731`) | **INFERRED reachable, not measured from the Zenbook.** Halogen admits `port` on `enp191s0` iff `openLanPort`, which defaults to `autoStart` (`halogen.nix:319-344,586-589`). The strix sets `autoStart = true` (`strix.nix:41`; asserted `flake.nix:2262`). The client's route to the strix is the closet LAN (`prefsrc 10.42.0.16`) or tailscale0 (`hosts/client/strix-reachability.nix:21-22`). **Over tailscale0 the port is NOT admitted** (the rule is scoped to `enp191s0`). `http://strix:8731` is also the fleet default (`halogen.nix:466-473`, `pi.nix:45`). |
| Precedent on the client | `ssh strix '…'` | `screen-ocr-area:4-5,10` deliberately sends the image over ssh and lets the strix dial the model ("only the strix dials worker:8731", a stale comment). |
| After the Gufo cutover | same URL and port | `gufo.nix:307-311` ("Halogen's, so callers keep their URL across the cutover"); `/ready` readiness endpoint (`gufo.nix:63-69`, `GF/docs/SERVER.md:399`). |

There is **no authentication** on either server (`halogen.nix:46-50`; pi sends a dummy key, `pi.nix:182-199`).

**Recommendation (INFERRED):** the shell reads a runtime file `~/.config/gpuix-shell/model.json`, not Nix,
following the model-catalog ruling of 2026-10-10. The file is optional and built-in defaults apply:

```json
{ "base": "http://strix:8731", "transport": "http", "prefer": ["qwen3.8-flash-next", "halogen-qwen3.8-flash-next"],
  "maxTokens": 1500, "firstByteTimeoutMs": 20000, "totalTimeoutMs": 90000 }
```

`transport: "ssh"` falls back to `ssh strix curl -sN --data-binary @- http://127.0.0.1:8731/v1/chat/completions`
and reads the same SSE bytes from stdout. That matches the screen-ocr precedent when the LAN door is
closed, for example on the road over tailscale0.

### 5.2 Model id

- **MEASURED now:** `/v1/models` →
  `{"object":"list","data":[{"id":"halogen-qwen3.8-flash-next","object":"model","owned_by":"halogen","max_model_len":262144,"context_length":262144,"max_tokens_cap":65536,"max_tokens_default":16384,…}]}`
  (three runs at 23:27:57 CEST, 200, 0.65–1.34 ms each).
- **MEASURED again at revision 2** (`curl -s -m 5 http://127.0.0.1:8731/v1/models`, 3 runs at 2026-10-21
  12:01:50 CEST, all `200`, 2.5 / 1.2 / 1.2 ms, during a 206k-token prefill from another client). Full body,
  verbatim:
  ```json
  {"object":"list","has_more":false,"first_id":"halogen-qwen3.8-flash-next","last_id":"halogen-qwen3.8-flash-next",
   "data":[{"id":"halogen-qwen3.8-flash-next","object":"model","type":"model","display_name":"halogen-qwen3.8-flash-next",
            "created_at":"1970-01-01T00:00:00Z","owned_by":"halogen","created":0,"max_model_len":262144,
            "context_length":262144,"meta":{"n_ctx_train":262144,"n_ctx":262144},
            "max_tokens_cap":65536,"max_tokens_default":16384}]}
  ```
  The body is OpenAI-shaped (`object`, `data[].id`) with Anthropic-style list fields too (`has_more`,
  `first_id`, `display_name`, `created_at`). Neither the Halogen body nor Gufo's (see below) carries a
  "chat-capable" flag. Gufo's `architecture.input_modalities` is the only modality hint, so `discover()` must
  treat "has no `architecture`" as text-capable (Halogen).
- `/health` (MEASURED, 1.003 s) also reports `"model":"halogen-qwen3.8-flash-next"`, `"slots":4`,
  `"busy":false`, `"in_flight":0`, `"queued":0`, `"vision":{"enabled":true,…}`,
  `"chat_template":{…"thinking_control":true}`, `"reasoning_effort_default":"xhigh"`,
  `"structured_output":{"enabled":true,"response_format":["json_schema","json_object"],"sampling":"greedy only (temperature 0)",…}`,
  and `"version":{"api":"0.16.0","engine":"0.16.0"}`.
- **After the cutover:** Gufo serves `qwen3.8-flash-next` (`gufo.nix:330`). Alternates are `qwen3.8-27b`
  and `deepseek-v4-flash` (`strix.nix:110-127`), started only by `gufo-switch`. Gufo returns **404 for any
  other id** (`GF/docs/SERVER.md:892`, `GF/src/cli/serve/http_server.cpp:690-691` "requested model is not
  loaded"). Its `/v1/models` entries carry `architecture.input_modalities` (`["text","image"]` when the
  projector is loaded) and also list ready audio and image services, so filter for the text model.
- Halogen's alternate `halogen-qwen3.8-27b` shares the port (`strix.nix:89-100`) and answers any id.
- `~/.config/substrate/models.toml` names `halogen-qwen3.8-flash-next` as the default `pi` model
  (MEASURED). That is the factory's catalog, not the shell's. Do not read it from the shell.

**Discovery code (INFERRED; `discover()` is new, small and testable without a model):**

```ts
// pkgs/gpuix-shell/src/ask/model.ts
export interface ModelInfo { base: string; id: string; contextLength?: number; vision?: boolean }
export class ModelUnavailable extends Error {}
export async function discover(base: string, prefer: string[], signal = AbortSignal.timeout(3000)): Promise<ModelInfo> {
  const r = await fetch(`${base}/v1/models`, { signal }).catch(e => { throw new ModelUnavailable(String(e)); });
  if (!r.ok) throw new ModelUnavailable(`/v1/models ${r.status}`);
  const { data = [] } = await r.json() as { data?: Array<Record<string, any>> };
  const text = data.filter(m => !m.architecture || m.architecture.input_modalities?.includes("text"));
  const m = prefer.map(id => text.find(x => x.id === id)).find(Boolean) ?? text[0];
  if (!m) throw new ModelUnavailable("no text model loaded");
  return { base, id: m.id, contextLength: m.context_length ?? m.max_model_len,
           vision: m.architecture ? m.architecture.input_modalities.includes("image") : undefined };
}
```

### 5.3 Request shape (OpenAI-compatible chat completions, streamed)

What SP actually sent, MEASURED working against Halogen (probe 14:20:01Z, and the journal shows "think off"):

```jsonc
// SP/scripts/local-server.ts:88-98
{ "model": "<id>", "stream": true, "temperature": 0, "max_tokens": 1800,
  "enable_thinking": false, "chat_template_kwargs": { "enable_thinking": false },
  "messages": [ { "role": "system", "content": "<workspacePrompt>" },
                { "role": "user", "content": "<generationContext JSON>\n\nCurrent request: <text>" } ] }
```

**Portable shape for the shell (INFERRED from both servers' docs and source):**

```jsonc
{ "model": "<discovered id>",
  "stream": true,
  "stream_options": { "include_usage": true },        // Halogen lists it; Gufo adds usage.gufo timing (SERVER.md:144-150)
  "temperature": 0,                                    // greedy on both; Gufo's thinking-off default would be 0.7 (SERVER.md:96-99)
  "max_tokens": 1500,                                  // always send: the budget covers reasoning on both servers
  "chat_template_kwargs": { "enable_thinking": false },// ONE thinking control only
  "messages": [ { "role": "system", "content": SYSTEM_PROMPT },
                { "role": "user",   "content": CONTEXT_JSON + "\n\nRequest: " + userText } ] }
```

- Send **one** thinking control. Halogen accepts top-level `enable_thinking` and the
  `chat_template_kwargs` form (MEASURED `/health`: `supported` includes `enable_thinking`;
  `chat_template_kwargs: ["reasoning_effort","enable_thinking","preserve_thinking"]`). Gufo reads
  `chat_template_kwargs.enable_thinking` (`GF/src/cli/serve/openai_chat.cpp:673-681`;
  `SERVER.md:324`) and returns `invalid_reasoning` on conflicting controls (`SERVER.md:359`). Whether Gufo's
  chat route rejects an unknown top-level `enable_thinking` is **unverified**. Its error contract says
  "400 invalid request or unsupported field" (`SERVER.md:911`), so drop the top-level field.
- Response: SSE `data: {…}` lines. Content is in `choices[0].delta.content`; reasoning, if it ever
  appears, is in `delta.reasoning_content` and must be ignored. `finish_reason` arrives on the last
  choice (`"stop"` is required; `"length"` means truncated). Then `data: [DONE]`. An in-stream
  `{"error":…}` aborts. Errors follow the OpenAI shape on both servers (Halogen `"error_format":"openai"`;
  Gufo `SERVER.md:894-915`).
- Gufo also returns `Server-Timing: ttft;dur=…, inter_token;dur=…` (`SERVER.md:139-142`), which is free
  telemetry for a status line.
- Vision variant (A5): the user `content` becomes
  `[{type:"text",text:"…"},{type:"image_url",image_url:{url:"data:image/png;base64,…"}}]`, exactly as
  `screen-ocr:29-32` does.
- Structured variant (A2): add `response_format: {type:"json_schema", json_schema:{name, strict:true, schema}}`.
  Halogen enforces it **greedy only** (temperature 0) and refuses `pattern`, `format`, `allOf` and others
  (MEASURED `/health.structured_output`). Gufo supports the same request form (`SERVER.md:822-826`).

### 5.4 SSE transport: reuse `completionChunks` verbatim

`SP/src/model/stream.ts:2-27` (MEASURED unit-tested in `SP/tests/model.test.ts:15-21`: split UTF-8,
reasoning ignored, missing finish → throws). It takes a `ReadableStream<Uint8Array>`, so it works on a
`fetch` body and also on an ssh child's stdout wrapped with `Readable.toWeb`. Copy it to
`pkgs/gpuix-shell/src/ask/sse.ts` and keep its test. The in-process shell needs no NDJSON hop:
`readEvents` (`stream.ts:29-43`) exists only because the browser talks to the localhost bridge.

```ts
// pkgs/gpuix-shell/src/ask/generate.ts (INFERRED sketch)
import { completionChunks } from "./sse";
export async function* generate(m: ModelInfo, system: string, user: string, opts: { maxTokens: number; signal: AbortSignal }) {
  const res = await fetch(`${m.base}/v1/chat/completions`, { method: "POST", signal: opts.signal,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: m.id, stream: true, stream_options: { include_usage: true }, temperature: 0,
      max_tokens: opts.maxTokens, chat_template_kwargs: { enable_thinking: false },
      messages: [{ role: "system", content: system }, { role: "user", content: user }] }) });
  if (res.status === 404) throw new ModelUnavailable("model id not loaded (cutover?)");   // re-discover once
  if (!res.ok || !res.body) throw new ModelUnavailable(`chat ${res.status}`);
  let chars = 0;
  for await (const ev of completionChunks(res.body)) {
    if (ev.chunk) { chars += ev.chunk.length; if (chars > 32_000) throw new Error("program too long"); }
    yield ev;                                  // { chunk } … { finish }
  }
}
```

### 5.5 Generating an OpenUI system prompt from a component library (lang-core)

Three ways. All were exercised tonight with bun against `@openuidev/lang-core@1.0.1` from
`SP/node_modules` (MEASURED):

1. **In-code core library** (SP's pattern, no React). `defineComponent({name, description, props: z.object(…), component: null})`,
   `defineAction({name, description, params})`, then `createLibrary({id, root, components, actions})` and
   `library.prompt({preamble, additionalRules, examples})`. SP's 9-component workspace library gives a
   **4,757-character, 66-line** prompt with a short preamble (MEASURED rev 1). Rev 2: SP's *exported*
   `workspacePrompt` (`SP/src/openui/library.tsx:112-120`, its real preamble and rules) is **5,236 chars =
   1,181 Qwen tokens**. SP's one live request carried **1,670 prompt tokens** in total (system + context JSON +
   request; Halogen journal 2026-10-20 16:20:01, the line matching `probe.json`'s `observedAt`). The prompt contains: syntax rules,
   component signatures with descriptions, the Action section (built-ins `@ToAssistant`, `@OpenUrl`, plus
   custom actions such as `@ExecuteStep`), and "Hoisting & Streaming (CRITICAL)" telling the model to write
   `root = …` first (so the UI shell appears immediately), then the components, then the data.
2. **Pre-generated spec of the full default library**, no React import:
   ```ts
   import { generateSystemPrompt, createStreamingParser } from "@openuidev/lang-core";
   const spec = await Bun.file(".../playground-library.spec.json").json();   // {root, components, componentGroups, schema, promptOptions}
   const system = generateSystemPrompt({ library: spec, promptOptions: { ...spec.promptOptions, preamble: "…" } });
   const parser = createStreamingParser(spec.schema, spec.root);
   ```
   MEASURED sizes: `playground-library.spec.json` (82 components, root `Stack`, groups Layout | Content |
   Tables | Charts (2D) | Charts (1D) | Charts (Scatter) | Forms | Buttons | Data Display | Cards) →
   **34,392 chars** with its own `examples`, 28,590 bare. `chat-library.spec.json` (84 components, root
   `Card`) → **53,352 chars** with its `examples` and `additionalRules`, 26,490 bare. The upstream
   benchmark prompt `OU/benchmarks/system-prompt.txt` is 13,194 bytes.
   Upstream's own playground does exactly this, then calls an OpenAI-compatible `/chat/completions` with
   `stream:true` and `[system, user]` messages (`OU/docs/app/api/playground/stream/route.ts:12-45`; it
   uses `openuiExamples` from `@openuidev/react-ui/genui-lib/prompt-options`). The specs are regenerated by
   `OU/docs/package.json:6` (`openui generate lib/{chat,playground}-library.ts --spec`).
   `docs/generated/playground-system-prompt.spec.json` (54 components, no `promptOptions`) is **not referenced by
   any code** in the clone (grep). Treat it as a stale snapshot; it lacks ListBlock/ListItem, Icon, Text,
   InlineHeader, MetricIndicator*, all the card blocks, Chips and EditableTable.

   **Token counts, rev 2 (MEASURED, Qwen3.8 tokenizer, `generateSystemPrompt` from lang-core 1.0.1):**

   | Prompt | chars | tokens | chars/token |
   |---|---|---|---|
   | `playground-library.spec.json` + its 6 examples (82 comps) | 34,392 | **9,018** | 3.81 |
   | same, no examples ("bare"; rev 1 measured 28,590 chars) | 28,774 | 7,174 | 4.01 |
   | playground spec + 5 shell host components + `ShellAction` (§5.5a) | 35,116 | **9,189** | 3.82 |
   | `chat-library.spec.json` + examples + additionalRules (84 comps) | 53,352 | **14,624** | 3.65 |
   | `playground-system-prompt.spec.json` (54 comps, stale) | 17,704 | 4,485 | 3.95 |
   | 30-comp subset, unions **not** pruned, group notes kept | 15,401 | 3,982 | 3.87 |
   | 30-comp subset, unions pruned, notes dropped | 9,639 | **2,503** | 3.85 |
   | 12-comp subset, unions not pruned | 8,676 | 2,241 | 3.87 |
   | 12-comp subset, unions pruned, notes dropped | 6,491 | **1,673** | 3.88 |
   | `subsetSpec(askSpec, [Stack, Card, CardHeader, TextContent, Buttons, Button, WorkspaceSlot, AgentRow])` (§5.5a code, run verbatim), still lists `@ShellAction`, no `Form` leak | 5,715 | **1,477** | 3.87 |
   | fixed overhead (Stack only, no notes): syntax rules, hoisting, verification | 2,871 | **710** | 4.04 |
   | SP `workspacePrompt` | 5,236 | 1,181 | 4.43 |
   | `OU/benchmarks/system-prompt.txt` | 13,080 | 3,364 | 3.89 |
   | SP's generated program (`evidence/model/generated.openui`) | 193 | 51 | 3.78 |

   OpenUI prompts run about 3.8 chars per token. Rev 1's "~3–4 chars/token" guess was right.
3. **The OpenUI CLI** `openui generate ./src/library.ts --out system-prompt.txt` writes the prompt and a
   `.spec.json` (`system-prompts.mdx:20-60`). It fetches through `npx`/`bunx`, so use it for a one-time
   dev step, never inside the Nix build. Better: a 5-line bun script calling `library.toSpec()` at build time.

Prompt options (`OU/packages/lang-core/src/library.ts:104-123`): `preamble`, `additionalRules[]`,
`examples[]`, `toolExamples[]`, `tools[]` (Query targets), `editMode` (patch output; merge with
`mergeStatements`), `inlineMode` (prose + fenced programs), `toolCalls` (Query/Mutation/@Run), `bindings`
(`$vars`, @Set/@Reset), `builtinFunctions`. Defaults: `toolCalls` on iff tools are given, and `bindings`
follows `toolCalls` (`system-prompts.mdx:93-99`). **For the shell v1, set none of the tool or binding flags**
(the prompt stays small and the model cannot emit Query or Mutation).

**Do not use OpenUI Gateway, Autofix or `cloud: true`** (`reliability.mdx`, `system-prompts.mdx:101-127`):
they send the library and generations to Thesys's cloud. **Telemetry:** lang-core runs a postinstall
installation ping (`OU/packages/lang-core/postinstall.cjs`). Runtime telemetry is opt-in, but it counts
*server-side* `generateSystemPrompt()`/`createParser().parse()`, and a bun shell process is server-side by
their definition (`README.md:157-176`). Set `OPENUI_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1` in dev shells and in
the systemd unit environment (INFERRED hygiene; the Nix sandbox has no network anyway).

**Prompt-size trick (rev 1 INFERRED → rev 2 MEASURED, with a catch):** build the *prompt* from a curated
subset of the default library (filter `spec.components` and `componentGroups` before
`generateSystemPrompt`), but *parse* with the full `spec.schema`. `generateSystemPrompt` accepts a filtered
spec without complaint. The full schema parses components that are absent from the prompt: `Slider` parsed
and was validated (it raised `null-required` on a bad argument, so it was checked, not ignored).
**The catch:** each pre-built `signature` string carries its full child union. With 30 components kept,
`Card(children: (TextContent | … | ImageGallery | Form | EditableTable | SnippetCardBlock …)[]` still names
dropped components (`Form` ×5, `EditableTable` ×4, `ImageGallery` ×3 in the subset prompt). The group notes
also mention dropped ones (`Modal`). A model would then emit components it was never taught. Fix, MEASURED to work:
rewrite each `(A | B | …)[]` union in the kept signatures down to its kept members and drop the group
notes. After that, no dropped name remains, and the prompt is 1,673 tokens for 12 components or 2,503 for 30.
The ~20-line rewrite is in §5.5a. Upstream's playground signature for `Stack` is `children: any[]`,
so `Stack` accepts anything, shell host components included.

### 5.5a Shell host components + `ShellAction` inside the default library, React-free (rev 2, MEASURED)

The default component *schemas* cannot be imported without React. Each `genui-lib/*/schema.ts` imports
`X.ref` from a sibling `index.tsx` that imports `@openuidev/react-lang` and React components
(`OU/packages/react-ui/src/genui-lib/Card/schema.ts:1-13`). The **spec JSON** is the React-free carrier: it
has `components` (prompt signatures), `componentGroups`, `schema` (a plain JSON Schema whose `$defs.<Name>`
property order is the positional ABI) and `promptOptions`. A core library made with `component: null` has
`toSpec()` (`OU/packages/lang-core/src/library.ts:316-325`), which emits the same shape plus `actions` and
`schema.actions`. Merging the two works. This exact code ran under bun 1.4.2 with lang-core 1.0.1 and zod 4.3.6:

```ts
import { createLibrary, defineComponent, defineAction, generateSystemPrompt,
         createParser, createStreamingParser, evaluateRoot } from "@openuidev/lang-core";
import { z } from "zod/v4";
import base from "./openui/playground-library.spec.json";   // vendored copy of OU/docs/generated/…

const ShellAction = defineAction({ name: "ShellAction",
  description: "Ask the shell to run one supplied action id from the context's actions list; never invent ids. arg is the optional argument the list shows.",
  params: z.object({ id: z.string(), arg: z.string().optional() }) });
const host = (name: string, description: string, props: z.ZodObject<any>) =>
  defineComponent({ name, description, props, component: null });
export const shellLib = createLibrary({            // NOTE: no `root` — createLibrary throws if root is not among *its* components
  id: "gpuix-shell.ask@1",
  components: [
    host("WorkspaceSlot",  "One herdr/Sway workspace slot (1-10) with its live name and agent status; the shell fills the facts.", z.object({ slot: z.number() })),
    host("AgentRow",       "One herdr agent by exact supplied id; live status comes from the shell, never from you.", z.object({ id: z.string() })),
    host("Battery",        "Live battery level and charging state.", z.object({})),
    host("AudioSink",      "A live audio output by supplied id (omit for the default sink) with volume and mute.", z.object({ id: z.string().optional() })),
    host("NotificationRef","One notification by exact supplied id, rendered by the shell.", z.object({ id: z.number() })),
  ],
  componentGroups: [{ name: "Shell (live facts, host-rendered)",
    components: ["WorkspaceSlot", "AgentRow", "Battery", "AudioSink", "NotificationRef"],
    notes: ["- Shell components take ids only; never write statuses, percentages or names yourself."] }],
  actions: [ShellAction],
});
const s = shellLib.toSpec();
export const askSpec = { ...base,
  components: { ...base.components, ...s.components },
  componentGroups: [...base.componentGroups, ...(s.componentGroups ?? [])],
  actions: s.actions,                                                    // → listed in the prompt's Action section
  schema: { ...base.schema, $defs: { ...base.schema.$defs, ...s.schema.$defs },
            properties: { ...base.schema.properties, ...s.schema.properties }, actions: s.schema.actions } };
export const askPrompt = generateSystemPrompt({ library: askSpec,
  promptOptions: { preamble: "You build small native panels for Tom's Linux desktop shell. Use only ids from the context.",
                   examples: base.promptOptions.examples } });
export const newAskParser = () => createStreamingParser(askSpec.schema, "Stack");

// optional subset: keep N components and prune their child unions (the §5.5 catch)
export function subsetSpec(spec: typeof askSpec, keep: string[]) {
  const prune = (sig: string) => sig.replace(/\(([A-Z][A-Za-z]*(?: \| [A-Z][A-Za-z]*)+)\)\[\]/g, (_m, u: string) => {
    const k = u.split(" | ").filter(n => keep.includes(n)); return k.length ? `(${k.join(" | ")})[]` : "any[]"; });
  return { ...spec,
    components: Object.fromEntries(Object.entries(spec.components).filter(([n]) => keep.includes(n))
      .map(([n, c]: [string, any]) => [n, { ...c, signature: prune(c.signature) }])),
    componentGroups: spec.componentGroups.map((g: any) => ({ ...g, notes: [], components: g.components.filter((c: string) => keep.includes(c)) }))
      .filter((g: any) => g.components.length) };   // use for the PROMPT only; parse with spec.schema (full)
}
```

Results (MEASURED):
- The merged prompt is 35,116 chars (9,189 tokens). Its Action section lists
  `- @ShellAction(id: string, arg?: string) — Ask the shell to run one supplied action id …`
  beside `@ToAssistant` and `@OpenUrl`, and the ActionExpression rule now reads "(@ToAssistant, @OpenUrl, @ShellAction)".
- This sample parses with `errors: []`, `unresolved: []`, `orphaned: []`, 6 statements:
  ```
  root = Stack([head, slots, ctl])
  head = CardHeader("Meeting setup", "Audio and workspaces")
  slots = Stack([WorkspaceSlot(3), WorkspaceSlot(10)], "row")
  ctl = Buttons([mute, chrome])
  mute = Button("Mute mic", @ShellAction("audio.mute", "source"), "secondary")
  chrome = Button("Jump to Chrome", @ShellAction("workspace.focus", "10"))
  ```
- `evaluateRoot(parsed, { library: shellLib, store: null, errors, ctx: { getState: () => null, resolveRef: () => null,
  actions: askSpec.schema.actions, functions: {} } })` returned the tree with no errors. Evaluation needs only
  the **shell** library object, not React defs for Stack/Button. Each Button's `action` became
  `{steps:[{type:"custom_action", name:"ShellAction", params:{id:"audio.mute", arg:"source"}}]}`. That is the
  same shape SP's `validateProgram` walks (`SP/src/openui/host.ts:65-77`), so the `ExecuteStep` checks port
  over with `name === "ShellAction"`.
- What the parser does **not** catch, so `validateAsk` must: `@OpenUrl("https://…")` parses clean (it is a
  built-in). `Frobnicate(1)` → `unknown-component` (statement dropped). `@ShellAction()` → `missing-required`.
  An invented id such as `@ShellAction("rm.rf")` parses clean (MEASURED: `errors: []`); only the host catalog can refuse it.
- The snippet above was re-extracted from this file and run as written, with only the import paths changed. It printed
  the 35,116-char prompt and the subset numbers in the token table.

### 5.6 The streaming parse API (what a native renderer consumes)

From `OU/packages/lang-core/src/parser/parser.ts:478-488,667-680,749-772` and `types.ts:72-86,285-311`:

```ts
createParser(schema: LibraryJSONSchema, rootName?: string): { parse(text): ParseResult }
createStreamingParser(schema, rootName?): {
  push(chunk: string, complete?: boolean): ParseResult;   // append
  set(fullText: string, complete?: boolean): ParseResult; // diff against buffer; resets if not an append
  getResult(complete?: boolean): ParseResult;
}
interface ParseResult {
  root: ElementNode | null; rootExpression?: ASTNode;     // rootExpression = runtime-chosen entry (root = $x ? A : B)
  meta: { incomplete: boolean; unresolved: string[]; orphaned: string[]; statementCount: number; errors: ValidationError[] };
  stateDeclarations: Record<string, unknown>; queryStatements: …[]; mutationStatements: …[];
}
interface ElementNode { type: "element"; statementId?: string; typeName: string; props: Record<string, unknown>;
  partial: boolean; /* + hasDynamicProps */ }
evaluateRoot(parsed, { library, store: null, errors: OpenUIError[],
  ctx: { getState, resolveRef: () => null, actions: library.toJSONSchema().actions, functions: library.functions } })
```

Behaviour (spec, MEASURED in part with bun):
- Statements complete at a depth-0 newline. The trailing incomplete statement is auto-closed, so the
  first `root = Stack([…])` line already yields `root` with unresolved children. **MEASURED:** a 3-line partial
  program gave `{root:"Stack", incomplete:true, unresolved:[], statementCount:3, errors:[]}`, then
  `incomplete:false` after `set(full, true)`.
- An existing statement id is replaced only once its expression no longer needs auto-closing (no flicker of
  half-typed props) (`parser.ts:624-633`). A `$var` at the very end of the buffer is held back until complete (`parser.ts:635-643`).
- "When the stream ends, the result equals a parse of the full text" (`specification/index.mdx:171-173`;
  SP measured that 7/7 streamed parses matched batch parses, `openui-method.md:111`).
- Renderers hold errors back until stream end (`specification/index.mdx:53`). Queries and mutations never
  run during streaming; custom controls must disable themselves while streaming (`openui-method.md:99-101`).
- Error codes (`specification/index.mdx:148-165`): `unknown-component` (dropped), `missing-required`,
  `null-required`, `type-mismatch`, `excess-args`, `inline-reserved`, `unknown-function`, `no-root`
  (warning when the fallback works), `parse-failed`, `runtime-error`. Skip `severity:"warning"` when
  reporting errors back to a model.
- Grammar, in short (`syntax.mdx`, `specification/index.mdx:8-33`): one `identifier = Expression` per line;
  `root` is the entry; arguments are **positional in Zod key order** (so prop order is the ABI:
  `openui-method.md:119`); `null` skips an optional argument; forward references are allowed; the last
  definition wins; `@Name(args)` is a function or action; `Action([@a, @b])` sequences actions; built-in
  actions are `@ToAssistant(msg, ctx?)`, `@OpenUrl(url)`, `@Set($v, x)`, `@Reset($v…)`, `@Run(ref)`, and a
  custom `@Name(...)` emits `{type:"Name", params}` to the host.

**Rev 2: frame-by-frame behaviour, MEASURED.** I fed the §5.5a sample (331 chars) through
`createStreamingParser(askSpec.schema,"Stack").set(prefix, last)` one character at a time, 331 frames, and
ran `evaluateRoot` on every frame:

| Chars typed | What `ParseResult` shows | Renderer rule (INFERRED) |
|---|---|---|
| `root = S` … `root = Stack` (8–12) | `root:null`, `unresolved:["S"]`, then `["St"]`, … `["Stack"]`. **`meta.errors:[no-root]`** ("root does not evaluate to a component") | Show nothing but the "thinking" status. Never surface errors before the stream ends. |
| `root = Stack([` (14) | `root: Stack, partial:true, children:[]`, errors `[]` | Draw the empty panel frame now. This is the "UI shell appears immediately" moment. |
| `root = Stack([head, slots, ctl])` (32) | root complete (`partial:false`, `incomplete:false`), `unresolved:["head","slots","ctl"]` | Unresolved children are placeholders. Skip them or draw hairline skeleton rows. |
| `head = C` … `head = CardHeader` (41–50) | `unresolved` holds the **half-typed type name** (`"C"`, `"Ca"`, … `"CardHeader"`) as if it were a reference | Never print `unresolved` names. They are not real references until the stream ends. |
| `head = CardHeader(` (51) | the child appears as `CardHeader`, `partial:true` | Render it. Its text props grow as they stream. |
| `… WorkspaceSlot(` / `Buttons(` / `Button(` (121, 166, 196, 275) | **one frame with `meta.errors.length === 1`** (`missing-required`: the call is auto-closed with no args), then `[]` on the next char | Same rule: errors are only read after `set(full, true)`. |
| `mute = Button("Mu` (197–201) | Button `partial:true`, `props:{label:"M"}` → `"Mu"` → `"Mut"` …; **no `action` prop yet** | Labels grow one character at a time, which is the "streaming" feel. A partial Button is **inert** (no listener) even when its action has arrived. |
| end, `set(full, true)` (331) | `incomplete:false`, `errors:[]`, 6 statements; **batch parse == streamed parse** (JSON-equal) | Run `validateAsk`, then attach listeners. |

- `evaluateRoot` on all 332 frames (the 331 above plus the final `set(full, true)`): **0 throws, 0 runtime errors**. It is safe to call on every partial frame.
- **Cost:** on the largest default example (1,942 chars, 29 statements, full 82-component schema), `set()` per
  character took p50 **0.035 ms**, p90 0.061 ms, max 1.54 ms. All 1,942 re-parses together took 85 ms. `push()` in 4-char chunks took
  p50 0.031 ms. Parsing is free next to a 50 ms repaint budget: re-parse on every SSE chunk and coalesce only the
  *paint*.
- `set()` "diffs against buffer; resets if not an append" (`parser.ts:749-772`). Prefer `push(delta)` with
  SSE deltas and use `set(full, true)` once at the end. Both gave identical final trees.

### 5.7 Latency expectations

| Operation | Number | Label / source |
|---|---|---|
| `GET /v1/models` on localhost | 0.65–1.34 ms (3 runs); **1.2–2.5 ms during a 206k-token prefill** (3 runs) | MEASURED 23:27:57 and 2026-10-21 12:01:50 |
| `GET /health` | 1.003 s (it PINGs the engine: `engine.probe_s 1.001`) | MEASURED, so keep it off the hot path |
| Prefill, tiny prompt (23 tokens) | 0.37 s | MEASURED journal 23:21:03 (another client) |
| Prefill, 1,161 tokens | 1.04 s | MEASURED journal |
| Prefill, 9,123 / 11,907 tokens | 6.18 s / 7.99 s (1,477 / 1,491 tok/s) | MEASURED journal; the 11,907 one at 23:22:39 (another reader's probe, I believe an OpenUI full-library prompt) |
| Prefill rate, large uncached prompts | p50 **1,641 tok/s** (p10 1,574, p90 1,691; n=97) | MEASURED journal since 2026-10-17 |
| **Prefill by size band (rev 2, new tokens, n=202 lines 10-17 → 10-21 12:02)** | <500: p50 384 tok/s, 0.66 s (n=8) · **500–2k: p50 973 tok/s, 1.30 s (n=79)** · **2k–6k: p50 1,171 tok/s, 2.07 s (n=17)** · 6k–15k: 1,483 tok/s, 7.08 s (n=2) · 40k–100k: 1,680 (n=18) · >100k: 1,637, 114 s (n=78) | MEASURED journal. Small prompts run well below the large-prompt rate, so a fixed cost dominates under ~2k tokens |
| Decode, thinking off | 53.8–62 tok/s (p50 55.9, n=7); 79.6 tok/s burst on 8 tokens. **Rev 2: p50 58.9, p10 53.8, p90 62.0 (n=12)**; 2026-10-21 08:15–11:57: 57.2–64.0 tok/s on 48–54-token replies | MEASURED journal (MTP drafter, greedy) |
| Decode, thinking on | p50 49.4 tok/s (n=95). Rev 2: p50 51.4 (n=173, head-on lines) | MEASURED journal |
| SP end-to-end, 4-line program (193 chars), 4.7k-char prompt + ~1.5k-char context | **3,271 ms** total | MEASURED by SP (`evidence/model/probe.json`) |
| **SP's generation split (rev 2)** | prompt **1,670 tokens**, prefill **1.36 s** (all new; KV pool was 100 % full from other lanes at the time), 52 tokens decoded in **0.85 s = 61 tok/s** (MTP, 17 rounds), think off. That leaves ≈1.0 s of the 3,271 ms for HTTP, the bridge and the client | MEASURED journal 2026-10-20 16:20:01 |
| Prefix cache across idle hours | 2026-10-21 requests reused a 192-token prefix after 165 s, 63 s, 9,319 s and **13,302 s (3.7 h)** ("192 cached, 10.5–15.3 %"). Agent lanes reuse 59–245k-token prefixes 1 s apart | MEASURED journal. A fixed system prompt is plausibly reused between asks; a 9k-token prefix after hours is **not** measured |
| Example: 11,907-token prompt + 527 output tokens | 7.99 s + 9.80 s ≈ **18 s** | MEASURED journal 23:22:39–57 |
| Warm restart after a crash | 52 s to engine; 62 s to healthy | MEASURED tonight (§0) |
| Cold load (weights not in page cache) | "minutes"; unit allows 45 min; health start period 20 min | REPORTED `halogen.nix:101-119,148-149` |
| Engine stall under host memory compaction | 45–180 s of silence, then watchdog kill | MEASURED tonight (§0) |
| Concurrent big lanes | prompts p50 177k tokens, prefill p50 108 s (think-on agent lanes); KV pool hit 92–99 % earlier tonight | MEASURED journal. A shell request admitted beside them prefills in 32k pieces with decode ticks between (journal 23:36:55), so it waits behind them |

**Expected `ask` latency (INFERRED from the rates above, on an idle server):**
- Shell-sized library prompt (~2–3k tokens) plus a context snapshot (~0.5–1k tokens): prefill ≈ 2–2.5 s.
  The `root` line (10–20 tokens) is visible ≈ 2.5–3 s after Enter. A 300-token program finishes in
  ≈ 8 s; a 600-token one in ≈ 13 s.
- The full default library prompt (~8–14k tokens, assuming ~3–4 chars/token): prefill ≈ 5–9 s before
  anything appears, then the same decode.
- Halogen's prompt cache (mode 2, prefix resume) should cut the repeated system-prompt prefix:
  "closest earlier: 262 tokens shared with a request 289s ago" shows prefix matching at work. The
  effective size is unclear: `/health` says `prompt_cache.cap_mb 110`, while the startup log says
  "2.7 GiB prompt cache in RAM". **UNMEASURED** whether a 3k or 10k-token system prefix stays warm between asks.
- Gufo after the cutover: no measurement on this box. 2 sessions instead of 4 slots, so more queueing.
- UX consequence: show a "thinking on strix…" status at once, render on the first `root`, keep Esc =
  cancel, and offer "Replay last" or the plain list when the model is down. Tom: "performance is not
  really the thing i m looking for here", so a 3–10 s generation is acceptable for an exploratory surface.

**Rev 2 recomputation with MEASURED token counts (§5.5) and band rates (still INFERRED arithmetic, idle server, cold prefix):**

| System prompt | + context ≈ 700 tok | Prefill (band rate) | `root` visible | 150-tok program done | 400-tok program done |
|---|---|---|---|---|---|
| pruned subset + shell comps (1,477–2,503 tok) | 2.2–3.2k | ≈ 2.0–2.8 s (≈1,100 tok/s) | ≈ 2.3–3.1 s | ≈ 4.6–5.4 s | ≈ 9–10 s |
| full default + shell (`askSpec`, 9,189 tok) | 9.9k | ≈ 6.7 s (1,483 tok/s) | ≈ 7 s | ≈ 9.3 s | ≈ 13.5 s |
| chat library (14,624 tok) | 15.3k | ≈ 10 s | ≈ 10.3 s | ≈ 12.6 s | ≈ 17 s |
| any of the above with the system prefix **cached** | only the context is new | ≈ 0.7–1.3 s (journal: 1,065–1,775 new tokens took 0.92–1.72 s) | ≈ 1–1.5 s | ≈ 3.5–4 s | ≈ 8 s |

Decode is taken at 59 tok/s. The SP sample program is 51 tokens and the §5.5a sample 97 (MEASURED, tokenizer), so a
"quick panel" of 100–200 tokens is the realistic size. **Recommendation:** ship v1 with the pruned
subset + shell components (≈1.5–2.5k tokens). It costs a third of the time to first paint and keeps the
vocabulary small enough for the local Flash model to follow (generation quality on large libraries is unmeasured, §6). Put "openui fully" (the full `askSpec`) behind
a flag or a launcher modifier and let Tom compare. The parse schema stays full in both cases, so nothing the model emits is lost.

### 5.8 Minimal design: `gpuix-shell ask` (prompt → stream → native render) — EXPLORATORY

Not on the critical path (BRIEF §3.7). Everything here is **INFERRED** design. Note 14 §6.2 lists the
same missing pieces from the adapter side; this section adds the model side and fixes the order.

**Entry and window.** `gpuix-shell ask [TEXT]` sends `{"cmd":"ask","text":…}` to `shell.sock` and toggles an
`ask` overlay process: layer `overlay`, launcher geometry, keyboard exclusive. The launcher can hand off
too: a question-shaped query puts an "Ask" row first, as Tacit's SearchWidget does (note 20:221).
There is no bar button (#51 ruling), no microphone (speech input is out), and no resident chat history
sidebar (#247 ruling). Keybind: defer to KEYS.md. **Rev 2:** KEYS.md:185 reserves `$mod+a` →
`gpuix-shell toggle ask` (not activated), and DESIGN.md §8.9 fixes the window (header 46, input 48 at the
bottom, Serif reply prose, buttons disabled until validated). SCOPE.md §20 makes it P2 (S-200, S-201) with
a 4k-token cap and no network in tests.

**Process pipeline:**

```
text ─▶ context snapshot (host) ─▶ discover() ─▶ generate() SSE ─▶ parser.push(chunk) ─▶ render(partial, inert)
                                                                            │  (coalesce ≤ 1 render / 50 ms)
                                                       finish=="stop" ─▶ parser.set(full,true) ─▶ validateAsk()
                                                                            │ ok                      │ fail
                                                                 render(interactive) ◀─┘      error card + "Show program"
action click / Enter ─▶ resolveShellAction(event) ─▶ catalog.run(id, args) ─▶ receipt card (role=status)
Esc ─▶ AbortController.abort() (server cancels within ~1 s) ─▶ close
```

**Library `gpuix-shell.ask@1` (new):** (rev 2: §5.5a has the working React-free construction, merging the
host components and `ShellAction` into the default spec; use `subsetSpec` for the v1 prompt and the full schema for parsing)
- Base it on the default library (Stack, Card, CardHeader, TextContent, Callout, Table/Col, ListBlock/ListItem,
  Tag/TagBlock, Steps/StepsItem, Buttons/Button, Separator, Tabs/TabItem, Accordion, MetricIndicator*,
  Bar/Line/PieChart), so "openui fully" holds and the default-library native mapping (note 14's lane) is reused.
- Add **host-filled shell components** whose props are only ids. The model places them and the host
  renders live facts, so the model never types a battery percentage or an agent status ("An LLM must
  not guess operational status"):
  `WorkspaceSlot(slot: 1..10)`, `AgentRow(workspaceId)`, `Battery()`, `AudioSink(id?)`, `Network()`,
  `BluetoothDevice(id)`, `NotificationRef(id)`, `NowPlaying()`. Each renders "not found: id" on a bad id,
  as `ContactRecord` does (`SP/src/openui/library.tsx`, `adapter.ts:112-117`).
- **One custom action:** `ShellAction(id: string, arg?: string)` with `description` "Ask the shell to run one
  supplied action id; never invent ids". It is the `ExecuteStep` pattern (`contract.ts:4-8`). The context
  message lists the allowed ids with labels, like `availableSteps` in `programs.ts:57`.
- Allowed built-ins: `@ToAssistant(text, ctx)` = a follow-up turn (re-prompt with the previous program as
  context, optionally `editMode` + `mergeStatements`). Refused at validation: `@OpenUrl` (or route https only
  to Chrome on workspace 10 after a host allowlist), `@Set`/`@Reset`/`@Run`, `Query`/`Mutation` (v1), and `Assign`.

**Context snapshot (host → user message JSON):** focused workspace and outputs (Sway IPC), the nine herdr
slots with name and status glyph (`herdr workspace list` / `herdr api snapshot`), battery, sinks, network,
paired Bluetooth devices, unread notification ids and summaries (only if the text mentions
notifications), and the allowed action catalog. Cap it at about 1k tokens. Never include secrets (Wi-Fi
PSKs, Navidrome tokens).

**Action catalog (host, typed; examples):** `workspace.focus:<1..10>`, `herdr.focus:<wsId>`,
`audio.volume:<0..100>`, `audio.mute`, `audio.route:<sinkId>` (wrap `audio-route`), `bt.connect:<id>`,
`bt.disconnect:<id>`, `brightness:<0..100>`, `theme:<noir|claude-dark|claude-light>` (`~/.local/bin/theme`),
`notify.dismiss:<id>`, `notify.dismissAll`, `launch:<desktopId>`, `music.play:<id>` (music lane),
`power.lock`. Destructive or session-ending ids (`power.suspend`, `power.logout`, `herdr.close`) need a
second native confirmation that the program cannot pre-fill. `wifi.connect` hands off to the Wi-Fi menu
(it needs a secret) rather than running from generated UI. Every id resolves to the **same function the
keybind or menu calls**, which gives Tom's human-click = agent-call parity.

**Validation `validateAsk(parsed)`:** port `SP/src/openui/host.ts:28-80`. Root must be `Stack` or `Card`
and not `partial`; no `meta.errors` except warnings; `unresolved` and `orphaned` empty; no
query/mutation statements; walk the syntax for forbidden `Comp` names and `Assign`; `evaluateRoot` without
errors; every action-bearing control has exactly one `ShellAction` or `ToAssistant` step; every `ShellAction`
id is in the snapshot's catalog, and its `arg` matches the catalog's type. The **host re-checks params at
dispatch** (`resolveStep` pattern, `host.ts:82-99`), because the parser lets union and strict-object
extras through (`openui-method.md:109-111`).

**Renderer: two options; pick B for v1.**
- **B (proven path):** lang-core + `evaluateRoot` → own `ElementNode → <@gpuix/react JSX>` mapper (themed).
  Partial frames: render whatever `root` exists. Children with `partial:true` or missing required props
  render as a hairline skeleton row. **No event listeners until validation passes** (SP's native adapter
  already attaches listeners only when not pending, `adapter.ts:123`).
  Rev 2 measured what B receives (§5.6 table): an empty `Stack` at the first `[`, children appearing as
  `partial:true` with text props growing one character at a time, transient `missing-required`/`no-root`
  errors and half-typed names in `unresolved` that must be ignored until the end, and `evaluateRoot`
  safe on every frame. Mapper sketch: `ElementNode → <view>` keyed by `statementId` when present, else
  `parentKey/index`. MEASURED: statement-level nodes carry `statementId` (`root`, `head`, `slots`, `ctl`,
  `mute`, `chrome`), while inline children such as `WorkspaceSlot(3)` inside an array have none. The keys
  are stable across frames, so React/GPUIX reuses nodes. `partial` → no listeners and a `brand.muted` underlay (DESIGN §8.9).
  Unknown `typeName` → nothing (the parser already dropped it). Host components → live-data React
  components that subscribe to the shell's stores by id.
- **A (experiment for "openui fully"):** import `@openuidev/react-lang` through its **`react-native` export
  condition**. That entry is the web entry minus the devtools/DOM bootstrap (`OU/packages/react-lang/src/index.native.ts:1-4`,
  `package.json` exports). Its `Renderer` renders intrinsic `div`s and guards `document` (`Renderer.tsx:194-201`),
  so under `@gpuix/react` with GPUIX-rendering component implementations it *may* give the real `$state`,
  forms, Query refresh and streaming semantics for free. **Untested**: `react-dom` is a declared peer, and
  the CSS-ish inline styles (`position:absolute`, `transition`) may not map to GPUIX. Note 14 recommends
  against the *web* entry. The native entry is a different question.

**Persistence and replay:** store each finished ask as an OpenUI stored message
(`]]>openui:content?library=gpuix-shell.ask%401` … `]]>openui:context` {prompt, snapshotHash, model id,
ms} … `]]>openui:end`, `specification/index.mdx:127-146`) under `$XDG_STATE_HOME/gpuix-shell/ask/`
(INFERRED path). "Replay last" re-renders it with live host data and no model call.

**Tests (bun, no compositor):** `completionChunks` fixtures (copy `SP/tests/model.test.ts:15-26`);
`discover()` against a stub server returning Halogen-shaped and Gufo-shaped `/v1/models`;
streaming-parser frames from `SP/evidence/model/generated.openui` cut at 1/7/35-character widths, as SP
did with three chunk widths; `validateAsk` refusal cases (OpenUrl, invented action id, Query, Assign,
orphan, truncated). The compositor smoke renders a **fixed program** in the overlay under
`runtime-test --render-node`. **No test may dial `strix:8731`** (§0).

**Build order (INFERRED):** (1) `sse.ts` + `model.ts` + tests; (2) the shell library and `validateAsk` + tests;
(3) the mapper rendering a fixed program (smoke); (4) replay-driven streaming render; (5) live generation
behind a `--live` flag, tried by Tom in the morning when the box is quiet.

### 5.9 "Notification summary" — EXPLORATORY

- **Trigger:** on demand only. A "Summarize N unread" control appears in the notification center once
  there are ≥5 unread, plus `gpuix-shell notifications summarize`. **No timer, and no automatic run on each
  notification** (2026-09-30 scheduled-work ruling; every request is a GPU job on a shared, memory-pressed box, §0).
- **Shape:** JSON-schema structured output, not OpenUI. The notifications surface already has native
  rows, so the model only needs to group and headline:
  ```json
  {"type":"object","additionalProperties":false,"required":["groups"],"properties":{
    "groups":{"type":"array","maxItems":8,"items":{"type":"object","additionalProperties":false,
      "required":["app","headline","ids"],"properties":{
        "app":{"type":"string","maxLength":40},"headline":{"type":"string","maxLength":120},
        "ids":{"type":"array","items":{"type":"integer"}}}}},
    "needsAttention":{"type":"array","items":{"type":"integer"}}}}
  ```
  Send `temperature: 0` (Halogen's schema mode is greedy only). Avoid the refused keywords (`pattern`,
  `format`, …; MEASURED `/health`). The host drops any id not in the input set and renders each group
  with its real rows one click away.
- **Rules:** label it "summary · local model" (Anthropic Sans, muted). Show summary text only, never a
  claimed status. Failure or timeout means the plain list, with no error toast. Input per notification:
  `{id, app, summary, body≤300 chars, age, urgency}`. Exclude apps on a denylist (OTP or password apps)
  from what is sent. Everything stays on the LAN.
- **Latency (INFERRED):** 20 notifications ≈ 1.5k tokens of input + schema; ~1.5 s prefill, ~150 output
  tokens ≈ 3 s, so ~5 s total.

### 5.10 "Quick controls, generated" — EXPLORATORY

- **Idea:** "make me a meeting strip: mute mic, headset volume, DND, jump to Chrome" → an OpenUI program
  over the §5.8 library (`Stack([AudioSink("headset"), Button("Mute mic", @ShellAction("audio.mute","source")), …])`).
  It is validated the same way, then **pinned**: saved as a stored message and shown as a small layer
  surface or as a section of the controls panel.
- **Generate once, execute many** (`architecture.mdx`, "The LLM generates the interface once. After that,
  the UI runs on its own"): a pinned panel re-renders from live host data and dispatches catalog actions
  with **zero further model calls**. Editing ("add brightness") uses `editMode: true` + `mergeStatements`,
  where the model outputs only the changed statements (~60 tokens instead of ~400, `architecture.mdx`).
- **v2:** allow `Query("audio_sinks")`, `Query("bt_devices")`, `Query("herdr_agents")` mapped to a
  read-only `toolProvider` function map in the shell. Panels then refresh reactively with no model.
  Mutations stay refused; writes go only through `ShellAction`.
- **Pins live in** `$XDG_STATE_HOME/gpuix-shell/panels/*.openui` (runtime state, not Nix). A launcher
  section "Panels" lists them. INFERRED.

### 5.11 Exact paths: reusable code and data

| What | Path:lines | Use |
|---|---|---|
| SSE parser | `SP/src/model/stream.ts:2-27` | copy verbatim |
| NDJSON reader (browser bridge only) | `SP/src/model/stream.ts:29-43` | not needed in-process |
| Model bridge (status, health gate, request body, caps, finish check) | `SP/scripts/local-server.ts:53-61,62-116` | port logic |
| Model probe script | `SP/scripts/probe-model.ts:1-35` | pattern for a manual `--live` probe |
| Transport tests | `SP/tests/model.test.ts:8-26` | copy |
| Core-only contracts | `SP/src/openui/contract.ts:1-71` | template for `gpuix-shell.ask@1` |
| React library binding + prompt | `SP/src/openui/library.tsx:91-120` (RunStep 91-98, `createLibrary` 106-110, `workspacePrompt` 112-120) | the prompt pattern |
| Validation / action resolution | `SP/src/openui/host.ts:8-10,28-80,82-99,101-112` | port |
| Example/focus programs and generation context | `SP/src/openui/programs.ts:5-22,26-51,53-65` | context-message pattern |
| Web chat loop (status, replay, generate, render errors) | `SP/src/openui/OpenUIChat.tsx:33-41,64-73,74-100,114-131` | UX reference |
| Native MutationHost adapter | `SP/src/native/adapter.ts:8,19-136,139-150` | note 14 |
| Saved model output (replay fixture) | `SP/evidence/model/generated.openui` (193 bytes, 5 lines) + `probe.json` | test fixture |
| Rendered evidence | `SP/evidence/model/web-render.png`, `SP/evidence/native/model-worker/{before,after,agent-projection}.png` | visual reference (light) |
| OpenUI method notes (limits, devtools, union probe) | `SP/docs/openui-method.md:85-130`; `SP/docs/openui-union-probe.{mjs,json}` | read before validating |
| lang-core parser/streaming | `OU/packages/lang-core/src/parser/parser.ts:478-488,490-680,749-772` | API |
| lang-core types | `OU/packages/lang-core/src/parser/types.ts:72-86,285-311` | API |
| Prompt options; library methods | `OU/packages/lang-core/src/library.ts:104-123,174-176,305-330` | API |
| Default library specs (82/84 comps) | `OU/docs/generated/{playground,chat}-library.spec.json`; `…/{playground,chat}-system-prompt.spec.json` | prompt + parser schema without React |
| Default library sources | `OU/packages/react-ui/src/genui-lib/*` (`openuiLibrary.tsx`, `openuiChatLibrary.tsx`, `rules.ts`, `prompt-options/`) | native mapping lane |
| react-lang native entry | `OU/packages/react-lang/src/index.native.ts:1-4`; `src/Renderer.tsx:187-201,398-400` | option A |
| Docs | `OU/docs/content/docs/openui-lang/{system-prompts.mdx:62-159, syntax.mdx, specification/index.mdx:26-173, architecture.mdx, incremental-editing.mdx, reliability.mdx, benchmarks.mdx}` | reference |
| Halogen module | `DF/modules/halogen.nix:46-50,101-143,179-219,290-300,319-344,408-430,466-480,586-589` | endpoint facts |
| Strix serving config | `DF/modules/strix.nix:39-60,89-100,106-135` | autoStart, maxTokensDefault 16384, healthKill, Gufo declared off |
| Cutover asserts | `DF/flake.nix:2256-2265` | `!gufo.enable`, halogen enabled + autoStart |
| Gufo module | `DF/modules/gufo.nix:63-69,77-84,301-337,397-419,464-466` | post-cutover facts |
| Gufo server contract | `GF/docs/SERVER.md:28-35,84-111,139-150,320-368,388-400,822-826,884-915` | post-cutover caller rules |
| Existing desktop model callers | `DF/home/dot_local/bin/screen-ocr:12-36`, `screen-ocr-area:9-12`; `DF/pkgs/utility-model/utility_model.py:97-98,126-138` | precedents |
| pi provider row | `DF/home/pi.nix:45-46,182-231` | fleet convention |
| **Rev 2:** upstream reference call (spec → prompt → OpenAI-compatible stream) | `OU/docs/app/api/playground/stream/route.ts:12-45` | the request the shell makes, minus OpenRouter |
| **Rev 2:** default-library spec to vendor (React-free) | `OU/docs/generated/playground-library.spec.json` (136,881 bytes; 82 comps; `schema.$defs` = positional ABI) | copy into `pkgs/gpuix-shell/src/ask/openui/` at a pinned OU commit; regenerate with `OU/docs/package.json:6` |
| **Rev 2:** working merge + subset code | §5.5a of this note (it ran as written, with only the import paths changed) | `src/ask/library.ts` |
| **Rev 2:** frame-by-frame expectations | §5.6 table of this note | streaming-render unit tests (`set()` at each prefix, assert the rules) |
| **Rev 2:** Qwen3.8 tokenizer (offline token counts for prompt budgeting tests) | `/var/lib/local-models/halogen-qwen38-flash-next/tokenizer/tokenizer.json` (12.8 MB); Python: `PYTHONPATH=/nix/store/96ymx07hrdyjg3sab1sxzkzwq1ak78l1-python3.13-tokenizers-0.22.2/lib/python3.13/site-packages /nix/store/05xfwnl62nipbw1ankbcv2crjhb9a918-python3-3.13.14/bin/python3.13` | a dev-only check that the shipped prompt stays under budget; never in the shell runtime |
| **Rev 2:** scratch prototypes (ephemeral, session scratchpad) | `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/r24/{e1..e6,snippet}.ts`, `tok.py`, generated `*.txt` prompts, `sample.openui` | may vanish. Everything that matters is quoted in this note |

---

## 6. Gaps / unknowns

1. **Zenbook → `strix:8731` is unmeasured.** The firewall door is `enp191s0`-only. Whether the client's
   path arrives there (LAN or NAS subnet route) or on `tailscale0` (refused) depends on where the
   Zenbook is. Tomorrow: `curl -m 3 http://strix:8731/v1/models` from the Zenbook. Keep the `ssh` transport fallback.
2. **The model server is fragile under tonight's load** (§0): a 23-token request was followed by a
   6-minute outage, a watchdog kill and a failure marker. Halogen says it "runs best on a host of its
   own". Any shell feature that calls it must degrade silently. Background or auto-triggered generation
   is ruled out on these grounds as well as by the no-timers rule.
3. **Gufo compatibility is unverified:** top-level `enable_thinking` acceptance on the chat route,
   `stream_options` behaviour, and real TTFT on this box. `screen-ocr:22` hard-codes the Halogen id and
   will 404 after the cutover (outside this branch's scope, but worth a line in MORNING.md).
4. **No native partial (streaming) render has ever been run.** SP's native adapter renders only fully
   validated programs (`adapter.ts:38-44`). How `evaluateRoot` behaves on partial nodes (missing required
   props) under a GPUIX mapper is untested. *Rev 2:* at the lang-core level it is now measured (§5.6): 332
   frames, no throws and no runtime errors, with partial nodes exposing growing props. The GPUIX side (a repaint per
   frame, node reuse by key, no flicker) is still **untested**. The first compositor smoke should replay
   the §5.5a sample program at about 60 tok/s (SP's 35 chars per 28 ms replay pacing is close: ≈1,250 chars/s against ≈200 chars/s at 59 tok/s, so slow it down to see real streaming).
5. **Prompt-cache effectiveness for a fixed system prefix is unmeasured** (`cap_mb 110` vs "2.7 GiB" in
   the logs). It decides whether the full default library (5–9 s prefill) is acceptable or a curated
   subset is required. *Rev 2, partly measured:* a 192-token shared prefix was resumed after up to 3.7 h of
   idle (journal 2026-10-21 08:15–11:57). Agent lanes resume 59k–245k-token prefixes. A 1.5k–9k-token
   OpenUI system prefix after minutes or hours is still **unmeasured**. The pruned-subset recommendation (§5.7)
   makes this matter less.
6. **Generation quality of Flash-Next on a large shell library is unknown.** There is exactly one accepted
   generation on record (SP, 9-component library, 4 lines). OpenUI's own benchmark reports 92.9 %
   completion across models (`reliability.mdx`); no Flash-Next data. Plan for refusal UX and a
   "Show program" escape hatch.
7. **Option A (react-lang `react-native` entry under `@gpuix/react`) is untested.** It is the cheapest way
   to "openui fully" (state, forms, queries), but it may need GPUIX-incompatible inline styles stripped.
8. ~~Token estimates are INFERRED~~ **Closed in rev 2:** counted offline with the model's own
   `tokenizer.json` (§5.5 table). OpenUI prompts run about 3.8 chars/token. The chat template's own wrapper
   tokens (role markers, the think-off switch) are not included; expect +10–30 tokens per message
   (INFERRED).
9. **Stale docs found (not fixed, read-only):** the `halogen.nix:15-18` header still says the worker
   hosts the model and the strix has `autoStart = false`, while `strix.nix:41` has `autoStart = true` and
   the worker is retired. `docs/local-ai/seats.md:15,33,349` and the `screen-ocr-area:5` comment still name
   `worker:8731`. `pi.nix:192` says "Halogen Flash on the worker".
10. **Privacy boundary for context snapshots** (notification bodies, window titles, screenshots) is my
    proposal, not a Tom ruling. It is LAN-only either way.
11. **Tom's #247 ruling** ("i have some ideas here") means his own ideas for AI in the shell are not
    captured anywhere I found. A2/A3 are this reader's proposals, marked exploratory.
12. **(rev 2) Subset prompts need their own examples.** The default `promptOptions.examples` (6 programs,
    261–1,942 chars) use `SnippetCardBlock`, `CompositeCardItem`, `IconText`, `InlineHeader` and others.
    Shipping them with a pruned subset would teach components the prompt no longer lists. A v1 subset prompt
    needs 2–3 shell-specific examples, like the §5.5a sample, and nothing from the defaults. The union-pruning
    regex handles only `(A | B | …)[]` child unions. Descriptions and examples are not rewritten, so
    grep the final prompt for dropped names in a unit test.
13. **(rev 2) DESIGN.md §8.9's mock has the model writing operational facts** ("Workspace 2 (gpuix-shell) has
    14 modified files …" as Serif prose). Under the "an LLM must not guess operational status" rule (§2) and
    the §5.8 host-component design, such facts should come from host components (`WorkspaceSlot(2)`,
    `AgentRow(id)`), with prose only around them. Either fix the mock or label generated prose
    "unverified". Not edited here (read-only).
14. **(rev 2) `evaluateRoot` with a spec-only default library is proven only for static props and actions.**
    It passed with `library: shellLib`, which has no zod defs for Stack/Button. `$bindings`, `@Set`, forms and
    reactive props on *default* components go through `evaluateElementProps`, which looks up
    `library.components[typeName]` (`OU/packages/lang-core/src/runtime/evaluate-tree.ts:39-77`). That path
    is untested without the React library. v1 refuses `$vars` anyway (§5.8).
15. **(rev 2) Stale upstream artifact:** `OU/docs/generated/playground-system-prompt.spec.json` (54 comps)
    is referenced by no code. Do not vendor it by mistake.
16. **(rev 2) Remote fallback is a choice nobody has made.** `~/.config/substrate/models.toml` also lists cloud pi
    providers (`qwen-token-plan` `qwen3.8-max`, OpenRouter `deepseek/deepseek-v4-pro`, …). The shell
    could fall back to them when the strix is down. This note recommends **no remote fallback** for
    `ask`/summaries, because notification bodies and window titles would leave the LAN. This is INFERRED and
    not ruled; record it in ASSUMPTIONS if a builder disagrees.
17. **(rev 2) The 88ada2f5… failure marker from §0 is gone.** `/var/lib/failure-markers/` was last modified
    2026-10-20 23:41, so the reconcile cleared it. The marker present now (`user-unit-failure`, 11:58,
    paper print loop) is unrelated to the model.

---

### What I did / could not do

- Did: read every listed source; ran three read-only `GET /v1/models` and two `GET /health`; generated
  OpenUI prompts and ran the streaming parser locally with bun (no network; telemetry disabled by env);
  read Halogen's journal and unit state; wrote this file only.
- Sent **one** tiny generation request (23 tokens, 23:30:46). It coincided with a host-memory-compaction
  stall that ended in a watchdog restart of `podman-halogen` (§0). I did not intervene. One failure marker
  remains for Tom or D41 reconcile.
- Did not run: any generation probe of the OpenUI prompt (abandoned after §0), any compositor test, any
  build, anything from the Zenbook. No other file was written.

**Revision 2 (2026-10-21 12:00–12:40 CEST):**
- Did:
  - three `GET /v1/models` (read-only; 200, 1.2–2.5 ms);
  - read-only `systemctl show podman-halogen` and `journalctl -u podman-halogen` (since 10-17), and `ss -ltnp`;
  - re-read `SP/src/model/stream.ts`, `SP/src/openui/{programs,host,contract}.ts`, `SP/scripts/local-server.ts`,
    `SP/evidence/model/*`, the lang-core README and source, the OU playground route, the spec JSONs, and
    `DF/modules/{halogen,gufo,local-models,strix-ai,strix}.nix`, `home/pi.nix` and `models.toml`. All
    pointers quoted above were spot-checked and still hold; `home/dot_config/substrate/` does not exist;
  - ran six bun experiments plus the §5.5a snippet against lang-core 1.0.1 (local, telemetry disabled by env,
    no network use);
  - counted tokens offline with the model's tokenizer;
  - edited only this file.
- **Did not:** send any POST to `:8731` (no generation, no `count_tokens`, no `/health`); touch any unit,
  the live Sway, herdr or `/home/tom/mecattaf/dotfiles`; run a compositor smoke; build anything.
- **Unverified and labelled as such above:** every latency figure in the rev 2 recomputation table (arithmetic over
  measured rates, not a timed ask); whether the model follows the merged or subset prompt well; option A;
  the Zenbook path.
