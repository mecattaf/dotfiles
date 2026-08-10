# Call absorption contract

This is the repeatable contract for absorbing a recorded work call into the
local CRM. The evidence path is:

```text
recording directory
  -> transcript.md (or one explicitly selected transcript variant)
  -> ~/mecattaf/notes/crm/transcripts/YYYY/
  -> crm log --kind call --transcript ...
  -> crm context readback
```

The CRM CLI is the only interface to CRM state. Never edit `crm.db` directly.
Private, engagement-specific decision logs live under
`~/mecattaf/notes/crm/`; do not put names, contact details, or engagement
facts in this public repository.

## Invariants

1. Build and use the CLI from the current worktree:

   ```bash
   crm="$(nix build .#crm --no-link --print-out-paths)/bin/crm"
   "$crm" status --format json
   ```

2. Identify a call from transcript content, never from its duration, calendar
   slot, directory order, or filename alone. Read `transcript.md` in each
   candidate recording directory. Use another transcript variant only when it
   is deliberately selected and recorded in the private decision log.
3. Exclude personal and non-work recordings completely. Do not copy them,
   create CRM records from them, or identify them in an engagement log.
4. Search before creating an organization or contact. Treat exit code 3 as
   ambiguity and stop for a human choice; never guess or merge records.
5. Every organization/contact fact needs `--source` pointing to the exact
   local file that supports it. Append durable understanding with
   `--context-append`; do not replace an established dossier merely to add a
   new engagement fact.
6. A transcript is the evidence of record. The interaction summary stays
   short and event-specific.
7. The transcript must exist beneath the directory containing the resolved
   database before `crm log` runs. Store its path in the CRM relative to that
   directory.

## Reconcile before writing

An absorption can be retried after partial completion. Inspect the current
state first and preserve anything already present:

```bash
"$crm" find "$org_name" --type org --format json
"$crm" find "$contact_name" --type contact --format json
"$crm" context "$contact_ref" --all --format json
"$crm" interaction ls --org "$org_ref" --kind call --all --format json
```

Before each mutation, decide from that readback whether the desired fact,
context paragraph, participant, transcript path, or interaction is already
present. Do not append the same context twice or create a second interaction
for the same call. Duplicate cleanup and `crm merge` remain human-gated.

## Resolve and enrich the entities

Create only missing records. Otherwise edit the resolved record, retaining its
existing fields and dossier:

```bash
"$crm" org add "$org_name" \
  --source "$org_source" \
  --context "$initial_org_context"

"$crm" org edit "$org_ref" \
  --context-append "$new_org_context" \
  --source "$org_source"

"$crm" contact add "$contact_name" \
  --org "$org_ref" \
  --source "$contact_source" \
  --context "$initial_contact_context"

"$crm" contact edit "$contact_ref" \
  --context-append "$new_contact_context" \
  --source "$contact_source"
```

Resolve and enrich every confirmed work participant needed for the call.
`--org` describes the contact's actual organization, not merely the
organization discussed on the call. Leave an affiliation unset when the
source material does not establish it.

## Copy the transcript into the CRM evidence tree

Use a stable, lowercase filename:

```text
YYYY-MM-DD-<contact-slug>-<org-slug>-call.md
```

For the default database layout:

```bash
crm_dir="$HOME/mecattaf/notes/crm"
year="${call_date%%-*}"
transcript_src="$recording_dir/transcript.md"
transcript_rel="transcripts/$year/$call_date-$contact_slug-$org_slug-call.md"
transcript_dst="$crm_dir/$transcript_rel"

mkdir -p "$crm_dir/transcripts/$year"
if test -e "$transcript_dst"; then
  cmp --silent "$transcript_src" "$transcript_dst"
else
  cp --preserve=mode,timestamps "$transcript_src" "$transcript_dst"
fi
test -f "$transcript_dst"
```

If the destination already exists, compare it with the selected source before
writing. A mismatch is a decision point, not permission to overwrite prior
evidence silently.

## Log the call

Attach every confirmed participant by repeating `--with`. `--org` is the
organization the interaction concerns. Do not attach someone who was absent
merely to make their personal timeline include the call.

```bash
"$crm" log \
  --kind call \
  --with "$contact_ref" \
  --org "$org_ref" \
  --date "$call_date" \
  --summary "$short_event_summary" \
  --transcript "$transcript_rel" \
  --format json
```

The transcript argument is relative to `~/mecattaf/notes/crm/`, not to the
shell's working directory and not to the recording directory.

## Read back and prove the absorption

Read the assembled dossier rather than assuming each write composed
correctly:

```bash
"$crm" context "$contact_ref" --all --format json
"$crm" context "$org_ref" --all --format json
```

Check all of the following:

- the contact has the intended organization link and sourced context;
- the organization retained its old dossier and received the appended one;
- each admitted call appears once, with the intended date, summary,
  participants, and organization;
- every stored `transcript_path` is relative and resolves to an existing file
  under `~/mecattaf/notes/crm/`;
- the source copy and CRM copy are byte-identical;
- no excluded recording appears in the CRM or private engagement log.

## Private decision log

Write one private log under `~/mecattaf/notes/crm/` for each absorption. It
must contain:

- the source documents reviewed;
- every admitted work-call decision and the transcript passages that support
  it;
- entity-resolution decisions, including why a record was added or edited;
- every mutating `crm` command exactly as run;
- transcript source/destination paths and integrity hashes;
- final counts for organizations touched, contacts touched, and calls logged;
- the final `crm context` checks and confirmation that every transcript path
  exists.

Keep personal recordings outside that log entirely. The private log is an
audit trail for the work engagement, not an inventory of everything in the
recordings directory.
