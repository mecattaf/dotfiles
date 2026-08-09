# crm — personal git-backed CRM

`crm` is a single-user CRM as one static Go binary (`modernc.org/sqlite`,
`CGO_ENABLED=0`, cobra). Two audiences, one surface: Tom at a shell, and agents
driving the same CLI via the `/crm` skill. There is no other interface — no
server, no API, no TUI, no web UI.

Tool source lives in the public dotfiles; data lives in the private notes repo.

- Database: `~/mecattaf/notes/crm/crm.db`. Resolution order, exactly:
  `--db` flag > `$CRM_DB` > that default.
- Transcripts and long notes: `~/mecattaf/notes/crm/transcripts/YYYY/` —
  markdown files, date-first slug names (`2026-07-29-nick-dupont-call.md`).
  The db row stores the notes-repo-relative path; the file is the evidence of
  record. Summaries never replace transcripts.
- The binary never touches git. Commit hygiene, ASR kickoff, and any other
  automation hang off the post-write hook (§8) — declared in the user's
  environment, not tool behavior.

## 1. Data model

Universal conventions: integer autoincrement `id`; `created_at`/`updated_at`
as RFC3339 UTC TEXT generated in Go; `archived_at` nullable TEXT (soft archive
is the default lifecycle); dates are `YYYY-MM-DD` TEXT; `name_norm` companion
columns (NFKD, strip combining marks, casefold) recomputed on every name
write; email lowercased on write; LinkedIn stored as a bare handle extracted
from any URL form, URL reconstructed at render time. Provenance is
first-class: `provenance_sources`, `provenance_details`, `relationship_hint`;
repeatable source/detail values join with ` || ` and always append, never
overwrite.

### orgs

`id, name, name_norm, category, website, linkedin, location, focus, context,
relationship_hint, provenance_sources, provenance_details, created_at,
updated_at, archived_at`. `name_norm` UNIQUE among live rows. `context` is the
agent-maintained rolling dossier; `relationship_hint` is how Tom knows them.

### contacts

`id, name, name_norm, org_id → orgs (real FK, never a text company column),
job_title, email, phone, linkedin, location, context, relationship_hint,
provenance_sources, provenance_details, created_at, updated_at, archived_at`.
Exactly ONE email, ONE phone, ONE linkedin — an extra address is prose in
`context`. `email` UNIQUE among live rows (byte-exact index; the application
lowercases before insert).

### interactions

`id, kind ∈ {call, meeting, email, message, note}, occurred_on (date),
summary, body, transcript_path, org_id → orgs (nullable), deal_id → deals
(nullable), created_at, updated_at, archived_at`. Participants are
many-to-many contacts via `interaction_people(interaction_id, contact_id)`,
UNIQUE pair. An interaction must link at least one of: a participant, an org,
a deal (application-enforced). `transcript_path` is notes-repo-relative and
must exist on disk at write time. The immutable event log: `summary` is
per-event and never a dossier.

Timeline composition is merged at read, never materialized: a contact's
timeline = interactions via the junction; an org's timeline = interactions
with `org_id` set OR any participant belonging to the org; a deal's timeline =
interactions with `deal_id` set, interleaved with its stage moves.

### contact_links

Person-to-person relationships. `id, contact_id → contacts,
related_contact_id → contacts, link_type (free text: "colleague",
"referred by", "mentor", …), note, created_at`. Stored directed (the type may
be asymmetric), read from both ends — a link appears in both contacts' `show`
and `context` output. `CHECK (contact_id <> related_contact_id)`;
UNIQUE `(contact_id, related_contact_id, link_type)`. Contacts only — there
are no org-to-org links.

### pipelines and stages

Multiple named pipelines (a fundraise, a customer motion, a job hunt…), each
with its own ordered stages. Both are database rows managed through CLI verbs
— not config files. `pipelines`: `id, name, name_norm, position, timestamps,
archived_at`; live `name_norm` UNIQUE. `stages`: `id, pipeline_id, name,
name_norm, position, rot_days (nullable; NULL = never rots), timestamps,
archived_at`; live `(pipeline_id, name_norm)` UNIQUE. Stage names resolve
within their pipeline, not globally.

### deals

Stage-only opportunities: `id, title, title_norm, org_id (nullable),
contact_id (nullable), pipeline_id, stage_id, status ∈ {open, won, lost},
outcome_reason (free text), closed_at (nullable; set by win/lose, cleared by
reopen), stage_changed_at, created_at, updated_at, archived_at`. At least one
of org/contact required (CHECK). No money, amount, currency, probability, or
forecast columns of any kind. `stage_id` must belong to `pipeline_id`
(application-enforced, doctor-checked). `stage_changed_at` and `closed_at`
are RFC3339 UTC datetimes (CHECK-enforced). A deal is rotting when its stage
has a `rot_days` and `now − stage_changed_at` exceeds `rot_days` days
(julianday arithmetic, both operands UTC).

### stage_moves

Every stage transition is deal data with real columns — never prose parsed
back out of a summary: `id, deal_id, from_stage_id (nullable), to_stage_id,
moved_at, note`. `moved_at` is an RFC3339 UTC datetime (CHECK-enforced) —
the same instant written to `deals.stage_changed_at`, one format. Deal
creation writes an opening row with `from_stage_id` NULL. A move to the current stage is rejected with a distinct error (exit 4,
"already in stage X"); the DDL backs this with
`CHECK (from_stage_id IS NULL OR from_stage_id <> to_stage_id)`.

## 2. Reference resolution

One shared resolver, applied at every ref site; every ref flag is a string.
Ladder, each rung a SQL query with `LIMIT 2`, first rung with a hit wins:

1. prefixed id — `c12`, `o4`, `i9`, `d3`, `p2`, `s7` (wrong entity prefix for
   the site = exit 2 with a clear message)
2. bare numeric id
3. exact email, lowercased (contacts)
4. exact linkedin handle (contacts, orgs; URL forms normalized first)
5. exact `name` (deals: `title`)
6. exact `name_norm`
7. substring on `name_norm`

Rungs 1–2 reach archived rows (so `show`/`unarchive` work); rungs 3–7 match
live rows only. Two hits on any rung = exit 3 — never first-match — with a
candidate list on stderr, each line pasteable back as a ref:
`c12  Martin Lévy  m@x.fr  @Acme`. A destructive verb never accepts an
ambiguous ref, even with `--confirm`. Stage refs resolve by prefixed id
(`s7`) or by name within the deal's/named pipeline (exact `name_norm`, then
substring). Resolution failure on a
link flag prints the exact create command to run; nothing is ever auto-created
on a failed resolution (sole exception: `import --create-missing`, §5 import).

## 3. Exit codes

| code | meaning |
|---|---|
| 0 | success |
| 1 | generic / validation / usage |
| 2 | not found (including: a ref whose prefix names another entity; no database at the resolved path) |
| 3 | ambiguous ref (candidates on stderr) |
| 4 | constraint / duplicate / idempotent conflict |

Sentinel errors map to codes in one `ExitCode` switch; one `os.Exit` site;
every code provoked end-to-end by at least one integration test. Error voice:
one line on stderr, `crm: error: <what> "<value>" — <who/why>, <what to do>`.
Duplicates name the owning row (`duplicate email "x" — already on contact 17
(Nick Dupont)`). Not-found carries a remedy (`try: crm find nick`).

## 4. Output contract

- stdout = data, stderr = messages (confirmations, prompts, notices, errors).
  Zero exceptions; only the output formatter writes to stdout.
- No flags needed: human table when stdout is a TTY, JSON when piped.
  `--format` is the explicit override, drawn from `table|json|csv|ids`: every
  verb accepts `table` and `json`; `ids` only on verbs whose rows carry refs;
  `csv` only on flat `export` (`export all` is JSON-only). An unrecognized or
  unsupported value is a hard usage error listing that verb's accepted set.
- `ids` emits one prefixed ref per line (`c12`, `o4`, `i9`, `d3`, `p2`, `s7`)
  — the composition primitive; the resolver accepts these back (§2).
- Tables: declarative per-entity column projection (curated subset), columns
  where every row is empty are elided, rune-count widths, no rule line when
  piped. Entity JSON carries the complete record: stable key set, explicit
  `null`, a derived `ref` field (`"c12"`), raw stored values (display
  coercions live only in renderers). Report verbs (`find`, `context`,
  `status`, `stale`, `dupes`, `doctor`, `import`) define their own documented
  shapes in §5.
- Empty collections serialize as `[]`, never `null` — asserted at the byte
  level.
- Every mutation echoes the full resulting record through the normal
  formatter, as a one-element array — `add`/`edit`/`move`/`archive`/
  `unarchive` produce the same shape as `ls`; `delete` echoes the pre-delete
  record with a `deleted: true` marker, since no row survives it. Stage
  mutations echo the stage record (`ref` `s7`); `relate`/`unrelate` echo the
  first-named contact's full record, links included.
- JSON is pretty-printed on a TTY, compact when piped.

## 5. Verb surface

Grammar: noun-first for entity verbs (`crm org add`, `crm deal move`);
top-level verbs for cross-entity operations (`init`, `log`, `context`, `find`,
`status`, `stale`, `import`, `dupes`, `export`, `doctor`). Aliases: `org`→`o`,
`contact`→`c`, `interaction`→`i`, `deal`→`d`, `pipeline`→`p`, `ls`→`list`;
singular and plural nouns both accepted. Every verb's help carries an
`Example:` block; enum flag help is generated from the enum slices.

Positional sugar on the hottest verb: `crm log call nick "quick sync"`
desugars to `crm log --kind call --with nick --summary "quick sync"`; the
flag form is canonical and the only one the skill teaches. One polymorphic
reader exists for piped prefixed refs: `crm show <prefixed-ref>` dispatches
on the prefix (`crm show c12` ≡ `crm contact show c12`); it accepts prefixed
refs only.

### init

The ONLY verb that creates anything: the database (running all migrations),
`notes/crm/`, `transcripts/YYYY/` for the current year, and the orientation
`README.md` beside the data. Idempotent; echoes the resolved db path. Every
other verb errors on a missing database, naming the resolved path:
`crm: error: no database at /home/tom/mecattaf/notes/crm/crm.db (run 'crm init')`.

    crm init

### orgs

    crm org add "Kima Ventures" --category vc --website kima.vc \
        --location Paris --hint "met at DLD" --source notes/2026-07-12.md
    crm org show kima
    crm org ls [--category vc] [--all] [--limit N]
    crm org edit kima --focus "pre-seed, 2/week pace" --context-append "…"
    crm org archive kima     # and unarchive
    crm org delete kima --confirm
    crm org merge o4 o17     # winner first (§5 dupes and merge)

`add` flags: `--category --website --linkedin --location --focus --context
--hint --source --detail`. `edit` takes the same flags with true PATCH
semantics — a field is written only when its flag was typed; `--flag ""`
clears, and clearing writes SQL NULL — the empty string is never stored in
any nullable column (cleared fields serialize as JSON `null`); a no-op edit
returns the record without touching `updated_at`.
`--context-append` appends to the dossier with a blank-line separator instead
of replacing it. `--source`/`--detail` always append to the provenance columns
with ` || `.

### contacts

    crm contact add "Nick Dupont" --org kima --title Partner \
        --email nick@kima.vc --linkedin nickdupont \
        --hint "intro from Jean" --source notes/2026-07-12.md
    crm contact show nick
    crm contact ls [--org kima] [--all] [--limit N]
    crm contact edit nick --phone +33612345678 --context-append "prefers WhatsApp"
    crm contact relate nick jean --type "referred by" --note "Jean made the intro"
    crm contact unrelate nick jean [--type "referred by"]
    crm contact archive nick     # and unarchive
    crm contact delete nick --confirm
    crm contact merge c12 c31

`add` flags: `--org --title --email --phone --linkedin --location --context
--hint --source --detail`. Setting a field to the value it already holds
(post-normalization) is a silent no-op, exit 0; only a value owned by a
*different* live record errors (exit 4, naming the owner). `unrelate` without
`--type` removes all links between the pair (either direction); with `--type`,
just that link. Links render in `show` and `context` from both ends.

### log (interaction creation)

    crm log --with nick --with jean --kind call \
        --summary "intro call; wants the deck before Friday" \
        --date 2026-07-29 --transcript transcripts/2026/2026-07-29-nick-dupont-call.md
    crm log --org kima --kind note --summary "fund II closed at 60M" \
        --body-file - < clipping.txt
    crm log --deal d3 --with nick --kind email --summary "sent the deck"

`--with` repeats (deduplicated — repeating a participant is a silent no-op);
`--kind` required, from the enum; `--summary` required; `--date` defaults to
today local; `--body-file <path>|-` reads long prose; `--transcript` is
validated to exist on disk before the write; `--org`/`--deal` attach the
interaction to an org and/or deal. At least one of `--with`/`--org`/`--deal`
required. All refs resolve before the transaction opens; the interaction row
and its junction rows commit atomically.

### interactions (read/repair)

    crm interaction show i43
    crm interaction ls [--with nick] [--org kima] [--deal d3] [--kind call] [--all] [--limit N]
    crm interaction edit i43 --summary "corrected: wants deck by Thursday" \
        [--date …] [--kind …] [--transcript …] [--body-file …] \
        [--add-with <ref>] [--rm-with <ref>] [--org <ref>] [--deal <ref>]
    crm interaction archive i43     # and unarchive
    crm interaction delete i43 --confirm

Listings order `occurred_on DESC, id DESC` — deterministic, id tiebreaker.
`edit` re-validates the ≥1-link invariant after applying
`--rm-with`/`--org`/`--deal`: a patch that would leave an interaction with no
participant, org, or deal is rejected (exit 4, naming what would remain).

### pipelines and stages

    crm pipeline add "Seed raise"
    crm pipeline ls [--all]
    crm pipeline show p1              # stages in order with rot thresholds
    crm pipeline rename p1 "Seed round"
    crm pipeline archive p1           # and unarchive; delete --confirm
    crm stage add p1 "contacted" --rot 14 [--after "sourced" | --first]
    crm stage rename p1 contacted "first contact"
    crm stage reorder p1 sourced contacted pitched "term sheet" closed
    crm stage set-rot p1 pitched 7    # or: none
    crm stage archive p1 sourced      # and unarchive; delete --confirm

`stage add` appends last by default. `stage reorder` takes the complete new
order and applies it in one transaction; a partial list is an error listing
the missing stages. `set-rot … none` clears the threshold. An archived stage
cannot receive moves. Deleting a stage that any deal occupies (live or
archived) *or* that any `stage_moves` row references is refused with both
counts — once any move has touched a stage, it is effectively archive-only.

### deals

    crm deal add "Kima seed ticket" --pipeline "Seed raise" --org kima \
        --contact nick [--stage sourced]
    crm deal show d3          # includes stage history and timeline
    crm deal ls [--pipeline p1] [--stage pitched] [--status open] [--rotting] [--all] [--limit N]
    crm deal edit d3 --title "Kima seed" [--org …] [--contact …]
    crm deal move d3 pitched --note "deck sent 07-29, partner meeting booked"
    crm deal win d3 --reason "led the round"
    crm deal lose d3 --reason "passed — too early"
    crm deal reopen d3
    crm deal archive d3       # and unarchive; delete --confirm

`add` requires `--pipeline` and at least one of `--org`/`--contact`; the stage
defaults to the pipeline's first stage; creation writes the opening
`stage_moves` row and sets `stage_changed_at`. `ls --stage` requires
`--pipeline` (usage error, exit 1, without it) — stage names have no global
scope. `move` resolves the stage name
within the deal's pipeline, rejects no-op moves with a distinct exit-4 error,
records the move row, and updates `stage_id` + `stage_changed_at` in one
transaction. `win`/`lose` set `status`, `outcome_reason` (`--reason` optional
on win, expected on lose), and `closed_at`; `reopen` returns a closed deal to
`open` and clears `closed_at` while *preserving* `outcome_reason` as the
record of the last outcome (the next `win`/`lose` overwrites it). `edit`
never changes stage or status — stage history lives complete in
`stage_moves`; status history is `status` + `closed_at` + `outcome_reason`.
`ls --rotting` lists open deals sitting past their stage's `rot_days`, most
overdue first, with `days_in_stage` and the threshold in the output.

### context

    crm context nick
    crm context kima

The one-call briefing; accepts a contact or org ref. A document, not a row
set: `# Nick Dupont (c12)` header; profile lines including
`relationship_hint`, the `context` dossier, and provenance ("how do I know
this person" comes first); org block; contact links (both directions); open
deals with stage and days-in-stage; then `Timeline (N):` — merged, newest
first, `i43  2026-07-29  call  summary`, transcript path rendered prominently
per entry. Empty sections are omitted entirely; section headings carry counts.
Timeline capped at 20 (`--limit N`, `--all`). JSON form: one object
`{contact|org, org?, links, deals, timeline}`. One assembler feeds both
renderers. Cost ladder for agents: `show` (cheap) → `context` (everything).

### find

    crm find "nick kima"
    crm find dataroom --type interaction --limit 5

Cross-entity FTS5 search, bm25-ranked, globally rank-merged (never
concatenated in entity order) into uniform rows `{type, ref, name, detail,
rank}` — `detail` disambiguates (contact → email/org; org →
category/location; interaction → date + kind; deal → pipeline/stage). Raw
bm25 scores are corpus-relative and not comparable across the four indexes,
so the merge key is normalized per table: divide each hit's bm25 score by
that table's best (most negative) score for the query, then sort globally on
the normalized score with `type, id` as tiebreakers — deterministic, and a
strong match in one entity outranks a weak match in another (the
distinguishing test: an exact-name contact outranks an interaction that
merely mentions the token). Query
text is tokenized, each token escaped as a quoted phrase, last token
prefix-starred; raw `@ . - :` never reach FTS syntax. Contacts of a matched
org are unioned in at query time (no denormalized cache). Archived rows
excluded. Default cap 20, `--limit` to change; `--type
(org|contact|interaction|deal)` validated early.

### status

    crm status

Zero-argument dashboard: entity counts (orgs / contacts / interactions / open
deals), last-logged date with days-ago, never-contacted count, stale count
(90d), rotting-deal count, and the resolved db path — a mis-set `$CRM_DB` is
visible at a glance. All aggregates COALESCE to 0 on an empty db. Doubles as
the agent's session-opening call.

### stale

    crm stale [--days 90] [--type contact|org] [--recent-first]

Contacts (default) or orgs with no live interaction in N days. LEFT-JOIN
shape so never-contacted rows are included, rendered `last: never`. For orgs,
"interaction" means the full org-timeline definition (§1): `MAX(occurred_on)`
over the union of org-tagged interactions and interactions of any of the
org's live contacts — an org whose only touch was logged via a participant is
not stale. Default order: never-contacted first, then oldest-contact first,
id as tiebreaker; `--recent-first` reverses. `--format ids | xargs -n1 crm
context` is the morning-outreach recipe.

### import

    crm import orgs ~/mecattaf/investor-crm/organizations.csv --source investor-crm
    crm import contacts ~/mecattaf/investor-crm/contacts.csv --source investor-crm \
        [--dry-run] [--skip-errors] [--update] [--reject-file rejects.csv] [--create-missing]

Idempotent search-before-create: match on org `name_norm` / contact lowercased
`email` (fallback `name_norm`); default on an existing match is *skip*, so
re-running is idempotent by definition — the acceptance test is a second run
reporting 100% skipped with row counts unchanged. `--source` is mandatory
(provenance is never optional on import). `--update` patches matched rows and
*appends* provenance with ` || `. `--dry-run` prints the plan without
writing. `--skip-errors` converts per-row failures into counted skips
(per-row savepoints inside the file transaction). `--reject-file` captures
failed rows with line numbers. `--create-missing` is the single sanctioned
auto-create gate: a contact row naming an unknown org creates a stub org
stamped `provenance_sources = auto-created by crm import`, announced on
stderr. Summary always ends on stderr: `Imported: N, updated: N, skipped: N,
errors: N`; created refs stream to stdout.

### dupes and merge

    crm dupes [--type contact|org] [--threshold 0.3] [--limit N]
    crm contact merge c12 c31
    crm org merge o4 o17

`dupes` is strictly read-only: pairwise scoring with
`max(normalized-Levenshtein, Dice-bigram)` on `name_norm` (rune-based), plus
named reasons accumulated into a capped weighted score, per type — contacts:
identical `name_norm` 0.5, similar name 0.4, shared non-free email domain
0.15 (gmail/yahoo/hotmail/outlook excluded); orgs: similar name 0.4, same
website registrable domain 0.2. (Same-email and same-live-org-name pairs
cannot exist — the partial UNIQUE indexes forbid them, so they are not
reasons.) Output rows `{left, right, score, reasons[]}` — auditable, never
a bare number.

`merge` keeps the first, absorbs the second, in one transaction: (1) archive
the loser's presence on UNIQUE-constrained columns before touching the winner;
(2) COALESCE scalars winner-first; (3) concatenate both provenance columns
with ` || ` — merge is where provenance accumulates, never chooses;
(4) repoint references per entity — contact merge: `interaction_people` via
`INSERT OR IGNORE` of winner rows + delete of loser rows; `deals.contact_id`;
`contact_links` in three steps: first delete any winner↔loser links (the
self-link CHECK makes them unrepointable), then `UPDATE OR IGNORE` each
endpoint column from loser to winner (the
`(contact_id, related_contact_id, link_type)` UNIQUE swallows duplicates),
then delete the loser's leftover link rows; org merge: `contacts.org_id`,
`interactions.org_id`, `deals.org_id` (orgs have no links table);
(5) soft-archive the loser (reversible); (6) echo the surviving record.

### export

    crm export contacts --format json > contacts.json
    crm export all --format json > backup.json
    crm export tree [~/mecattaf/notes/crm/tree]

Flat export: `(orgs|contacts|deals|interactions|all)` as JSON or CSV
(`--format json|csv`; `all` is JSON-only, one object keyed by entity). Deals
and interactions export is one-way (backup/inspection) — `import` exists only
for orgs and contacts. The
tree export writes a git-diffable markdown projection: one file per entity —
`contacts/<slug>.md` with YAML frontmatter (id, org, email, provenance) and
the timeline as prose with relative links to transcripts — plus one generated
`index.md` and the orientation README at the root. Strictly derived, one write
path, regenerated wholesale; never file-copied index directories. `git log -p`
on the tree shows what changed about a person in reviewable English.

### doctor

    crm doctor [--rebuild-fts]

Integrity report: `PRAGMA integrity_check`, `PRAGMA foreign_key_check`,
per-table FTS `integrity-check` + row-count comparison, journal-mode assertion
(fails loudly if the file is not `delete`), every `transcript_path` resolves
on disk, every deal's `stage_id` belongs to its `pipeline_id`, every
interaction has ≥1 link, and the `user_version` report. `--rebuild-fts` runs
FTS `rebuild` per table in a transaction — the repair path after any bulk
operation or bad merge.

### archive / unarchive / delete (all entities)

`archive` and `unarchive` exist for every entity; `ls --all` genuinely
includes archived rows, visibly marked. Archiving an already-archived row is
exit 4 (idempotent conflict — a retrying agent learns it already succeeded);
a missing row is exit 2. `delete` is hard deletion: requires `--confirm`; on
a TTY without the flag, prompts on `/dev/tty` naming the *resolved* record
(`Delete contact "Nick Dupont" (c17)? [y/N]`); non-interactive without the
flag, refuses (`refusing to delete without --confirm (non-interactive)`).
Never batched — piped ids still fail per-invocation confirmation. Every hard
delete pre-checks all blocking references and refuses with a counted message
(`contact appears in 4 interactions — archive instead`), exit 4, never raw
driver text. The blocking references, exhaustively: org ← contacts, deals,
interactions; contact ← interaction_people, deals, contact_links (either
endpoint); pipeline ← stages, deals; stage ← deals, stage_moves (either
endpoint); deal ← interactions (its own stage_moves cascade with it);
interaction ← nothing (its junction rows cascade). One integration test per
blocking reference provokes the exit-4 refusal end-to-end.

### --version

`crm --version` prints the version injected at build time into exactly one
variable.

## 6. Search internals

FTS5 external-content tables per searchable entity (orgs, contacts,
interactions, deals), maintained by AFTER INSERT/UPDATE/DELETE triggers
(update = command-form delete + insert; trigger column lists match FTS column
order exactly). Queries join the FTS table to the base table on rowid and
order by `bm25(...)` ascending — never `id IN (subquery)`, which discards
rank. Archived rows are excluded in the outer WHERE (they stay in the index
and reachable by explicit ref).

## 7. Transcription input contract

A recorded call arrives as a WAV (≈up to 60 minutes). An external pipeline —
entirely outside this tool — produces a timestamped, speaker-diarized markdown
transcript under `notes/crm/transcripts/YYYY/`. The CRM's whole involvement:

    crm log --kind call --with <ref> --transcript <path> --summary "<agent-written summary>"

`--transcript` validates existence; the row stores the repo-relative path; the
file remains the evidence of record.

## 8. Post-write hook

`$CRM_POST_WRITE_HOOK`, when set, names a shell command run after every
successful mutation — the environment is the tool's only configuration
surface; there is no config file. JSON payload on stdin (`{event: "post-write", verb,
entity, refs, records, db_path}`), 30 seconds timeout, exit status ignored —
fire-and-forget, never blocks or fails the verb, stderr passed through. This
is the entire automation surface: the git-commit seam
(`git -C ~/mecattaf/notes add crm/ && git commit -m "crm: $verb"`), the
ASR-kickoff seam, the tree-export regeneration seam. Unset = no-op. Read
verbs never fire it.

## 9. Agent surface

- `/crm` skill, situation-shaped, shipped with the tool and updated in the
  same commit as any verb change. Organized by user situation with numbered
  call sequences — *just got off a call* → `find` → `contact add` if absent →
  `log --kind call --with … --transcript …` → `edit --context-append`;
  *about to talk to X* → `crm context X`; *mentions a new company* →
  `org add` with provenance flags. Includes: one runnable example per verb,
  the exit-code table, the stdout/stderr rule, the transcript protocol, and
  the dossier discipline (append, never overwrite; `interactions.summary` is
  immutable per-event; `context` is the mutable current understanding).
  Exhaustive flag reference lives in a sibling file (progressive disclosure);
  the skill says "run `crm <verb> --help`" instead of duplicating flags.
- Closing "Tips for AI Agents" block: prefer `context` over show+ls; refs
  accept name/email/id — don't look up ids first; exit 3 = ambiguous — re-ask
  the human, never guess; long prose goes through `--body-file`/`--transcript`,
  never 5k words into `--summary`; `find` is bm25 — real words, not globs;
  never hand-edit crm.db — use the CLI, repair with `crm doctor`.
- `AGENTS.md` in the tool directory carries the same doctrine for non-skill
  agents, plus two annotated end-to-end transcripts (post-call flow first).
- Orientation `README.md` beside the data (written by `init`): db is
  authoritative; transcripts are evidence of record; ref-resolution rule;
  never hand-edit crm.db.

## 10. Composition recipes (documented and tested)

Three guarantees — stdout=data, stderr=messages, structured exit codes — and
the pipelines they enable; every documented recipe runs as an integration
test:

    crm find kima --format ids | xargs -n1 crm show
    crm stale --days 60 --format ids | xargs -n1 crm context
    crm contact ls --format json | jq -r '.[] | select(.email == null) | .ref'
    crm deal ls --rotting --format ids | xargs -n1 crm deal show
