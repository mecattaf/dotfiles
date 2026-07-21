# Ouverture — the one shape

A forward-looking companion to `nix-decisions.md`. Not decisions; the *thesis*
that the whole migration is quietly converging on.

## The thesis: everything bespoke becomes one shape

The thing you fell for in `june18-nix-learnings.md` (microvm.nix) isn't a tool —
it's a **shape**: a flake-module that takes **typed options → emits a small
CLI/daemon + its config**, composable, reversible, reductive. NixOS, niri-flake,
microvm.nix, pi.nix all share it. The realization of this migration is that
**every bespoke thing you own wants that same shape** — kmux, asr-rs, *and the
skills collection*. The flake is not just where configs live; it's a **registry
of your own small tools**, each a module.

## kmux as the exemplar — and its lesson is "keep subtracting"

The arc across your notes is one continuous act of subtraction:

1. **kitty-harness (the failure).** A kitty-maximalist multiplexer that
   re-emulated the terminal and bolted on agent features. Your own verdict: *"a
   great lesson in overbuilding… minimal features over-engineered, for nothing."*
   The core was a terminal engine you didn't need to own.
2. **kerdr (the ideal shape, june18).** Invert it: kitty renders, shpool
   persists, CEF paints — kmux shrinks to the **one novel seam**: a data-model +
   delta-stream + thin CLI. Package as a nix flake-module (the microvm.nix shape).
   *"The seam is the product; everything else is delegation."*
3. **june15-update (subtract again).** pi runs **rpc/headless natively** and the
   real lever is **the right subagent extension** — *"superseding most other
   things completely."* So even the persistence core (shpool "keep the session
   alive") is in question: pi may already do it. The seam may shrink to almost
   nothing.

**The discipline:** keep subtracting until only the irreducible novel bit remains
— then, and only then, package *that* as a flake-module. kmux's final size is
unknown precisely because you're still subtracting, and that's correct.

## The skills frontier — same shape, next domain

The 3-agent survey of `dotfiles/skills/` (territory below) shows what you already
said: it's **aspiration, not a real collection** — mostly notes/plans, a few
real-shaped. The inspiration: rebuild each as a **real Claude skill** — a
`SKILL.md` + (often) a **small CLI** — and package both the Nix-native way. A
"skill + its CLI" *is* a flake-module. The skills collection becomes another set
of modules in the same flake.

The lovely recursion: your **`microvm/` sandbox skill** literally *is*
microvm.nix applied — the skill teaches the agent to use the very pattern this
whole migration adopts.

### Territory map (from the survey)

| cluster | items | maturity |
|---|---|---|
| **git workflow** | git-history-mgmt (REAL, skill-shaped), git-aicademy (3 outlines), task-6.1 | **strongest / ready** |
| presentations | slides-skill + task-6.5 (detailed prompt + sample artifact) | strong, fragmented (consolidate) |
| google workspace | task-6.4 + google-workspace-cli (CLI exists → thin skill) | medium |
| browser automation | task-6.2 (ties to fgp-browser decision) | medium, blocked on browser tooling |
| sandboxing | microvm/ (deep research + draft `sandbox.sh`, 4 blockers; no SKILL.md) | far-future but = the pattern |
| task/CRM/OCR | task-6.6 / 6.7 / 6.8 | far-future (6.6 overlaps backlog-discipline) |
| meeting memory | meeting-memory-concept (full architecture, no code) | research |
| writing/coding curriculum | aicademy-2025-writing | KEEP as knowledge, not a skill |
| reference (not skills) | COWL-approach, jean-build-magic-prompts, remote-connection, project-mgmt | knowledge to keep |
| stubs | frontend-design, video-aigen, md-artifact, screenshot-tool | research bookmarks |

**Ship-first candidates:** (1) **git-history-mgmt** — already has a `skill.md` +
scripts, nearly loadable; (2) **presentation maker** — merge task-6.5's prompt +
slides-skill into one SKILL.md (+ tiny preview CLI); (3) **google-cli skill** —
thin wrapper over an existing CLI. Each is a clean first "skill-as-module."

**Duplication to resolve:** git (git-history-mgmt vs git-aicademy vs task-6.1 —
split by scope: rewrite/undo vs release/commit discipline); slides (task-6.5 ==
slides-skill); google (task-6.4 == google-workspace-cli).

## The third pillar: CUBS (the browser-shell) — same lesson, biggest stakes

Lineage (`june16-cowl-revived.md`): **quickshellX** (abandoned QML webshell) →
**COWL** (Chromium·Ozone·Wayland·Layer — the substrate tier) → **CADE** (Chromium
Aura Desktop Environment — the *overshoot*: a compositor, "NO MORE NIRI") →
**CUBS** (Chromium Unified Browser-Shell — where you netted out).

It's the **exact same arc as kitty-harness**: a maximalist impulse ("own the
stack / be the compositor") that measured progress as "how much substrate have I
harnessed" instead of "what can the user now do" — pivoted, twice, each time
toward less code. The banked discipline is the anti-maximalist gate:
**use-case precedes the surface** — a capability doesn't exist until a concrete
experience strains against the alternative.

**CUBS netted (decisions banked, june16):**
- Roll back the compositor; build the **browser+shell unified client UNDER niri**.
- **Keep `//chrome/`** — a real, LLM-controllable, **de-Googled (ungoogled) +
  vimium** browser is a *wanted* capability (graduate from fragile CDP-on-flatpak
  to reliable in-process control). It rides the **bounded, additive diff shape**;
  the unbounded deletion-shaped de-Ash work is dropped.
- **COWL = substrate tier, CUBS = the product** (umbrella name if forced: CUBS).
- Schema-first surface: `os.*` (in-page Mojo, shell hardware/surfaces) + a CDP-like
  wire for the agent (browser + thin orchestration; agent gets **no raw hardware**).
- The product is the **surface continuum**: a widget *is* the app, the
  `you@agency.agency` account is the identity thread. agency.agency = account
  boundary only.

**The retained, load-bearing piece — and why Nix is the enabler:** you maintain a
**patched Chromium, built daily**. Fork mechanics: anchor-based `apply-manual.py`
patching, pinned `CHROMIUM_VERSION`, ~40–50 *additive* patches in `//chrome/`,
quarterly rebase tax (~8–24 h). The june18 Nix decision makes this tractable:
**build the patched Chromium ONCE on the Strix Halo box, push to Attic/Cachix,
every client substitutes** — content-addressed, same artifact-flow as COPR→bootc
minus the reflash. So **the Nix migration (esp. the Strix-Halo build box + binary
cache) is literally CUBS's build infrastructure.** That's the connective tissue:
Nix isn't a sibling project to CUBS — it's the foundation that makes daily patched
Chromium painless.

**Open read (confirm):** CUBS *is* "the own Linux shell" you said you'd build —
which means **eqsh/quickshell is its abandoned predecessor**, not a HOLD to
resume. The bar-less/notification-less interim is "bar-less until CUBS surfaces
exist," and the dying quickshell `qs ipc` scripts are predecessors CUBS replaces.

## What this opens — the 2-month picture

The build phase isn't "port dotfiles + reinstall packages." It's: **stand up one
flake that is a registry of small, typed, reductive modules** — host configs,
yes, but also your own tools (kmux when its seam settles, asr-rs v2, the real
skills + their CLIs). The kitty-harness lesson (don't overbuild) and the
microvm.nix shape (typed module → small CLI) are the two rails. Skills are the
first new domain to lay on those rails.

Open thread to pull next: pick **one** skill (git-history-mgmt is the obvious
first) and make it the *skills* equivalent of what mactahoe was for packages —
the proof that "real skill + CLI, nix-packaged" is the repeatable unit.

### The ~2-month map (one substrate, three pillars)

**Nix is the substrate; the projects ride on it.**

```
            ┌─ kmux / agent-orchestration  (seam still shrinking;
            │     pi rpc/headless + a subagent extension may absorb it)
 NIX flake ─┼─ skills collection           (each = real SKILL.md + small CLI,
 (one repo, │     as flake-modules; git-history-mgmt ships first)
 registry   │
 of modules)└─ CUBS                         (patched de-Googled Chromium browser-
                  built daily on Strix-Halo → binary cache → substitute everywhere)
```

Proof-units, one per pillar (the mactahoe pattern, repeated):
- packages: **mactahoe** ✅ (done).
- skills: **git-history-mgmt** as the first real skill-as-module.
- CUBS: **patched Chromium building on the Strix-Halo box → pushed to cache** —
  the moment that lands, daily de-Googled Chromium is solved and CUBS has legs.

The single rail under all three: **use-case precedes the surface** (kitty-harness
/ COWL→CADE taught it the hard way) + **the microvm.nix shape** (typed module →
small CLI/daemon). Build reductively; package as modules; let Nix's cache carry
the heavy artifacts across the fleet.
