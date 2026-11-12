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
`<agency>/.agency/scheduled/<item>.jsonc`. The master agency is `~`;
another agency is any folder with a `.agency/` directory up to three
levels below `~`, named by its path (`work/acme:<item>`).
For Tom's work, never use any of these:
- Claude cloud routines or session cron tools;
- DSH's own schedule tools;
- systemd timers or crontab.

The heartbeat only nudges: when an item is due, it writes one record into
the superagent's inbox and starts the floor. The main Session reads the
item's prompt and decides. So write conditions, checks and context
("skip if the journal already exists", "only on workdays") into
`job.prompt` in words. There are no `if`, `window`, `outcome` or
`context` keys, and no `model`, `pair` or `priority`: scheduled work runs
on the floor's default pair.

## Write
- `scheduled new ID --cron EXPR --tz ZONE --prompt TEXT` (or
  `--prompt-file .agency/prompts/x.md`, relative to the agency folder).
  New items are always `"enabled": false`. For a new agency,
  `mkdir -p <folder>/.agency` first.
- Show Tom the next instants (`scheduled show ID -n 3`, printed in UTC)
  and say them in his local time.
- Arm only what Tom asked for: `scheduled set ID enabled true`. To
  disarm: `scheduled set ID enabled false`. The first hourly tick that
  sees an item armed fires nothing, so arming less than an hour before
  an instant skips that instant. Say so.
- Small edits: `scheduled set ID on.schedule[0].cron '"0 6 * * 1"'`
  (a value is JSON when it parses, so keep the inner quotes).
  Pass `--expect REV` when Tom may be editing too.
- Every schedule entry needs a `"timezone"`. Prefer `:00` minutes, and
  never use 02:00–02:59 in Europe/Paris.
- To try out a new item: `scheduled run ID` while it is still
  disabled, check the result, then enable it.

## Run and inspect
- `scheduled run ID` writes one manual record now and starts the floor
  if it is stopped. It does not wait. The work shows up in the
  superagent, not here.
- `scheduled ls`, `scheduled show ID`, `scheduled history ID [-n N]`.
  history lists what the floor received (done) or refused (bad, with
  the error).
- The work itself: `dshd ls` (units `sa-…-a<k>`), `dshd read <unit>`,
  the Claude session under `~/.claude-work/projects/<agency path with / and . as ->/`,
  the floor's panel (`dshd attach floor`). A failed run is not retried;
  the next occurrence runs on its own.
- Edits take effect at the next hourly pass. Say so.

## Workflows
A workflow script is never an item key. It starts when the superagent is
asked to call `orchestrator_workflow_start` with the script and the
agency folder. To run one on a schedule or now, write an item whose
prompt is that request: "This is a request to you, the superagent, not
work for a worker. Do not accept it as a ticket. Call
orchestrator_workflow_start with script <abs path> and cwd <agency
folder>. Then ignore this trigger with the reason: started workflow <the
run id you got>." (dotfiles `docs/scheduled.md`, `docs/dsh-master.md`).

## Never
- Never edit the inbox, `.done/`, `.bad/` or `~/.local/state/scheduled`
  by hand, and never write to the floor database.
- Never put secrets, env, model, profile or priority in an item.
- Never put item files in the dotfiles repo (it is public).
