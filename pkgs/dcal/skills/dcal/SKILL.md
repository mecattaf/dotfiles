---
name: dcal
description: Operate the local calendar through the dcal CLI. Use when the user mentions an event, agenda, calendar availability, scheduling a call with a CRM contact, syncing calendars or accounts, finishing a recorded call, or asks "what's on my calendar".
---

# dcal

Use the `dcal` CLI as the only interface to calendar state. Never edit
`dcal.db` or generated ICS files directly. Start a broad calendar session with
`dcal status --format json`, then use the situation below that matches the
user's request.

Event reads and mutations talk to the user daemon. If it is unavailable,
report the service failure; do not launch a second long-running daemon unless
the user explicitly asks. Run `dcal <verb> --help` before an unfamiliar or
destructive call. Read [flags.md](flags.md) for exact flags and accepted
values.

## Add an event

1. Resolve the intended date, start, end, and timezone. Pass start and end as
   RFC3339 with an explicit offset; never guess a missing timezone.
2. Use the configured default calendar unless the user named another one:
   `dcal add "Design review" --start 2026-08-12T09:00:00+02:00 --end 2026-08-12T10:00:00+02:00`.
3. When a calendar was named, pass it directly:
   `dcal add "Design review" --calendar Work --start 2026-08-12T09:00:00+02:00 --end 2026-08-12T10:00:00+02:00`.
4. Treat the single ref printed on stdout as the created event ref. Use
   `dcal show <event-ref> --format json` when the result must be read back.

Use `--all-day` only when the user explicitly wants an all-day event. Status
accepts only `confirmed`, `tentative`, or `cancelled`.

## Show an agenda for a range

Use `dcal agenda`, not one-calendar `ls`, for "what's on my calendar" and
availability questions:

```bash
dcal agenda --from 2026-08-10 --to 2026-08-16 --format json
```

Plain dates use local time and `--to` is inclusive. Use RFC3339 bounds when
the user asks for exact instants. Summarize the returned events in chronological
order and preserve calendar names; an empty JSON array means the range is
clear in the calendars dcal knows about.

## Schedule a call with a CRM contact

Pass the contact ref or an unambiguous CRM-resolvable contact directly to
`--crm`:

```bash
dcal add --crm nick --start 2026-08-13T14:00:00+02:00 --end 2026-08-13T14:30:00+02:00
```

`dcal` resolves the contact through `crm show`, stores the canonical contact
ref, marks the event as a call, and supplies `call with <name>` when no title
was given. An explicit title is still allowed. Do not pass another value to
`--kind`; the only accepted kind is `call`.

Exit 2 means the CRM contact or calendar was not found. Exit 3 means a ref was
ambiguous: show the candidates from stderr and ask the user to choose; never
guess.

## After a call

`dcal status --format json` includes finished CRM call events that have not
yet been logged under `pendingCalls`. For the selected event, inspect the plan
when recording selection or transcript placement needs confirmation:

```bash
dcal done <event-ref> --dry-run --format json
```

Then complete the workflow with `dcal done <event-ref>`. The command requires
an ended CRM-linked call, finds its recording, runs `call-diarize`, copies the
resulting transcript into the CRM transcript tree without overwriting different
evidence, and invokes `crm log`. Do not reproduce those steps by hand when
`dcal done` can own the complete transition.

## Sync and check status

- Run `dcal sync` for all configured accounts and the managed read-only Tally
  calendar.
- Run `dcal sync <account-id>` only when the user names one account.
- Run `dcal account list --format json` to inspect configured account ids.
- Run `dcal status --format json` after sync to report authorization, calendar
  counts, last-sync state, and pending calls.

When the daemon is running, `dcal sync` asks it to sync asynchronously and
prints the progress notice on stderr. Do not treat empty text stdout as a
failure; check the exit code and use status for the resulting state.

## Maintain an existing event

```bash
dcal show <event-ref> --format json
dcal edit <event-ref> --title "Reviewed design"
dcal rm <event-ref>
```

`edit` requires at least one changed field and prints the event ref on success.
Run `rm` only after an explicit request to remove that event; it has no
confirmation prompt.

## Compose safely

Stdout is data. Stderr is progress, prompts, notices, dependency diagnostics,
and errors. Preserve both streams and use `--format json` for structured
processing. Text-mode mutations print a stable ref when they produce one;
text-mode sync reports progress only on stderr.

Never hand-edit the SQLite database, the local collection ICS files, or the
managed Tally calendar. Tally projection is replaced from producer inventory
on a full sync and is intentionally read-only.

## Interpret exit codes

| Code | Meaning | Agent response |
|---:|---|---|
| 0 | Success | Consume stdout and retain relevant stderr notices. |
| 1 | Validation, usage, dependency, or generic failure | Correct the call from stderr or report the failed dependency. |
| 2 | Not found | Follow the remedy in stderr or ask for the missing input. |
| 3 | Ambiguous ref | Show candidates and ask the user; never guess. |
| 4 | Conflict, constraint, duplicate, disabled, or read-only target | Preserve the named state and follow the remedy. |
