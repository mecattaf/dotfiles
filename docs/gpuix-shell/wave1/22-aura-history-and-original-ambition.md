# 22 — Aura history and the original ambition (March 2026 SolidJS shell → Aura/Views/CUBS → Hyprland/GPUIX → Sway)

Reader note for the gpuix-shell overnight build, 2026-10-20/21. Read-only pass over the
five-lane history Codex wrote on 2026-10-13 and its one primary Tom-voice source, the March 16
2026 claude.ai discussion. Every claim is tagged MEASURED (I read the bytes at the cited line),
REPORTED (a research note or transcript digest says so; I did not re-open the underlying file)
or INFERRED (my reading). Tom's words are quoted verbatim, typos included, with the timestamp
the source gives. Nothing outside this file was written.

Builder's one-paragraph takeaway: the March 16 2026 plan was never "a nicer bar". It was one
component library and one visual language that would render **the shell** (menu bar, spotlight
launcher, dock, settings, clipboard history, notifications) **and the apps** (a local Linear/Trello
board, Superhuman-style mail, a calendar), with the compositor owning blur and geometry, 13 px
shell density, a near-black monochrome ramp, one accent, and one 50 ms motion value. Seven months
of Chromium/Aura/Views/CUBS/Otto oscillation changed *who renders* and *who owns the desktop*
several times but never changed that list. On 2026-10-13 Tom ruled "this supersedes the whole aura
requirement. it even fucking correesponds to the solidjsidea i had!!!" and the same evening "let s
tick to sway window manager. less effort". What the gpuix-shell inherits is therefore the March
surface list minus the glass, minus the top bar, minus the apps (which moved behind the 10-20
boundary into Chrome web apps), plus the herdr-centred left rail that grew out of June 27's COWL
sidebar and July 23's "flagship workspace vertical left tab bar".

---

## 1. What this source is

| File | Lines | Author / date | Nature | Read |
|---|---|---|---|---|
| `/home/tom/mecattaf/dotfiles/reports/From Aura to Hyprland.md` | 83 | Codex five-lane synthesis, 2026-10-13 23:14 | Secondary; written minutes before Tom's Hyprland→Sway reversal, so its "Hyprland supplies the desktop" framing (§ "Hyprland supplies the desktop; Solid supplies your environment", lines 41-65) is **stale on the compositor** and current on everything else | all |
| `.../research_notes/From Aura to Hyprland/concept_history.md` | 81 | Codex lane 1, 2026-10-13 | Secondary; 21 full-file reads of ~/notes; strongest on what Tom wanted and which "sacred cows" were assistant inventions | all |
| `.../chromium_aura.md` | 106 | Codex lane 2 | Secondary; dated archaeology March→August 2026, Tom-vs-assistant authorship kept separate | all |
| `.../later_transitions.md` | 82 | Codex lane 3 | Secondary; August→October 2026: workerd.nix, Cloudflare OS, CUBS revision, Otto, PRIMITIVES reset, herdr seam | all |
| `.../gpuix_solidjs.md` | 72 | Codex lane 4 | Secondary; GPUIX source audit at 6a5c7c1 (0.10.0) and GPUI Kit c5f8eca; no runtime test | all |
| `.../hyprland_architecture.md` | 95 | Codex lane 5 | Secondary; Hyprland IPC/groups/layer-shell audit. **Obsolete as a compositor plan** (Sway ruled 22:25Z same night); its identity-mapping and bounded-proof sections are compositor-neutral and still useful | all |
| `/home/tom/notes/references/devlogs/1h26/pre-sync/quickshellX-solidjs2-discussion.md` | 1568 | **Primary.** Tom's own export of a claude.ai chat, March 16 2026, 06:57–09:21 (timestamps in-file); header line 1 says "seminal, long chat with claude on march 16 we came up with the key concepts for the visual layer" | all 1568 lines, MEASURED |
| `/home/tom/notes/references/devlogs/1h26/pre-sync/SOLIDJS-THEME-SYSTEM.md` | 779 | The "final output" the discussion header points to (line 10: "SEE SOLIDJS-THEME-SYSTEM.md fle for the final output"); assistant-authored SYSTEM.md after Tom's corrections | token/section spans, MEASURED |
| `/home/tom/notes/references/devlogs/1h26/pre-sync/FINAL-LINUX-DESIGN.md` | 107 | Tom's note around March 16-17: Duncan Rose niri config, noctalia Monochrome kitty palette | all |
| Supporting Tom-voice spans re-opened to verify quotes: `sync-march30/conv-chromium-fork-decision/chat.md` (2116 lines; spans 8-14, 170-200, 224-232, 560-572, 655-665, 684-690, 788-800), `cubs-steelman/CHAT-LOG.md` (266 lines; all thirteen Tom turns T1-T13), `kitty-harness/may20/08-thomas-additional-notes.md:1-35`, `1h26-claude-memories/mecattaf/agency-foundational-pillars.md:15-48`, `archive/2026-10-06-wm-scoping/notes8/shell/ROADMAP.md:25-80,160-195`, `.../notes7/PRIMITIVES.md:1-45`, `journal/2026/10/06/README.md:1-40`, `june27-cowl-nextsteps/REPORT-2026-06-27.md:8-40,125-140`, `cubs-steelman/04-reason-to-exist-capture-and-signalsources.md:43-70,100-116`, `july17-v1-annotation/00-DECIDE.md:18-32` | | | MEASURED at those spans only |

Provenance warnings the sources themselves raise, which bind this note:
- The five lanes classify both the March 2026 "retrospective" and the July "strategy" as commissioned AI work, not Tom (concept_history.md:45-46, 73). I quote none of those as Tom.
- The June 29 CHAT-LOG preserves Tom's prompts verbatim but condenses assistant turns (concept_history.md:19). The pasted claude.ai sub-chat inside T2 (CHAT-LOG.md:36-86) is "condensed; Tom's prompts within it verbatim".
- The July 23 pillars file is "a secondary memory with a session ID, not the original transcript" (concept_history.md:21).
- `concept_history.md:44` warns: "Read corrections before inheriting failure stories" (May 31 audit corrected itself in an appendix; later syntheses repeat the stale verdict).
- The reports were written into the **main** checkout by the 10-13 Codex session (wave1/02:304); they are read-only for this branch.

---

## 2. Verbatim Tom rulings relevant to the desktop shell, chronological

Format: date/time · quote · pointer · status tonight (STANDS / SUPERSEDED by what / NUANCED).

### 2.1 March 16 2026 — the SolidJS/QuickshellX design day (all MEASURED in `quickshellX-solidjs2-discussion.md`)

- **06:5x (line 32-34)** "Is there an alternative to radix or some sort of ui components? Is solid React compatible? I'm using a custom quick shell that uses QT web engine and QT web channel to render my shell components on niri window manager as web component. I previously thought of using solid JS with A sq lit database that would be local." — Starting stack: QuickshellX (Qt WebEngine + WebChannel) on niri; Solid + local SQLite. STATUS: renderer SUPERSEDED (GPUIX); "Radix-like primitives" and "local data" STAND.
- **06:57 (174-181)** "Raycast / Linear.app / And a bit of macos tahoe / This is the aesthetic I'm going for this sort of dark glass look with few shades of black the whole thing being blur from the compositor / Something rather monochrome but that makes the background pop. / What would even go in such a brand kit anyway?" — STATUS: "few shades of black, monochrome" STANDS (noir); "dark glass / compositor blur / background pop" SUPERSEDED (BRIEF §1: no blur, no frost, wallpaper #000000; PRIMITIVES.md "blur went unused").
- **07:28 (342)** "…it is clear that they [Apple] have the most rich one and by far it might even be a little Overkill compared to what I'm trying to achieve with my own setup, which is something more of a static single file team kit" — STATUS: STANDS in spirit (one theme fragment, `gpuix-shell.json`).
- **07:30 (376-377)** "Go ahead. Do your best in oneshot. I think you understand that this is going to be a web toolkit, but it will be leveraged to implement Linux shell items like **the menu bar, the spotlight search even the settings page, the dock, the launcher, the clipboard History management** / This is where I really was drawn towards the likes of raycast and taskade because they do bring over that sort of unified glass feel especially in their renderings more so than the actual product itself when you launch it" — **The first surface list.** STATUS: launcher/settings/clipboard STAND; menu bar SUPERSEDED ("no top bar on the Linux head"); dock FADED (never ruled out, never asked for again).
- **07:43 (414-417)** "We definitely don't need figma as a tool or as a dependency… when I mention linear raycast and some others, it seems like you immediately get it… I would like to experiment with defining the minimum amount of information needed so that subsequent versions of Claude are also able to create the aesthetic" — STATUS: STANDS as method (design kit U-01..U-19 in wave1/11 is this "minimum").
- **07:51 (465-471)** "I also see design as A practice moving further away from a clear, descriptive CSS kit to something that is just more text prompt based… Recall the start of this chat where we mentioned solid JS. I do see value in creating a tailwind css style singular component library still, but that is not as a design mechanism but as a uniformization mechanism" — STATUS: STANDS (component library = uniformity, not design).
- **07:57 (523-524)** "Actually, let's roll back a little because I feel more comfortable with something. Deterministic like the figma example or in fact just a a components collection like radix etc / I think this would guarantee more uniformity. Do you concur? What is the best approach here" — Tom chose deterministic components over prompt-only. STATUS: STANDS (OpenUI full component library + Primer-shaped kit).
- **08:02 (579-586)** "So with that I want to be able to go far beyond what a desktop shell provides and this is why I didn't want to use figma for that / We want the same aesthetic that powers the spotlight search bar dock and other shell utilities to also be powering what I use to build local web apps / I want to have a custom local linear style Trello board, superhuman style, email and calendar; basically, applying a methodology that I've been doing so far with AI that works like magic, which is take a screenshot of a SAS product that I like and have the AI implemented as a local web app. The only difference is that we're really aiming for that localhost unified glass aesthetic. / I would like you to research a product that has been out for a few years called Taskade…" — **The application ambition.** STATUS: NUANCED. The *shared language* STANDS (10-20: "openUI for the desktop shell", same font/colours). The *apps inside the shell* are MOVED OUT by the 10-20 boundary ("Mail/CRM/projects/chat utilities are NOT built here; the shell only launches them", BRIEF §3.8); today they are Chrome apps (`binds.conf:29-30` Mod+Shift+w mail.google.com, Mod+Shift+period calendar.notion.so).
- **08:07 (649-652)** "No the library is not glass / Blur is provided by the compositor. / I feel glass bcz there s a wallapper that gets blurred w passes (compositor) / We must start with a clear definition of boundaries" — STATUS: the **boundary rule** STANDS (compositor owns geometry/effects; shell never fakes them; carried into BRIEF §3.8 and the GPUIX report's "blur should remain a compositor policy"); the blur itself is gone.
- **08:08 (686)** "Again, no effects on the css side. All compositor blur" — STATUS: as above; tonight reads as "no shadows, no blur, no frost in the renderer; hairlines only".
- **08:11 (716-723)** "Yes. It s all 000000 hues of 'grey' like 070707 i believe. On the kobalte side of things (if that s what i end up going for) / I gave you research mode now so you can really delve deep on linear raycast and taskade / I want to analyze if this has already been attempted before… / The github design conponent library needs much more unpacking, because it comes with many elaborate rules but we can use in our desire" — STATUS: the #000000-based grey ramp STANDS (noir); **Primer named as the reference design system on March 16**, seven months before "react (solidjs compat) superset of github primer" (10-13 23:07Z) — STANDS.
- **08:19 (891-893)** "I already have a working version of a fork of quickshell namely https://github.com/mecattaf/quickshellX / It has cutie web channel and web engine / Your scope should be narrowed at the design handoff so so you are basically primed to understand that the project is going on and you have just been hired as a designer." — STATUS: QuickshellX SUPERSEDED (10-20: "without using quickshell"); no local clone found (`/home/tom/mecattaf/quickshellX*` absent, MEASURED).
- **08:21 (911-913)** "My preferred approach to software engineering is style transfer / I take take existing projects that have rather complete implementations and I strategically and surgically 'rip' items from them for example in this case we will start with dnakmaterialshell, noctalia, eqsh / For that specifically, they have many different functionalities that are already part of the shell that are really low hanging fruit and minimal starting points for me too to write that desktop shell" — STATUS: STANDS verbatim in 10-20 ("functionality pull from quickshell NOT visuals"; Tacit is the new third donor).
- **08:25 (971-973)** "Dankmaterialshell followed material 3 And I think in recent versions, a newer version of that design system / I used it in the past and it was very uniform, which was good. I think because we're using web technologies not qml. The approach is far far more optimized / But it's still worth it to also explore its design system and methodology" — STATUS: STANDS (M3 *methodology* — three-tier tokens, surface containers, on-colour pairing — not M3 looks).
- **08:28 (1081-1082)** "Apple has m1 through m5 for their mactahoe / Explire that" — led to the M2–M5 surface vocabulary. STATUS: vocabulary SUPERSEDED by the kit's named tokens (wave1/11 §4.2), concept (4 luminance steps) STANDS.
- **08:36 (1163-1166)** "Compare and contrast apple and quickshell implementations / For my purposes, they should be the same concepts / Tie in the linear design system… See how the layers pop despite being black to white monochrome" — STATUS: STANDS as a taste statement (luminance steps, not colour, carry hierarchy).
- **08:44 (1202-1204)** "Here s dankmaterialshell s launcher v2 / Reprpdicue it in the raycast/linear style (whatever you just defined) / Output to jsx, mockup, background green hue gradient so i can see the cotnradt" — the first "take a DMS module, keep its structure, reskin it" exercise. STATUS: method STANDS; the JSX artifact is not in ~/notes (searched, MEASURED absent).
- **08:50 (1222)** "Keep the designer undertone but with very heavy technical explanations and condense that into a philosophy. Actually looking at the artifact you just rendered for me. It's a little too white or light theme. Maybe reverse that vision OS decision. I think linear looked that good because in the screenshots I gave you especially they rendered contrast beautifully. But I think my key direction is the dark glass aesthetic that is achieved. For example, currently with my blur 0.85 on kitty 000000 term color works perfectly" — produced the correction "surfaces are solid dark hex fills, not white rgba overlays" (1245-1256). STATUS: **STANDS and is load-bearing for noir**: flat opaque near-black fills, depth from luminance (#0a0a0a → #1c1c1c), never translucent surfaces inside the renderer.
- **08:58 (1264-1308)** Tom pastes his Discord exchange with Duncan Rose (niri): opacity 0.85, blur passes 3 offset 3.7, terminal #000000; "I even found the wallpaper he uses!" — STATUS: SUPERSEDED (no blur; wallpaper is solid #000000).
- **08:59 (1329)** "So update that all in a single markdown artifact that I can use moving forward that contains the design, token and philosophy without mentions of Mac OS vision, just the correct one including the linear stuff and the material m1 through M5" — STATUS: that artifact is `SOLIDJS-THEME-SYSTEM.md` (779 lines, MEASURED); its token values are §4 below.
- **09:02 (1346-1347)** "Where would the 'box corners' be defined? / See attached raycast screenshot which has really nice corners. This can only he dealth with by the compositor for the outer edge of the webengine qtwebchannel item like say raycast style launcher" — STATUS: STANDS as a question; on GPUIX the outer radius is the window's own (transparent layer surface + rounded root), compositor clip is Sway `corner_radius` not available (Sway has no corner rounding; INFERRED).
- **09:08 (1413-1414)** "How easy would it be to build menus that are as simple as the above or as complex as the above givne this philosophy? / Update it to include items about the font (system installed SF pro) and the the default corner radius which you found in the above screenshot of raycast because it looks really good on Mac OS" — STATUS: font SUPERSEDED (Anthropic Sans is a hard rule, BRIEF §1); Raycast 10 px panel radius ≈ kit's 8/12 "rounded inner corners" (BRIEF §3.6) — NUANCED.
- **09:15 (1447)** "50ms? I remember that for some reason linear web app had the fastest reactivity to my clicks for some reason I'm really not sure why explore" — STATUS: STANDS as the latency reference.
- **09:18 (1511-1512)** "50ms is what it advertized on linear s landing page as of jan 2026. You got it wrong. Clarofy. / You also pointed me to https://dasroot.net/posts/2025/12/local-first-software-offline-applications/ which corresponds to what we're doing here we are building offline web apps" — STATUS: STANDS ("local-first, no network in the click path" → tonight: Sway IPC + herdr snapshot in-process, no HTTP).
- **09:21 (1541-1542)** "So one more clarification that I would like to make here. **I am trying to build the world's fastest most responsive desktop shell** / That means I want snappiness everywhere. You deliberately introduced later slower ones for the animations, whereas actually that was exactly off. I want the most responsive" — produced "one token, one value: --sys-dur: 50ms" (1553-1557). STATUS: NUANCED. The *motion rule* (one short duration, no tiers, no spring) STANDS. The *benchmark ambition* is softened by 10-13 "performance is not really the thing i m looking for here" (wave1/01:141). Read together: don't optimise, don't animate.

### 2.2 March 26–27 2026 — the Chromium-fork decision (MEASURED in `sync-march30/conv-chromium-fork-decision/chat.md`)

- **Mar 26 (line 8-14)** "pasted is open ended research question… but it does come off as a little uninformed about: CEF, other alternatives we have not thought of (**zed's gpui?** servo? i remember the days of nyxt browser) / i m not scared by the compexity of 'redoing quickshell but without the qt' anymore." — GPUI was on Tom's own list in March. The assistant's artifact `files/02-gpui-dark-horse.md:75` dismissed it as "if TypeScript/SolidJS, GPUI is architecturally irrelevant" (REPORTED, chromium_aura.md:17). STATUS: that dismissal is exactly what GPUIX overturned.
- **Mar 26 (175)** "I need your thorough reconsideration I am trying and the reason why I built quickshell X myself was because I needed to be using web technologies all the way through for my Linux shell… **I do not want to be using a special coding language to build the front end.**" — STATUS: STANDS, reinterpreted: TypeScript/JSX authoring is the requirement, not a browser engine.
- **Mar 26 (189)** "I don't specifically need the chromium rendering engine but it sounds extremely appealing to me to keep. this is a fucking tension… I arrived at the conclusion that solid JS was the best and fastest way to use web components to have a highly reactive layer shell 50 milliseconds something that feels like linear.app… I'm going beyond the layer shell and little widgets. I might also eventually start rebuilding entire desktop web apps that I had previously used in the past, like superhuman for male and the calendar or let's say a custom Trello board that would somehow be very integrated with my system… **nothing is final here.**" — STATUS: STANDS (the 10-13 ruling is the resolution of this tension).
- **Mar 26 (191)** "Even the framework doesn't matter — I just need HTML/CSS/JS in a browser engine" and (194) "I'm open to anything as long as web tech renders the UI" — STATUS: SUPERSEDED on "browser engine" by 10-13; STANDS on "framework doesn't matter" (React chosen tonight).
- **Mar 26 (227-229)** "I really really don't like that you went through with the gtk recommendation… I'm thinking that I'm wanting to **build the fastest shell in the world** and it despite using web technologies" — STATUS: see 09:21 nuance.
- **Mar 27 (567)** "Native chromium then. Purposebuilt on same le el level as electtron, cef and ithers. We are anbiyious" — STATUS: ABANDONED (10-01 "no forking my browser"; 10-13 supersession).
- **Mar 27 (658)** "I want to maintain for the front end side of things that solid JS kobalte was also something that I may have inherited from previous scoping chats that might not be relevant anymore. We spoke about the react all the way through. **React and the default radix components are fine by the way.**" — STATUS: STANDS; this is the earliest licence for tonight's React choice (BRIEF §3.1).
- **Mar 27 (660-662)** "recall the pi agents front ends discussion… this one project that could generate front-end code sort of on the fly and render it as component by component… And separately… linear.com… getting latency fast for their front end" — generative UI + Linear latency named together. STATUS: STANDS as the `gpuix-shell ask` / OpenUI lane (BRIEF §3.7).
- **Mar 27 (791-794)** "That's the rapper on chromium / That's where it all starts" (choosing a Proxy-based reactive store + morphdom as the kernel) — STATUS: ABANDONED as mechanism (React + GPUIX mutations do this job); "the LLM is the frontend developer" idea STANDS in OpenUI.

### 2.3 May 20 2026 — posture (kitty-harness, a sibling project; MEASURED `may20/08-thomas-additional-notes.md:1-31`)

- "**Great functionality. Super-duper niche. I am completely comfortable with this being a solo project that only I use.**" and "the design heuristic is: *subtract to a sharper niche*, then go deep on functionality within it." — STATUS: STANDS (the Anthropic-font branch cannot even be public, BRIEF §1).
- "the spec was deliberately built to be language-agnostic. I don't care what language we use." — STATUS: STANDS in spirit (Solid→React swap is not a betrayal).

### 2.4 June 29 2026 — the CUBS steelman (MEASURED, all thirteen Tom turns in `cubs-steelman/CHAT-LOG.md`)

- **T2 pasted chat (line 54)** "chrome tabs c++ interface but for the wayland desktop" — STATUS: STANDS as the *idiom* (a tab-strip-quality workspace rail), ABANDONED as C++.
- **T2 (56-57)** "wifi settings… accessible in a views toggle on the top bar… AND a control center overlay… AND a chrome://network-manager page. all in one seam." — **the wifi triad**. STATUS: STANDS minus the top bar: rail toggle + controls overlay + a full settings surface (10-20 "wifi menu, or bluetooth pairing menu; etc.").
- **T2 (60-61)** "something about the uniformity of a mono interface is very appealing… we keep the bar in views and pay the price of being backed by chromium." — STATUS: uniformity STANDS; price no longer paid.
- **T2 (66-68)** "i want my tier-2 chromium program — chrome-cowl — to have the same uniform themability as the tabstrip… written from the get-go." — STATUS: STANDS (theme fragment read by every surface; runtime switch; "color-IDs everywhere, raw colors nowhere" = tokens only).
- **T2 (69-70, condensed)** ghostex/cmux as the UX target: "terminals + web tabs in one scrollable grouped plane" — STATUS: NUANCED; today the plane is Sway workspaces 1-9 + Mod+0 Chrome, one herdr workspace per slot (BRIEF §1).
- **T3 (88-95)** "i had a functional top bar, and a functional left side bar (that manages workspaces). but this one was written using web technologies." — confirms June 27 COWL shipped a left workspace sidebar. STATUS: the left sidebar STANDS (the rail); the top bar does not.
- **T9 (160-170)** "there was a point at which i had arrived at a design decision … a material glass sort of thing, but that was coming from the world where every single item on the layer shell was a web app… acknowledging that what i'm trying to get to here is **a more complete desktop environment shell that is at minimum on par with noctalia v5**…" — STATUS: STANDS verbatim in the 10-20 order ("same level as quickshell… dankmaterialshell; noctalia; omarchy").
- **T11 (201-211)** "niri still handles inputs, seats, greetd and shortcuts… it enables me to build arbitrary 'concepts' that get captured. say, like ghostex or cmux, **how we map a niri workspace to a grouping of windows placed in a certain way (and accessory we capture the topic of the claude ai chat that started that workspace)**. you will find in ~/mecattaf several alleys where i'm trying to integrate a deeper concept: kerdr for recoverable sessions… or any cli that exposes the right signals that we design our shell around." — STATUS: STANDS, now literally herdr: one herdr workspace = one Sway workspace; agent status glyphs in the rail (BRIEF §1).
- **T12 (223-230)** "this is CUBS: chromium unified browser and shell (notice how, unlike cade… it doesn't have the pretense of being a DE, it works with your DE like noctalia v5)… for wifi, network this gives me top bar in views, control center in views, chrome:// (or whatever) network-manager…" — STATUS: CUBS ABANDONED (10-13); the "works with your DE, not a DE" stance STANDS (Sway stays).

### 2.5 July 17–23 2026 — Agency pillars (REPORTED via `00-DECIDE.md:18-32` and `agency-foundational-pillars.md:15-48`, MEASURED at those spans)

- **July 17-18 00-DECIDE.md A1** "Agency IS the compositor: one Chromium process owns the scene… a tiny separate wlroots-based program (the 'appliance') holds the screen/DRM" with Tom's inline "from part A confirmed, unless i object". The "NO TABS" line was amended July 18 to admit tabbed columns (chromium_aura.md:57). STATUS: ABANDONED (10-01 "the wlroots-based system that i use is already good enough").
- **July 23 pillars (secondary memory)** "2) A complete shell that can control the system — io, hardware, dbus, everything — including the **flagship workspace vertical left tab bar (the left rail)**"; "4) Theming system completely implemented"; "3) A chrome://-style Lit control interface, comprehensive, with an account"; "5) A new integrated terminal… full feature parity with kitty"; gate doctrine "whole domains… genuinely daily-drivable… never stubs". STATUS: 2 and 4 STAND (tonight's rail + theme); 3 NUANCED (a full settings surface, no account, no Lit); 5 ABANDONED (kitty + herdr kept, 10-06 PRIMITIVES); gate doctrine STANDS as the BRIEF's "every surface ships a test and a smoke" (INFERRED).

### 2.6 September 26 – October 7 2026 — subtraction (REPORTED via later_transitions.md; verbatim where the lane quotes Tom)

- **2026-09-26** CUBS "already detailed"; Cloudflare OS "more urgent"; wanted "a 'retool/notion made out of claude ai artifacts'" (later_transitions.md:12). STATUS: that is the OpenUI/generative lane's ancestor; Cloudflare OS ABANDONED 10-13.
- **2026-10-01** "i have been stuck on dreaming about this full control over chromium aura, when i should hvae instead realized that the wlroots-based system that i use is already good enough; and there is no need to reinvent this exact wheel." / "no forking my browser" (wave1/04:166, MEASURED there). STATUS: STANDS.
- **2026-10-06 12:13Z** Chrome's tab bar is "unbeatable … dragging, tabbing"; **15:37Z** herdr "gave me the same concept of tabs as i had with google chrome … sessions"; **17:47Z** pushing back on "the only home is the tabbed tiling container": "it doesn't have layershell?" (ROADMAP.md:31-35, MEASURED). STATUS: STANDS; the rail is a layer-shell surface, not a compositor tab container.
- **2026-10-06 PRIMITIVES.md:5-30** keep Chrome ("The best browser, I really like it."), kitty, herdr ("use it, don't reimplement it"), the WM ("the WM is not the core"); the three-question filter: "Does it cost me time this week? Does a widely used tool already do it? Will I still use it in week three? This is the blur test."; the ambition-cycle list "Omarchy (Hyprland + Quickshell) → niri (for blur, then blur went unused) → scroll". STATUS: STANDS; it is the strongest written reason the gpuix-shell has no blur.
- **2026-10-07** Otto: "Frosting, animations and the otto file manager was just not enough"; "the aesthetic items do not matter to him" (journal 10/06 README:22-25). STATUS: STANDS.
- **2026-10-07 pm** "settling for a unified interface - all through a google chroem browser, no native shell whatsoever. this is the boundary where i stand now." (wave1/04:169) — SUPERSEDED by the 10-20 order for a native gpuix shell; the "utilities are Chrome web apps" half STANDS.
- **2026-10-07** "i also push back completely on its 'keep vicinae' framing.. i would like to fully supersede this." (wave1/04:117) and **2026-10-12** "we keep vicinae actually.. i was getting a little carried away" (wave1/05:130) and **2026-10-20** "a mod+d menu (vicinae remplacement)" — two reversals; the 10-20 order is the last word: REPLACE.

### 2.7 October 13 2026 — the pivot this source was written for (MEASURED in wave1/01-02 digests of the Codex rollout)

- **21:04:11Z** "revisit the chromium aura entire epoch historiically, and understandh how it will now be done on…" (the order that produced the five lanes).
- **21:06:46Z** "**this supersedes the whole aura requirement. it even fucking correesponds to the solidjsidea i had!!!**" — the ruling that retires Aura/CUBS/Views and names March 16 as the lineage. STANDS.
- **22:25:30Z** "i digress on the hyprland parts, i m sorry. **let s tick to sway window manager. less effort..** but do list all the hyprland functionality that we're missing" — retires the report's Hyprland half 3 hours after it was written. STANDS (BRIEF §1).
- **23:07:03Z** "i am expecitng it to be a react (solidjs compat) superset of github primer, cloudflare kumo + cloudflare-os … desktop shell to the functional desktop" — React, Primer. STANDS.
- **(line 3454)** "performance is not really the thing i m looking for here" — the nuance on §2.1 09:21.

### 2.8 October 20 2026 — the order (BRIEF §1 and §5; not re-quoted here beyond what §3 needs)

"the 'ultimate' gpuix-based shell… at the same level as quickshell… dankmaterialshell; noctalia; and omarchy"; "a mod+d menu (vicinae remplacement)… notify-send remplacement to mako; a left bar with workspace switcher that remplaces waybar"; "keeping the anthropic font"; "close to the current minimal 'noir' colorscheme with the possibility to switch to claude 'light and dark'"; "functionality pull from quickshell NOT visuals"; "no top bar on the Linux head"; "the file explorer… the aesthetic… vanilla-ness"; "wifi menu, or bluetooth pairing menu; etc.".

---

## 3. Feature / behaviour inventory

### 3.1 The original ambition list (every surface and app named in the March 16 source, in order of first appearance)

| # | Surface / app | First named (line) | By whom | What exactly was described | Where it lives today | Keep / replace / new | Notes |
|---|---|---|---|---|---|---|---|
| A1 | Menu bar (top, translucent, tray icons, clock) | 376 Tom; 403 demo | Tom | "the menu bar"; demo: "translucent veil with system tray icons and clock"; SYSTEM.md "Panel(bar) + ghost buttons + system icons + clock", 32 px, radius 0, M2 | nothing (waybar deleted 2026-09-11, `git show 1d926f2e^:home/dot_config/waybar/`) | **replace with the left rail**; no top bar (10-20) | Clock/tray/battery move into the rail's bottom cluster (INFERRED from SHELLS-DIGEST §4, see wave1/11) |
| A2 | Spotlight search / command palette / launcher | 376 Tom; 404 demo; 942 table | Tom | "the spotlight search", "the launcher"; demo: ⌘K/Ctrl+K, type to filter, action bar with keyboard hints, Esc closes; DMS launcher reskin at 1212: "sectioned search results, collapsible sections with view toggles, icon grid for emoji/nerd fonts, plugin tags, bottom tab bar with keyboard hints" | Vicinae (`home/vicinae.nix`, `binds.conf:6-7` Mod+d / Mod+space) | **replace** (`gpuix-shell launcher`, overlay 700×580, top margin 108) | Providers from March table: apps, files, emoji, calc, windows, commands (DMS column, 942) |
| A3 | Settings page / panel | 376 Tom; 405 demo | Tom | "even the settings page"; demo: toggles, steppers, accent colour picker, sidebar navigation | `theme`/`theme-prompt` (F2/Shift+F2), `fzf-nmcli`, `audio-route` (F9) prompts in kitty | **new** (`gpuix-shell controls` quick settings + a fuller settings window) | June 29 wifi triad: rail toggle + overlay + full page |
| A4 | Dock | 376 Tom; 407 demo | Tom | "the dock"; demo: hover scale + tooltip, running indicators as accent dots, separators; SYSTEM.md "Panel(bar, pill-shaped) + icon buttons + running dots", radius-full | nothing | **faded** — not in the 10-20 order; the rail's pinned-apps cluster can absorb it (INFERRED) | Last mention March 16; never in June/July/Oct lists |
| A5 | Clipboard history | 376 Tom; 406 demo | Tom | "the clipboard History management"; demo: pinned items, content-type icons, copy buttons, timestamps; DMS: image preview | Vicinae `cmd launch clipboard:history` (`binds.conf:~114` Mod+v) | **replace** (own `wl-paste --watch` store, BRIEF §3.4) | Pinning and image preview are in the March spec |
| A6 | Toast notification | 408 demo | assistant, Tom accepted | auto-dismiss 5 s with progress bar; SYSTEM.md "Toast stack + Panel(attached) history" | mako (`home/vicinae.nix:111-166`, makoctl dismiss/restore) | **replace** (`gpuix-shell notifications`: D-Bus server + toasts top-right 390 wide max 4) | History panel was in the March spec; DND from Noctalia column (941) |
| A7 | Local Linear-style Trello board | 581 Tom | Tom | "a custom local linear style Trello board" | nothing (project tracking is `project` CLI / herdr-web-ui desk) | **moved out** (10-20 boundary: utilities, not shell) | Component needs listed at 624-634: Table/DataGrid, Tabs, Dialog/Sheet, Select, Calendar, Checkbox, Avatar, Progress, Textarea, Popover, Kanban column |
| A8 | Superhuman-style email | 581 Tom; 189 (Mar 26) | Tom | "superhuman style, email" | Chrome app `--app=https://mail.google.com/` (`binds.conf:29`), `mail` script | **moved out** | July 24 "ambient badge vs full mailbox" rule: the shell may show a count, never the mailbox |
| A9 | Calendar | 581 Tom; 628 | Tom | "and calendar"; DMS/Noctalia calendar widget (948) | Chrome app `calendar.notion.so` (`binds.conf:30`) | **moved out** (app); a clock/date popover in the rail is shell (INFERRED) | |
| A10 | Component library (Radix-like, deterministic) | 32, 523 Tom | Tom | "a components collection like radix"; Kobalte then; "React and the default radix components are fine" (Mar 27) | OpenUI default library + GPUIX adapter (`/home/tom/tuesday-oct20/build/shared-parity/`) | **keep** (React + OpenUI full library, BRIEF §5) | |
| A11 | Design brief for AI generation (DESIGN.md ~100 words) | 417, 471 Tom | Tom | "minimum amount of information needed so that subsequent versions of Claude are also able to create the aesthetic" | wave1/11 design kit U-01..U-19; `/home/tom/today/2026-10-17-frank/design-handoff/` | **keep** | |
| A12 | Token file (CSS custom properties, three tiers) | 311, 1000 | assistant, Tom accepted via 8:11/8:59 | `glass-shell.css` → SYSTEM.md tiers ref/sys/component | `home/themes/*.nix` → `~/.config/theme/gpuix-shell.json` (to create) | **keep as TS tokens** | gpuix_solidjs.md:22 "Port the design decisions, not their former rendering machinery" |
| A13 | Generative UI (LLM writes components live) | Mar 27 chat 660, 684 | Tom | pi-generative-ui + morphdom; "a new DOM" | `gpuix-shell ask` (BRIEF §3.7), local model at strix :8731 | **keep, exploratory** | |

### 3.2 The donor inventory Tom asked for on March 16 (`:931-953`, assistant table from DMS / Noctalia / rdnashell; Tom's instruction at 911-913 was to "rip" from these)

| Feature | DMS | Noctalia | rdnashell | Today (Sway branch) | Tonight |
|---|---|---|---|---|---|
| Bar/Panel | DankBar (top, autohide) | Bar | Bar (3 slots) | none | rail (left) |
| Workspaces | switcher | buttons | NiriWorkspaces | Mod+1..9/0 binds only; `sway-workspace` script | rail slots 1-9 + herdr status |
| Clock/DateTime | yes | yes | yes | none | rail |
| System tray (SNI) | yes | yes | yes | none | **gap** — GPUIX has no SNI; needs `org.kde.StatusNotifierWatcher` over dbus-next (INFERRED) |
| Audio | widget + popout | service | widget | `volume` F6-F8 + `osd` | controls + OSD |
| Network | + VPN popout | service | widget | `fzf-nmcli`, `vpn-status` | wifi menu (10-20) |
| Bluetooth | popout | service | widget | none | bluetooth pairing menu (10-20) |
| Brightness | CLI + widget | control | — | `brightness` script | OSD |
| Battery/Power | widget | module | — | none | rail + `gpuix-shell power` |
| Notifications | center + toasts | + history + DND | toasts | mako | notifications daemon |
| Launcher | apps, files, emoji, calc, windows | app + search | AppLauncher | Vicinae | launcher |
| Clipboard | history + image preview | cliphist | — | Vicinae | own store |
| Media/MPRIS | player widget | controls | — | `media` F3-F5 | MPRIS in controls; Navidrome demo (BRIEF §5) |
| Lock screen | + idle + greeter | session lock | yes | **not in any Tom ruling** | gap (see §6) |
| Wallpaper | manager | Wallhaven | — | `wallpaper` script; solid #000000 | none needed |
| Settings/Control center | GUI panel | — | — | prompts | controls |
| Calendar | sync widget | yes | — | Chrome app | popover only |
| Weather | yes | — | — | none | not asked |
| System monitor | DGOP | — | — | none | not asked; `claude-capacity` exists |
| Desktop widgets | plugins | widget system | — | none | not asked |
| Screenshots | tool | — | — | `screenshot` Mod+s/Shift+s/Alt+s, `screen-ocr-area` | keep scripts; shell could host the area picker later |
| Color picker | yes | — | — | `colorpicker` Mod+c | keep script |

Component tiers the assistant derived and Tom did not contest (`:957-963`): Tier 1 Panel, Text, Icon, Button(ghost/subtle/accent), Separator, Tooltip; Tier 2 ListRow, Input, Badge/Kbd, SectionLabel, ScrollArea, Toast; Tier 3 Toggle, Slider, Stepper, Dropdown/Select, ProgressBar, Avatar; Tier 4 Calendar grid, Media controls, Workspace indicator dots, Circular gauge, Image preview. This is a usable checklist against the OpenUI default library (INFERRED: map each to an OpenUI component; the ones OpenUI lacks — workspace dots, circular gauge, media transport — are shell-local components).

### 3.3 What each era added to the surface list (and what it proved)

| Era | Renderer / owner | New surfaces or behaviours named | Evidence it ran | Lesson carried forward |
|---|---|---|---|---|
| Pre-March 2026 (QuickshellX) | Qt WebEngine + WebChannel in a quickshell fork, on niri | the shell as web components; local SQLite apps | "I already have a working version" (:891) | REPORTED only; no clone on disk |
| March 16 (design day) | same; SolidJS + Kobalte planned | A1-A13 above; the module donor table; three-layer boundary (compositor / host / web) | interactive JSX demo of bar, palette, settings, clipboard, dock, toast (:401-409) — claude.ai artifact, not on disk | compositor owns effects; one language for shell + apps; deterministic components; 13 px density; 50 ms |
| March 26-27 (COWL decision) | purpose-built Chromium Content-API embedder, Ozone layer-shell, niri | Proxy/morphdom kernel; LLM-authored UI; D-Bus events + niri IPC (chromium_aura.md:18) | handoff doc only | "framework doesn't matter"; React/Radix fine; GPUI dismissed on a false premise |
| April 10 | "Chromium is the compositor" (Aura tree per display, Exo) | one window model, integrated effects | proposal only | over-reach begins (chromium_aura.md:41) |
| June 10 | keep Ash | — | ledger entry | — |
| **June 27 (COWL web shell)** | Chromium 149 fork, four layer-shell surfaces on niri | **bar** (3 summon buttons + widgets), **ccd left sidebar = workspace switcher grouped by output with window counts, click-to-focus, true layer-shell collapse 12.5 % ⇄ 5 % (320 ⇄ 128 DIP @2560)**, **launcher** (app/calculator/command providers), **clui** (Claude control: output + permissions) | MEASURED REPORT-2026-06-27.md:12-30; idle PSS 325 MB, 1.9 % CPU, startup ~600 ms vs DMS 396 MB / 6.6 % (:130-136) | the measured bottleneck was niri's ~120 ms retile animation, not the renderer (hideSurface 0.45 ms) — **animation policy, not language, decides perceived speed** |
| June 28-29 (CADE boot) | Ash on Linux DRM | real 5120×2880 modeset with animation | MONITOR-TEST-RESULTS.md:90 (REPORTED) | mouse scroll dead, Nautilus crashed the session; "the desired design already delegated geometry to niri, so owning the scene was not earning its cost" |
| June 29-30 (CUBS steelman) | Views C++ layer-shell client under niri | wifi triad; chrome-tabs idiom; captured workspace with provenance (chat topic + recoverable session); SignalSource (any CLI emitting typed state) | views-shell spike (`/home/tom/mecattaf/views-shell`, exists on disk, not read) | **capture = grouping + provenance + session + evidence**; "keep the leaf, drop the tree"; "the browser is an instrument; the shell is the point" |
| July 17-24 (Agency) | Chromium owns scene + wlroots appliance | flagship left rail; comprehensive settings; theming; integrated terminal; service-backed apps (CRM, calendar, email, agent supervision); ambient badge vs full app | July 16 journal: shell/launcher prototype ran with screenshots (REPORTED concept_history.md:50) | services own data, surfaces are replaceable, CLI and GUI are peers; "removing a frontend must not remove data" |
| Sept 26-28 | vanilla Chrome reuse; Cloudflare OS | "retool/notion made out of claude ai artifacts" | none | subtraction; "no forking my browser" (10-01) |
| Oct 6-7 (Otto) | Smithay + Skia compositor with its own shell | workspace strip coloured by herdr agent state (blocked amber / working accent / done green / idle neutral); otto-herdr bridge | ran on VT5 Vulkan/GL (journal 10/06) | rejected: "Frosting, animations and the otto file manager was just not enough"; PRIMITIVES reset; **only Chrome's tab-strip arithmetic is portable** (44 lines, 23 040 oracle layouts) |
| Oct 13-14 (GPUIX + Hyprland) | @gpuix/native 0.10.0 + Solid, Hyprland 74 min | bar 32 px, launcher 700×580, controls 560×710, notification centre 500×650, toasts, D-Bus daemon (wave1/13) | 30 unit tests pass; never rendered on Tom's screen (wave1/02:162) | GPUIX layer-shell is real; Hyprland dropped same night |
| Oct 20 (this build) | @gpuix/native 0.11.0 + React on Sway | rail 56/220, launcher, switcher, controls, notifications, OSD, files, power, ask | rail probe MEASURED 23:45 (BRIEF end) | — |

### 3.4 Requirements that never died (present in March 16 and in the 10-20 order, with every intermediate era in between)

| # | Requirement | Mar 16 | Mar 26-27 | Jun 29 | Jul 23 | Oct 6-7 | Oct 13 | Oct 20 | Tonight's owner |
|---|---|---|---|---|---|---|---|---|---|
| N1 | One component language renders shell *and* application surfaces | :580 | :189 | T2 "uniformity of a mono interface" | pillar 4 | — | 23:07Z "react superset of primer" | "openUI for the desktop shell" | React + OpenUI library over GPUIX adapter |
| N2 | Declarative TypeScript/JSX authoring; "I do not want to be using a special coding language" | Solid | :175 | (Views was the detour) | — | — | 21:06Z "corresponds to the solidjs idea" | "gpuix as the frontend all the way" | @gpuix/react |
| N3 | A keyboard-first launcher / command palette | :376 | — | COWL launcher | — | otto-launcher kept | pkgs/desktop-shell launcher | "mod+d menu (vicinae remplacement)" | `gpuix-shell launcher` |
| N4 | A left workspace rail that is the primary navigation | — (menu bar then) | — | COWL ccd sidebar; T3 "left side bar (that manages workspaces)" | "flagship workspace vertical left tab bar" | 220 px rail of workspaces (views-shell `--left-tabs`) | — | "a left bar with workspace switcher that remplaces waybar" | `gpuix-shell rail` |
| N5 | The compositor owns geometry and effects; the shell never fakes them | :649, :686 | — | T9 "substrate-neutral" | — | "blur went unused" | report: "blur should remain a compositor policy" | "no blur, no frost" | Sway + flat opaque surfaces |
| N6 | Near-black monochrome ramp, luminance hierarchy, one accent, hairline borders | :716 "000000 hues of grey"; :1245 solid dark fills | — | T9 "restrained single-token / OLED identity" | — | — | — | noir OLED black, "hairlines not shadows" | `home/themes/noir.nix` |
| N7 | Snappiness over animation; one short duration; no tiers, no spring | :1541 → 50 ms | :227 | June 27 lesson | — | "aesthetic items do not matter" | "performance is not really the thing" | — | one motion token (wave1/11 §4.5) |
| N8 | Clipboard history with pins/previews | :376 | — | — | — | Mod+V kept | — | BRIEF §3.4 | own store |
| N9 | Notifications: toasts + history, replacing the daemon | :408 | — | — | pillar 2 "dbus, everything" | "add libnotify" | notifications-daemon.ts | "notify-send remplacement to mako" | `gpuix-shell notifications` |
| N10 | Settings / control centre with wifi, bluetooth, audio; the wifi triad (toggle + overlay + full page) | :376 | — | T2/T12 | pillar 3 | network/BT "skip" under the week-three filter | controls window | "wifi menu, or bluetooth pairing menu" | `gpuix-shell controls` + settings window |
| N11 | A workspace remembers what produced it; recoverable sessions; agent status visible | — | — | T11 | pillar 2 | herdr; state colours | — | herdr "centerpiece"; ◉◐●✓○ | rail reads herdr snapshot |
| N12 | Style transfer: rip functionality from complete shells, re-render in own language | :911 | — | T9 "noctalia v5 parity" | — | — | — | "functionality pull from quickshell NOT visuals"; Tacit | DMS/Noctalia/Tacit/gpui-shell/vicinae donors |
| N13 | Keep Chrome and kitty as real clients; never embed them | Mar 26 :10 (retain niri, kitty, Chrome, Nautilus) | — | T11 "niri still handles…" | — | PRIMITIVES | report roles | Mod+0 Chrome, kitty projectors | launch only |
| N14 | Local-first: no network in the click path; durable data outside the UI process | :34 SQLite; :1512 | — | SignalSource | services own data | herdr survives UI | — | herdr/Sway IPC | poll + subscribe, no HTTP |
| N15 | Single-user, niche, no marketplace | — | — | — | (enterprise pitch is AI-authored) | — | — | private repo (fonts) | — |
| N16 | Primer as the design-system reference | :723 | — | — | — | — | 23:07Z | design kit | wave1/11 |
| N17 | Generative / LLM-authored UI as a lane | — | :660, :684 | L5 agent canvas | — | — | — | OpenUI | `gpuix-shell ask` |

### 3.5 Explicitly abandoned (with the ruling that killed each)

| # | What | Introduced | Killed by | Status for builders |
|---|---|---|---|---|
| X1 | Chromium rendering engine as a requirement | Mar 26 :175, :191 | Mar 26 :189 "don't specifically need"; 10-01 "no forking my browser"; 10-13 21:06Z | dead |
| X2 | Purpose-built Chromium embedder (COWL), Proxy/morphdom kernel | Mar 27 :567, :791 | 10-13 | dead; only the "LLM writes UI" idea survives in OpenUI |
| X3 | Aura/Ash/Exo compositor ownership (CADE), the July "appliance" | Apr 10; Jun 10; Jul 17 | 10-01 "wlroots-based system… already good enough"; 10-13 "supersedes the whole aura requirement" | dead |
| X4 | CUBS / Views C++ layer-shell shell; views-shell | Jun 29-30 | 10-13 "abandoning CUBS in its entirety" (later_transitions.md:28) | dead; functionality list mined in wave1/10 |
| X5 | Otto (Smithay + Skia compositor) | Oct 6 | 10-07 "Frosting, animations and the otto file manager was just not enough" | dead; herdr-state colour table and tab-strip arithmetic survive |
| X6 | Hyprland | Oct 13 (74 min) | 10-13 22:25Z "let s tick to sway window manager. less effort" | dead |
| X7 | niri, scroll | pre-March; Oct 6 | `modules/display.nix:2` marks niri/scroll retired (later_transitions.md:19) | dead |
| X8 | Compositor blur / glass / wallpaper bleed; opacity 0.85 window rules | Mar 16 :178, :1222, :1287 | 10-06 PRIMITIVES "blur went unused"; 10-20 "no blur, no frost, wallpaper is #000000 solid" | dead; **the ownership rule (N5) survives, the effect does not** |
| X9 | Dark-only ("No theme toggle. Glass is always dark." :441) | Mar 16 | 10-20 "possibility to switch to claude 'light and dark' variants"; three themes since 09-17 | dead; the shell must follow the `~/.config/theme` pointer |
| X10 | Top menu bar | Mar 16 :376; Jun 27 bar; T2 "views toggle on the top bar" | 10-20 "no top bar on the Linux head" | dead; its contents fold into the rail |
| X11 | SF Pro / Inter / JetBrains Mono | Mar 16 :1431 | Anthropic Sans/Serif/AnthropicMono Nerd Font (BRIEF §1 "keeping the anthropic font… is important") | dead |
| X12 | CSS custom properties, Kobalte, Tailwind, DOM components | Mar 16 | GPUIX has no DOM/CSS cascade (gpuix_solidjs.md:18, 22) | dead as mechanism; token *values* portable |
| X13 | Solid 2 | Mar 16 :17-28 | GPUIX Solid peer range `>=1.9 <2`; React chosen 10-20 (BRIEF §3.1) | dead |
| X14 | QuickshellX / Qt WebEngine / WebChannel | pre-March | Mar 27 "not QtWebEngine" (chat :569); 10-20 "without using quickshell" | dead |
| X15 | Wallpaper-derived dynamic colour (matugen) | rejected Mar 16 :1047 | still rejected (solid #000000) | dead |
| X16 | A new integrated terminal (zmx/libghostty, Chromium Aura) | Jul 23 pillar 5 | 10-06 PRIMITIVES "kitty… keep"; herdr #385 | dead |
| X17 | chrome://-style Lit control interface with an account | Jul 23 pillar 3 | 10-13 (CUBS gone); 10-20 boundary | dead; a plain settings window replaces it |
| X18 | Mirroring every herdr workspace as a compositor workspace | Oct 6 (135 workspaces, 7 agents) | ROADMAP §3 "impossible"; BRIEF nine-slot cap | dead; detached work stays behind the picker/Goto |
| X19 | Reimplementing herdr (herdr-kitten) | mid-2026 | PRIMITIVES "use it, don't reimplement it" | dead |
| X20 | Tally, workerd.nix, Cloudflare OS | 2026-08/09 | 10-13 desk ruling (later_transitions.md:28) | dead; do not revive via the shell |
| X21 | Three animation tiers (80/120/180 ms); M3 Expressive springs; three accents | Mar 16 assistant | Tom :1541 → one 50 ms; :1039-1045 "skip this entirely"; "one accent" | dead |
| X22 | A platform: signed apps, marketplace, plugin host, universal plugin framework | Jul 24 ladder; Oct 6 "plugin host" | May 20 "solo project"; ROADMAP "fails the filter"; later_transitions.md:82 | deferred indefinitely; not in scope tonight |
| X23 | "Unified interface all through Chrome, no native shell whatsoever" | Oct 7 pm | 10-20 order | dead for the shell; alive for utilities |
| X24 | Keep Vicinae (10-12) | | 10-20 "vicinae remplacement" | replaced; inventory its features (BRIEF §5) |
| X25 | Apple/visionOS naming (ultraThin…ultraThick, Liquid Glass) | Mar 16 :1081 | Tom :1329 "without mentions of Mac OS vision" | dead; the M2-M5 idea became named tokens |

---

## 4. Design values (historical, with their tonight equivalents)

All values below are MEASURED in `SOLIDJS-THEME-SYSTEM.md` unless noted. They are **the March 2026 web/CSS numbers**; the current source of truth is the design kit (wave1/11 §4) and `home/themes/*.nix`. I list them because they are the only place Tom personally argued a density, a radius and a motion value, and because the grey ramp is the ancestor of noir.

### 4.1 Grey ramp and surfaces (`:305-345`)
- `--ref-grey-0..9`: #000000, #070707, #0a0a0a, #0e0e0e, #111111, #161616, #1c1c1c, #222222, #2a2a2a, #333333. Tom's own anchor: "000000 hues of grey like 070707" (:716); his kitty: #000000 (:1222); Duncan's: #030303 (FINAL-LINUX-DESIGN.md:62).
- Surfaces: base transparent; M2 #0a0a0a (bars, search input, chrome); M3 #111111 (panels, sidebars, cards); M4 #161616 (inputs, elevated panels); M5 #1c1c1c (overlays, dropdowns, toasts) (`:188-191`). "The jump from #0a0a0a to #1c1c1c is clearly perceptible on a dark display" (Weber's law argument, `:195`).
- States: hover rgba(255,255,255,0.04); active 0.02; selected accent at 0.10-0.12 (`:348-350`).
- Rule (Tom-corrected 08:50): **solid hex fills inside the renderer; never translucent surfaces; depth from luminance steps** (`:1245-1251`). Tonight: identical in spirit — noir is OLED black with opaque surfaces and hairlines (BRIEF §1).

### 4.2 Text and borders (`:355-372`)
- fg 0.92 white; fg-muted 0.56; fg-subtle 0.36; fg-ghost 0.18; fg-inverse rgba(0,0,0,0.85). "~18:1 contrast" for fg on #111111 (`:1253`).
- border-subtle 0.06; border 0.10; border-strong 0.18; rim highlight `inset 0 0.5px 0 rgba(255,255,255,0.06)` (`:245-246`).
- Pairing table (`:498-512`): never fg-subtle on M2; never accent on accent; never raw hex.
- Tonight: three-theme palette replaces the opacity ramps (wave1/11 §4.1); the "hairlines not shadows" rule is the descendant of `--sys-border` 0.10 + no-shadow-on-panels.

### 4.3 Accent and semantics (`:375-389`)
- One accent, muted blue #5B9DFF (assistant's pick at :457; Tom never contested; hover #74ADFF); muted accent 0.12.
- destructive rgba(240,101,101), success (74,222,128), warning (251,191,36), info (96,165,250), each with a 0.12 muted. Tonight: Claude accent set and herdr state colours from the kit (wave1/11 §4.8); the Oct 6 Otto table blocked=amber / working=accent / done=green / idle,unknown=neutral (ROADMAP.md:68-74, MEASURED) is the only Tom-era *state→colour* mapping on record (assistant-proposed, Tom did not answer Q2 on it).

### 4.4 Typography (`:392-414`)
- SF Pro Display/Text, SF Mono (SUPERSEDED: Anthropic Sans / AnthropicMono Nerd Font).
- Sizes: xs 10, sm 12, **base 13 (shell)**, md 14 (app), lg 16, xl 20, 2xl 28. Weights 400/500/600/700. Leading 1.0/1.2/1.4. Tracking -0.01em / 0 / 0.05em.
- Tonight: Anthropic Sans 12 for UI (BRIEF §3.5). The March 13-px shell base is one point larger; Tom asked Vicinae for font 12 (wave1/04:250), so 12 is the current ruling.

### 4.5 Space, radii, heights (`:417-455`)
- Spacing: 0, 1, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64 px; unit 4.
- Radii: sm 4 (badges, kbd), md 6 (buttons, inputs, list items), lg 10 (panels, cards — "Raycast window radius"), xl 14 (floating panels, launcher), full. Per-window: launcher 14, menu bar 0, dock pill (`:1435`).
- Heights: compact 28, default 32, comfortable 36, input 36, input-lg 44, bar 32, row 36 (`:449-455`). ListRow 36 single-line / 48 two-line (`:557`); Toggle 36×20 (`:568`); Slider 2 px track, 14 px thumb; Avatar 24/28/32; ScrollArea thumb 4 px at 0.08.
- Density rule (`:627-633`): shell 13 px / rows 28-36 / max padding 16; apps 14 px / rows 36-44 / max padding 20. "If content feels cramped, the content needs editing, not the padding."
- Tonight: rail 220/30/12/2/8 (herdr-web-ui DESIGN.md), rounded 8/12 inner corners (BRIEF §3.6), launcher 700×580. The March 10/14 radii are within one step of today's 8/12.

### 4.6 Motion (`:445-446`, `:637-660`)
- `--sys-dur: 50ms`, `--sys-ease: cubic-bezier(0.16, 1, 0.3, 1)`; animate only opacity/transform; entry fade + translateY 3-4 px; exit fade; `prefers-reduced-motion` → 0. "There is no fast, normal, or slow. There is only the speed of the shell."
- Tonight: wave1/11 §4.5 holds the kit's motion values; the rule "one duration, no tiers, no spring" is Tom's own (09:21).

### 4.7 Icons (`:664-666`)
- Phosphor or Lucide, stroke 1.5 px, 16 default / 18 in bars / 24 large, currentColor. Tonight: Anthropicons glyph font (BRIEF §2) + the kit's icon rules.

### 4.8 Z-order (`:458-465`)
- base 0, dock 100, bar 200, dropdown 300, overlay 400, modal 500, toast 600, tooltip 700. Tonight: layer-shell layers replace this (rail=top, launcher/toasts/OSD/switcher=overlay, BRIEF §3.3).

### 4.9 Compositor-side numbers that are now historical
- niri `opacity 0.85` (bar/dock 0.80, palette 0.85, notifications 0.90), `blur { passes 3; offset 3.7 }` (`:140-150`; Duncan Rose :1287-1297). FINAL-LINUX-DESIGN.md:55-57 later argued the true opacity was ~0.80-0.83 and that niri's `saturation` multiplier (2.5-4.5) explained the green. All dead under X8; kept here so nobody re-derives them.
- June 27 COWL rail: full width = output/8, collapsed = output/20 (320 ⇄ 128 DIP @2560), C++-owned, proportional (REPORT:28-33). Tonight's 56/220 fixed-px rail is the descendant; the *true exclusive-zone collapse that makes the compositor re-tile* is the behaviour to keep (BRIEF §3.3 "exclusive zone 56 collapsed, 220 expanded").
- June 27 benchmarks (REPORT:130-136): cowl idle 1.9 % CPU / 325 MB PSS / ~600 ms start; waybar ~0 % / 47 MB; DMS 6.6 % / 396 MB / 438 ctxsw/s; rofi 0.1 % / 34 MB. Historical and for a Chromium shell; a GPUIX figure does not exist yet (gpuix_solidjs.md:27).

---

## 5. Reusable code or data, exact paths

| What | Path | Reuse tonight | Caveat |
|---|---|---|---|
| The March token architecture (ref/sys/component tiers, pairing rules, component→material table, density, motion, icon rules) | `/home/tom/notes/references/devlogs/1h26/pre-sync/SOLIDJS-THEME-SYSTEM.md` (`:305-495` tokens; `:498-512` pairing; `:517-538` component table; `:540-605` component specs; `:607-623` shell compositions; `:625-660` density + motion) | Port as a TypeScript token object with the kit's values substituted; keep the *shape* (three tiers, pairing rules, per-component baked material) | CSS/DOM assumptions; SF Pro; dark-only; values superseded by `home/themes/*.nix` |
| The March 16 chat itself (Tom's rulings, the donor module table, the tier list) | `/home/tom/notes/references/devlogs/1h26/pre-sync/quickshellX-solidjs2-discussion.md` (`:931-953` donor table; `:957-963` tiers; `:1212` DMS launcher v2 structure; `:1353-1405` three-level radius ownership) | Checklist source for launcher structure and component coverage | assistant tables; Tom accepted by not objecting |
| Duncan Rose / noctalia Monochrome kitty palette | `/home/tom/notes/references/devlogs/1h26/pre-sync/FINAL-LINUX-DESIGN.md:59-91` | Reference for a zero-hue palette (R=G=B) — the idea behind noir | dead compositor numbers around it |
| June 27 COWL report: the only shipped left workspace sidebar with true layer-shell collapse; providers; benchmarks | `/home/tom/notes/references/devlogs/1h26/june27-cowl-nextsteps/REPORT-2026-06-27.md` (`:12-40` surfaces; `:28-33` collapse; `:125-140` benchmarks, `:129` 120 ms niri lesson) | Behavioural spec for rail collapse (resize the surface + exclusive zone, let Sway re-tile) | Chromium C++; niri |
| CUBS capture model and SignalSource | `/home/tom/notes/references/devlogs/1h26/cubs-steelman/04-reason-to-exist-capture-and-signalsources.md:43-98` | The rail's data model: {Sway workspace} + {herdr workspace id, origin, agent status} with the window ids as transient refs | `:100-116` exclusivity claim is retired |
| June 29 Tom turns (wifi triad, chrome-tabs idiom, noctalia-v5 parity, captured workspace) | `/home/tom/notes/references/devlogs/1h26/cubs-steelman/CHAT-LOG.md` T2 `:36-86`, T9 `:160-170`, T11 `:201-211`, T12 `:223-230` | Rulings only | — |
| Chrome tab-strip policy transliteration (closing-width freeze, reorder hysteresis, detach distance, motion guard), 44 lines vs 23 040 oracle layouts | `/home/tom/notes/references/archive/2026-10-06-wm-scoping/notes8/views-on-otto/SYNTHESIS.md:15, :86` (REPORTED; not opened) | If the rail ever gets drag-to-reorder of workspace slots | Sway workspaces are numbered 1-9; reorder = rename/move, may not be wanted |
| herdr→Otto bridge design: `events.subscribe`, state colours, "detached workspaces stay behind Goto" | `/home/tom/notes/references/archive/2026-10-06-wm-scoping/notes8/shell/ROADMAP.md:59-80` | The herdr subscription recipe and the state→colour table | bash/socat/jq; Otto D-Bus; tonight `herdr api snapshot` polling (BRIEF §3.4) |
| herdr-client / herdr-protocol crates, pushed snapshots with `boot_id`; the focus-side-effect warning | `/home/tom/notes/references/archive/2026-10-06-wm-scoping/notes8/otto-kit/herdr-gpui-precedent.md:18-26` (REPORTED) | Rule: **never call herdr focus from the shell; focus the Sway window instead** (report line 63) | Rust, not TS |
| PRIMITIVES reset and the three-question filter | `/home/tom/notes/references/archive/2026-10-06-wm-scoping/notes7/PRIMITIVES.md:1-45` | Scope filter for every "nice to have" tonight | — |
| July 24 service/surface model (ambient badge vs full app; lifecycle rules) | `/home/tom/notes/references/devlogs/2h26/inbox-july23/agency-apps-service-backed-frontends.md:147-228, :386-416` (REPORTED) | Boundary doctrine for what the rail may show about mail/CRM (a count, never the data) | AI-authored proposal; deferred then |
| Hyprland-era GPUIX shell (Solid, 0.10.0): notifications daemon, applications index, controller, providers, theme loader, layer-shell option sets | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/` — see wave1/13 §5 for file-level reuse | Direct port candidates | Solid → React |
| GPUIX Sway proof with framework-neutral Sway adapter | `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/platform.ts` (wave1/13 §5.4) | Sway IPC adapter | — |
| Old waybar config (what the rail replaces, module by module) | `git -C /home/tom/mecattaf/dotfiles show 1d926f2e^:home/dot_config/waybar/{config,modules,style.css}` | Module list for the rail's bottom cluster | deleted 2026-09-11 |
| Scripts the shell wraps today | `/home/tom/.wt/dotfiles/gpuix-shell/home/dot_local/bin/{osd,volume,brightness,media,audio-route,theme,theme-prompt,fzf-nmcli,vpn-status,screenshot,colorpicker,pomodoro,monitors-off,sleep-monitors,touchpad-toggle,herdr-picker,herdr-chord,herdr-projector,herdr-sway-projector,sway-workspace,wallpaper}` (MEASURED present) | Keep calling them from the shell until a native path exists | — |
| Current binds that name every replaced surface | `/home/tom/.wt/dotfiles/gpuix-shell/home/dot_config/sway/binds.conf:6-7` (Vicinae), `:~114` (Mod+v clipboard), `:139-157` (F2-F10 prompts, media/volume keys), `:28-30` (Chrome apps for claude/mail/calendar) | The CLI verbs `gpuix-shell` must accept | — |
| CUBS repo (functionality list, compositor adapters, schemas) | `/home/tom/mecattaf/cubs/` — mined in wave1/10 | — | — |
| views-shell spike (`--left-tabs` 220 px rail) | `/home/tom/mecattaf/views-shell/` (exists, not read; SPEC.md:114 per ROADMAP) | Rail proportions precedent | C++ |

Not on disk (searched, MEASURED absent): the March 16 claude.ai artifacts `glass-shell-kit.md`, `glass-shell.css`, `DESIGN.md`, `SURFACES.md`, `TOKENS.md`, `COMPONENTS.md`, `PHILOSOPHY.md`, the "Glass shell demo" and "Launcher dark" JSX; a local `quickshellX` clone. Only the consolidated `SOLIDJS-THEME-SYSTEM.md` survives.

---

## 6. Gaps, unknowns, conflicts

1. **The dock has no ruling.** Named by Tom on March 16 (:376) and demoed; never mentioned again in June, July, October or the 10-20 order. Default taken: no dock; the rail's pinned/running-apps cluster covers it. ASSUMPTION for ASSUMPTIONS.md.
2. **Lock screen, idle, greeter** appear in every donor table (DMS, Noctalia, rdnashell; Otto shipped otto-lock) but in no Tom ruling across seven months. Default: out of scope tonight; `swaylock`/`swayidle` remain whatever `home/` declares (not checked).
3. **Dock vs menu bar vs rail precedence** is settled (rail), but the *rail's bottom cluster contents* (clock, battery, tray, volume glyph) are INFERRED from the deleted waybar config and SHELLS-DIGEST, not from a Tom sentence. 10-20 says only "left bar with workspace switcher".
4. **System tray (SNI)** is in every donor and in the March menu bar demo; GPUIX has no StatusNotifier host. Unverified whether any tray-dependent app matters to Tom (Chrome? none obvious). Default: skip SNI in v1, log it.
5. **"World's fastest" vs "performance is not really the thing"**: both are Tom, March vs October. Resolution used here: no benchmarks, no animation tiers; do not spend agent time on latency measurement tonight. INFERRED.
6. **13 px vs 12 px base**: March shell density 13; October Vicinae request 12; BRIEF says Anthropic Sans 12. 12 wins (later). Row heights 28-36 from March have no later contradiction.
7. **Radius 10/14 (Raycast) vs 8/12 (kit)**: kit wins (later, Tom-approved on 10-17 per wave1/11). Difference is one step.
8. **Colour semantics for workspace slots** were never answered by Tom (ROADMAP Q2: agent state vs stable identity). Both the Oct 6 memo and the BRIEF use agent state (◉◐●✓○). Default: state glyphs, neutral colour, accent only on the focused slot. INFERRED.
9. **What a "tab" is** remains the open product decision the report flags (lines 59-61, 77): Sway workspace ≠ herdr workspace ≠ Chrome tab ≠ chat thread. The 10-20 order resolves the first two (one-to-one, nine slots) and leaves Chrome tabs out (Mod+0 is one Chrome workspace). Chrome-internal tabs are not a shell concern tonight.
10. **The apps (board, mail, calendar)** — the ambition that most distinguished March from "a nicer bar" — are explicitly outside the shell (BRIEF §3.8). The only thing the shell may build toward them is the *shared component language* (OpenUI library) and launch verbs. If Tom's morning reaction is "where are the apps", point to N1 and §3.1 A7-A9: they are launched, not hosted.
11. **Hyprland half of the report** (lines 41-65, hyprland_architecture.md entire) is dead on arrival; do not cite it for compositor facts. Its compositor-neutral content (identity mapping, close-view ≠ terminate-session, the bounded-proof ladder at hyprland_architecture.md:86-90) still applies to Sway.
12. **GPUIX unknowns the lanes list and nobody has measured on the Zenbook**: output selection, hotplug, fractional scale, popup grabs, IME, accessibility, touch, keyboard-interactivity change after creation (gpuix_solidjs.md:49-51; later_transitions.md:67). The 23:45 rail probe (BRIEF end) proves layer-shell + exclusive zone + font on headless Sway only.
13. **Authorship caveat on the donor table and tier list** (§3.2): assistant-authored on March 16; Tom's acceptance is implicit (he moved on to "which modules first"). Treat as a checklist, not a ruling.
14. **Earlier history not read**: "December webshell groundtruth" (`~/notes/references/devlogs/1h26/december-webshell-groundtruth.md:445`, pointer from wave1/02:305), `april-webshell-refs/spec/surfaces.md`, the March 9/17 `rice-update` decisions, `sync-march30/font-wanted.md` and `newblur-test.md`. They may hold an even earlier surface list. Not opened; flagged for a later reader.
15. **No live verification** of anything: no compositor run, no package build, no herdr call. This is a reading note.

### What I did
Read all six assigned files completely (83 + 81 + 106 + 82 + 72 + 95 lines) and the 1568-line March 16 discussion completely; opened the cited Tom-voice spans in nine supporting files to verify every quote above; checked the worktree for today's paths; searched ~/notes for the March artifacts. Wrote this file only.

### What I did not do
Did not read the 2116-line March 26-27 chat beyond the cited spans; did not open views-shell, cubs, the July 24 service model, or the Views-on-Otto synthesis (REPORTED via the lanes); did not reconcile against wave1/10, /11, /13 beyond their headings and the lines grepped (cross-pointers only). Unverified = labelled.
