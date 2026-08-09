# crm — engineering constitution

Non-negotiables for every implementing agent. `SPEC.md` says what the tool
does; this says how it must be built. When a shortcut conflicts with a rule
here, the rule wins.

## SQLite discipline

- `journal_mode=DELETE`. For file-backed databases, assert the *actual*
  journal mode read back at open and in `doctor`; fail loudly if it is
  anything but `delete`. In-memory databases (`:memory:` or a
  `file:...mode=memory` URI — the unit-fixture path) always report `memory`;
  the funnel accepts that and asserts `delete` only for files (`doctor` only
  ever runs on a real file, so its check stays strict). The database lives in
  a git repo — one file, never `-wal`/`-shm` sidecars.
- `busy_timeout=5000`, `foreign_keys=ON`, `synchronous=FULL` (durability over
  speed — the file is committed to git), `temp_store=MEMORY`,
  `cache_size=-64000`, applied in one open funnel, each pragma error wrapped
  with the pragma's name: `db.Open(path)` does open → `SetMaxOpenConns(1)` →
  pragmas → migrate, and closes the handle on any failure. There is no way to
  obtain a connection that skipped pragmas or migrations.
- `SetMaxOpenConns(1)` means a second query while a `*sql.Rows` is open
  self-deadlocks. Never call a query inside a `rows.Next()` loop: drain into
  a slice, close, then batch-load children with one `IN (...)` query fanned
  through a map. Give the regression test a timeout — the failure mode is a
  hang, not an error.
- Per-invocation lifecycle: open inside the command, defer close, no daemon,
  no long-lived handle.

## Migrations

- Embedded (`//go:embed migrations/*.sql`), keyed on `PRAGMA user_version`,
  ordinals derived from filename prefixes (`001_`), never from slice index.
- Each migration and its version bump apply inside one transaction; a failed
  migration leaves the version untouched. `PRAGMA user_version = %d` via
  `Sprintf` — placeholders are illegal in PRAGMA; keep the comment saying so.
- Copy the `.db` file aside before applying any migration.
- Never split migration SQL on semicolons — the FTS triggers contain them.
  Execute each migration as one string.

## Data hygiene

- Timestamps generated in Go — `time.Now().UTC().Format(time.RFC3339)` for
  datetimes, `YYYY-MM-DD` for dates — bound as parameters. Never
  `datetime('now')` (wrong format, violates the GLOB CHECK). Never two SQL
  shapes for present-vs-absent optionals; compute defaults in Go, keep one
  statement.
- Canonical-on-write, never normalize-on-read: email lowercased before
  insert; `name_norm` (NFKD, strip combining marks, casefold) recomputed in
  the same UPDATE whenever a name is patched; LinkedIn handle extracted from
  URL forms on write. Three normalization tiers, chosen per field by
  false-reject vs false-accept cost: Strict (reject invalid — dates, kinds,
  email syntax), Permissive (store as-is on parse failure — website, phone,
  location), Extract (best-effort, never a gate — linkedin, name_norm).
- Dedup is enforced by DB UNIQUE constraints, never by application pre-scan
  (TOCTOU). The application's job is to catch the violation and translate it
  into a remedy-carrying message naming the owning row, exit 4. Sole
  exception: `import`'s idempotent search-before-create runs its match inside
  the file transaction, because idempotence needs identity semantics (org
  `name_norm`; contact email, `name_norm` fallback) the schema deliberately
  does not encode as UNIQUE. The contact `name_norm` fallback is heuristic
  and can double-create under concurrent imports; the concurrency test does
  not cover `import`.
- Structured facts are columns, never prose recovered by regex. Never parse
  `summary`/`body` to reconstruct a fact.

## Writes and errors

- Every multi-statement write runs in a transaction with `defer tx.Rollback()`;
  the post-commit re-read happens outside the transaction (a read on the pool
  while the tx is open deadlocks under one connection).
- Resolve and validate every ref *before* opening the transaction; FK
  constraints are defense in depth, not the front line.
- Sentinel errors wrapped once (`ExitError{Message, Err}`), classified by
  `errors.Is`, mapped in one `ExitCode` switch pinned by a table-driven test.
  Exactly one `os.Exit` site. Every exit code is provoked end-to-end by at
  least one integration test — an exit code no code path produces is a
  documentation lie.
- Cobra: `SilenceUsage: true, SilenceErrors: true`; runtime errors never dump
  usage; the error line is `crm: error: <msg>` on stderr.
- Enum values live in one Go slice feeding the validator, the error text, the
  flag help, and completion — plus a test that parses the CHECK constraint out
  of `sqlite_master` and asserts the slice matches, so DDL and code cannot
  drift.
- `edit` is true PATCH: pointer-struct inputs gated on
  `cmd.Flags().Changed()`; absent / present-empty / present-value are three
  states; a no-op edit returns the record without fabricating `updated_at`.

## Search

- FTS queries escape per token (phrase-quote each token, double inner
  quotes), star only the last token; never phrase-quote the whole query.
- Rank via a bm25 join on rowid, ascending — never `id IN (subquery)`, which
  discards rank. Cross-entity `find` is globally rank-merged on per-table
  normalized scores (raw bm25 is corpus-relative and not comparable across
  indexes — the normalization is specified in SPEC §5 find), never
  concatenated in entity order.
- Deterministic ordering everywhere, id as tiebreaker
  (`ORDER BY occurred_on DESC, id DESC`).

## Output

- Only the output formatter touches stdout. Data on stdout, everything else —
  confirmations, prompts, notices, errors — on stderr. Proven by stream
  assertions in every integration test.
- TTY/pipe detection selects table vs JSON; unknown `--format` is a hard
  usage error. Declarative per-entity column projection with all-empty column
  elision for tables; stable JSON keys with explicit null and a derived `ref`
  field. Empty collections are `[]`, asserted at the byte level.
- No silent leniency anywhere: no fallback formats, no swallowed parse
  errors, no registered-but-unread flags, no mutations that print nothing.

## Performance and paths

- No LLM calls, no network calls, no blocking external processes in any verb
  path. The post-write hook is fire-and-forget with a timeout.
- The binary never touches git and never creates the database outside `init`.

## Testing doctrine

- **Integration harness on the real binary.** `TestMain` builds `./cmd/crm`
  once into a temp dir; a helper `crm(t, dbPath, args...) (stdout, stderr,
  code)` runs it with `--db` against a fresh `t.TempDir()` database (real
  file, real journal mode — not `:memory:`). This is the primary test layer:
  it asserts the three things a user or agent observes — bytes per stream and
  exit code. Unit fixtures use one shared `dbtest` package
  (`db.Open(":memory:")` + cleanup) that runs the real migrations.
- **Concurrent-writer test, calibrated, with the no-sidecar assertion.** N
  parallel *processes* (not goroutines — `-race` sees nothing across
  processes) each exec the built binary running `crm log` against one file
  database; every one must exit 0 and the final count must equal N. Calibrate
  N until it demonstrably contends and record the evidence in a comment.
  After the run, `os.Stat(db + "-wal")` and `-shm` must both return NotExist
  — the one-line mechanical enforcement of DELETE journaling.
- **Persona scenario tests first.** One file per real workflow, written
  before the implementation, walking a multi-day session against the real
  binary and ending with full final-state verification: first lead
  (org/contact/backdated log/context); post-call (transcript file + log
  --transcript, context shows the path); messy refs (accented names resolve
  to one row, ambiguity → exit 3 with candidates, duplicate → exit 4 naming
  the owner, archive vs `ls --all`); deal loop (pipeline/stages/moves/rot,
  no-op move rejected); merge (two mutually-linked duplicates that also share
  a third contact's link merge cleanly in one transaction); agent session
  (find → context → log, all
  `--format json`); import run twice (second run 100% skipped, provenance
  appended).
- **Distinguishing assertions per claimed capability** — every claim gets an
  assertion only the real mechanism passes: ranked search → a strong match
  *outranks* a weak one, not "non-empty"; normalization → `Léger` and
  `Leger` hit the same row; idempotent import → second run all-skipped and
  count unchanged; provenance → re-import appends; exit codes asserted
  numerically, never `!= 0`; the FTS UPDATE trigger → an updated row's old
  term no longer matches. Documented composition recipes execute as tests.
- Export→import roundtrip test — `crm export orgs|contacts --format csv` fed
  back through `crm import orgs|contacts`: row-by-row struct equality across
  CSV escaping, ` || ` separators, embedded newlines, NULL vs empty string,
  unicode. Deals/interactions export is one-way; no roundtrip exists for it.
- `go vet`, `go test -race ./...`, golangci-lint with `errcheck, staticcheck,
  unused, ineffassign, gocritic, revive`.

## Build and packaging

- `CGO_ENABLED=0`; pure-Go SQLite (`modernc.org/sqlite`, driver name
  `"sqlite"`).
- Build locally with `nix shell nixpkgs#go` — there is no go on PATH.
  Packaged with `buildGoModule` in dotfiles; `crm --version` as the
  `installCheckPhase`.
- Version injected into exactly one variable via ldflags; nothing else
  assigns to it; the test asserts the injected *value*, not a prefix.
- No release ceremony: no changelogs, no versioning machinery, no git
  operations in or around the binary.
- Docs describe only what exists. Every doc claim has a distinguishing test;
  aspirations live in issues, never in SPEC, skill, or help text.
