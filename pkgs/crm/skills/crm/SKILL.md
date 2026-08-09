---
name: crm
description: Operate the local personal CRM through its CLI. Use when the user mentions a person, company, conversation, transcript, relationship, pipeline, deal, stale contact, duplicate cleanup, or CRM data; has just finished a call; is preparing to speak with someone; or wants facts captured, corrected, found, briefed, archived, merged, or checked.
---

# CRM

Use the `crm` CLI as the only interface to the CRM. Never edit `crm.db`
directly. Start a broad CRM session with `crm status --format json`, then use
the situation below that matches the user's request.

Run `crm <verb> --help` before an unfamiliar or destructive call. Read
[flags.md](flags.md) when exact flags or accepted enum values are needed.

## Just got off a call

1. Find the person before creating anything:
   `crm find "Nick Dupont" --type contact --format ids`.
2. If no contact exists, create one with every known anchor and provenance:
   `crm contact add "Nick Dupont" --org kima --email nick@kima.vc --source notes/2026-07-29.md`.
3. Ensure the transcript file already exists, then log the event:
   `crm log --kind call --with nick --org kima --summary "wants the deck before Friday" --date 2026-07-29 --transcript transcripts/2026/2026-07-29-nick-dupont-call.md`.
4. Append durable current understanding to the dossier:
   `crm contact edit nick --context-append "Prefers the deck before partner meetings." --source transcripts/2026/2026-07-29-nick-dupont-call.md`.
5. Read back the assembled state when accuracy matters:
   `crm context nick --format json`.

## About to talk to someone

1. Call `crm context nick` once. Prefer this briefing over assembling separate
   `show` and `ls` calls.
2. Summarize the relationship hint, dossier, organization, links, open deals,
   and recent timeline for the user. Mention transcript paths as evidence.
3. If the ref is ambiguous, stop and ask the user to choose a candidate ref.

## The user mentions a new company

1. Search before creating: `crm find "Kima Ventures" --type org --format ids`.
2. If absent, capture the company with provenance:
   `crm org add "Kima Ventures" --category vc --website kima.vc --location Paris --source notes/2026-07-29.md --detail "Mentioned by Nick Dupont"`.
3. Add or update the people attached to it, using the resolved org ref:
   `crm contact add "Nick Dupont" --org kima --title Partner --source notes/2026-07-29.md`.

## Preserve evidence and dossiers

- Resolve transcript paths from the directory containing the resolved database
  path. Pass a relative path such as `transcripts/2026/call.md`, or an absolute
  path inside that base. The file must exist before `crm log` or
  `crm interaction edit`; the stored path is base-relative.
- Treat a transcript as the evidence of record. Keep `--summary` concise and
  event-specific. Put long prose in `--body-file` or the transcript, not in a
  giant summary.
- Treat `context` on a contact or organization as the mutable current dossier.
  Use `--context-append`; do not replace established context unless the user is
  explicitly correcting it.
- Treat an interaction summary as history for that event. Use
  `crm interaction edit` only to repair the recorded event, not to turn it into
  a rolling dossier.

## Compose safely

Stdout is data. Stderr is messages, prompts, notices, hook diagnostics, and
errors. Use `--format json` for structured processing and `--format ids` for
one pasteable prefixed ref per line.

```bash
crm find kima --format ids | xargs -n1 crm show
crm stale --days 60 --format ids | xargs -n1 crm context
crm contact ls --format json | jq -r '.[] | select(.email == null) | .ref'
crm deal ls --rotting --format ids | xargs -n1 crm deal show
```

Refs accept prefixed ids, bare numeric ids, and entity-appropriate names,
emails, or LinkedIn handles. Use the ref already in hand; do not perform an id
lookup first.

## Interpret exit codes

| Code | Meaning | Agent response |
|---:|---|---|
| 0 | Success | Consume stdout. |
| 1 | Validation, usage, or generic failure | Correct the call from stderr. |
| 2 | Not found | Follow the remedy in stderr or ask for the missing input. |
| 3 | Ambiguous ref | Show the candidates and ask the user; never guess. |
| 4 | Constraint, duplicate, or idempotent conflict | Preserve the named owner/state and follow the remedy. |

## Runnable verb examples

Use these as canonical call shapes. Add `--format json` when consuming records
programmatically.

### Top-level verbs

```bash
crm init
crm log --kind note --org kima --summary "Fund II closed at 60M"
crm show c12
crm find "nick kima"
crm context nick
crm status
crm stale --days 60
crm dupes --type contact --threshold 0.3
crm import orgs organizations.csv --source investor-crm --dry-run
crm export contacts --format json
crm export tree
crm doctor
```

### Export behavior

Use flat JSON or CSV when backing up records or inspecting them with another
tool. Flat exports include archived rows. `all` is JSON-only:

```bash
crm export contacts --format json > contacts.json
crm export all --format json > backup.json
```

Use the Markdown tree for reviewable git diffs. It contains live records only,
is strictly derived from `crm.db`, and is replaced wholesale on regeneration.
With no directory argument it writes `tree/` beside the resolved database:

```bash
crm export tree
```

### Import behavior

Import organizations before contacts because contact organization names must
already resolve. Always pass a provenance source. Start with a dry run, then
repeat the same command without `--dry-run` after reviewing the plan:

```bash
crm import orgs organizations.csv --source investor-crm --dry-run
crm import orgs organizations.csv --source investor-crm
crm import contacts contacts.csv --source investor-crm --dry-run
crm import contacts contacts.csv --source investor-crm
```

Matches are skipped by default, so repeating a completed import does not add
rows. Use `--update` only when existing matches should be patched and receive
another provenance entry. Use `--skip-errors --reject-file rejects.csv` for a
reviewable worklist of failed source lines. Unknown contact organizations are
an exit-2 error unless the explicit `--create-missing` gate is used; that gate
creates and announces stamped organization stubs.

Only organizations and contacts can be imported. Deal and interaction exports
are one-way backup/inspection formats.

### Organizations

```bash
crm org add "Kima Ventures" --category vc --source notes/2026-07-12.md
crm org show kima
crm org ls --category vc
crm org edit kima --context-append "Partner meeting booked"
crm org merge o4 o17
crm org archive o4
crm org unarchive o4
crm org delete o4 --confirm
```

### Contacts and relationships

```bash
crm contact add "Nick Dupont" --org kima --email nick@kima.vc
crm contact show nick
crm contact ls --org kima
crm contact edit nick --phone +33612345678
crm contact relate nick jean --type "referred by" --note "Jean made the intro"
crm contact unrelate nick jean --type "referred by"
crm contact merge c12 c31
crm contact archive c12
crm contact unarchive c12
crm contact delete c12 --confirm
```

### Interactions

```bash
crm interaction show i43
crm interaction ls --with nick --kind call
crm interaction edit i43 --summary "Wants the deck by Thursday"
crm interaction archive i43
crm interaction unarchive i43
crm interaction delete i43 --confirm
```

### Pipelines

```bash
crm pipeline add "Seed raise"
crm pipeline ls
crm pipeline show p1
crm pipeline rename p1 "Seed round"
crm pipeline archive p1
crm pipeline unarchive p1
crm pipeline delete p1 --confirm
```

### Stages

```bash
crm stage add p1 sourced --rot 14
crm stage rename p1 contacted "first contact"
crm stage reorder p1 sourced contacted pitched "term sheet" closed
crm stage set-rot p1 pitched 7
crm stage archive p1 sourced
crm stage unarchive p1 sourced
crm stage delete p1 sourced --confirm
```

### Deals

```bash
crm deal add "Kima seed ticket" --pipeline p1 --org kima
crm deal show d3
crm deal ls --pipeline p1 --stage pitched
crm deal edit d3 --title "Kima seed"
crm deal move d3 pitched --note "Deck sent"
crm deal win d3 --reason "Led the round"
crm deal lose d3 --reason "Passed — too early"
crm deal reopen d3
crm deal archive d3
crm deal unarchive d3
crm deal delete d3 --confirm
```

### Exports

```bash
crm export orgs --format csv
crm export contacts --format json
crm export deals --format json
crm export interactions --format csv
crm export all --format json
crm export tree ~/mecattaf/notes/crm/tree
```

### Imports

```bash
crm import orgs organizations.csv --source investor-crm
crm import contacts contacts.csv --source investor-crm --skip-errors --reject-file rejects.csv
```

### Duplicate cleanup

Use `crm dupes` as an advisory, read-only report. Review its named reasons,
then merge only explicit refs with the survivor first. A merge fills missing
scalar fields, preserves both provenance histories, repoints references, and
soft-archives the absorbed row:

```bash
crm dupes --type contact --threshold 0.3 --format json
crm contact merge c12 c31
crm org merge o4 o17
```

## Tips for AI Agents

- Prefer `crm context <ref>` over separate `show` and timeline calls.
- Pass names, emails, handles, or refs directly; do not look up numeric ids
  first.
- Treat exit 3 as a request for human disambiguation. Never guess.
- Put long prose through `--body-file` or `--transcript`, never thousands of
  words in `--summary`.
- Search with real words. `crm find` is BM25 full-text search, not a glob
  matcher.
- Never hand-edit `crm.db`. Use the CLI and audit or repair search with
  `crm doctor` and `crm doctor --rebuild-fts`.
