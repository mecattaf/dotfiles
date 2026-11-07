# Skills ownership review

Reviewed 2026-11-07 against Tom's latest direction in Projects dotfiles T-100
and his earlier [issue #674](https://github.com/mecattaf/dotfiles/issues/674).
This inventories the 24 tracked skill entry points before these five
retirements (19 afterward), the external publishing skill, and the local
vendor downloads. It distinguishes a capability's owner, its distribution,
and what an agent actually receives.

## Direction and first changes

Tom's current instruction is:

> now that this is built,  i feel like we are in a place to continue with the remaining skills. i had an idea to use in-dotfiles skills less, making them in-dsh instead. this is improtant to keep in mind. critically go through the skills i have and undrestand: thos ethat generate presentations are out ; that is in dsh. steer-codex for example is also removed, ineracting with te superagent architecture will make thta automatic. slash-speak for tts willbecome somehting that is controlled domicile-side.

He previously specified that `/print` remains in dotfiles because it is
specific to his NixOS fleet; portable artifact management is DSH-centric with
selective Claude Code specialization. These are ownership decisions, not
evidence that all replacement integrations are already running.

This patch removes `presentation-beta`, `steer-codex`, `speak`, `handoff` and
`pickup`. The last two implement the explicit earlier request in #674.
It removes obsolete handoff/pickup instruction assertions without removing
the memory engine or its behavioral tests. It stops the legacy speech launcher
from automatically enabling speech or instructing agents to submit answers.
The generic HTML skills stop advertising deck generation. The remaining
Markdown renderer guide uses the external private publisher, rather than
repeating the broken private `.dev`/Caddy recipe.

The patch also stops linking Claude's downloaded `synced` tree into
`.agents/skills`. Both Claude seats retain their downloads and producer paths.
No vendor account data is deleted or deduplicated.

The remaining portable skills still need owner migrations. Keeping them
temporarily discoverable avoids equating removal of instructions with delivery
of their replacements. Nix can continue pinning and installing a product without
owning its operational procedures.

## What is actually loaded

[agent-tools.nix](../home/agent-tools.nix) links retained source entries into
both Claude roots and `.agents/skills`; PR696 changed the brain from whole-root
links to individual entries. Merely moving this entire tree to a DSH directory
would retain its overlapping instructions, stale dependencies and broad triggers.

The installed DSH 0.2.1-rc.2 filesystem provider scans direct skill bundles and
top-level Markdown, deliberately excluding nested `**/SKILL.md`. Its roots are
project `.dsh/skills`, project `.agents/skills`, configured custom roots,
`$DSH_HOME/skills`, and `$DSH_AGENTS_HOME/skills`. It does not scan
`.claude/skills`. Consequently:

- `design-references/uncodixfy` and the three `effective-html/references/html*`
  skills are not independently discovered through this layout by that provider.
  A future owning package must register them deliberately. The umbrella HTML
  guide can still load its nested references.
- The two nested synced account trees were exposed to recursive consumers such
  as Codex, but are not loaded by DSH's shallow filesystem discovery. Removing
  that `.agents` link corrects exposure; it does not remove 26 DSH capabilities.
- The active native Claude adapter passes `settingSources` for user, project
  and local configuration. Claude keeps its own discovery inside that adapter;
  a DSH-only skill does not automatically reach its inner agent loop.

DSH already has scoped roots and plugin registration. This review does not
justify inventing another general-purpose skill loader. New capability packages
should own code and resources, then expose only the operations and guidance
needed by each configured agent/profile.

## Retired instruction layers

- **presentation-beta:** retired. This was Claude-authored Reveal HTML with
  an old brand-kit doctrine and rehearsal/publishing procedure. Presentation
  generation belongs to DSH. The separately packaged
  [artifact-deck-init](../pkgs/artifact-deck/default.nix), renderer assets and
  existing decks remain available; they are not imported from the deleted guide.
  DSH ships a genuine `office-pptx` resource, but the active Agency profile does
  not mount its Office provider. `agency-presentation` provides branding;
  `dsh-agent-tool-presentation` selects tool schemas. Neither is a deck generator.
  Feature availability needs verification when enabling the intended DSH owner.
- **steer-codex:** retired. This directory was an instruction-only executor
  recipe. Preserve its useful behavior in Superagent integration: unchanged task
  scope, isolated worktrees, durable worker identity, exact resume, and verified
  results. The inspected profile does not establish an installed Codex/Superagent
  executor. Deleting the recipe does not establish automatic orchestration.
- **speak:** retired. Domicile owns speech controls. The reviewed Domicile
  sources do not demonstrate TTS output control, and `dsh-domicile`'s read-only
  desktop snapshots are not a speech implementation. Preserve the NAS queue,
  compute synthesis, accepted K2SO voice, playback, quiet hours and receipts.
  The legacy [session launcher](../pkgs/speech-session/session.py) is still
  distributed on some hosts and names obsolete `strix`; this patch removes its
  automatic speech prompt, not the backend or existing sessions. See
  [speech operations](speech-operations.md).
- **handoff:** retired under #674. Preserve bounded continuation, decisions,
  evidence and exact lineage in session/project orchestration. Old marker
  readers remain necessary for historical notes; no memory is deleted.
- **pickup:** retired under #674. Preserve exact-session lookup, wrong-session
  refusal and access to historical reviewed continuations. These behaviors and
  their tests remain in [ai_memory.py](../home/dot_claude/skills/drain/scripts/ai_memory.py)
  and [tests/ai-memory](../tests/ai-memory/test_ai_memory.py).

## Fleet utilities

- **print — keep in dotfiles.** This is Tom's explicit exception. It also
  contains code imported by [paper-daemon](../pkgs/paper-daemon/default.nix)
  and the paper renderer. Keep its instructions, scripts, NAS intake/receipts,
  compute renderer, printer configuration and quiet-hours policy together.
- **update-check — retain fleet logic; demote the guide to a routine brief or
  runbook.** Its watch manifest, gate, locks, admission and job receipts belong
  to this fleet; its schedule belongs to Substrate, not a new Nix timer. DSH
  tool availability is not a replacement for this mechanism. The existing
  [build gate](../home/dot_local/bin/update-check) hard-codes `--max-jobs 2
  --cores 4`; an owner migration must preserve compute-host execution instead
  of invoking it on NAS. This finding is recorded, not silently fixed by the
  instruction retirement patch.
- **microvm — retain fleet infrastructure; make the manual a fleet runbook.**
  The host module, units, generated commands, guest state and GC roots remain.
  A DSH bubblewrap runner does not implement microVM lifecycle or teardown.
  Preserve teardown/GC-root guidance and update stale host/Caddy recipes when
  moving [the manual](../home/dot_claude/skills/microvm/SKILL.md).

Only print is a confirmed permanent skill exception from Tom. The suggested
runbook treatment of the other two is this review's recommendation.

## Product-owned operations

- **publish-artifact — already extracted.** The private
  [artifact-publish package](https://github.com/mecattaf/artifact-publish)
  owns Tailscale Serve routes, ownership manifests, TTL, refresh and reap.
  It supplies a thin skill from its own release. Public Cloudflare deployment
  is explicit and not claimed as an implemented command in that private tool.
  PR696 provides the fleet link/reaper integration.
- **crm — put distribution under the CRM product.** The dotfiles skill and
  655 KB reference are byte-identical to `agency-agency/crm/skills/crm`.
  The dotfiles copy's `../../AGENTS.md` link is broken; it resolves correctly
  in the product tree. The current CRM package exports only `dist`, so there is
  no installed skill path to link yet. Package a versioned resource tree that
  preserves that relative link before removing the duplicate. Keep CLI,
  configuration, auth, Worker/data and mail-delivery integration. The older
  `mecattaf/crm` skill describes the superseded local-database product.
- **projects — put product instructions with the project service; keep durable
  records distinct from worker execution.** The pinned standalone CLI installs
  only `bin/project` and `lib/project/project.mjs`, and its source currently has
  no skill directory. Substrate's DSH sessions already receive role-scoped
  project tools; coordinators disable skill discovery. However, the MCP refuses
  ordinary front-door chats, so removing the current global guide would lose
  its Tom-chat filing behavior without a verified replacement. Move a narrower
  product-owned adapter with an installed resource path, then revise profile
  exposure. Retain service, records, CLI, credentials and session integration.
- **backlog-discipline — retire global discovery after preserving project
  context.** This describes the historical Leger/Sodimo Backlog.md workflow.
  Its named board configuration, daily-log directory and Downloads methodology
  are absent here; broad `TASK-*` triggers can catch unrelated work. The current
  Projects product explicitly treats that clone as historical documentation.
  This is no authorization to migrate or delete the historical board's records.

CRM and Projects require product packaging changes; neither has been replaced
with another mutable checkout symlink in this patch.

## Session memory and execution

- **drain — extract the tested memory engine before retiring the remaining
  directory.** This is not just a slash prompt: its 76 KB engine implements
  identity, trace/provenance validation, journal writes, harvest and unresolved
  exports. Flake checks and evaluator probes import it. The engine understands
  Claude Code/Codex traces, not DSH sessions. DSH mnemon currently disables
  automatic capture, idle review and skill evolution, so it is not evidence
  of a working automatic successor. Its guide's 45-minute cold-start story also
  conflicts with the engine's 1,200-second utility timeout and current demand
  loading. Move code and explicit operations to the memory owner, preserve
  historical codecs, local-model boundaries, journal/harvest and exact lineage.
- **spec — move useful contracts and proof checking into orchestration.**
  The global procedure mixes authoring, ratification, task derivation, execution
  and merge policy. Its example still selects retired Halogen while the actual
  Substrate workflow rejects that route. Its template fixes one old Cloudflare
  toolchain for all projects; its blanket merge ban lags explicitly authorized
  workflow merging. Preserve the checker, fixtures, observable claims, source
  rulings and proof receipts. Neither that older workflow nor the skill proves
  a complete DSH successor. Move those resources before retiring the directory.

## Authoring and formatting

- **effective-html — portable optional authoring package.** Keep the licensed
  example corpus and report/prototype workflow. It does not need fleet hosts.
  Remove deck advertising now; relocating the same long global recipe would
  not resolve its overlap with other design guides.
- **html — package with effective-html.** It is the general report/explainer
  mode, not a separate infrastructure utility. Deck advertising is removed.
- **html-plan — package with effective-html.** Preserve pragmatic organization
  and fidelity to Tom's wording; register it explicitly if independently exposed.
- **html-diagram — package with effective-html.** Preserve its SVG-first
  architecture examples; a PPTX generator is not its replacement.
- **diagram-design — portable optional design resources.** Keep grammars,
  templates and useful examples. Before migration, remove the stale first-run
  gate: it detects rust `#b5523a` as the default while the shipped guide uses
  orange `#eb6c36`, mistaking shipped content for customization. Global bans on
  glow/JetBrains Mono conflict with its locally grafted dark architecture
  recipe, and external Google Fonts conflict with its self-contained promise.
  Project design tokens should govern actual output.
- **uncodixfy — optional project design reference, not a global frontend
  governor.** It has no runtime code. Its blanket bans conflict with diagram
  references and even with its own permitted headings and blue palettes.
  Keep useful examples subordinate to the project's actual design system.
- **md-artifact — migrate beside artifact tooling.** Preserve deterministic GFM
  rendering, Pandoc flags, template/CSS and vendored Mermaid until packaged by
  its successor. Browser-seat viewing is a fleet adapter. This patch corrects
  private publishing guidance; removal of its skill alone would not replace the
  renderer. Existing local viewing and explicit publication remain distinct.
- **resume-builder — package as a personal formatting tool.** Preserve its
  constrained grammar, exact resume layout and ATS reading order. The working
  CLI needs Python, Chrome and font assets; its sibling-font lookup or explicit
  `RESUME_PDF_FONTS` must survive extraction. Neither generic DSH Office support
  nor deleting the prompt provides that exact formatter.

## Optional upstream GPU tools

- **rocm-doctor — optional upstream support capability.** The `rocm` CLI already
  owns probing/fixes; personal dotfiles need not own its catalog. Generic curl
  installers, group/driver fixes and Linux/Windows assumptions need a NixOS
  fleet adapter. The CLI is absent from NAS PATH; compute availability was not
  inferred. Preserve diagnostic receipts and upstream routing.
- **magpie-kernel-evaluator — optional performance package.** Preserve pinned
  workload/model/config provenance, correctness gates, clean baselines and
  end-to-end verification. Replace the local pip-install recipe with the
  declared compute environment when used here.
- **tracelens-analysis-orchestrator — package beside performance tools.**
  Preserve shared trace preparation, specialist analysis, validated findings
  and source-linked reports. Its unconditional questionnaire, direct “local”
  execution, raw SSH templates and harness-specific Task paths need adapting
  to discoverable inputs, `fleet-exec`, `runtime-test` and the actual executor.
  Do not copy those procedures wholesale into a DSH plugin.

All three record upstream ownership in `VENDORED.md` or `.federated.json`;
Magpie and TraceLens also record exact source commits. ROCm Doctor's vendoring
note does not establish an exact commit pin.
No functioning DSH replacement for them was established in this review.

## Vendor and connected skills

The ignored `synced` tree is written by Claude, not tracked source. There are
two account buckets, each with these 13 skill entry points:

- `built-in-browser`, `chrome-browser`, `computer-use`: Claude-specific tool
  adapters; keep with the provider exposing those tools.
- `docs`, `docx`, `xlsx`, `pdf`, `pptx`: vendor document capabilities. DSH's
  Office resource is a different implementation; its `office-pptx` is 4,415
  bytes versus the synced `pptx`'s 29,203. Preserve vendor downloads and use the
  selected provider's implementation, rather than treating every document
  editor as a bespoke deck-generation skill.
- `google-workspace`: provider-specific connector instructions.
- `deep-research`, `morning`, `import-memory`, `skill-creator`: vendor workflows,
  not NixOS fleet utility definitions. Expose deliberately with their owning
  tools/profile and avoid duplicate descriptions winning by discovery order.

All 13 corresponding `SKILL.md` pairs were byte-identical at review time. That
does not prove their complete resource trees or account state are interchangeable.
No producer-managed files were removed. The narrow `.agents/synced` omission
prevents these Claude downloads from becoming duplicate Codex instructions.

The 14 Cloudflare links under `~/.codex/skills` already point to an external
marketplace. Codex system skills and connected plugin skills are likewise
provider-owned, not custom skill definitions in dotfiles. Their availability
does not justify duplicating them or migrating their content into DSH by hand.
Name collisions, such as vendor and system `skill-creator`, should be resolved
through deliberate profile selection when those providers are configured.

## Earlier intent and next migration order

Primary human messages recovered from `~/notes/archives/ai-chats/transcripts`
support this direction over time:

- October 13, Claude `6479261c-6e12-4152-b591-70c0b9148240`, line 91: manual,
  outdated skills had become vestigial; the system should handle complexity
  from ordinary language and preserve context for later agents.
- October 22, Claude `bb6fb08a-f4d4-4ebb-addd-e7480f97c803`, line 1016:
  DSH plugins should supersede scattered skills and per-repository procedures;
  describe functionality and reuse plugins, then package with Nix.
- October 25, Claude `d629c78a-d371-43df-881c-c98d7e9c8e18`, line 5:
  move the suite into DSH with a common human/model access surface.
- November 1, Codex `01a1931a-6ca9-7fe3-a567-f1b42ba6e26d`, line 2945:
  selective Claude registration was called a feature, not a bug.
- November 1, Codex `01a195ee-9fb2-7252-9c8a-cb8d551d0849`, line 8:
  the skill review should be thoughtful, not a one-shot purge.
- November 1, #674: retire handoff/pickup and keep bespoke utilities such as
  print as the exception to no skills in dotfiles.

The artifact lineage, exact archive filenames and SSL incidents are retained
in T-126. Earlier acceptance assumptions by agents are not promoted into Tom's
requirements. In particular, old choices to package artifacts in dotfiles or
use one private/public hostname are superseded by his current instructions.

The recommended sequence after this patch is product distribution for CRM and
Projects; artifact renderer/resume packaging; optional authoring resources;
memory/contract extraction with real DSH operations; then upstream GPU packages
and fleet runbook demotion. Presentation, Superagent and Domicile availability
must be checked against the active profiles as their integrations are built.
These recommendations remain work in T-100, not claims of completed migration.
