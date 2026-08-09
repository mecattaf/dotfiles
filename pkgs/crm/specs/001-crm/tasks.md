# Tasks: crm — personal git-backed CRM

**Input**: `specs/001-crm/plan.md`, `specs/001-crm/spec.md`,
`specs/001-crm/data-model.sql`, `specs/001-crm/style-transfer-map.md`,
`.specify/memory/constitution.md`

**Organization**: 19 strictly dependency-ordered vertical increments. Each
task becomes one GitHub issue and is sized for one autonomous coding-agent
session. Every task ships its own tests — integration tests against the real
binary and, where named, a persona scenario file — in the same increment;
there is no separate testing task. Before writing code, read the
style-transfer references cited in the task (they are corpora to transfer
implementation style from, not code to copy) and the constitution.

## Universal gates

Every task's acceptance criteria end with the same four gates, all run from
the repo root and all required to exit 0 (constitution: Testing doctrine):

```
nix shell nixpkgs#go -c go build ./...
nix shell nixpkgs#go -c go vet ./...
nix shell nixpkgs#go nixpkgs#gcc -c go test -race ./...
nix shell nixpkgs#golangci-lint -c golangci-lint run ./...
```

`-race` needs a C toolchain (the detector is cgo-backed), hence `nixpkgs#gcc`
in that gate; `CGO_ENABLED=0` governs the *shipped* binary (T15), not the test
run. Lint and race are gates from T01 onward — never deferred to a later task.

## Harness conventions

In the acceptance-criteria snippets below, `crm` means the freshly built
binary and `$T` is a fresh temp dir. The build command — used both by the
integration harness's `TestMain` and by hand — is:

```
nix shell nixpkgs#go -c go build \
    -ldflags "-X main.version=0.0.0-test" -o /tmp/crm ./cmd/crm
```

The `-X` target is the single version variable in `cmd/crm/main.go`, and
`0.0.0-test` is the sentinel the version test asserts *exactly* (constitution:
Build and packaging — assert the injected value, not a prefix). Every listed
command is also encoded as an integration test asserting stdout bytes, stderr,
and the numeric exit code.

## Cross-cutting conventions ruled here (bind every task)

These resolve points the spec leaves implicit; they are binding on every task
so two agents cannot pick two different answers.

1. **Transcript base directory.** `transcript_path` is stored relative to the
   *directory containing the resolved db path* — the `notes/crm/` directory in
   production (spec preamble: db at `~/mecattaf/notes/crm/crm.db`, transcripts
   at `~/mecattaf/notes/crm/transcripts/YYYY/`), and `$T` in tests. `init`
   creates `transcripts/YYYY/` under that same base (T01). `--transcript`
   accepts a path relative to the base, or an absolute path *inside* the base
   (stored relativized); an absolute path outside the base is exit 1. `doctor`
   resolves stored paths against the same base — one rule, two call sites
   (T04 writes it, T10c audits it).
2. **Missing path arguments are exit 2.** A file named by a path flag that
   does not exist is a not-found failure carrying a remedy, not a usage error
   (spec §3 exit 2 is glossed "not found (including: …)" — a non-exhaustive
   list). This covers `--transcript`, `--body-file <path>`, and
   `import <file.csv>`. Unlike `--transcript`, `--body-file` is an ordinary
   filesystem path resolved against cwd and only *read* — nothing about it is
   stored — and `--body-file -` reads stdin.
3. **Default output directory.** `crm export tree` with no argument writes to
   `tree/` under the same base as (1) (spec §5 export shows the default as
   `~/mecattaf/notes/crm/tree`).
4. **Noun aliases land with their nouns.** Spec §5 mandates `org`→`o`,
   `contact`→`c`, `interaction`→`i`, `deal`→`d`, `pipeline`→`p`, `ls`→`list`,
   and singular/plural. T03 ships the registration mechanism plus `o`/`c`;
   `i` lands in T04, `p` in T06, `d` in T07. T11's command-tree walk asserts
   the complete alias table.

---

## T01 — Scaffold, db open funnel, embedded migration, `init`, exit-code spine, test harness — [#1](https://github.com/mecattaf/crm/issues/1)

**Goal**: Bring the repository from empty to a buildable, testable binary
with the entire foundation every later task stands on: module layout
(`cmd/crm`, `internal/cli`, `internal/db`, `internal/model`,
`internal/format` stub, `internal/resolve` stub), the single db open funnel
with pragmas and the embedded migration runner, the `init` verb as the only
creator, the sentinel-error → exit-code spine with one `os.Exit` site, the
ldflags version variable, and the integration harness + `dbtest` package that
all subsequent tasks' tests use.

**Delivers** (spec citations):
- `go.mod` (`github.com/mecattaf/crm`), cobra root command with
  `SilenceUsage/SilenceErrors`, `--db` persistent flag, db resolution order
  `--db` > `$CRM_DB` > `~/mecattaf/notes/crm/crm.db` (spec preamble).
- `internal/db/migrations/001_initial.sql` with the content of
  `specs/001-crm/data-model.sql`; `db.Open(path)` funnel: open →
  `SetMaxOpenConns(1)` → pragma loop (each error wrapped with the pragma
  name) → journal-mode read-back (`delete` for files, `memory` accepted for
  memory dbs) → migrate; close on any failure (constitution: SQLite
  discipline).
- Migration runner (constitution: Migrations): `go:embed`, ordinals from
  filename prefix, `PRAGMA user_version` via `Sprintf` with the
  placeholders-are-illegal comment, one whole-string execution per migration
  in one tx with its version bump. The runner takes its migration set as an
  `fs.FS` parameter (production passes the embedded FS) so a unit test can
  drive it with a two-migration fixture. **Pre-migration copy**: before
  applying a migration to a *file-backed* db that already carries
  `user_version > 0`, copy the file aside as `<db>.pre-migrate-<ver>` in the
  same directory (on a fresh db at version 0 there is nothing to preserve, so
  no copy is written).
- `crm init` (spec §5 init): creates db + all migrations, the directory
  layout and `transcripts/YYYY/` for the current year under the transcript
  base (convention 1), and a stub orientation `README.md` beside the data;
  idempotent; echoes the resolved db path. Every other verb's missing-db guard
  (exit 2 naming the resolved path) as a shared pre-run hook — end-to-end
  provocation lands in T02a with the first reader verb.
- `crm --version` (spec §5 --version): one version variable in
  `cmd/crm/main.go`, `-X main.version` injected by the harness build
  (see Harness conventions); the test asserts the exact sentinel value
  `0.0.0-test`, not a prefix.
- `internal/model`: `ExitError{Message, Err}`, sentinel errors, the one
  `ExitCode` switch pinned by a table-driven test; error voice
  `crm: error: <msg>` on stderr (spec §3).
- Test infrastructure: `TestMain` builds `./cmd/crm` once with the ldflags
  above; `crm(t, dbPath, args...) (stdout, stderr, code)` helper;
  `internal/db/dbtest` (`:memory:` through the real funnel + real
  migrations). golangci-lint config
  (`errcheck, staticcheck, unused, ineffassign, gocritic, revive`) — live as a
  gate from this task onward.

**Read first** (style-transfer-map.md):
- "CLI skeleton, errors, exit codes": `crm-cli/cmd/crm/main.go`,
  `crm-cli/internal/cli/root.go`, `crm-cli/internal/model/errors.go` +
  `errors_test.go`.
- "db open, pragmas, migrations": `crm-cli/internal/db/db.go`,
  `crm-cli/internal/db/migrations/001_initial.sql` (anti-pattern for the
  runner: `crm.cli/src/db.ts` semicolon splitting).
- "testing": `crm-cli/internal/cli/person_test.go`,
  `crm.cli/test/helpers.ts`.
- "packaging" (version wiring anti-pattern): `crm-cli/cmd/crm/main.go`.

**Acceptance criteria** (runnable):
```
crm --db $T/crm.db init                 # exit 0; prints resolved path $T/crm.db
test -d $T/transcripts/$(date +%Y)      # exit 0
test -f $T/README.md                    # exit 0
crm --db $T/crm.db init                 # exit 0 again (idempotent)
ls $T/crm.db.pre-migrate-*              # exit != 0; no copy on a fresh db
crm --version                           # exit 0; prints exactly "0.0.0-test"
crm definitely-not-a-verb               # exit 1; stderr starts "crm: error:"; NO usage dump
ls $T/crm.db-wal $T/crm.db-shm          # both absent (exit != 0)
```
- Integration test asserts, post-`init`: `PRAGMA journal_mode` == `delete`,
  `PRAGMA user_version` == 1, `foreign_keys` == 1, no sidecar files.
- Migration-runner unit test drives the runner with a two-migration fixture
  `fs.FS` against a file db: after the second migration applies,
  `<db>.pre-migrate-1` exists beside it and its bytes are the pre-migration
  file; a failing fixture migration rolls back and leaves `user_version`
  untouched.
- Table-driven unit test pins the full sentinel→exit-code map (0/1/2/3/4).
- The four gates exit 0.

**Depends on**: nothing.

---

## T02a — Normalization tiers and the output formatter, proven on `org add|ls` — [#2](https://github.com/mecattaf/crm/issues/2)

**Goal**: Ship two of the three cross-cutting engines — the normalization
tiers and the entire output layer — proven end-to-end on the two org verbs
that need no ref resolution. After this task every later verb inherits the
formatter unchanged.

**Delivers** (spec citations):
- `internal/model` normalization (spec §1, constitution: Data hygiene):
  `name_norm` (NFKD, strip combining marks, casefold) recomputed on every
  name write; email lowercased; LinkedIn handle extracted from URL forms;
  three tiers as paired `NormalizeX() (string, error)` /
  `TryNormalizeX() (string, bool)` (Strict: dates, email syntax; Permissive:
  website, phone, location; Extract: linkedin, name_norm).
- `internal/format` (spec §4): TTY table / piped JSON, `--format
  table|json|csv|ids` with per-verb accepted sets and hard usage error on
  unsupported values; `ColumnDef` projection, all-empty column elision,
  rune-count widths, hand-rolled tabwriting; stable JSON keys, explicit
  `null`, derived `ref`, `[]` for empty collections (byte-asserted);
  pretty-on-TTY/compact-piped; `ids` mode one prefixed ref per line; mutation
  echo as one-element array.
- `crm org add` (spec §5 orgs): all add flags
  (`--category --website --linkedin --location --focus --context --hint
  --source --detail`); `--source`/`--detail` append to the provenance columns
  with ` || `; duplicate live `name_norm` → exit 4 naming the owning row
  (UNIQUE-violation translation, constitution: Data hygiene — never a
  pre-scan).
- `crm org ls [--category] [--all] [--limit N]` (`--all` is a listing flag
  now; archived rows only start existing in T10a).
- Missing-db guard provoked end-to-end (exit 2) now that a reader exists.
- Repo layer conventions (constitution: column consts, `scanX`, tx +
  `defer Rollback()`, post-commit re-read outside the tx).

**Read first** (style-transfer-map.md):
- "Normalization": `crm.cli/src/normalize.ts`, `crm.cli/spec/normalization.md`.
- "Output formatting": `crm-cli/internal/format/format.go`,
  `crm.cli/src/format.ts`.
- "Repository layer, scanning, batch child loading":
  `crm-cli/internal/db/repo/person.go`.

**Acceptance criteria** (runnable, after `crm init`):
```
crm org add "Kima Ventures" --category vc --website kima.vc --source n.md | cat
                                        # exit 0; compact JSON one-element array, ref "o1"
crm org add "Kima Ventures"             # exit 4; stderr names the owning row (o1)
crm org add "Léger Capital"             # exit 0; name_norm stored accent-stripped
crm org ls --format bogus               # exit 1; stderr lists accepted set
crm org ls --format json | cat          # empty db case asserted as literal [] bytes in test
crm org ls --format ids                 # exit 0; one prefixed ref per line ("o1")
crm --db $T/absent.db org ls            # exit 2; "no database at ... (run 'crm init')"
```
- Test asserts nothing but the formatter writes stdout (stream assertions on
  every command above). The four gates exit 0.

**Depends on**: T01.

---

## T02b — Ref-resolution ladder, `org show|edit` with true PATCH — [#3](https://github.com/mecattaf/crm/issues/3)

**Goal**: The third cross-cutting engine — the seven-rung resolver — plus the
read and PATCH halves of org CRUD that prove it. After this task every later
ref site reuses the ladder unchanged.

**Delivers** (spec citations):
- `internal/resolve` (spec §2): the seven-rung ladder (prefixed id, bare id,
  exact email, exact linkedin handle, exact name/title, exact `name_norm`,
  substring on `name_norm`), `LIMIT 2` per rung, first rung with exactly one
  hit wins, archived rows reachable on rungs 1–2 only, wrong-entity prefix →
  exit 2, ambiguity → exit 3 with pasteable candidate lines on stderr. All
  resolution happens before any transaction opens (constitution: Writes and
  errors).
- **Link-flag remedy** (spec §2): resolution failure at a *link flag* site
  emits the exact create command to run on stderr
  (`crm: error: no org "kima" — try: crm org add "kima"`); nothing is ever
  auto-created on a failed resolution (sole exception: `import
  --create-missing`, T14). Unit test pins the message construction per entity;
  the end-to-end assertions land with the first consumers (T03 `--org`, T04
  `--with`).
- Not-found at a non-link ref site carries its own remedy (`try: crm find
  nick`, spec §3).
- `crm org show|edit` (spec §5 orgs): true PATCH via `cmd.Flags().Changed()`
  (absent / present-empty / present-value; `--flag ""` clears to SQL NULL —
  the empty string is never stored in a nullable column); `--context-append`
  with blank-line separator; `--source`/`--detail` always append with ` || `;
  a no-op edit returns the record without touching `updated_at`.

**Read first** (style-transfer-map.md):
- "Reference resolution": `crm.cli/src/resolve.ts`
  (anti-pattern: `crm-cli/internal/cli/context.go`).
- "edit PATCH semantics": `crm-cli/internal/cli/person.go`,
  `crm-cli/internal/db/repo/person.go` `Update`.

**Acceptance criteria** (runnable, after T02a's fixtures):
```
crm org show leger                      # exit 0; accent-normalized ref hits the row
crm org show o1; crm org show 1         # both exit 0 (prefixed + bare id rungs)
crm org add "Kima Partners" && crm org show kima
                                        # exit 3; stderr lists both candidates as pasteable refs
crm org show nosuchorg                  # exit 2; stderr carries a "try: crm find" remedy
crm org edit o1 --focus "pre-seed"      # exit 0; echoes full record
crm org edit o1 --focus "pre-seed"      # exit 0; updated_at unchanged (asserted in test)
crm org edit o1 --website ""            # exit 0; JSON shows "website": null
crm org edit o1 --context-append "…"    # exit 0; blank-line separator, prior dossier intact
crm org edit o1 --source b.md           # exit 0; provenance_sources == "n.md || b.md"
```
- The four gates exit 0.

**Depends on**: T02a.

---

## T03 — Contact CRUD, polymorphic `show`, messy-refs persona (part 1) — [#4](https://github.com/mecattaf/crm/issues/4)

**Goal**: Second entity, exercising the org FK, the email/linkedin resolver
rungs, and duplicate-translation on UNIQUE email — plus the top-level
polymorphic `crm show` dispatcher. Lands the messy-refs persona scenario
(everything except the archive leg, which completes in T10a).

**Delivers** (spec citations):
- `crm contact add|show|ls|edit` (spec §5 contacts): all flags; `--org`
  resolves through the shared resolver (a real FK, never text); exactly one
  email/phone/linkedin; email lowercased on write, UNIQUE-violation
  translated to exit 4 naming the owner; setting a field to the value it
  already holds (post-normalization) is a silent no-op exit 0; `ls --org`
  filter.
- Resolver rungs 3–4 live: exact email, exact linkedin handle (URL forms
  normalized first) (spec §2).
- Link-flag remedy asserted end-to-end at the `--org` site (spec §2, T02b).
- `crm show <prefixed-ref>` (spec §5 grammar): dispatches on prefix,
  prefixed refs only; `crm show nick` → exit 1 usage error.
- Alias registration mechanism on the root command plus `org`→`o`,
  `contact`→`c`, singular/plural, `ls`→`list` (spec §5 grammar,
  convention 4); later nouns register their own alias as they land.
- Persona: `scenario_messy_refs_test.go` (constitution: persona scenarios) —
  accented names resolving to one row, ambiguity exit 3 with candidates,
  duplicate email exit 4 naming the owner. (Archive vs `ls --all` leg is
  added in T10a.)

**Read first** (style-transfer-map.md):
- "Repository layer, scanning, batch child loading":
  `crm-cli/internal/db/repo/person.go`.
- "Reference resolution": `crm.cli/src/resolve.ts`.
- "edit PATCH semantics": `crm-cli/internal/cli/person.go`,
  `crm.cli/src/commands/contact.ts`,
  `crm.cli/test/scenarios/messy-input.test.ts`.
- "Normalization" (linkedin extraction): `crm.cli/src/normalize.ts`.
- "Output formatting" (prefixed refs): `crm.cli/src/format.ts`,
  `crm.cli/spec/data-model.md`.

**Acceptance criteria** (runnable):
```
crm contact add "Nick Dupont" --org kima --email Nick@Kima.VC   # exit 0; JSON email "nick@kima.vc"
crm contact add "X" --org nosuchorg                             # exit 2; stderr carries the runnable `crm org add "nosuchorg"` line
crm contact show nick@kima.vc                                   # exit 0 (email rung)
crm contact add "Other Guy" --email nick@kima.vc                # exit 4; stderr names contact 1 (Nick Dupont)
crm contact edit nick --email nick@kima.vc                      # exit 0; silent no-op
crm contact add "Ana" --linkedin https://linkedin.com/in/ana-x/ # exit 0; stored handle "ana-x"
crm contact show ana-x                                          # exit 0 (linkedin rung)
crm show c1                                                     # exit 0; same bytes as `crm contact show c1`
crm show o1                                                     # exit 0; dispatches to org
crm show nick                                                   # exit 1; prefixed refs only
crm contact show o1                                             # exit 2; wrong-entity prefix message
crm c ls --org kima --format ids                                # exit 0; "c1" line format
```
- `scenario_messy_refs_test.go` passes with full final-state verification.
- The four gates exit 0.

**Depends on**: T02b.

---

## T04 — `log`, interaction read/repair, enum spine, concurrent-writer test — [#5](https://github.com/mecattaf/crm/issues/5)

**Goal**: The hottest write path. `crm log` creates interactions with
participants atomically; the interaction noun gets show/ls/edit; the kind
enum becomes the single-source slice with its CHECK-drift test; and the
calibrated cross-process concurrent-writer test proves the busy-timeout +
DELETE-journal discipline. Lands the post-call persona.

**Delivers** (spec citations):
- `crm log` (spec §5 log, §7): `--with` repeatable + deduplicated (repeat is
  a silent no-op), `--kind` required from the enum, `--summary` required,
  `--date` defaulting to today local, `--body-file <path>|-`, `--org`/`--deal`
  attach flags (`--deal` returns exit 2 until deals exist — resolver is
  entity-generic), ≥1 of `--with`/`--org`/`--deal` required (exit 1); all refs
  resolved before the tx; interaction + junction rows commit atomically.
  Positional sugar `crm log call nick "quick sync"` desugaring to the
  canonical flag form. Link-flag remedy asserted end-to-end at the `--with`
  site (spec §2).
- **Transcript path handling** (convention 1, spec §1/§7): `--transcript` is
  resolved against the transcript base (the directory containing the resolved
  db path), validated to exist on disk *before* the write, and stored relative
  to that base; an absolute path inside the base is relativized, an absolute
  path outside it is exit 1; a path that does not exist is exit 2
  (convention 2). This is the rule `doctor` audits in T10c — one rule, two
  call sites.
- `crm interaction show|ls|edit` (spec §5 interactions): `ls` filters
  `--with/--org/--kind/--limit`, ordering `occurred_on DESC, id DESC`;
  `edit` full PATCH incl. `--add-with`/`--rm-with` idempotent set-membership
  and `--transcript`/`--body-file` under the same path rules;
  re-validation of the ≥1-link invariant after patching (exit 4 naming what
  would remain).
- `interaction`→`i` alias registered (convention 4).
- Kind enum: one Go slice feeding validator, error text, flag help,
  completion, plus the test parsing the CHECK out of `sqlite_master`
  (constitution: Writes and errors).
- Batch participant loading after `rows.Close()` with the deadlock comment
  and a timeout-guarded regression test (constitution: SQLite discipline).
- Concurrent-writer test (constitution: Testing doctrine): N parallel
  processes exec `crm log`; all exit 0; count == N; N calibrated with
  evidence in a comment; post-run `-wal`/`-shm` NotExist assertion.
- Persona: `scenario_post_call_test.go` — transcript file on disk +
  `log --transcript`, interaction shows the path.

**Read first** (style-transfer-map.md):
- "log / interaction creation": `crm-cli/internal/cli/log.go`,
  `crm-cli/internal/model/types.go`, `crm-cli/internal/cli/task.go:91-93`,
  `crm.cli/src/commands/activity.ts:21-31`.
- "Repository layer" (batch child loading):
  `crm-cli/internal/db/repo/interaction.go`.
- "edit PATCH semantics" (add-to-set shape):
  `crm.cli/src/commands/contact.ts`, `crm.cli/test/scenarios/messy-input.test.ts`.
- "testing" (concurrency): `crm.cli/test/db-busy-timeout.test.ts`.

**Acceptance criteria** (runnable):
```
crm log --with nick --with nick --kind call --summary "intro"    # exit 0; one participant row
crm log call nick "quick sync"                                   # exit 0; sugar == flag form
crm log --kind call --summary "orphan"                           # exit 1; needs --with/--org/--deal
crm log --with nosuchone --kind call --summary x                 # exit 2; stderr carries the runnable `crm contact add` line
crm log --with nick --kind zoom --summary x                      # exit 1; stderr lists call,meeting,email,message,note
mkdir -p $T/transcripts/2026 && touch $T/transcripts/2026/x.md
crm log --with nick --kind call --summary x --transcript transcripts/2026/x.md
                                                                 # exit 0; stored path is exactly "transcripts/2026/x.md"
crm log --with nick --kind call --summary x --transcript $T/transcripts/2026/x.md
                                                                 # exit 0; absolute-inside-base relativized identically
crm log --with nick --kind call --summary x --transcript /etc/hosts
                                                                 # exit 1; absolute path outside the transcript base
crm log --with nick --kind call --summary x --transcript nope.md # exit 2; transcript not found on disk
crm log --with nick --kind call --summary x --body-file nope.txt # exit 2; body file not found
crm interaction ls --with nick --format json | cat               # exit 0; ordered occurred_on DESC, id DESC
crm interaction edit i1 --rm-with nick                           # exit 4 when it would leave zero links; names what remains
crm i show i1                                                    # exit 0 (alias)
```
- Kind CHECK-drift test passes; concurrent-writer test passes with the
  no-sidecar assertion; `scenario_post_call_test.go` passes.
- The four gates exit 0.

**Depends on**: T03.

---

## T05a — `find`: cross-entity FTS with the normalized global rank merge — [#6](https://github.com/mecattaf/crm/issues/6)

**Goal**: The search engine. Per-token escaping, bm25 rowid joins, and the
per-table score normalization that makes a global merge honest.

**Delivers** (spec citations):
- `crm find` (spec §5 find, §6, constitution: Search): per-token phrase
  escaping with doubled inner quotes, last-token prefix star, raw `@ . - :`
  never reaching FTS syntax; bm25 rowid join ascending (never
  `id IN (subquery)`); per-table score normalization (divide by that table's
  best score) then global sort with `type, id` tiebreakers; uniform rows
  `{type, ref, name, detail, rank}` with per-type `detail` (contact →
  email/org; org → category/location; interaction → date + kind; deal →
  pipeline/stage); query-time union of contacts of matched orgs; archived rows
  excluded; default cap 20, `--limit`, `--type` validated early.
- `--format table|json|ids` accepted set (spec §4: `ids` on verbs whose rows
  carry refs — find rows carry `ref`); this is what the T11 composition recipe
  `crm find kima --format ids | xargs -n1 crm show` stands on.

**Read first** (style-transfer-map.md):
- "FTS5 search and `find`": `crm-cli/internal/db/migrations/001_initial.sql`,
  `crm-cli/internal/db/repo/person.go` `Search`,
  `crm-cli/internal/cli/search.go` (anti-patterns:
  `crm.cli/src/commands/search.ts` word-overlap `find`,
  `crm.cli/src/lib/helpers.ts` denormalized index content).

**Acceptance criteria** (runnable):
```
crm find "nick kima" --format json | cat        # exit 0; rows {type,ref,name,detail,rank}
crm find nick@kima.vc                           # exit 0; raw @ and . cause no FTS syntax error
crm find dataroom --type interaction --limit 5  # exit 0
crm find dataroom --type meeting                # exit 1; --type validated early
crm find kima --format ids                      # exit 0; one prefixed ref per line, mixed types
crm find kima --format csv                      # exit 1; accepted set on stderr
```
- Distinguishing tests: an exact-name contact outranks an interaction that
  merely mentions the token (global merge, not concatenation); after
  `interaction edit` changes a summary, the old term no longer matches (FTS
  UPDATE trigger); `Léger`/`Leger` find the same row; a matched org surfaces
  its contacts via query-time union.
- The four gates exit 0.

**Depends on**: T04.

---

## T05b — `context` briefing: one assembler, two renderers; first-lead + agent-session personas — [#7](https://github.com/mecattaf/crm/issues/7)

**Goal**: The flagship read verb. A briefing document and its JSON twin from
a single assembler, so table and JSON can never diverge. Lands the first-lead
and agent-session personas.

**Delivers** (spec citations):
- `crm context <contact-or-org-ref>` (spec §5 context): document renderer —
  `# Name (ref)` header, profile lines with `relationship_hint` and
  provenance first, dossier, org block, contact links (both directions),
  open deals with stage and days-in-stage, then `Timeline (N):` merged
  newest-first with transcript paths rendered prominently, capped 20 with
  `--limit/--all`; empty sections omitted entirely; headings carry counts.
- JSON form: one object `{contact|org, org?, links, deals, timeline}`. One
  assembler feeds both renderers.
- Org timeline = org-tagged ∪ participants-of-org interactions (spec §1).
- **Section wiring is explicit**: the `links` section is assembled here and
  goes live in T08; the `deals` section is assembled here and goes live in
  T07. Until then each renders as an omitted-empty section, and each of T07
  and T08 owns the acceptance criterion that closes its half.
- Personas: `scenario_first_lead_test.go` (org/contact/backdated
  log/context), `scenario_agent_session_test.go` (find → context → log, all
  `--format json`).

**Read first** (style-transfer-map.md):
- "`context` briefing": `crm-cli/internal/cli/context.go`,
  `crm.cli/src/fuse-json.ts`.

**Acceptance criteria** (runnable):
```
crm context nick                        # exit 0; header "# Nick Dupont (c1)"; timeline present
crm context kima --format json | cat    # exit 0; one object {org, timeline, ...}
crm context nick --format json | jq -e 'has("links") and has("deals") and has("timeline")'
                                        # exit 0; keys always present, empty ones as []
crm context nick --limit 2              # exit 0; timeline capped, heading count reflects the total
crm context o1                          # exit 0; org form via prefixed ref
```
- Distinguishing test: an org whose only touch was logged via a participant
  still shows that interaction in its context timeline (org-timeline union).
- Both persona scenarios pass. The four gates exit 0.

**Depends on**: T05a.

---

## T06 — Pipelines and stages management — [#8](https://github.com/mecattaf/crm/issues/8)

**Goal**: Pipelines and their ordered stages as database rows managed
entirely through CLI verbs — the substrate deals stand on. Lifecycle
(archive/delete) for these entities arrives with the lifecycle tasks (T10a,
T10b); deletion refusal rules need deals to exist first.

**Delivers** (spec citations):
- `crm pipeline add|ls|show|rename` (spec §5 pipelines and stages): live
  `name_norm` UNIQUE (violation → exit 4); `show` renders stages in order
  with rot thresholds.
- `crm stage add|rename|reorder|set-rot` (spec §5): `add` appends last by
  default, `--after <stage>` / `--first` placement, `--rot N`; `reorder`
  takes the complete new order in one transaction, partial list → exit 1
  listing the missing stages; `set-rot ... none` clears; stage names resolve
  within their pipeline (spec §2: prefixed `s7`, exact `name_norm`, then
  substring), never globally; live `(pipeline_id, name_norm)` UNIQUE →
  exit 4.
- `pipeline`→`p` alias registered (convention 4).
- Stage mutations echo the stage record with ref `s7` (spec §4).

**Read first** (style-transfer-map.md):
- "pipelines, stages, deals, stage_moves, rot":
  `sodimo-crm/src/server/db/schema.ts` (stages.rot_days:71),
  `sodimo-crm/src/server/services/pipelines.ts` (stage CRUD + reorder).
- "Repository layer": `crm-cli/internal/db/repo/person.go`.

**Acceptance criteria** (runnable):
```
crm pipeline add "Seed raise"                       # exit 0; echoes record, ref "p1"
crm pipeline add "Seed raise"                       # exit 4
crm stage add p1 sourced && crm stage add p1 pitched
crm stage add p1 contacted --rot 14 --after sourced # exit 0; order sourced,contacted,pitched
crm p show p1                                       # exit 0 (alias); stages in position order with rot
crm stage reorder p1 pitched sourced                # exit 1; stderr lists missing "contacted"
crm stage reorder p1 pitched contacted sourced      # exit 0
crm stage set-rot p1 pitched 7                      # exit 0
crm stage set-rot p1 pitched none                   # exit 0; rot_days null in JSON
crm stage rename p1 contacted "first contact"       # exit 0
```
- The four gates exit 0.

**Depends on**: T02b (resolver/format). No code dependency on T04/T05a/T05b;
sequenced after T05b in the issue queue only.

---

## T07 — Deals, stage moves, win/lose/reopen, rot, the context deals section; deal-loop persona — [#9](https://github.com/mecattaf/crm/issues/9)

**Goal**: The full deal loop: stage-only opportunities, every transition a
real-columned `stage_moves` row, rot math, the deal timeline interleaved
with interactions, and the `context` briefing's open-deals section going
live. Lands the deal-loop persona.

**Delivers** (spec citations):
- `crm deal add|show|ls|edit` (spec §5 deals): `--pipeline` required + ≥1 of
  `--org`/`--contact` (exit 1); stage defaults to the pipeline's first;
  creation writes the opening `stage_moves` row (`from_stage_id` NULL) and
  `stage_changed_at`; `show` includes stage history and the merged timeline
  (interactions with `deal_id` interleaved with stage moves, spec §1);
  `ls --pipeline/--stage/--status/--rotting/--all/--limit`; `ls --stage`
  without `--pipeline` → exit 1 (no global stage scope); `edit` never
  changes stage or status.
- `crm deal move` (spec §5): stage resolved within the deal's pipeline;
  no-op move → exit 4 "already in stage X"; move row + `stage_id` +
  `stage_changed_at` in one transaction.
- `crm deal win|lose|reopen` (spec §5): status/`outcome_reason`/`closed_at`
  semantics; `reopen` clears `closed_at`, preserves `outcome_reason`.
- Rot (spec §1, §5): julianday arithmetic, both operands UTC; `ls --rotting`
  most-overdue first with `days_in_stage` and threshold in the output.
- **The T05b assembler's `deals` section goes live**: open deals with stage
  and `days_in_stage` render in both the document and the JSON renderer
  (spec §5 context). Closed deals (won/lost) are excluded — the section lists
  *open* deals only.
- `deal`→`d` alias registered (convention 4).
- `crm log --deal` and `interaction ls --deal` now resolve end-to-end (T04
  left the flag entity-generic).
- Status enum CHECK-drift test (constitution: Writes and errors).
- Persona: `scenario_deal_loop_test.go` — pipeline/stages/moves/rot, no-op
  move rejected. (The rot fixture backdates `stage_changed_at` directly in
  the test db — the CLI has no backdating path, by design.)

**Read first** (style-transfer-map.md):
- "pipelines, stages, deals, stage_moves, rot":
  `sodimo-crm/src/server/db/schema.ts` (deals.stage_changed_at:150),
  `sodimo-crm/src/server/services/deals.ts` (`moveDeal`),
  `sodimo-crm/src/server/services/views.ts` (rotting math)
  (anti-pattern: `crm.cli/src/commands/deal.ts` prose-encoded moves).

**Acceptance criteria** (runnable):
```
crm deal add "Kima seed ticket" --pipeline "Seed raise" --org kima  # exit 0; stage = first; opening move row
crm deal add "No anchor" --pipeline p1                              # exit 1
crm deal move d1 pitched --note "deck sent"                         # exit 0
crm deal move d1 pitched                                            # exit 4; "already in stage pitched"
crm d show d1 --format json | cat                                   # exit 0 (alias); stage history + timeline present
crm deal ls --stage pitched                                         # exit 1; requires --pipeline
crm deal ls --pipeline p1 --stage pitched                           # exit 0
crm context nick                                                    # exit 0; open-deal line carries stage and days-in-stage
crm context kima --format json | jq -e '.deals | length == 1'       # exit 0; deals section populated
crm deal win d1 --reason "led the round"                            # exit 0; closed_at set
crm context nick --format json | jq -e '.deals == []'               # exit 0; a won deal is excluded (distinguishing test)
crm deal reopen d1                                                  # exit 0; closed_at null, outcome_reason preserved
crm deal ls --rotting                                               # exit 0; backdated fixture deal listed with days_in_stage
```
- Status CHECK-drift test and `scenario_deal_loop_test.go` pass.
- The four gates exit 0.

**Depends on**: T04, T05b (context assembler), T06.

---

## T08 — Contact links: `relate` / `unrelate`, both-ends rendering — [#10](https://github.com/mecattaf/crm/issues/10)

**Goal**: Person-to-person relationships stored directed, read from both
ends, rendered in `show` and `context`.

**Delivers** (spec citations):
- `crm contact relate <a> <b> --type <free text> [--note]` (spec §5
  contacts, §1 contact_links): directed storage; duplicate
  `(a, b, type)` → exit 4; self-link rejected in validation before the tx
  (exit 1; the CHECK is defense in depth); echoes the first-named contact's
  full record, links included (spec §4).
- `crm contact unrelate <a> <b> [--type]` (spec §5): without `--type`
  removes all links between the pair in either direction; with `--type`,
  just that link.
- Links render in both contacts' `show` and `context` output (both
  directions; the T05b assembler's `links` section goes live).

**Read first** (style-transfer-map.md):
- "contact links": `crm-cli/internal/cli/relate.go`,
  `crm-cli/internal/db/repo/relationship.go`.

**Acceptance criteria** (runnable):
```
crm contact relate nick jean --type "referred by" --note "Jean made the intro"
                                            # exit 0; echoes nick's record with the link
crm contact relate nick jean --type "referred by"   # exit 4
crm contact relate nick nick --type peer            # exit 1; "cannot relate a contact to itself"
crm contact show jean --format json | cat           # exit 0; link visible from the far end
crm context jean                                    # exit 0; links section with count
crm contact unrelate nick jean                      # exit 0; both directions gone
```
- The four gates exit 0.

**Depends on**: T05b (context assembler). No code dependency on T07;
sequenced after T07 in the issue queue only.

---

## T09 — `status` dashboard and `stale` report — [#11](https://github.com/mecattaf/crm/issues/11)

**Goal**: The zero-argument dashboard and the outreach worklist, both built
on repo-level aggregate queries with the LEFT-JOIN shape that keeps
never-contacted rows.

**Delivers** (spec citations):
- `crm status` (spec §5 status): entity counts, last-logged date with
  days-ago, never-contacted count, stale count (90d), rotting-deal count,
  resolved db path; all aggregates COALESCE to 0 on an empty db.
- `crm stale [--days 90] [--type contact|org] [--recent-first]` (spec §5
  stale): LEFT-JOIN so never-contacted rows appear as `last: never`; org
  staleness uses the full org-timeline definition (org-tagged ∪
  participant-of-org interactions, spec §1); default order never-contacted
  first then oldest-first with id tiebreaker; `--recent-first` reverses;
  `ids` format supported.

**Read first** (style-transfer-map.md):
- "status / stale": `crm-cli/internal/cli/status.go`,
  `crm.cli/src/reports.ts` (do NOT transfer the report family —
  conversion/velocity/forecast are out of surface).

**Acceptance criteria** (runnable):
```
crm --db $T/empty.db init && crm --db $T/empty.db status   # exit 0; all counts 0; db path printed
crm status --format json | cat                             # exit 0; stable keys
crm stale --days 60 --format json | cat                    # exit 0; never-contacted rows "last": null first
crm stale --type org                                       # exit 0
crm stale --recent-first                                   # exit 0; order reversed
crm stale --days 60 --format ids | xargs -n1 crm context   # exit 0 (the morning-outreach recipe)
```
- Distinguishing test: an org whose only touch was logged via a participant
  is NOT stale (org-timeline union, not `interactions.org_id` alone).
- The four gates exit 0.

**Depends on**: T05b, T07 (rotting count).

---

## T10a — Archive / unarchive for every entity, honest `ls --all`; messy-refs persona completed — [#12](https://github.com/mecattaf/crm/issues/12)

**Goal**: The soft-archive lifecycle — the default lifecycle for every entity
— with listings that tell the truth about it.

**Delivers** (spec citations):
- `archive`/`unarchive` for orgs, contacts, interactions, pipelines, stages,
  deals (spec §5 archive/unarchive/delete): already-archived → exit 4
  (idempotent conflict — a retrying agent learns it already succeeded),
  missing → exit 2; echo the resulting record through the normal formatter
  (spec §4).
- `ls --all` genuinely includes archived rows, visibly marked, on every
  entity listing; archived rows reachable by the id rungs only (spec §2 —
  rungs 1–2 reach archived, 3–7 do not; this is the task where that
  distinction first becomes observable).
- Archiving frees the live-UNIQUE names/emails (partial indexes) — asserted
  by re-adding a name whose only holder is archived.
- An archived stage cannot receive moves (spec §5 pipelines and stages):
  `deal move` onto an archived stage is refused, exit 4 — the retrofit into
  T07's `move` path.
- Persona: extend `scenario_messy_refs_test.go` with the archive vs
  `ls --all` leg (constitution: persona scenarios — messy refs ends on
  archive vs `ls --all`).

**Read first** (style-transfer-map.md):
- "delete confirmation, archive lifecycle":
  `crm-cli/internal/db/repo/task.go` `Complete`
  (RowsAffected → archived-vs-missing distinction).

**Acceptance criteria** (runnable):
```
crm org archive kima          # exit 0; echoes record with archived_at set
crm org archive kima          # exit 4 (idempotent conflict)
crm org archive nosuchorg     # exit 2
crm org ls | grep -c Kima     # 0 hits; crm org ls --all shows it marked
crm org show o1               # exit 0 (id rung reaches archived)
crm org show kima             # exit 2 (name rungs are live-only)
crm org add "Kima Ventures"   # exit 0; the archived name is free again
crm org unarchive o1          # exit 0
crm stage archive p1 pitched && crm deal move d1 pitched
                              # exit 4; an archived stage cannot receive moves
```
- The completed messy-refs persona passes. The four gates exit 0.

**Depends on**: T07, T08 (every entity and link type must exist).

---

## T10b — Hard `delete`: confirmation machinery and the blocking-reference matrix — [#13](https://github.com/mecattaf/crm/issues/13)

**Goal**: The one irreversible verb, gated by confirmation and by an
exhaustive pre-check that refuses with counts instead of driver text.

**Delivers** (spec citations):
- `delete` for orgs, contacts, interactions, pipelines, stages, deals (spec
  §5 archive/unarchive/delete): `--confirm` required; on a TTY without the
  flag, prompts on `/dev/tty` naming the *resolved* record
  (`Delete contact "Nick Dupont" (c17)? [y/N]`); non-interactive without the
  flag, refuses (`refusing to delete without --confirm (non-interactive)`,
  exit 1). Never batched — piped ids still fail per-invocation confirmation.
- A destructive verb never accepts an ambiguous ref, even with `--confirm`
  (spec §2) — exit 3.
- Pre-checked blocking references, exhaustively (spec §5): org ←
  contacts/deals/interactions; contact ← interaction_people/deals/
  contact_links (either endpoint); pipeline ← stages/deals; stage ←
  deals/stage_moves (either endpoint, live or archived); deal ←
  interactions; interaction ← nothing (junction rows cascade). Each refusal
  is a counted remedy message (`contact appears in 4 interactions — archive
  instead`), exit 4, never raw driver text — **one integration test per
  blocking reference**, provoked end-to-end.
- `delete` echoes the pre-delete record with a `deleted: true` marker
  (spec §4).

**Read first** (style-transfer-map.md):
- "delete confirmation, archive lifecycle": `crm.cli/src/lib/helpers.ts`
  (confirm).

**Acceptance criteria** (runnable):
```
echo | crm contact delete nick            # exit 1; "refusing to delete without --confirm (non-interactive)"
crm contact ls --format ids | xargs -n1 crm contact delete
                                          # every invocation exits 1; row count unchanged (never batched)
crm contact delete nick --confirm         # exit 4; "contact appears in N interactions — archive instead"
crm contact delete amb --confirm          # exit 3 when "amb" is ambiguous; destructive verbs never guess
crm interaction delete i1 --confirm       # exit 0; JSON carries "deleted": true
crm interaction show i1                   # exit 2 after the delete
crm stage delete p1 pitched --confirm     # exit 4; both the deals count and the stage_moves count named
```
- 13 integration tests, one per blocking reference in the matrix above, each
  asserting exit 4 and the counted message. The four gates exit 0.

**Depends on**: T10a.

---

## T10c — `doctor` integrity report and `--rebuild-fts` repair — [#14](https://github.com/mecattaf/crm/issues/14)

**Goal**: The audit and repair path over the now-complete schema surface.

**Delivers** (spec citations):
- `crm doctor` (spec §5 doctor), eight checks, each independently reported:
  `PRAGMA integrity_check`; `PRAGMA foreign_key_check`; per-table FTS
  `integrity-check` + row-count comparison; strict journal-mode assertion
  (fails loudly if the file is not `delete`); every `transcript_path` resolves
  on disk — **resolved against the transcript base of convention 1, the same
  rule T04 writes with**; every deal's `stage_id` belongs to its
  `pipeline_id`; every interaction has ≥1 link; and the `user_version`
  report. Non-zero exit on drift.
- `--rebuild-fts` runs FTS `rebuild` per table in one transaction — the
  repair path after any bulk operation or bad merge.

**Read first** (style-transfer-map.md):
- "doctor": `crm.cli/src/commands/search.ts:146-178`.

**Acceptance criteria** (runnable):
```
crm doctor                                # exit 0 on a healthy db; user_version reported
crm doctor --format json | cat            # exit 0; one documented report shape, all eight checks keyed
crm doctor                                # exit != 0 after the test deletes $T/transcripts/2026/x.md
                                          #   from disk; the offending interaction ref is named
crm doctor --rebuild-fts                  # exit 0; corrupted-FTS fixture repaired (test desyncs the index first)
crm doctor                                # exit 0 again after the rebuild
```
- Distinguishing tests: a deal whose `stage_id` is forced (in the test db) to
  a stage of another pipeline is reported; an interaction stripped of all
  links in the test db is reported; a db opened after `PRAGMA journal_mode=WAL`
  is forced on it fails the journal check.
- The four gates exit 0.

**Depends on**: T05a (FTS tables), T07 (deals/stages). Sequenced after T10b.

---

## T11 — Post-write hook, `/crm` skill, help examples, agent docs, composition recipes as tests — [#15](https://github.com/mecattaf/crm/issues/15)

**Goal**: The entire automation and agent surface: the fire-and-forget
post-write hook, the `Example:` block audit across the command tree, the
situation-shaped `/crm` skill with its sibling flag reference, the
tool-directory AGENTS.md with annotated transcripts, the final orientation
README written by `init`, and the four composition recipes executing as
integration tests.

**Delivers** (spec citations):
- `$CRM_POST_WRITE_HOOK` (spec §8): runs after every successful mutation
  with JSON payload `{event, verb, entity, refs, records, db_path}` on
  stdin; 30s timeout; exit status ignored; stderr passed through; never
  blocks or fails the verb; unset = no-op; read verbs never fire it.
- **Help-text audit** (spec §5): every cobra leaf command carries a non-empty
  `Example:` block, and every enum flag's help text is generated from the enum
  slice (not hand-typed). Both are enforced by one mechanical test that walks
  the command tree — the same walk asserts the complete alias table
  (`o`, `c`, `i`, `d`, `p`, `ls`→`list`, singular/plural; convention 4) and
  that every leaf verb named in the tree appears in `skills/crm/SKILL.md`,
  which replaces any unverifiable prose criterion about coverage.
- `/crm` skill at `skills/crm/SKILL.md` (spec §9): situation-shaped numbered
  call sequences (post-call, about-to-talk, new-company), one runnable
  example per verb, the exit-code table, the stdout/stderr rule, the
  transcript protocol (including the transcript base of convention 1), the
  dossier discipline, the "Tips for AI Agents" closer; exhaustive flags in a
  sibling file, skill says "run `crm <verb> --help`"; triggers in frontmatter
  `description`.
- Tool-directory `AGENTS.md` with the same doctrine plus two annotated
  end-to-end transcripts, post-call flow first (spec §9). Final orientation
  `README.md` content written by `init` (spec §9) replacing the T01 stub.
- Composition recipes (spec §10) each running as an integration test:
  `find --format ids | xargs -n1 crm show`;
  `stale --format ids | xargs -n1 crm context`;
  `contact ls --format json | jq` null-email selection;
  `deal ls --rotting --format ids | xargs -n1 crm deal show`.
- Docs describe only what exists; every skill claim maps to a distinguishing
  test (constitution: Build and packaging / docs).

**Read first** (style-transfer-map.md):
- "post-write hook": `crm.cli/src/hooks.ts`.
- "skill, AGENTS.md, help text": `crm-cli/AGENT.md`,
  `crm.cli/skills/SKILL.md`.

**Acceptance criteria** (runnable):
```
CRM_POST_WRITE_HOOK='cat > $T/payload.json' crm org add "Hooked"   # exit 0
jq -e '.event=="post-write" and .verb=="add" and .entity=="org"' $T/payload.json  # exit 0
CRM_POST_WRITE_HOOK='exit 1' crm org add "Hook fails"              # exit 0 (hook status ignored)
CRM_POST_WRITE_HOOK='cat > $T/read.json' crm org ls                # exit 0; $T/read.json absent (reads never fire)
crm org add --help                                                 # exit 0; stdout contains "Example:"
test -f skills/crm/SKILL.md                                        # exit 0
```
- The command-tree walk test fails on any leaf command with an empty
  `Example:`, any missing alias, or any verb absent from `SKILL.md`.
- All four §10 recipe tests pass end-to-end. The four gates exit 0.

**Depends on**: T10b, T10c.

---

## T12 — Export: flat (JSON/CSV) and markdown tree — [#16](https://github.com/mecattaf/crm/issues/16)

**Goal**: All egress. Flat entity export for backup/inspection and the
git-diffable markdown tree projection, regenerated wholesale from one write
path.

**Delivers** (spec citations):
- `crm export (orgs|contacts|deals|interactions|all) --format json|csv`
  (spec §5 export): `all` is JSON-only, one object keyed by entity (`csv` on
  `all` → exit 1 listing the accepted set); CSV writer discipline that the
  T14 roundtrip will enforce — proper escaping, ` || ` separator survival,
  embedded newlines, NULL vs empty string, unicode.
- `crm export tree [dir]` (spec §5 export): one markdown file per entity
  (`contacts/<slug>.md` with YAML frontmatter — id, org, email, provenance —
  timeline as prose with relative transcript links), one generated
  `index.md`, orientation README at the root; strictly derived, regenerated
  wholesale (a deleted entity's file disappears on regeneration); never
  file-copied index directories. With no argument the destination is `tree/`
  under the base of convention 3.

**Read first** (style-transfer-map.md):
- "import / export (flat)" (export half):
  `crm.cli/src/commands/importexport.ts`,
  `crm.cli/test/import-export.test.ts` (the assertions the CSV writer must
  survive).
- "export tree": `crm.cli/src/export-fs.ts`, `crm.cli/src/fuse-json.ts`
  (invert: JSON entity files, `_by-*` copy dirs, everything FUSE/daemon).

**Acceptance criteria** (runnable):
```
crm export contacts --format json > $T/contacts.json    # exit 0; complete records, [] when empty
crm export contacts --format csv > $T/contacts.csv      # exit 0; header row; quoting per test fixtures
crm export all --format json | jq -e 'keys==["contacts","deals","interactions","orgs"]'  # exit 0
crm export all --format csv                             # exit 1; accepted set on stderr
crm export tree $T/tree                                 # exit 0
test -f $T/tree/index.md && test -f $T/tree/README.md   # exit 0
grep -l "^---$" $T/tree/contacts/*.md                   # frontmatter present
crm export tree                                         # exit 0; no argument writes under $T/tree (db-dir default)
crm contact archive ana && crm export tree $T/tree      # regeneration reflects lifecycle state
```
- CSV fixture tests cover escaping, embedded newlines, NULL-vs-empty,
  unicode, ` || ` survival. The four gates exit 0.

**Depends on**: T10a.

---

## T13 — `dupes` scoring and transactional `merge`; merge persona — [#17](https://github.com/mecattaf/crm/issues/17)

**Goal**: Data-quality tooling: advisory read-only duplicate detection with
auditable named reasons, and the six-step single-transaction merge for
contacts and orgs. Lands the merge persona.

**Delivers** (spec citations):
- `crm dupes [--type contact|org] [--threshold 0.3] [--limit N]` (spec §5
  dupes and merge): strictly read-only; `max(normalized-Levenshtein,
  Dice-bigram)` on `name_norm`, rune-based; named reasons with weights
  capped at 1.0 (contacts: identical name_norm 0.5, similar name 0.4,
  shared non-free email domain 0.15 with gmail/yahoo/hotmail/outlook
  excluded; orgs: similar name 0.4, same registrable website domain 0.2);
  output rows `{left, right, score, reasons[]}`.
- `crm contact merge <winner> <loser>` and `crm org merge` (spec §5): one
  transaction — (1) loser's UNIQUE-column presence archived first,
  (2) COALESCE scalars winner-first, (3) both provenance columns
  concatenated with ` || `, (4) references repointed (contact:
  `interaction_people` INSERT OR IGNORE + delete, `deals.contact_id`,
  `contact_links` three-step winner↔loser-delete / UPDATE OR IGNORE /
  leftover-delete; org: `contacts.org_id`, `interactions.org_id`,
  `deals.org_id`), (5) loser soft-archived, (6) surviving record echoed.
  Ambiguous refs never accepted (spec §2).
- Persona: `scenario_merge_test.go` — two mutually-linked duplicates that
  also share a third contact's link merge cleanly in one transaction.

**Read first** (style-transfer-map.md):
- "dupes and merge": `crm.cli/src/commands/dupes.ts`,
  `crm.cli/src/commands/contact.ts` merge, `crm.cli/spec/data-model.md`
  (anti-pattern: crm.cli's transactionless merge).

**Acceptance criteria** (runnable):
```
crm dupes --type contact --format json | cat   # exit 0; rows carry reasons[], never a bare number
crm dupes                                      # exit 0; db row counts unchanged (asserted read-only)
crm contact merge c1 c2                        # exit 0; echoes surviving c1 with merged links
crm contact show c2                            # exit 0 via id rung; archived_at set (loser soft-archived)
crm contact merge c1 amb                       # exit 3 when "amb" is ambiguous; destructive verbs never guess
```
- Distinguishing tests: two contacts sharing only `@gmail.com` do NOT get
  the email-domain reason; provenance of both rows survives concatenated;
  the mid-merge invariant is transactional (a forced failure leaves both
  rows untouched). `scenario_merge_test.go` passes. The four gates exit 0.

**Depends on**: T10a (archive machinery), T08 (contact_links). Sequenced
after T12.

---

## T14 — Import (orgs, contacts) with idempotence and roundtrip — LAST implementation task — [#18](https://github.com/mecattaf/crm/issues/18)

**Goal**: The only ingress, landed last so the fully proven tool receives
data, never the reverse. Idempotent search-before-create import for orgs and
contacts, the export→import roundtrip test closing the loop with T12, and the
import-run-twice persona.

**Delivers** (spec citations):
- `crm import (orgs|contacts) <file.csv> --source <name>` (spec §5 import):
  mandatory `--source`; match on org `name_norm` / contact lowercased email
  with `name_norm` fallback, run inside the file transaction (constitution:
  Data hygiene sole exception); default skip on match (second run 100%
  skipped, counts unchanged); `--update` patches matched rows and appends
  provenance with ` || `; `--dry-run` prints the plan without writing;
  `--skip-errors` per-row savepoints converting failures to counted skips;
  `--reject-file` with line numbers; `--create-missing` stub orgs stamped
  `auto-created by crm import` and announced on stderr (the single
  sanctioned auto-create); summary `Imported: N, updated: N, skipped: N,
  errors: N` on stderr; created refs stream to stdout; orgs-before-contacts
  documented order. A missing input file is exit 2 (convention 2).
- Committed fixture CSVs mirroring the investor-crm export header shape
  (anonymized) — `testdata/import/orgs.csv`, `contacts.csv`, `bad.csv`,
  `unknown-org.csv` — so every assertion below runs on a fresh checkout.
- Export→import roundtrip test (constitution: Testing doctrine): export
  fixtures through `crm export --format csv`, re-import, row-by-row struct
  equality across escaping, ` || `, newlines, NULL-vs-empty, unicode.
  Deals/interactions have no import — one-way, documented.
- Persona: `scenario_import_twice_test.go` — second run all-skipped,
  provenance appended on `--update`.

**Owner verification** (NOT an acceptance criterion, NOT a gate — the files
live outside the repo and no assertion can be made about them on a fresh
checkout): before the real load, the owner runs
`crm import orgs ~/mecattaf/investor-crm/organizations.csv --source
investor-crm --dry-run` and the contacts equivalent and eyeballs the plan.
The actual load is the owner's action, not this task's.

**Read first** (style-transfer-map.md):
- "import / export (flat)": `crm.cli/src/commands/importexport.ts`,
  `crm.cli/test/import-export.test.ts`,
  `sodimo-crm/PIPEDRIVE-MIGRATION.md` (dependency-safe order, identity
  rules, reject worklist).

**Acceptance criteria** (runnable, against the committed fixtures):
```
crm import orgs testdata/import/orgs.csv                         # exit 1; --source is mandatory
crm import orgs testdata/import/nope.csv --source test           # exit 2; input file not found
crm import orgs testdata/import/orgs.csv --source test           # exit 0; created refs on stdout; summary on stderr
crm import orgs testdata/import/orgs.csv --source test           # exit 0; "Imported: 0, updated: 0, skipped: <all>, errors: 0"
crm import contacts testdata/import/contacts.csv --source test --dry-run
                                                                 # exit 0; no rows written (count asserted)
crm import contacts testdata/import/bad.csv --source test --skip-errors --reject-file $T/rej.csv
                                                                 # exit 0; rejects carry line numbers
crm import contacts testdata/import/unknown-org.csv --source test
                                                                 # exit 2; prints the exact org add command
crm import contacts testdata/import/unknown-org.csv --source test --create-missing
                                                                 # exit 0; stub org announced on stderr, stamped provenance
```
- Roundtrip test passes for orgs and contacts;
  `scenario_import_twice_test.go` passes. The four gates exit 0.

**Depends on**: T12 (roundtrip needs export), T13.

---

## T15 — Graduation prep: buildGoModule derivation and install docs (no dotfiles move) — [#19](https://github.com/mecattaf/crm/issues/19)

**Goal**: Prepare everything the dotfiles graduation needs without
performing the move: a working `buildGoModule` derivation proven by
`nix build` in this repo, the version wiring verified through it, and the
install/graduation documentation.

**Delivers** (spec citations, constitution: Build and packaging):
- `nix/package.nix`: `buildGoModule`, `CGO_ENABLED=0`, `-s -w` ldflags with
  the one `-X main.version` target, `crm --version` as the
  `installCheckPhase`; minimal `flake.nix` wiring it so the derivation is
  provable here before it moves.
- Version test tightened to assert the exact value the derivation injects
  (not a prefix, not `dev`) — the nix-build twin of T01's `0.0.0-test`
  sentinel assertion.
- `docs/INSTALL.md`: how the derivation graduates into dotfiles, the db
  bootstrap (`crm init`), `$CRM_DB`/`$CRM_POST_WRITE_HOOK` environment
  wiring, and the skill installation path. Docs describe only what exists.
- No git machinery, no release ceremony, no changelog (constitution). The
  dotfiles move itself is explicitly out of scope.

**Read first** (style-transfer-map.md):
- "packaging": `crm-cli/.goreleaser.yml` (evidence only that CGO-off
  cross-builds cleanly), `crm-cli/cmd/crm/main.go` version wiring as the
  anti-pattern (dual variable reporting `dev`).

**Acceptance criteria** (runnable):
```
nix build .#crm                                  # exit 0 (installCheckPhase ran crm --version)
./result/bin/crm --version                       # exit 0; prints the derivation's version value exactly
test -f docs/INSTALL.md                          # exit 0
```
- The four gates exit 0.

**Depends on**: T14.

---

## Dependency graph

The table below is authoritative; the sketch is a reading aid and must never
disagree with it.

```text
main spine   T01 → T02a → T02b → T03 → T04 → T05a → T05b → T07 → T10a
                                                                   → T10b → T11
branches     T02b → T06 ──────────────────────────────────────→ T07
             T05b → T08 ─────────────────────────────────────→ T10a
             T05a + T07 → T10c ──────────────────────────────→ T11
             T05b + T07 → T09
             T10a → T12
             T10a + T08 → T13
             T12 + T13 → T14 → T15
```

Edges, explicitly:

| task | depends on |
|---|---|
| T01  | — |
| T02a | T01 |
| T02b | T02a |
| T03  | T02b |
| T04  | T03 |
| T05a | T04 |
| T05b | T05a |
| T06  | T02b |
| T07  | T04, T05b, T06 |
| T08  | T05b |
| T09  | T05b, T07 |
| T10a | T07, T08 |
| T10b | T10a |
| T10c | T05a, T07 |
| T11  | T10b, T10c |
| T12  | T10a |
| T13  | T08, T10a |
| T14  | T12, T13 |
| T15  | T14 |

Issue order T01, T02a, T02b, T03, T04, T05a, T05b, T06, T07, T08, T09, T10a,
T10b, T10c, T11, T12, T13, T14, T15 respects every edge; executing strictly
in that sequence is always safe.
