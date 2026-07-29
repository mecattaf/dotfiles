# CRM build knowledge — consolidated 2026-07-29

Everything a fresh agent needs to implement the personal git-backed CRM.
Companion files: `SPEC.md` (frozen v0.1 surface), `schema.sql` (frozen DDL).

## Decisions of record (Tom-ratified)

- **Tool in dotfiles, data in notes.** CLI source lives here
  (`dotfiles/crm/`), the database lives at
  `~/mecattaf/notes/crm/crm.db`. `mecattaf/notes` is private and "will remain
  so forever" — **no git-crypt, no encryption** (ruled 2026-07-29; supersedes
  the earlier git-crypt-in-public-dotfiles plan).
- **Go + `modernc.org/sqlite`** (cgo-free static binary, `buildGoModule`-clean
  on NixOS). Rust and Bun were ruled out in July 2026.
- **No bespoke repo, no MCP server.** Seam = CLI + a `/crm` skill documenting
  it (progressive disclosure). jdanielnd's half-broken MCP validated CLI-only.
- **Build-as-we-go**: usable from day one. First real lead is "Nick" — one
  past conversation on paper to transcribe as the first call note, plus a live
  call on 2026-07-29 afternoon to test the transcription protocol end-to-end.
- Deals/tasks/pipeline deliberately deferred to v2 (reachability-first).

## Lineage (the three reference repos in ~/mecattaf/)

- `~/mecattaf/crm` ≡ `~/mecattaf/sodimo-crm` — byte-identical checkouts of one
  project (github.com/mecattaf/crm and github.com/sodimo/crm). The
  Worker+D1+SPA app shape is the over-built demo Tom dropped; its
  **Twenty-inspired schema is the reference** (organizations/contacts/deals/
  activities/notes/events/pipelines/stages). Its docs worth reading:
  `SPEC.md`, `EXTENDING.md`, `PIPEDRIVE-MIGRATION.md` (idempotent
  search-before-create import playbook — reuse for our import).
  Design rules to keep: consolidated verbs not per-entity CRUD; accept
  human-readable names everywhere, resolve internally; soft archive default +
  `--confirm` delete never batched; every mutation returns the full record;
  timeline = merged-at-read union of interaction sources.
- `~/mecattaf/investor-crm` — the dataset: `organizations.csv` (1,135 rows) +
  `contacts.csv` (1,812 rows) masters plus filtered views, agent-extracted,
  "not yet loaded into a database". Contributes the provenance model:
  `provenance_sources` (` || `-joined repo-relative sources),
  `provenance_details`, `relationship_hint` as first-class columns. Known
  caveats: latin-1→GBK encoding corruption from the Twenty export (lossy),
  ~375 `category: other` non-investor orgs kept for provenance,
  `dedup-review.csv` holds 22 parked human merge calls.

## Reference-CLI audit lessons (jdanielnd/crm-cli + dzhng/crm.cli, July 2026)

STEAL: cli→repo→format layering; sentinel-error→exit-code mapping; FTS5
external-content + AFTER triggers verbatim; `context <ref>` one-call briefing;
resolve-by-anything (id/email/name); stdout=data stderr=messages; tuned
`busy_timeout` + a concurrent-writer test.
AVOID: docs drifting from code; redundant company text next to `org_id` FK;
missing transactions on multi-statement writes; ignoring bm25 rank; dedup
without DB UNIQUE; ID-only ergonomics; FUSE mounts; second incomplete agent
surface.
CRITICAL: **`journal_mode=DELETE`, never WAL** — WAL sidecars + git/sync
backup is the known corruption path.

## Data layout in notes (private repo)

- `~/mecattaf/notes/crm/crm.db` — database of record (`$CRM_DB` override).
- `~/mecattaf/notes/crm/transcripts/YYYY/` — call transcripts / long notes as
  markdown files; the interactions row stores the repo-relative path. Files
  are evidence of record; db summaries never replace them.
- notes `CLAUDE.md` must be amended when this lands: new top-level `crm/`
  lane + partial reversal of the C8 externalization ruling
  (investor-crm CSVs become the one-time import source, then freeze as
  provenance archive).

## Transcription integration

The [model roster](../../docs/local-ai/model-roster.md) and
[deployment decisions](../../docs/local-ai/deployment-decisions-2026-07-29.md)
are the prose sources of truth for local model identity, provenance, placement,
and runtime state. Check them at implementation time instead of copying those
facts into this CRM document. In particular, similarly named VibeVoice ASR and
TTS appliances are distinct; a TTS-only toolbox is not an ASR runtime.

This document owns only the CRM-side contract:

- Input: a recorded call as WAV, up to roughly 60 minutes.
- Output: a timestamped, speaker-diarized speech-to-text transcript saved as
  markdown beneath `notes/crm/transcripts/YYYY/`.
- Registration: `crm log --kind call --with <contact> --transcript <path>`,
  with an agent-written summary.
- Execution may be batch rather than live, but the complete WAV-to-transcript
  path must be tested before relying on it for a call.

## Immediate next actions

1. Implement the CLI per `SPEC.md`/`schema.sql` (v0.1 verbs; tests including
   the concurrent-writer case; `nix shell nixpkgs#go` — no go on PATH;
   install to `~/.local/bin/crm` now, `default.nix` packaging later).
2. `crm init`; create `notes/crm/` + transcripts dir; amend notes CLAUDE.md.
3. Enter Nick: org (if any), contact, first interaction from Tom's paper
   notes (Tom supplies photo or typed text — not yet provided).
4. Consult the canonical local-AI docs, wire the selected ASR batch runner,
   and test WAV → diarized transcript before relying on it for a call.
5. v0.2: `import` from investor-crm CSVs (idempotent, search-before-create,
   provenance mandatory), `dupes`/`merge`, `/crm` skill, nix packaging.

## Working-style constraints (Tom, this session)

- Local state in dotfiles is the source of truth — check it before any web
  research; do not spawn research agents for things already pinned locally.
- Strategy conversations get direct recommendations in prose; implementation
  only starts when Tom green-lights, and stays within the scoped step.
