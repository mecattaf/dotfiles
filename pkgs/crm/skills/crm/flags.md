# CRM flag reference

Use this reference for the current command surface. Run `crm <verb> --help`
for the canonical help at execution time.

Every command inherits `--db <path>` and `--help`. The root also accepts
`--version`. Database resolution is `--db`, then `CRM_DB`, then
`~/mecattaf/notes/crm/crm.db`.

Set `CRM_POST_WRITE_HOOK` to a shell command when post-write automation is
needed. After each successful mutation, the command receives
`{event, verb, entity, refs, records, db_path}` JSON on stdin. Its stdout is
discarded, stderr passes through, and failure or the 30-second timeout never
changes the CRM verb's result. Read verbs do not invoke it.

Record commands accept `--format table|json|ids`. `context`, `status`,
`dupes`, and `doctor` accept `--format table|json`. Flat entity exports accept
`--format json|csv`; `export all` accepts JSON only. Without an explicit
format, output is a table on a terminal and JSON through a pipe where that
format is supported. Flags marked “repeatable” may be passed more than once.

## Top-level verbs

### `crm init`

Accept no verb-specific flags. Create the database, current-year transcript
directory, and orientation README idempotently.

### `crm log`

- `--with <contact-ref>`: attach a participant; repeatable.
- `--kind <call|meeting|email|message|note>`: require an interaction kind.
- `--summary <text>`: require an event summary.
- `--date <YYYY-MM-DD>`: set the event date; default to today locally.
- `--body-file <path|->`: read long body text from a file or stdin.
- `--transcript <path>`: attach an existing path inside the database base.
- `--org <org-ref>`: attach an organization.
- `--deal <deal-ref>`: attach a deal.
- `--format <table|json|ids>`: select output.

Canonical flags may be replaced by positional sugar
`crm log <kind> <contact> <summary>`, but do not combine the two forms.

### `crm show <prefixed-ref>`

- `--format <table|json|ids>`: select output.

Require a prefixed contact, organization, interaction, pipeline, or deal ref.

### `crm find <query>`

- `--type <org|contact|interaction|deal>`: restrict the search entity.
- `--limit <N>`: cap results; default 20.
- `--format <table|json|ids>`: select output.

### `crm context <contact-or-org-ref>`

- `--limit <N>`: cap timeline entries; default 20.
- `--all`: return the complete timeline; mutually exclusive with `--limit`.
- `--format <table|json>`: select output.

### `crm status`

- `--format <table|json>`: select output.

### `crm stale`

- `--days <N>`: set a positive last-touch threshold; default 90.
- `--type <contact|org>`: choose the entity; default `contact`.
- `--recent-first`: reverse the default oldest-first worklist.
- `--format <table|json|ids>`: select output.

### `crm dupes`

- `--type <contact|org>`: restrict candidate pairs; omit to scan both types.
- `--threshold <0..1>`: set the minimum weighted score; default 0.3.
- `--limit <N>`: cap globally ranked pairs; 0 means all.
- `--format <table|json>`: select output. Each row carries `left`, `right`,
  `score`, and named `reasons`.

### `crm import orgs <file.csv>`

- `--source <text>`: required provenance source.
- `--dry-run`: print create/update/skip decisions and roll back the file
  transaction.
- `--skip-errors`: roll back failed rows to savepoints and continue.
- `--update`: patch matched rows and append provenance.
- `--reject-file <path>`: write failures with original CSV line numbers.

Import organizations before contacts. Created refs are written to stdout; the
counted summary is written to stderr. Existing `name_norm` matches are skipped
unless `--update` is set.

### `crm import contacts <file.csv>`

- `--source <text>`: required provenance source.
- `--dry-run`: print create/update/skip decisions and roll back the file
  transaction.
- `--skip-errors`: roll back failed rows to savepoints and continue.
- `--update`: patch matched rows and append provenance.
- `--reject-file <path>`: write failures with original CSV line numbers.
- `--create-missing`: auto-create unknown organizations as stamped stubs and
  announce each stub on stderr.

Contacts match by lowercased email, then `name_norm`. Without
`--create-missing`, an unknown organization is exit 2 with the exact
`crm org add` remedy. Deals and interactions have no import command; their
flat exports are one-way.

### `crm doctor`

- `--rebuild-fts`: rebuild all FTS indexes atomically before auditing.
- `--format <table|json>`: select output.

### `crm export orgs|contacts|deals|interactions`

- `--format <json|csv>`: select a complete flat record export. Archived rows
  are included. CSV writes a header even for an empty collection.

### `crm export all`

- `--format <json>`: write one object keyed by `contacts`, `deals`,
  `interactions`, and `orgs`.

### `crm export tree [dir]`

Accept no flags. Regenerate a Markdown projection of live organizations,
contacts, deals, and interactions. With no argument, write `tree/` under the
directory containing the resolved database. The destination is replaced
wholesale after a successful staged render; a nonempty unrelated directory is
refused.

## Organization verbs

### `crm org add <name>`

- `--category <text>`
- `--website <url-or-host>`
- `--linkedin <handle-or-url>`
- `--location <text>`
- `--focus <text>`
- `--context <text>`
- `--hint <text>`
- `--source <text>`: provenance source; repeatable.
- `--detail <text>`: provenance detail; repeatable.
- `--format <table|json|ids>`

### `crm org show <ref>`

- `--format <table|json|ids>`

### `crm org ls`

- `--category <text>`: filter by exact category.
- `--all`: include archived organizations.
- `--limit <N>`: cap rows; 0 means all.
- `--format <table|json|ids>`

### `crm org edit <ref>`

- `--category <text>`
- `--website <url-or-host>`
- `--linkedin <handle-or-url>`
- `--location <text>`
- `--focus <text>`
- `--context <text>`: replace the dossier.
- `--context-append <text>`: append with a blank-line separator.
- `--hint <text>`
- `--source <text>`: append provenance; repeatable.
- `--detail <text>`: append provenance; repeatable.
- `--format <table|json|ids>`

For nullable edit fields, passing an explicit empty string clears the field.

### Organization lifecycle

`crm org merge <winner> <loser>` accepts `--format <table|json|ids>` and
soft-archives the loser after atomically repointing its references.

- `crm org archive <ref>`: `--format <table|json|ids>`.
- `crm org unarchive <ref>`: `--format <table|json|ids>`.
- `crm org delete <ref>`: `--confirm`, `--format <table|json|ids>`.

## Contact verbs

### `crm contact add <name>`

- `--org <org-ref>`
- `--title <text>`
- `--email <address>`
- `--phone <text>`
- `--linkedin <handle-or-url>`
- `--location <text>`
- `--context <text>`
- `--hint <text>`
- `--source <text>`: repeatable.
- `--detail <text>`: repeatable.
- `--format <table|json|ids>`

### `crm contact show <ref>`

- `--format <table|json|ids>`

### `crm contact ls`

- `--org <org-ref>`: filter by organization.
- `--all`: include archived contacts.
- `--limit <N>`: cap rows; 0 means all.
- `--format <table|json|ids>`

### `crm contact edit <ref>`

- `--org <org-ref>`: set or clear the organization.
- `--title <text>`
- `--email <address>`
- `--phone <text>`
- `--linkedin <handle-or-url>`
- `--location <text>`
- `--context <text>`: replace the dossier.
- `--context-append <text>`: append with a blank-line separator.
- `--hint <text>`
- `--source <text>`: append provenance; repeatable.
- `--detail <text>`: append provenance; repeatable.
- `--format <table|json|ids>`

For nullable edit fields, passing an explicit empty string clears the field.

### `crm contact relate <contact> <related-contact>`

- `--type <text>`: require a free-text directed relationship type.
- `--note <text>`: attach relationship context.
- `--format <table|json|ids>`

### `crm contact unrelate <contact> <related-contact>`

- `--type <text>`: remove only that directed type; omit to remove all links
  between the pair in either direction.
- `--format <table|json|ids>`

### Contact lifecycle

`crm contact merge <winner> <loser>` accepts `--format <table|json|ids>` and
atomically collapses interaction participants, deals, and contact links before
soft-archiving the loser.

- `crm contact archive <ref>`: `--format <table|json|ids>`.
- `crm contact unarchive <ref>`: `--format <table|json|ids>`.
- `crm contact delete <ref>`: `--confirm`, `--format <table|json|ids>`.

## Interaction verbs

### `crm interaction show <ref>`

- `--format <table|json|ids>`

### `crm interaction ls`

- `--with <contact-ref>`
- `--org <org-ref>`
- `--deal <deal-ref>`
- `--kind <call|meeting|email|message|note>`
- `--all`: include archived interactions.
- `--limit <N>`: cap rows; 0 means all.
- `--format <table|json|ids>`

### `crm interaction edit <ref>`

- `--summary <text>`
- `--date <YYYY-MM-DD>`
- `--kind <call|meeting|email|message|note>`
- `--transcript <path>`: set or clear an existing in-base transcript path.
- `--body-file <path|->`: replace body text from a file or stdin.
- `--add-with <contact-ref>`: add a participant; repeatable.
- `--rm-with <contact-ref>`: remove a participant; repeatable.
- `--org <org-ref>`: set or clear the organization.
- `--deal <deal-ref>`: set or clear the deal.
- `--format <table|json|ids>`

### Interaction lifecycle

- `crm interaction archive <ref>`: `--format <table|json|ids>`.
- `crm interaction unarchive <ref>`: `--format <table|json|ids>`.
- `crm interaction delete <ref>`: `--confirm`, `--format <table|json|ids>`.

## Pipeline verbs

### `crm pipeline add <name>`

- `--format <table|json|ids>`

### `crm pipeline ls`

- `--all`: include archived pipelines.
- `--format <table|json|ids>`

### `crm pipeline show <ref>`

- `--format <table|json|ids>`

### `crm pipeline rename <ref> <new-name>`

- `--format <table|json|ids>`

### Pipeline lifecycle

- `crm pipeline archive <ref>`: `--format <table|json|ids>`.
- `crm pipeline unarchive <ref>`: `--format <table|json|ids>`.
- `crm pipeline delete <ref>`: `--confirm`, `--format <table|json|ids>`.

## Stage verbs

### `crm stage add <pipeline-ref> <name>`

- `--rot <days>`: set a positive rotting threshold.
- `--after <stage-ref>`: place after a stage.
- `--first`: place first; mutually exclusive with `--after`.
- `--format <table|json|ids>`

### `crm stage rename <pipeline-ref> <stage-ref> <new-name>`

- `--format <table|json|ids>`

### `crm stage reorder <pipeline-ref> <stage-ref>...`

- `--format <table|json|ids>`

Require the complete set of live stages exactly once.

### `crm stage set-rot <pipeline-ref> <stage-ref> <days|none>`

- `--format <table|json|ids>`

### Stage lifecycle

- `crm stage archive <pipeline-ref> <stage-ref>`:
  `--format <table|json|ids>`.
- `crm stage unarchive <pipeline-ref> <stage-ref>`:
  `--format <table|json|ids>`.
- `crm stage delete <pipeline-ref> <stage-ref>`: `--confirm`,
  `--format <table|json|ids>`.

## Deal verbs

### `crm deal add <title>`

- `--pipeline <pipeline-ref>`: required.
- `--stage <stage-ref>`: choose an opening stage; default to the first stage.
- `--org <org-ref>`
- `--contact <contact-ref>`
- `--format <table|json|ids>`

Require at least one of `--org` or `--contact`.

### `crm deal show <ref>`

- `--format <table|json|ids>`

### `crm deal ls`

- `--pipeline <pipeline-ref>`
- `--stage <stage-ref>`: require `--pipeline`.
- `--status <open|won|lost>`
- `--rotting`: list open deals past their stage threshold.
- `--all`: include archived deals.
- `--limit <N>`: cap rows; 0 means all.
- `--format <table|json|ids>`

### `crm deal edit <ref>`

- `--title <text>`
- `--org <org-ref>`: set or clear the organization.
- `--contact <contact-ref>`: set or clear the contact.
- `--format <table|json|ids>`

### `crm deal move <deal-ref> <stage-ref>`

- `--note <text>`: record transition context.
- `--format <table|json|ids>`

### `crm deal win <ref>` and `crm deal lose <ref>`

- `--reason <text>`: record the outcome reason.
- `--format <table|json|ids>`

### `crm deal reopen <ref>`

- `--format <table|json|ids>`

### Deal lifecycle

- `crm deal archive <ref>`: `--format <table|json|ids>`.
- `crm deal unarchive <ref>`: `--format <table|json|ids>`.
- `crm deal delete <ref>`: `--confirm`, `--format <table|json|ids>`.
