---
name: scheduled
description: Create, edit, pause, run now and inspect Tom's scheduled
  workflows (JSONC files under <agency>/.agency/workflows/, run by the
  hourly heartbeat on the dshd factory floor). Use when Tom asks for
  recurring or later work ("every night", "each Monday", "run X now",
  "why did the nightly fail", "what is scheduled").
---

# Scheduled

Scheduled work is files. One workflow = one file =
<agency>/.agency/workflows/<stem>.jsonc. The master agency is ~.
Never use Claude cloud routines, session cron tools, DSH's own
schedule tools, systemd timers or crontab for Tom's work.

## Write
- Tom asked for it: write it enabled. Unasked idea: write a proposal
  (scheduled put ID --proposal), never an armed file.
- Draft the text, then: scheduled put ID --expect none --by cc <file
  (new) or scheduled put ID --expect REV --by cc <file (replace).
  put validates and refuses invalid text. Show Tom the next fires
  from its output in local time.
- Small edits: scheduled set ID enabled false (pause), or
  scheduled set ID on.schedule[0].cron '"0 6 * * 1"'.
- Every schedule entry needs "timezone". Prefer :00 minutes; never
  02:00-02:59 in Europe/Paris.
- A new workflow you want to test: write it paused, scheduled run ID,
  read the result, then scheduled set ID enabled true.

## Run and inspect
- scheduled run ID [--input k=v] [--wait] [--follow]. Gates (if) still apply. `--wait` prints the final occurrence row and exits 0 only on `done`.
- scheduled ls; scheduled show ID; scheduled history ID [-n N];
  scheduled history ID --occurrence KEY --log.
- Edits take effect at the next hourly pass. Say so.

## Never
- Never edit ~/.agency/state/. Never open the floor database for
  writing. Never put secrets, env or model choices in a workflow.
- Never put workflow files in the dotfiles repo (it is public).
