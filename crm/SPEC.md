# crm — personal git-backed CRM

Single static Go binary (`modernc.org/sqlite`, cgo-free). Tool lives in public
dotfiles; data lives in the private notes repo. No encryption — the notes repo
is private and stays private (ruled 2026-07-29, supersedes the git-crypt plan).

- Database: `~/mecattaf/notes/crm/crm.db` (override with `$CRM_DB`)
- Transcripts/attachments: `~/mecattaf/notes/crm/transcripts/YYYY/` — the db
  row stores a repo-relative path, the file is the evidence of record
- Import source (one-time, idempotent): `~/mecattaf/investor-crm` CSVs

## Non-negotiables (from the July 2026 reference-CLI audit)

- `journal_mode=DELETE` — single file, no `-wal`/`-shm` sidecars. WAL + git
  backup corrupts. `busy_timeout=5000` for concurrent shell/agent invocations.
- Real `org_id` FK on contacts — never a redundant company text column.
- All multi-statement writes in transactions.
- UNIQUE constraints enforce dedup in DDL, not in application hope:
  partial unique on live org `name_norm`, live contact `email`.
- Name normalization = NFKD, strip combining marks, casefold — stored in
  `name_norm` columns (the investor corpus has real accent corruption).
- Provenance is first-class: `provenance_sources`, `provenance_details`,
  `relationship_hint` on orgs and contacts.
- Soft archive is the default lifecycle; `delete` requires `--confirm` and is
  never batched.
- stdout = data, stderr = messages; sentinel errors map to exit codes
  (1 generic, 2 not found, 3 ambiguous, 4 constraint/duplicate).
- Resolve-by-anything: every entity ref accepts id, email, or name
  (exact → normalized → substring); ambiguity is an error that lists candidates.
- FTS5 external-content tables per entity, maintained by AFTER triggers,
  queried with bm25 rank.

## Schema v0.1 (reachability-first; deals/tasks/pipeline deferred to v2)

Tables: `orgs`, `contacts`, `interactions` (kind: call|meeting|email|message|note,
`occurred_on` date, summary, body, `transcript_path`), `interaction_people`
junction (UNIQUE pair). Timestamps ISO-8601 UTC TEXT; `archived_at` nullable.
Schema DDL in `schema.sql` is the source of truth; `PRAGMA user_version`
tracks migrations.

## Verb surface v0.1

    crm init
    crm org add <name> [--category --website --linkedin --location --focus
                        --context --hint --source --detail]
    crm contact add <name...> [--org <ref> --title --email --phone --linkedin
                        --location --context --hint --source --detail]
    crm log --with <ref> [--with <ref>...] --kind <k> --summary <s>
            [--date YYYY-MM-DD] [--body-file <path>|-] [--transcript <path>]
    crm context <ref>              # one-call briefing: profile + org + timeline
    crm find <query>               # FTS bm25 across all entities
    crm show (org|contact|interaction) <ref>
    crm ls (orgs|contacts|interactions) [--all]
    crm edit (org|contact) <ref> --field value...
    crm archive (org|contact|interaction) <ref>
    crm delete (org|contact|interaction) <ref> --confirm

Later (v0.2+): `import` (investor-crm CSVs, search-before-create, provenance
mandatory), `dupes`/`merge`, `export`, `/crm` skill, nix packaging
(`buildGoModule` via `default.nix`), git commit hygiene.
