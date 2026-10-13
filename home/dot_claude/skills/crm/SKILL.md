---
name: crm
description: Use the Worker CRM CLI for an explicit CRM task, a named person or company to look up or record, or a just-finished call. Do not trigger on photos, files, or generic mentions of people.
---

# Worker CRM

Use `crm` against the configured Worker. See [REFERENCE.md](REFERENCE.md) for
operation schemas and [the agent doctrine](../../AGENTS.md) for write rules.
Configuration comes from flags, environment and `~/.config/crm/config.json`.
Set `CRM_ACTOR=claude:<seat>` or `CRM_ACTOR=codex:<seat>` for agent attribution.
Never print credentials or place a bearer token on argv.

## Just got off a call

Record facts, participants and commitments together with `crm batch` or `crm apply`:
`orgs.assert`, `contacts.assert` (org `$ops[0].ref`), `interactions.assert`
(with `$ops[1].ref`), then one `followups.assert` per commitment. Keep the atomic
group within the server batch limit. Derive a stable `external_ref`, for example
`call:<contact-ref>:<date>:<slug>`, so retries do not create another event.
Attach an available transcript afterwards with `crm transcript attach <interaction> <file>`.

## About to talk to someone

Start with `crm context <ref> --format md`. It includes relationship history,
follow-ups and email sends. Resolve ambiguous matches before recording a change.

## The user mentions a new company

For a requested lookup or recording task, use `crm org assert` with known identity
keys, then assert contacts with that org. Do not invent domains or addresses.

## Preserve evidence and dossiers

Append context with `--context-append`; never overwrite existing evidence.
Keep each interaction summary immutable. Put new information in a new event.
Use `--body-file PATH` or `--body-file -` for long prose.

## Record follow-ups

Use `crm fu add` or `followups.assert` with a due date and the relevant contact,
org or deal. Track commitments individually; `crm today` lists work due.

## Email came in

Use `crm email resolve <address>...`, `crm email threads --ref <ref> --human-only`
and `crm email thread <thread-ref>`. Link with `crm email link <thread> <ref>`;
remove a mistaken link with `crm email unlink <link-id>`.
`crm email unmatched --two-way` finds unresolved handles with traffic both ways.

## Compose safely

Use `crm email send <recipient-ref-or-address>... --from <identity> --subject <subject>
--body-file PATH` (or `-` for stdin); `--html-file` supplies HTML. Preview with
`--dry-run`, which performs local validation without calling mail. Mail validates
the identity on the real send. Agent sends require approval; preserve your actor
and use `--require-approval` when explicit approval is desired. Mail owns approval
and delivery. Check `crm email sends` or `crm email sends show <outbox-id>` until
sent; acceptance into the outbox is not confirmation of delivery.

## Interpret exit codes

- 0: success.
- 1: invalid request; correct it before retrying.
- 2: not found; check the reference.
- 3: ambiguous; ask, never guess. An unattended agent may choose only when an
  independent key it already holds re-resolves to exactly that candidate;
  otherwise record a follow-up for Tom and continue independent work.
- 4: conflict; read the current state and reconcile.
- 5: temporary or server failure; retain the request identity when retrying.
- 6: authentication or configuration failure; repair configuration without exposing secrets.

## Tips for AI Agents

Prefer assertions over search-then-create and context over separate show/list
calls. Use refs returned by the Worker. Use `--dry-run` before merging. The CLI
manages write idempotency keys. Use JSON when composing commands; `--format ids`
feeds references to other verbs. Generic operations remain available through
`crm api <operationId> --body-file PATH`.
