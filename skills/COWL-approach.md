# COWL Development Methodology

> 2026-04-05. Decisions made during a REVOLUTION-2 deep-dive session covering architecture, organizational split, build discipline, and project management for the COWL open-source project.

---

## What COWL Is

COWL (Chromium Ozone Wayland Layer) is an open-source Chromium fork that is simultaneously a full web browser and a full Wayland desktop shell. It starts from `chrome_main.cc` — Chrome boots normally, then `AgencyShellManager::CreateShellSurfaces()` activates layer-shell surfaces that replace Chrome's Views UI.

Three programs run on the desktop: **niri** (compositor), **kitty** (terminal), **cowl** (everything else).

## Organizational Split: COWL vs agency.agency

**The rule**: if removing it breaks the local runtime, it's open source. If it coordinates across machines or generates with AI, it can be proprietary.

### COWL — open source (MIT/Apache-2.0)

- `github.com/<tom>/cowl` on personal profile
- Fedora COPR for distribution, other distros community-contributed
- GitHub Wiki for documentation
- GitHub Issues for work tracking, GitHub Releases for packaging
- Everything that works without an account: shell surfaces, browser, agent sidebar (local), extensions, os.db, all 22 os.* namespaces, browser modes, Wayland protocols

### agency.agency — proprietary SaaS

- `github.com/agency-agency/` private org
- Own yum.d repo, binary = COWL + proprietary client patches (auth, sync, vault)
- Cloud sync (delta packets), E2E encrypted vault, fine-tuned AI model, design generator, extension marketplace
- `agency.agency/changelog` covers both COWL releases and cloud changes
- Self-hosted escape hatch: sync protocol documented, Headscale pattern

### The Tailscale Parallel

```
Chromium          = WireGuard         (open-source engine)
COWL              = Tailscale client  (open-source, on GitHub)
agency.agency     = Tailscale SaaS   (proprietary coordination)
Self-hosted sync  = Headscale         (community escape hatch)
```

Full details: `~/webshell-refs/REVOLUTION-2/revisions-pt2/COWL-VS-AGENCY-ORGANIZATIONAL-SPLIT.md`

---

## Architecture: Chrome-Plus-a-Shell

COWL is NOT a shell that optionally gains a browser. It IS Chrome, with shell surfaces on top. The entry point is `chrome_main.cc`. Chrome's services (BookmarkModel, HistoryService, PasswordManager, TabStripModel, ExtensionService) are consumed by shell surfaces via Mojo IPC.

Chrome's Views UI (tab strip, omnibox, bookmarks bar) is compiled but hidden. Shell surfaces replace everything the user sees. `chrome://` WebUI pages (settings, history, extensions) survive as-is — they're already HTML.

### The Patch Set (~40-50 patches from 4 forks)

| Source | Patches | Purpose |
|--------|---------|---------|
| COWL | 9 in `//ui/ozone/` + ~6,500 LOC in `//cowl/` | Layer-shell, 11 Wayland protocols, Mojo bridge, V8 injection |
| Omarchy | 3 in `//chrome/browser/themes/` | GM3 theme CLI, compositor color sync |
| BrowserOS | ~20-30 cherry-picked in `//chrome/browser/` | Auth, MV2, importer, CDP extensions, extension bundler |
| Browserbase | 3 in `//third_party/blink/` | Stealth (webdriver, UA, keep-alive) |

Forward-porting: 8-24 hours per quarterly Chromium bump.

---

## The Two-Nature Split: Bounded C++ vs Unbounded TypeScript

This is the most important architectural insight for how COWL gets built. The project has two fundamentally different natures:

### The C++ Layer: Spec Implementation (Bounded, One-Time)

The C++ layer (~6,500 LOC in `//cowl/`, 9 Ozone patches, ~30 cherry-picked patches) is **implementing a finished specification**, not iterative product development. REVOLUTION-2 defined every Mojo namespace, every Wayland protocol, every method signature. The protocol XMLs define every state machine. There is nothing to discover.

This is closer to writing a protocol implementation from an RFC than it is to product development. You write it correctly, to spec, once. Then you don't touch it again except for quarterly forward-ports.

**The C++ effort is a focused campaign, not an incremental rollout:**

1. **Ozone patches** — all 9, applied together, compile gate
2. **`//cowl/` source tree** — AgencyShellManager, os_service_impl, V8 bindings, Mojo interfaces, URL handler, permission gate — all written to the final spec. Compile gate.
3. **Chrome patches** — BrowserOS cherry-picks, Omarchy theme, Browserbase stealth. Applied together, compile gate.
4. **Full build** — the ~5 hour gate. Binary starts, surfaces appear on niri, Mojo IPC works.
5. **Protocol validation** — test each of the 11 protocols against niri one by one. Fix what's broken. This is debugging, not design.

After this, the C++ layer is done. `//cowl/` is bounded, stable, and correct.

### The TypeScript Layer: Product Development (Unbounded, Iterative)

The TypeScript layer is where surfaces, services, modes, and extensions live. This is genuine product development — iterative, issue-per-feature, Shape Up compatible. Each surface, each service, each mode is an independent issue and PR.

The contract between the two layers is `os.d.ts` (TypeScript types) and `*.mojom` (Mojo interfaces). The C++ implements it. The TypeScript consumes it. They don't need to iterate together because the interface is spec'd.

### Why This Split Matters

The traditional phased-release model (ship unfinished work, plan to come back later) has a failure mode:
1. We release unfinished/unpolished work expecting to revisit it
2. We don't properly document the gaps
3. We never go back — the shortcuts calcify into constraints

For COWL specifically, the risk is: building the shell on `//content/` because "it's simpler for Phase 1," then discovering the architecture is wrong when Chrome integration arrives in Phase 2. Or shelling out to `wl-paste` because "it works for now," then never implementing native protocol bindings.

**The fix is not incremental slicing — it's recognizing that the C++ layer is spec'd and should be built to its final form from day one.** There is no "Phase 1 shell without Chrome." There is one C++ implementation that supports both shell and browser from the start, and a TypeScript layer that grows features over time.

### The No-Shortcut Rule for C++

> **If a shortcut would need to be undone for the final architecture, don't take it. If it's compatible with the final architecture, it's fine to be minimal.**

| Temptation | Why it's wrong | Do instead |
|---|---|---|
| Build on `//content/` first, add `//chrome/` later | Different entry point, profile system, browser client. Everything rewrites. | Start from `//chrome/` from day one. |
| Shell out to `wl-paste` for clipboard | Subprocess is pull-based. Native is push-based. Store wiring changes. | Implement `ext_data_control_v1` natively. |
| Stub Mojo, inject data directly into V8 | Skips process boundary. Security model changes. | Wire real Mojo from the start. |
| Skip blur, add later | Fine — blur is additive. No architectural impact. | Ship without blur, add later. |
| One bar widget showing static clock | Fine — minimal but correct architecture. | Ship minimal widget, flesh out later. |

The distinction: **is this shortcut in the bones or in the meat?** Shortcuts in the meat (fewer widgets, fewer surfaces) are fine. Shortcuts in the bones (wrong entry point, wrong IPC, wrong rendering pipeline) are forbidden.

### Architectural Fitness Tests

Cheap automated checks that verify the architecture hasn't drifted, run in CI:

- Binary entry point is `chrome_main.cc`, not `cowl_main.cc`
- Shell surfaces are `zwlr_layer_shell_v1`, not `xdg_toplevel`
- `os.*` bindings reach renderer via Mojo, not direct V8 globals
- No subprocess calls for protocols that have native implementations
- Chrome's `ProfileManager` is running (`BookmarkModel` is queryable)

These encode architectural decisions permanently. If issue #47 accidentally regresses to subprocess clipboard, the test catches it.

### Issue Count Revised

| Work | Issues | Nature |
|------|--------|--------|
| Build infrastructure | 2-3 | Setup |
| C++ layer (all patches + `//cowl/`) | 3-5 | Spec implementation, compile gates |
| Protocol validation against niri | 5-8 | Debugging, not design |
| TypeScript surfaces | ~7 | One per surface, independent |
| TypeScript services | ~8-10 | One per service, independent |
| Chrome integration bridges | ~5-6 | Each independent |
| Browser modes | ~5-6 | Each independent |
| Extension system | ~4-5 | Sequential |
| Agent integration | ~4-5 | Sequential |
| **Total** | **~45-55** | |

The first ~10 issues produce the **complete C++ foundation** — not a skeleton, the real thing. Then 35-45 issues of TypeScript product development fan out in parallel.

---

## Build Discipline

Source: `~/cowl-secondpass/docs/panel/ai-dev-strategy.md`, `r2-quality-orchestration.md`, `~/webshell-refs/REVOLUTION-2/cowl-docs-analysis/03-panel-validation-and-release.md`

### The Core Rule

> "Never let agents write code that will not be validated within the same session. If an agent cannot compile its output, the output is not code — it is a suggestion."

### Verification Levels

1. **Level 1**: Compiles (`autoninja` exits 0)
2. **Level 2**: Doesn't crash within 10 seconds
3. **Level 3**: Specific functionality works
4. **Level 4**: Visual verification (human)

No code merges without Level 1. No milestone gates without Level 3.

### Incremental Build

First full build is ~5 hours. After that, `is_component_build = true` gives ~30s incremental builds. The discipline is: get everything right before the first build, then iterate fast.

### Build System

Adopt from existing forks — don't build from scratch. Reference:
- BrowserOS (`~/tmp/BrowserOS/packages/browseros/`) — `features.yaml` + `browseros dev extract/apply` CLI for patch management
- Omarchy (`~/tmp/omarchy-chromium/`) — PKGBUILD + `args.gn` + nightly build scripts

### Context Engineering

CLAUDE.md in the COWL repo serves as a **territory map**, not prescriptive instructions:
- Where reference repos live (BrowserOS, Omarchy, cowl-secondpass, webshell-refs)
- Ground truth files (mojo/*.mojom, surfaces/lib/kernel.js, os.d.ts)
- Anti-patterns (no polling, no CSS blur, no frameworks, no shelling out when a protocol exists)

Agents self-navigate from this map. They're not told which files to read for which task.

---

## Dependency Map (Build Order)

The full elephant, organized by what blocks what. Read bottom-up.

### Layer 0: Build Infrastructure
Chromium checkout, GN args, patch management, deploy script, `is_component_build = true`.

### Layer 1: Ozone Patches (blocks all shell surfaces)
`kLayerShell` window type, `WaylandLayerShellWindow` class, protocol globals, object traits, BUILD.gn wiring, `ext_background_effect_v1` blur.

### Layer 2: Minimal Embedder (blocks any visible output)
`AgencyShellManager`, `os://` URL handler, V8 injection, Mojo stubs, `ChromeContentBrowserClient` hook.

**Milestone: one layer-shell surface renders HTML on niri.**

### Layer 3: Wayland Protocols (each independent, one PR each)
`ext_data_control_v1` (clipboard), `ext_session_lock_v1` (lock), `ext_idle_notify_v1` (idle), `zwp_idle_inhibit_v1`, `zwlr_gamma_control_v1` (night light), `zwlr_foreign_toplevel_v1` (window list), `ext_workspace_v1` (workspaces), `zwlr_output_management_v1` (displays), `zwlr_screencopy_v1` (screenshot).

### Layer 4: TypeScript Runtime
Proxy store, morphdom, `html```, design tokens, `os.d.ts` contract.

### Layer 5: System Services (each independent)
`os.command`, `os.socket` (niri IPC), `os.dbus`, `os.db`, `os.settings`, audio, power, network, bluetooth, brightness, media, notification daemon.

### Layer 6: Shell Surfaces (each independent)
Bar, OSD, notifications, overlay, dock, lockscreen, KMUX sidebar.

### Layer 7: Chrome Integration Patches (each independent)
Views bypass, `os.browser.*` Mojo bridges, Omarchy theme, MV2 support, extension bundler, data importer, notification routing, settings extensions.

### Layer 8: Browser Modes (each independent)
vim-normal, vim-insert, hint-mode, blocker-mode, reader-mode, password-mode, annotation-mode.

### Layer 9: Extension System
`.agency.ts` parser, loader, permission gate, Shadow DOM isolation, hot-reload, 5 extension types.

### Layer 10: Agent Integration
CCD sidebar, NDJSON/pi-mono parser, auto-approval, KMUX sessions, agent-generated surfaces/extensions.

### Layer 11: Stealth/Automation
`navigator.webdriver = false`, UA masking, keep-alive, CDP extensions.

### Layer 12: Cloud (agency.agency proprietary, Phase 4)
Auth, sync adapter, delta-packet engine, vault, cross-device identity, AI model, marketplace.

**The hard part is narrow**: Layers 0-2. Once a single surface renders on niri, every subsequent feature is one issue, one PR, one incremental compile.

---

## Project Management: Issues-Driven, Outcome-Based

### Philosophy: Shape Up

Work items describe outcomes, not approaches. Each GitHub Issue is a **pitch** with:
- **Outcome**: what's true when this is done
- **Verification**: concrete, testable acceptance criteria
- **Boundaries**: what's explicitly out of scope

No prescribed file lists, no step-by-step instructions. The Claude Code session assigned to the issue figures out the approach — including finding reference material from the local clones.

### The Pipeline

```
GitHub Issue (outcome-based pitch)
  → Claude Code session picks it up
  → Branch: feat/42-clipboard-protocol (or fix/, chore/, etc.)
  → Conventional commits (commit-craft skill)
  → PR closes #42
  → Merge to main
  → release-please reads commits, bumps version, writes CHANGELOG
  → GitHub Release published
  → Starlight changelog pulls to agency.agency/changelog
  → COPR rebuilds
```

### Issue Structure

```markdown
Title: feat: native clipboard read/write/subscribe via ext_data_control_v1

## Outcome
A TypeScript surface can read the system clipboard, write to it,
and subscribe to changes through os.wayland.dataControl — no
subprocess calls to wl-copy/wl-paste.

## Verification
- [ ] autoninja exits 0
- [ ] Bar widget shows last 5 clipboard entries
- [ ] Copying in any app updates the widget live on niri

## Boundaries
- Only ext_data_control_v1. No clipboard history persistence.
- No os.db storage yet.
```

### Tracking

| Need | Tool |
|------|------|
| Dependency ordering | Milestones (one per layer or key milestone) |
| Categorization | Labels (`layer:*`, `type:feat/fix/chore`, `source:omarchy/browseros`) |
| Progress tracking | Issue close rate per milestone |
| Public visibility | Issues are public, anyone can watch/subscribe |
| Claude Code native | `gh issue view`, `gh issue list --milestone` |

### Milestones

Key gates, not calendar dates:
- **First surface on niri** (Layers 0-2 complete)
- **Bar renders with live data** (Layer 4-5 subset + Layer 6a)
- **All 11 protocols validated** (Layer 3 complete)
- **Full shell** (Layers 3-6 complete)
- **Browser integration** (Layer 7 complete)
- **Daily driver** (Layers 8-10 complete)

### Labels

```
layer:0-build, layer:1-ozone, layer:2-embedder, layer:3-protocol,
layer:4-runtime, layer:5-services, layer:6-surfaces, layer:7-chrome,
layer:8-modes, layer:9-extensions, layer:10-agent, layer:11-stealth

type:feat, type:fix, type:chore, type:docs, type:refactor

source:cowl, source:omarchy, source:browseros, source:browserbase

priority:high, priority:medium, priority:low
```

---

## Release Automation

Uses the existing skill stack from `~/mecattaf/dotfiles/skills/git-aicademy/`:

1. **`repo-bootstrap`** — scaffolds `.github/workflows/`, issue templates, PR template, CLAUDE.md
2. **`commit-craft`** — conventional commits (`feat(ozone): add layer-shell window type`)
3. **`release-flow`** — release-please creates versioned releases + enhanced CHANGELOG
4. **Starlight changelogs** — deployed to Cloudflare Pages, pulls from GitHub Releases, becomes `agency.agency/changelog`

### Version Bumps (Conventional Commits)

| Commit type | Bump |
|---|---|
| `fix:`, `perf:` | Patch |
| `feat:` | Minor |
| `feat!:` or `BREAKING CHANGE:` | Major |
| `docs:`, `chore:`, `refactor:`, `test:`, `ci:` | No bump |

---

## Reference Material (Local Clones)

These repos are on disk and available for Claude Code sessions to reference:

| Repo | Path | What to learn from it |
|------|------|----------------------|
| BrowserOS | `~/tmp/BrowserOS/` | Patch management (features.yaml), auth, MV2, CDP, build system |
| Omarchy | `~/tmp/omarchy-chromium/` | PKGBUILD, args.gn, theme patches, build scripts, CI |
| cowl-secondpass | `~/cowl-secondpass/` | **Docs = vision. Code = inspiration only.** Mojo interfaces, surface specs, protocol inventory |
| webshell-refs | `~/webshell-refs/` | REVOLUTION-2 architecture decisions, prior art research |
| Chromium | `~/chromium/` | Source checkout, depot_tools |

### cowl-secondpass: What to Use

- `docs/` — the vision of what COWL should be (architecture, API reference, guides)
- `docs/CLAUDE.md` — anti-patterns and conventions (adapt for new repo)
- `mojo/*.mojom` — interface definitions (reference, may need updates)
- `surfaces/` — TypeScript surface templates and kernel (inspiration)
- `patches/` — Ozone patches (starting point, need validation and likely rewriting)
- `src/` — C++ source (inspiration only, not validated, not high quality)

---

## Phase 0: Pre-Build Setup (Before Any Code)

Three workstreams that must complete before the first line of COWL code is written.

### 0a. Reference Compilation, Indexing, and Consolidation

Extensive reference research exists but is scattered across multiple sessions and locations. It needs to be re-indexed and consolidated specifically for the COWL project — a single pass that produces a usable reference map for Claude Code sessions.

**What exists today:**

| Collection | Path | Contents | Status |
|---|---|---|---|
| QuickShell shells (25+) | `~/webshell-refs/reference/` | DankMaterialShell, noctalia, caelestia, equora, nucleus-shell, etc. | Audited, snippets extracted |
| Feature matrix (280 features) | `~/webshell-refs/ANNOTATED-feature-matrix.md` | Every feature mapped to os.* namespace with "Best impl" pointers | Complete |
| Code snippets | `~/webshell-refs/snippets/` | 93 files across 6 dirs, extracted from reference shells | Complete |
| REVOLUTION targets (21 repos) | `~/webshell-refs/REVOLUTION/references-targets/` | CEF, Electron, morphdom, niri, wayland-protocols, QuickShell, BrowserOS, Fabric, etc. | Cloned, analyzed |
| REVOLUTION-2 deep-dives | `~/webshell-refs/REVOLUTION-2/` | 89 files, ~200K+ words. BrowserOS audit, ChromeOS retrospective, Zen analysis, DMS extensions, Wayland protocol inventory | Complete |
| Chromium forks | `~/tmp/BrowserOS/`, `~/tmp/omarchy-chromium/` | Patch management, build systems, auth, MV2, theme CLI | On disk, analyzed |
| Fabric reference | `~/webshell-refs/reference-fabric/` | Fabric-vs-WebShell analysis, monday-concept expert panels | Complete |
| Nyxt reference | `~/webshell-refs/reference-nyxt/` | Nyxt browser architecture, roundtable analysis | Complete |
| cowl-secondpass | `~/cowl-secondpass/` | Docs = vision. Mojo interfaces, surface specs, protocol inventory | Docs are reference, code is inspiration only |
| KMUX scoping | `~/webshell-refs/KMUX-*.md`, `kmux-next-session.md` | Evaluation criteria, integration surface spec, ~238 URLs across 32 files | **Least consolidated — needs work** |
| Zen Browser | `~/tmp/desktop/` | Full source: XUL patches, CSS, JS modules, build system | Analyzed in REVOLUTION-2 |

**What the consolidation pass produces:**

A single `REFERENCE-INDEX.md` in the COWL repo that maps each reference to what it's useful for. Not a deep analysis — a lookup table for Claude Code sessions:

```markdown
## For Ozone/layer-shell patches
- ~/webshell-refs/REVOLUTION/references-targets/critical/niri/ — compositor source, protocol support
- ~/webshell-refs/REVOLUTION/references-targets/critical/wayland-protocols/ — protocol XMLs
- ~/cowl-secondpass/patches/ozone/ — prior attempt (inspiration, not copy)

## For build system
- ~/tmp/BrowserOS/packages/browseros/build/ — features.yaml, extract/apply CLI
- ~/tmp/omarchy-chromium/ — PKGBUILD, args.gn, smart_update.sh

## For KMUX/agent integration
- ~/webshell-refs/KMUX-EVALUATION-CRITERIA.md — what to evaluate
- ~/webshell-refs/KMUX-INTEGRATION-SURFACE.md — os.claude, os.terminal stubs
- ~/webshell-refs/clui-cc-reference/ — Claude Code UI reference
...
```

The heterogeneity is the point — Chromium forks for C++ quality, QuickShell shells for TypeScript surface design, Fabric/DMS for extension systems, KMUX docs for agent integration. The index makes it navigable.

### 0b. Testing, Automation, and Local Build Protocols

Before writing COWL code, the repo needs the infrastructure that enforces quality. From `cowl-secondpass/docs/panel/quality-engineering.md` and `r2-quality-orchestration.md`:

**CI pipeline (GitHub Actions):**
- `ci.yml` — lint, build verification on every PR (from `repo-bootstrap`)
- `release-please.yml` — automated versioning and CHANGELOG (from `release-flow`)
- Architectural fitness tests (entry point check, surface type check, IPC check)

**Local build protocol:**
- Chromium checkout at pinned version
- GN args for Linux/Wayland (`is_component_build = true` for 30s incremental)
- Patch application script (adopt from BrowserOS or write `apply-manual.py`)
- `deploy.sh` — copy COWL source into Chromium tree + apply patches + `autoninja`
- Distrobox or native build environment on Fedora

**Test infrastructure:**
- Kernel unit tests (~200-300 LOC, pure JS, no COWL deps): Proxy reactivity, html escaping, render + dependency tracking, effect, computed, batch
- CDP integration test harness (pytest): start nested Wayland compositor, boot COWL, evaluate JavaScript, verify surface behavior
- Protocol conformance tests: for each protocol, create object, exercise every method, verify events fire against niri
- `ci-gate.sh` — deterministic gate script: compile inside distrobox, report pass/fail

**The test suite is the memory of what works.** When a protocol passes validation, the test encodes that permanently. Future changes that regress it get caught.

### 0c. Build-in-Public Stack

From `~/cowl-secondpass/docs/vision/COWL-V1-VISION.md` (the go-to-market strategy):

> "Build in public starts now. It's showing the construction site, not cutting the ribbon."

**Content pipeline:**
- Weekly raw content: screen recordings of building features with AI. "Today I added Bluetooth pairing to my shell in 4 minutes."
- 30-second clips of interesting moments: debugging a Wayland protocol state machine, first blur rendering on niri, AI generating a widget in real-time.
- No download link, no repo link, no CTA except "follow along" until launch.

**Platform strategy:**

| Platform | Content | Purpose |
|----------|---------|---------|
| r/unixporn | The screenshot | The detonator |
| Hacker News | Show HN: agency.agency | The amplifier |
| YouTube short (60s) | Agent sidebar demo | The evergreen funnel |
| Twitter/X thread | Build log narrative | The community |
| r/linux, r/fedora, r/niri | Cross-posts | The ecosystem |

**Release pipeline (from existing skills):**
1. Conventional commits → release-please → GitHub Release → CHANGELOG
2. `release-flow` skill enhances auto-generated notes into human-readable descriptions
3. Starlight changelogs site (Astro + `starlight-changelogs`) deployed to Cloudflare Pages → becomes `agency.agency/changelog`
4. Optional: `notify-twitter.ts` for auto-tweeting releases, cross-repo webhook dispatch

**Sequencing matters:** The build-in-public content starts during Phase A (C++ foundation) — "first surface on niri" is inherently interesting content. It doesn't wait for a polished product.

---

## What Starts Today

### Phase 0 (pre-build, ~1-2 days)
1. Create the `cowl` GitHub repo
2. Run `repo-bootstrap` to scaffold workflows, templates, CLAUDE.md
3. Create labels and milestones matching the layer map
4. Consolidation pass: produce `REFERENCE-INDEX.md` from scattered research
5. Set up local build protocol (Chromium checkout, GN args, deploy script)
6. Set up build-in-public accounts/pipeline (optional, can be deferred)
7. Write seed issues for Phase A and Phase B

### Phase A: C++ Foundation (focused campaign, ~3-5 issues)
Cathedral-style. Write to the final spec. No shortcuts in the bones. Compile gates between each unit. Ends when: binary boots from `chrome_main.cc`, surfaces appear on niri, Mojo IPC works, all 11 protocols pass validation.

### Phase B: TypeScript Product (ongoing, ~35-45 issues)
Shape Up style. Outcome-based issues. Scope-flexible. Agent-navigated. Each surface, service, mode, and extension is independent. The `os.d.ts` contract is the bridge — C++ implements it, TypeScript consumes it, they don't iterate together.

The elephant is mapped. The methodology is set. Build it.
