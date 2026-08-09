# Implementation Plan: crm — personal git-backed CRM

**Branch**: `001-crm` | **Date**: 2026-07-31 | **Spec**: `specs/001-crm/spec.md`

**Input**: `specs/001-crm/spec.md`, `specs/001-crm/data-model.sql`,
`specs/001-crm/style-transfer-map.md`, `.specify/memory/constitution.md`

## Summary

Build `crm`: a single-user CRM as one static Go binary (cobra +
`modernc.org/sqlite`, `CGO_ENABLED=0`), serving Tom at a shell and agents via
the `/crm` skill over the same CLI. One SQLite file in the notes repo,
DELETE-journaled, opened per invocation through a single funnel that applies
pragmas and embedded migrations before any query. All entity refs pass through
one shared resolver ladder; all data leaves through one output formatter
(stdout = data, stderr = messages, exit codes 0/1/2/3/4). The plan decomposes
the spec into 19 strictly ordered vertical increments (`tasks.md`), each
shippable and gate-clean on its own, with `import` deliberately last so the
tool is fully proven before any real data loads.

## Technical Context

**Language/Version**: Go (latest stable via `nix shell nixpkgs#go`; no Go on PATH)

**Primary Dependencies**: `github.com/spf13/cobra`, `modernc.org/sqlite`
(driver name `"sqlite"`, pure Go). No other runtime dependencies.

**Storage**: one SQLite file (`--db` > `$CRM_DB` > `~/mecattaf/notes/crm/crm.db`),
`journal_mode=DELETE`, `SetMaxOpenConns(1)`, per-invocation open/close.
Schema is the single embedded migration `internal/db/migrations/001_initial.sql`,
byte-identical in content to `specs/001-crm/data-model.sql`.

**Testing**: `go test` — integration harness exec-ing the real built binary
(primary layer), shared `dbtest` in-memory fixture package (unit layer),
persona scenario files, one cross-process concurrent-writer test. Four gates
run on *every* task from T01 onward (constitution: Testing doctrine):
`go build ./...`, `go vet ./...`, `go test -race ./...`, and golangci-lint
(`errcheck, staticcheck, unused, ineffassign, gocritic, revive`). The race
detector is cgo-backed, so the race gate runs under
`nix shell nixpkgs#go nixpkgs#gcc`; `CGO_ENABLED=0` constrains the shipped
binary, not the test run.

**Target Platform**: Linux (Tom's fleet); static binary, cross-compiles freely
because CGO is off.

**Project Type**: single CLI binary. No server, no API, no TUI, no web UI.

**Performance Goals**: interactive-path latency — every verb is open → work →
close on a small local file; no LLM calls, no network, no blocking external
processes in any verb path (post-write hook is fire-and-forget, 30s timeout).

**Constraints**: `CGO_ENABLED=0`; binary never touches git; only `init`
creates anything; one `os.Exit` site; database file never gains `-wal`/`-shm`
sidecars.

**Scale/Scope**: single user, thousands of rows, one database file committed
to a git repo. Correctness and composability over throughput.

## Constitution Check

*GATE: re-checked against `.specify/memory/constitution.md` after design.*

| Constitution rule | Where the plan satisfies it |
|---|---|
| SQLite discipline (DELETE journal, pragma funnel, MaxOpenConns(1), per-invocation lifecycle) | `internal/db` open funnel (below); doctor journal assertion; concurrent-writer test with no-sidecar stat |
| Migrations (embed, `user_version`, one tx, no semicolon splitting, pre-copy) | migration runner design (below); T01 |
| Data hygiene (Go-generated timestamps, canonical-on-write, three tiers, UNIQUE-first dedup) | `internal/model` normalize functions; repos; T02a–T03 |
| Writes and errors (tx + `defer Rollback`, resolve-before-tx, sentinel errors, one ExitCode switch, one os.Exit) | `internal/model` errors + `cmd/crm` (below); T01 pins the map |
| Enum single-source + CHECK-drift test | `internal/model` slices; drift tests in T04 (kind) and T07 (status) |
| Search (per-token escaping, bm25 join, normalized global merge) | `internal/db` search repo; T05a distinguishing tests |
| Output (formatter-only stdout, TTY/pipe, `[]` bytes, mutation echo) | `internal/format` (below); stream assertions in every integration test |
| Testing doctrine (real-binary harness, dbtest, personas-first, calibrated concurrency, distinguishing assertions, roundtrip) | testing architecture (below); tests live inside every task |
| Gates (`go vet`, `go test -race`, golangci-lint) | the four universal gates in `tasks.md`, required from T01 — never deferred |
| Packaging (buildGoModule, one ldflags version variable, no release ceremony) | T01 version wiring; T15 derivation |

No violations; the Complexity Tracking table is empty.

## Project Structure

### Documentation (this feature)

```text
specs/001-crm/
├── spec.md              # complete product specification (input)
├── data-model.sql       # initial migration DDL, source of truth (input)
├── style-transfer-map.md# per-capability reference corpora (input)
├── plan.md              # this file
└── tasks.md             # 19-task issue sequence
```

### Source Code (repository root)

```text
cmd/crm/
└── main.go              # version var (ldflags -X target), signal.NotifyContext,
                         # os.Exit(run()) — the ONLY os.Exit site

internal/cli/            # cobra commands; one file per noun/verb family
├── root.go              # root cmd: SilenceUsage/SilenceErrors, --db/--format
│                        # persistent flags, db-path resolution, alias wiring
├── init.go              # the only creator
├── org.go  contact.go  interaction.go  log.go
├── pipeline.go  stage.go  deal.go
├── context.go  find.go  status.go  stale.go
├── relate.go  lifecycle.go (archive/unarchive/delete)  show.go (polymorphic)
├── importcmd.go  export.go  dupes.go  merge.go  doctor.go
├── hook.go              # post-write hook dispatch
└── *_test.go            # integration harness + per-verb + scenario_* persona tests

internal/db/
├── db.go                # Open funnel: open → SetMaxOpenConns(1) → pragmas → migrate
├── migrate.go           # embedded runner keyed on PRAGMA user_version
├── migrations/001_initial.sql   # go:embed; content of specs/001-crm/data-model.sql
├── repo/                # one file per entity: column consts, scanX, tx writes,
│                        # batch child loading, search (FTS)
└── dbtest/              # shared unit fixture: Open(":memory:") + real migrations

internal/model/          # types, enum slices, normalize (3 tiers),
│                        # sentinel errors, ExitError, ExitCode switch
internal/format/         # the only package that writes stdout:
│                        # table/json/csv/ids, TTY detection, ColumnDef projection
internal/resolve/        # the shared ref-resolution ladder

skills/crm/SKILL.md      # the /crm skill + sibling flag-reference file (T11)
nix/package.nix, flake.nix  # buildGoModule derivation (T15; graduation prep only)
```

**Structure Decision**: single-project CLI layout exactly as AGENTS.md
prescribes (`cmd/crm`, `internal/cli`, `internal/db`, `internal/model`,
`internal/format`, `internal/resolve`). Tests colocate with `internal/cli`
because the harness execs the built binary — there is no separate `tests/`
tree to keep in sync.

## Module Design

### cmd/crm — entry and exit

`main.go` declares the one version variable (`-X` ldflags target; nothing else
assigns to it), installs `signal.NotifyContext`, and calls `os.Exit(run())`.
`run()` executes the root command and maps any returned error through
`model.ExitCode(err)` — the single `errors.Is` switch pinned by a table-driven
test. Cobra runs with `SilenceUsage: true, SilenceErrors: true`; the one error
line `crm: error: <msg>` goes to stderr from `run()`, never from command
bodies.

### internal/db — the open funnel and embedded migrations

`db.Open(path)` is the only way to obtain a handle, and it either returns a
fully prepared connection or closes and returns an error — no partially
configured handle can escape:

1. `sql.Open("sqlite", path)` (modernc, no CGO).
2. `SetMaxOpenConns(1)` — immediately, before any statement.
3. Pragma loop, in order: `journal_mode=DELETE`, `busy_timeout=5000`,
   `foreign_keys=ON`, `synchronous=FULL`, `temp_store=MEMORY`,
   `cache_size=-64000`. Every pragma error is wrapped with the pragma's name.
   The journal mode is *read back*: files must report `delete`; in-memory
   databases (`:memory:` / `mode=memory` URIs — the dbtest path) report
   `memory` and the funnel accepts that; `doctor` (which only ever sees a real
   file) asserts `delete` strictly.
4. `migrate(db)` — see below.
5. Any failure at any step: close the handle, return the wrapped error.

Existence policy sits above the funnel: every verb except `init` stats the
resolved path first and fails with exit 2
(`crm: error: no database at <path> (run 'crm init')`); `init` is the only
code path allowed to create the file, the `notes/crm/` layout,
`transcripts/YYYY/`, and the orientation README, and it is idempotent.

**Path arguments and the transcript base.** The *transcript base* is the
directory containing the resolved db path — `~/mecattaf/notes/crm/` in
production, the harness temp dir in tests. It is derived in exactly one place,
beside db-path resolution, and every path-handling site takes it as an
argument. `--transcript` is resolved against it, validated to exist before the
write, and stored relative to it (spec §1: the row stores the notes-repo-
relative path); an absolute path inside the base is relativized, one outside it
is exit 1; `doctor` resolves stored paths against the same base, so `log` and
`doctor` cannot disagree. `crm export tree` with no argument defaults to
`tree/` under the same base (spec §5). A path argument naming a file that does
not exist is exit 2 — "not found" with a remedy, per spec §3's non-exhaustive
gloss — for `--transcript`, `--body-file <path>`, and `import <file.csv>`
alike. `--body-file` differs in one respect: it is an ordinary path resolved
against cwd and only read (`-` reads stdin); nothing about it is stored.

Migration mechanics (`migrate.go`):

- `//go:embed migrations/*.sql`; ordinal parsed from the `001_` filename
  prefix, never from slice index; files sorted by ordinal. The runner takes
  the migration set as an `fs.FS` parameter (production passes the embedded
  FS) so a unit test can drive it with a multi-migration fixture — the only
  way to test the pre-migration copy while the shipped set has one file.
- Current version read from `PRAGMA user_version`; only higher-ordinal files
  apply.
- Before applying a migration to a file-backed db that already carries
  `user_version > 0`, copy the `.db` file aside
  (`crm.db.pre-migrate-<ver>` in the same directory). A fresh db at version 0
  has nothing to preserve, so `init` leaves no copy behind — asserted in T01.
- Each migration executes as **one string** (never split on semicolons — the
  FTS triggers contain them) inside one transaction together with its version
  bump. The bump is `fmt.Sprintf("PRAGMA user_version = %d", n)` with the
  comment explaining that placeholders are illegal in PRAGMA. A failed
  migration rolls back and leaves `user_version` untouched.

`repo/` holds per-entity repositories: package-level column-list consts, one
polymorphic `scanX` shared by `QueryRow` and `Rows`, writes in transactions
with `defer tx.Rollback()` and the post-commit re-read outside the tx, and
batch child loading (drain rows into a slice, close, one `IN (...)` query
fanned through a map) — the `SetMaxOpenConns(1)` deadlock discipline, with the
load-bearing comment and a timeout-guarded regression test.

### internal/resolve — the ref ladder

One resolver package called from every ref site; every ref flag is a string.
`resolve.Ref(db, entity, ref)` walks the spec §2 ladder — prefixed id, bare
id, exact email (contacts), exact linkedin handle, exact name/title, exact
`name_norm`, substring on `name_norm` — each rung one SQL query with
`LIMIT 2`; the first rung with exactly one hit wins; two hits anywhere is
`AmbiguousError` (exit 3) carrying pasteable candidate lines for stderr.
Rungs 1–2 reach archived rows; 3–7 are live-only. A prefixed id of the wrong
entity is `NotFoundError` (exit 2) with a clear message. Stage resolution is a
scoped variant: prefixed `s7`, else exact-then-substring `name_norm` within
one pipeline. Resolution failure on a link flag prints the exact create
command; nothing auto-creates on failure (sole exception:
`import --create-missing`). All resolution happens **before** any transaction
opens.

### internal/format — the output layer

The only package that writes stdout. A `Formatter` is constructed once per
command with the output writer and a TTY bit (derived from `os.Stdout` at the
one construction site; every rendering function is writer-parameterized).
Format selection: TTY → table, pipe → JSON, `--format` overrides from
`table|json|csv|ids` with per-verb accepted sets — an unsupported value is a
hard usage error listing that verb's set. Tables use declarative per-entity
`ColumnDef` projections, all-empty column elision, rune-count widths,
hand-rolled tabwriting. JSON: stable key set, explicit `null`, derived `ref`
field, raw stored values, pretty on TTY / compact piped, empty collections as
`[]` (byte-asserted). `ids` emits one prefixed ref per line. Every mutation
echoes the resulting record through this formatter as a one-element array;
report verbs (`find`, `context`, `status`, `stale`, `dupes`, `doctor`,
`import`) render their own documented shapes through the same package, each
fed by a single assembler so table and JSON can never diverge.

### Testing architecture

- **Integration harness (primary layer, lands in T01).** `TestMain` in
  `internal/cli` builds `./cmd/crm` once into a temp dir with
  `-ldflags "-X main.version=0.0.0-test"`, so the version test asserts that
  exact sentinel value rather than a prefix (constitution: Build and
  packaging); the helper
  `crm(t, dbPath, args...) (stdout, stderr string, code int)` execs the real
  binary with `--db` against a fresh `t.TempDir()` file database. Assertions
  are the three things a user or agent observes: bytes per stream and the
  numeric exit code (never `!= 0`).
- **dbtest (unit layer).** `internal/db/dbtest` opens `:memory:` through the
  real funnel (real migrations, `memory` journal accepted) with cleanup —
  the fixture for repo/resolver/normalize unit tests.
- **Persona scenarios first.** One `scenario_*_test.go` file per real
  workflow, written before the implementation of its task, walking a
  multi-day session against the real binary with full final-state
  verification: first lead, post-call, messy refs, deal loop, merge, agent
  session (all `--format json`), import-run-twice. Each lands inside the task
  that completes its capability.
- **Concurrent-writer test (T04).** N parallel *processes* exec `crm log`
  against one file db; all must exit 0, final count == N; N calibrated until
  it demonstrably contends (evidence recorded in a comment); afterwards
  `os.Stat` on `-wal` and `-shm` must both return NotExist.
- **Distinguishing assertions** per claimed capability (rank ordering, accent
  normalization hitting one row, idempotent import all-skipped, FTS UPDATE
  trigger old-term test, provenance append), plus the export→import roundtrip
  (T14) and every documented composition recipe executing as a test (T11).
- **Mechanical surface audits (T11).** One test walks the cobra command tree
  and fails on any leaf command with an empty `Example:` block (spec §5), any
  missing noun alias (`o`, `c`, `i`, `d`, `p`, `ls`→`list`, singular/plural),
  and any leaf verb absent from `skills/crm/SKILL.md`. This replaces prose
  criteria that no test could falsify.
- **Fixtures are committed.** Import tests run against anonymized
  `testdata/import/*.csv` mirroring the investor-crm export header shape, so
  every gate is satisfiable on a fresh checkout. The dry-run against the real
  investor CSVs is owner verification before the real load — never a gate.

### Build-phase ordering rationale

The 19 tasks in `tasks.md` are strictly dependency-ordered along one spine.
Task size is a hard constraint, not a preference: each issue must land in one
autonomous session, which is why the three cross-cutting engines, the two
flagship read verbs, and the three lifecycle subsystems are each split rather
than bundled.

1. **Foundation before verbs (T01).** The db funnel, migration runner, exit
   spine, and the harness must exist before anything observable — every later
   task is tested through them.
2. **Cross-cutting engines, one per session, then first CRUD (T02a–T03).**
   T02a lands normalization + the output layer proven on `org add|ls` (verbs
   that need no ref); T02b lands the resolver ladder proven on `org
   show|edit` PATCH; T03 adds contacts, the email/linkedin rungs, and
   polymorphic `show`. Every later verb inherits proven plumbing.
3. **Interactions, then reads over them (T04–T05b).** `log` is the hottest
   write path and the concurrency vehicle. The two flagship read verbs split:
   T05a is the FTS engine (escaping, bm25, normalized global merge), T05b is
   the `context` assembler and its two renderers — different failure modes,
   different reference corpora, one session each.
4. **Pipelines/stages before deals (T06–T07).** Deals cannot exist without a
   pipeline; stage moves and rot complete the deal loop, and T07 closes the
   `context` deals section the T05b assembler left wired-but-empty.
5. **Cross-entity enrichment (T08–T09).** Links (closing the `context` links
   section the same way), then the dashboards that summarize everything so
   far.
6. **Lifecycle, split three ways (T10a–T10c).** Archive/unarchive across six
   entities, hard `delete` with its thirteen-reference blocking matrix, and
   `doctor` with eight independent checks are three distinct subsystems; as
   one task they were both unshippable in a session and a single choke point
   for everything downstream. Split, they also unblock T12/T13 off T10a alone.
7. **Agent surface (T11).** The skill, hook, help-example audit, and recipes
   document only behavior that now exists — docs-follow-code, per
   constitution.
8. **Egress before ingress (T12–T14).** Export, then dupes/merge (data
   quality tooling), and only then `import` — the tool must be fully proven,
   with the roundtrip test closing the loop, before any real investor data
   loads. Import is the last implementation task by ruling.
9. **Graduation prep (T15).** buildGoModule derivation + install docs,
   without performing the dotfiles move.

## Complexity Tracking

No constitution deviations to justify.
