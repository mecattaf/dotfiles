---
name: scheduled
description: Create, edit, enable, run now and inspect Tom's scheduled
  items (JSONC files under <agency>/.agency/scheduled/; the hourly
  heartbeat hands each due one to the superagent as an occurrence
  record). Use when Tom asks for recurring or later work ("every night",
  "each Monday", "run X now", "what did the nightly do", "what is
  scheduled").
---

# Scheduled

Scheduled work is files. One item is one file:
`<agency>/.agency/scheduled/<item>.jsonc`. The master agency is `~`.
For Tom's work, never use any of these:
- Claude cloud routines or session cron tools;
- DSH's own schedule tools;
- systemd timers or crontab.

The heartbeat only nudges: when an item is due, it writes one record into
the superagent's inbox and starts the floor. The main Session reads the
item's prompt and decides. So write conditions, checks and context
("skip if the journal already exists", "only on workdays") into
`job.prompt` in words. There are no `if`, `window`, `outcome` or
`context` keys.

## Write
- `scheduled new ID --cron EXPR --tz ZONE --prompt TEXT` (or
  `--prompt-file .agency/prompts/x.md`, relative to the agency folder).
  New items are always `"enabled": false`.
- Show Tom the next instants in local time (`scheduled show ID -n 3`).
- Arm only what Tom asked for: `scheduled set ID enabled true`. To
  disarm: `scheduled set ID enabled false`.
- Small edits: `scheduled set ID on.schedule[0].cron '"0 6 * * 1"'`.
  Pass `--expect REV` when Tom may be editing too.
- Every schedule entry needs a `"timezone"`. Prefer `:00` minutes, and
  never use 02:00–02:59 in Europe/Paris.
- To try out a new item: `scheduled run ID` while it is still
  disabled, check the result in the superagent, then enable it.

## Run and inspect
- `scheduled run ID` writes one manual record now and starts the floor
  if it is stopped. It does not wait. The work shows up in the
  superagent, not here.
- `scheduled ls`, `scheduled show ID`, `scheduled history ID [-n N]`.
  history lists what the floor received (done) or refused (bad, with
  the error).
- Edits take effect at the next hourly pass. Say so.

## Never
- Never edit the inbox, `.done/`, `.bad/` or `~/.local/state/scheduled`
  by hand, and never open the floor database.
- Never put secrets, env, model, profile or priority in an item.
- Never put item files in the dotfiles repo (it is public).
