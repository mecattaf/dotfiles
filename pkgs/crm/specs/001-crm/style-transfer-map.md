# crm — style-transfer map

Every implementation issue must cite its reference precedent(s) from this map
and read them before writing code. The references are corpora to transfer
implementation *style* from — each entry says what to imitate and what to
deliberately invert. Reference clones:

- `crm-cli` = `/home/tom/Downloads/crm-cli` (jdanielnd, Go + cobra +
  modernc.org/sqlite — our exact stack)
- `crm.cli` = `/home/tom/Downloads/crm.cli` (dzhng, Bun/TS — strongest product
  design and agent-skill genre)
- `sodimo-crm` = `~/mecattaf/sodimo-crm` (Twenty-inspired Worker+D1 —
  deals/pipelines/stages shape)

`dotfiles/crm/TRANSFER-BRIEF.md` is the deep-read behind this map; consult it
for full mechanics and line-level citations.

## CLI skeleton, errors, exit codes

Read: `crm-cli/cmd/crm/main.go`, `crm-cli/internal/cli/root.go`,
`crm-cli/internal/model/errors.go` + `errors_test.go`.
Imitate: `os.Exit(run())` single exit site; `signal.NotifyContext`;
`SilenceUsage/SilenceErrors`; `ExitError` sentinel wrapper + one `ExitCode`
switch on `errors.Is`; the 25-line table-driven exit-code test.
Invert: their exit-code table (ours is 1/2/3/4); their `ErrDatabase`→10 that
no code path ever produced; their auto-create of the DB at any path (`init`
is our only creator).

## db open, pragmas, migrations

Read: `crm-cli/internal/db/db.go`, `crm-cli/internal/db/migrations/001_initial.sql`.
Imitate: single `Open` funnel (open → `SetMaxOpenConns(1)` → pragma loop →
migrate, close on failure); embedded migrations on `PRAGMA user_version`,
each file executed as one whole string inside one transaction; the
Sprintf-not-placeholder PRAGMA comment.
Note: our migration files have no `-- up`/`-- down` section markers (the
reference's `-- up` convention is not transferred) — never scan for sections,
never split on semicolons, and there is no rollback path.
Invert: WAL (ours is DELETE, asserted at open + doctor); slice-index-derived
versions (derive from filename prefix); no pre-migration backup (copy the
file first). Anti-pattern for the runner: `crm.cli/src/db.ts` splits schema
SQL on `;` — would shred our triggers.

## Repository layer, scanning, batch child loading

Read: `crm-cli/internal/db/repo/person.go`, `crm-cli/internal/db/repo/interaction.go`.
Imitate: repo structs + package-level column-list const + one polymorphic
`scanX(row)` for QueryRow and Rows; transactions with `defer tx.Rollback()`
and post-commit re-read outside the tx; `loadParticipants`-style batch child
loading after `rows.Close()` (the in-code deadlock comment is load-bearing).
Invert: `strings.ReplaceAll` column-list surgery for joins (alias the table
unconditionally); their dual-INSERT for optional values (one statement,
defaults computed in Go); their `checkDuplicate` pre-scan dedup (ours is
UNIQUE-constraint-first, violation translated).

## Reference resolution

Read: `crm.cli/src/resolve.ts` (ladder-as-ordered-function, per-form rungs);
`crm-cli/internal/cli/context.go` as the anti-pattern.
Imitate: one shared resolver package called from every ref site; discrete
rungs tried in order; digit/handle extraction before matching.
Invert: crm.cli's first-row-wins on ambiguity (ours: `LIMIT 2` per rung,
`AmbiguousError` with pasteable candidates, exit 3); crm-cli's
resolution-in-one-command-only with `Int64Var` ids everywhere else (every ref
flag is a string, resolver applied universally).

## Normalization

Read: `crm.cli/src/normalize.ts`, `crm.cli/spec/normalization.md`.
Imitate: canonical-on-write doctrine and its failure-mode enumeration; the
Strict/Permissive/Extract three-tier split as paired
`NormalizeX() (string, error)` / `TryNormalizeX() (string, bool)` functions;
LinkedIn handle extraction regex; website canonicalization.
Invert: nothing major — this is crm.cli's best material; skip their E.164
phone strictness (phone is Permissive for us) and their four-platform social
matrix (we store linkedin only).

## FTS5 search and `find`

Read: `crm-cli/internal/db/migrations/001_initial.sql` (FTS tables +
triggers), `crm-cli/internal/db/repo/person.go` `Search`,
`crm-cli/internal/cli/search.go` (flat `{type,id,name,detail}` projection).
Imitate: external-content FTS + AFTER-trigger form verbatim (our schema.sql
already matches); the uniform cross-entity result row.
Invert: `id IN (subquery)` rank discarding (bm25 join, ascending rank);
whole-query phrase quoting (per-token escaping, last-token prefix star);
fixed entity-order concatenation (global rank merge); untested UPDATE trigger
(add the old-term-no-longer-matches test). For org-name reachability of
contacts, invert `crm.cli/src/lib/helpers.ts` denormalized index-content:
query-time union instead. Anti-pattern: `crm.cli/src/commands/search.ts`
`find` — "semantic" search that is a word-overlap counter; every search claim
needs a distinguishing test.

## Output formatting

Read: `crm-cli/internal/format/format.go`, `crm.cli/src/format.ts`.
Imitate: TTY-vs-pipe detection; `ColumnDef` declarative projection; `ids`
quiet mode handled once in the formatter; crm.cli's all-empty column elision.
Invert: unknown format silently degrading to table (hard usage error); nil
slice marshaling to `null` (normalize to `[]`, byte-asserted); sparse JSON
maps (stable keys, explicit null, derived `ref`); mutations printing nothing
(every mutation echoes the record; lifecycle verbs included); prettiness
derived from `os.Stdout` inside a writer-parameterized function; go-pretty
dependency (hand-rolled tabwriter, rune-count widths). Prefixed refs:
`crm.cli/src/format.ts` ids mode + `spec/data-model.md` prefix doctrine.

## `context` briefing

Read: `crm-cli/internal/cli/context.go` (assembler + renderer),
`crm.cli/src/fuse-json.ts` (self-contained capped JSON shape).
Imitate: one `Briefing` assembler struct with two renderers; capped inline
timeline; profile-first ordering.
Invert: crm-cli's separately-written CLI and MCP context builders that
diverged (one assembler, ever); their name-resolution-only-here (resolver is
shared); render transcript paths prominently (neither reference had files of
record).

## status / stale

Read: `crm-cli/internal/cli/status.go`, `crm.cli/src/reports.ts` (stale
semantics: zero-activity-ever is always stale).
Imitate: cheap COALESCE'd counts; resolved-db-path line; the
LEFT-JOIN-GROUP-BY-HAVING stale shape that keeps never-contacted rows.
Invert: raw SQL in the command body (counts go through repo functions);
implicit never-contacted ordering (explicit direction flag). Do NOT transfer
crm.cli's report family (conversion/velocity/forecast) — out of surface.

## pipelines, stages, deals, stage_moves, rot

Read: `sodimo-crm/src/server/db/schema.ts` (stages.rot_days:71,
deals.stage_changed_at:150, status/lost_reason shape),
`sodimo-crm/src/server/services/deals.ts` (`moveDeal` as the single
transition path), `sodimo-crm/src/server/services/pipelines.ts` (stage CRUD +
reorder), `sodimo-crm/src/server/services/views.ts` (stale_deals/rotting
math, next-ordering).
Imitate: stage-only deal shape with `stage_changed_at`; per-stage nullable
`rot_days`; stage resolution by name within the pipeline; one move verb
updating stage + timestamp + history atomically; pipelines/stages as ordered
rows managed by verbs.
Invert: money/forecast_weight/FX columns (stage-only, no money ever);
`expected_close_date` (no due dates, deadlines, or next-action tracking
anywhere in the tool); `label` (no tags of any kind);
events-table generality (stage_moves is a real-columned deal-data table, not
an audit log); owner/actor columns (single-user). Anti-pattern:
`crm.cli/src/commands/deal.ts` `move` encoding transitions as
`"from X to Y | note"` prose parsed back by regex in six files — the exact
disease stage_moves' real columns prevent.

## contact links

Read: `crm-cli/internal/cli/relate.go`, `crm-cli/internal/db/repo/relationship.go`.
Imitate: directed storage + both-ends read (`FindForPerson` matches either
endpoint); self-link CHECK; the alias test pattern.
Invert: unrelate-by-relationship-id (ours unrelates by contact pair
+ optional type); their fixed type enum (free-text `link_type`); no junction
visibility in context (links render in show + context).

## log / interaction creation

Read: `crm-cli/internal/cli/log.go`, `crm-cli/internal/model/types.go` (the
kind-enum slice + `ValidKind`), `crm-cli/internal/cli/task.go:91-93` (enum
feeding flag help), `crm.cli/src/commands/activity.ts:21-31` (positional
sugar, enum list in help).
Imitate: the enum-as-one-Go-slice feeding validator, error text, flag help,
and completion (plus the CHECK-drift test against `sqlite_master`);
activity.ts's positional sugar desugaring to the canonical flag form.
Invert: log.go's `Int64Var` refs (every ref flag is a string through the
shared resolver); its write-once no-edit verb (interactions are editable);
its leaked raw FK error text (translated, remedy-carrying messages, exit 4).
`--body-file`/`--transcript` get explicit existence/readability validation
neither reference performs.

## edit PATCH semantics

Read: `crm-cli/internal/cli/person.go` (pointer inputs +
`cmd.Flags().Changed()`), `crm-cli/internal/db/repo/person.go` `Update`.
Imitate: three-state patch; dynamic SET clause; `RowsAffected` + re-read;
no-op short-circuit.
Invert: the twenty-line per-field if-blocks duplicated across five files (one
helper/table); `updated_at` fabricated on no-op edits; `name_norm` not
recomputed on name patch (recompute in the same UPDATE). Idempotent
add-to-set semantics: `crm.cli/src/commands/contact.ts` merge-friendly edits
+ `crm.cli/test/scenarios/messy-input.test.ts` — but invert the add-to-set
targets themselves (`--add-tag`/`--rm-tag` and the `emails`/`phones`
arrays): there are no tags and exactly one email / one phone / one linkedin
here. Transfer only the idempotent set-membership *shape*; its sole
application is `interaction edit --add-with`/`--rm-with`.

## delete confirmation, archive lifecycle

Read: `crm.cli/src/lib/helpers.ts` (confirm: `/dev/tty` prompt,
non-interactive refusal), `crm-cli/internal/db/repo/task.go` `Complete`
(RowsAffected→re-query archived-vs-missing distinction).
Imitate: both mechanisms exactly; prompt names the resolved record.
Invert: both references' soft-delete-with-no-restore (ours has `unarchive` +
honest `ls --all`); crm.cli's cascade deletes on rm (FK-blocked hard delete
is a deliberate, well-worded outcome).

## import / export (flat)

Read: `crm.cli/src/commands/importexport.ts` (both halves: triad flags,
summary line, email-match skip/update; and the CSV/JSON export writer),
`crm.cli/test/import-export.test.ts` (the roundtrip assertions: CSV escaping,
separator survival, embedded newlines, NULL vs empty, unicode),
`sodimo-crm/PIPEDRIVE-MIGRATION.md` (dependency-safe order, per-entity
identity rules, dropped-field logging, human-review list).
Imitate: `--dry-run/--skip-errors/--update` semantics; counted stderr
summary; search-before-create idempotence with run-twice-all-skipped as the
acceptance test; orgs-before-contacts order; reject file as a reviewable
worklist; the CSV writer discipline the roundtrip test enforces.
Invert: silent dropping of malformed values (reject file + counts, never
silent); auto-create-on-link default (gated behind `--create-missing`,
stamped and announced); missing provenance (mandatory `--source`, ` || `
append on `--update`).

## dupes and merge

Read: `crm.cli/src/commands/dupes.ts` (two-metric scoring, named reasons,
free-mail exclusion), `crm.cli/src/commands/contact.ts` merge +
`crm.cli/spec/data-model.md` (merge doctrine).
Imitate: `max(Levenshtein, Dice)` on runes; weighted named reasons capped at
1.0; advisory-only dupes.
Invert: crm.cli's transactionless merge (its crash-mid-merge half-destroyed
loser is the vivid failure — ours is one transaction, uniques-nulled-first,
provenance concatenated, junction `INSERT OR IGNORE`, loser soft-archived);
custom-fields winner-takes-collisions (we have no custom fields).

## export tree

Read: `crm.cli/src/export-fs.ts` (static export path only),
`crm.cli/src/fuse-json.ts` (slug + llm.txt genre).
Imitate: no-daemon static tree; date-first slugify; orientation doc at the
root; self-contained per-entity files.
Invert: JSON entity files (ours are markdown + YAML frontmatter, timeline as
prose); `_by-*` file-copy index dirs (one file per entity, ever — git diffs
are the point); everything FUSE/NFS/daemon (2,600-line graveyard; the 327-line
static export was the product).

## post-write hook

Read: `crm.cli/src/hooks.ts`.
Imitate: config-declared shell command, entity JSON on stdin, 30s timeout,
post-hook exit ignored.
Invert: the 20-hook-point matrix (one `post-write` event); pre-hook vetoes
(none); hooks bypassed by a second surface (there is no second surface).

## doctor

Read: `crm.cli/src/commands/search.ts:146-178` (the status/rebuild verb pair
for FTS: `integrity-check` + command-form `rebuild`).
Imitate: the paired report-verb/repair-flag form; per-table FTS
`integrity-check` and `rebuild` in a transaction.
Invert: the reference's silent tolerance of index desync (ours reports drift
and exits non-zero); add the checks it has no analogue for — journal-mode
assertion, `PRAGMA integrity_check`/`foreign_key_check`, transcript-path
existence, stage/pipeline consistency, `user_version` report.

## skill, AGENTS.md, help text

Read: `crm-cli/AGENT.md` (situation-shaped instructions, dossier discipline,
search-before-create), `crm.cli/skills/SKILL.md` (structure, one runnable
example per verb, "Tips for AI Agents" closer).
Imitate: situation-indexed numbered call sequences; append-never-overwrite
dossier rule with a worked example; the tips block; frontmatter triggers in
`description`.
Invert: crm.cli's mount-first tips (CLI-only here); doc claims beyond shipped
behavior (both references drifted — every skill claim gets a distinguishing
test, skill edits ship in the same commit as the verb).

## testing

Read: `crm-cli/internal/cli/person_test.go` (TestMain builds the real binary;
`crm(t, ...)` helper), `crm-cli/internal/model/errors_test.go` (table-driven
exit map), `crm.cli/test/helpers.ts` (`OK()/Fail()/JSON()/WithEnv()` runner
ergonomics), `crm.cli/test/db-busy-timeout.test.ts` (calibrated concurrent
writers), `crm.cli/test/import-export.test.ts` (the export→import roundtrip
genre), `crm.cli/test/scenarios/` — especially `messy-input.test.ts` and
`ai-agent.test.ts` (persona genre).
Imitate: all of it — this is the highest-value material in either repo. Add
the post-run no-`-wal`/`-shm` stat assertion to the concurrency test.
Invert: crm-cli's package-level flag globals that blocked `t.Parallel()`
(flags in structs captured by closures); tests that unmarshal into slices and
hide null-vs-`[]` (assert bytes); assertions a stub could pass (see
constitution: distinguishing assertions).

## packaging

Read: `crm-cli/.goreleaser.yml` (only as evidence `CGO_ENABLED=0` cross-builds
cleanly) and `cmd/crm/main.go` version wiring as the anti-pattern.
Imitate: `-s -w` ldflags, single static binary.
Invert: the dual version variable that made every release report `dev` (one
variable, one `-X` target, value-asserted test); all
GoReleaser/Homebrew/changelog machinery (none — `nix shell nixpkgs#go`
locally, `buildGoModule` in dotfiles).
