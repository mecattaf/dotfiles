# Fresh day workspaces

`journal-day` creates the current date directory under an existing configured
journal and atomically points a convenience symlink there. It prints the
permanent physical directory. It neither moves old work nor generates a brief,
reads notes, changes running sessions, harvests chats or schedules a job.

The host-local `~/.config/journal-day.json` contains `journal_root`, `today_link`,
and optionally `timezone` (default `Europe/Paris`) and `state_dir`. These concrete
paths are private machine settings. The default state directory is
`$XDG_STATE_HOME/journal-day`, or `~/.local/state/journal-day`.

Fresh `cc`/`cc2` launches from home run `journal-day --seat cc|cc2`. Continue and
resume flags use `--resume-seat` to retain the last fresh physical cwd for that
seat. The old alias target is retained as a fallback for pre-migration sessions.
An explicit project cwd or custom `CLAUDE_ENVELOPE` is untouched. To resume a
specific older project conversation, use its original directory as before.

The helper refuses to replace a real directory or a symlink outside the dated
journal. If old work occupies the alias, preserve and triage it explicitly before
commissioning. Existing dated directories and contents remain unchanged. The
helper's file lock serializes its own calls; external schedulers should invoke
this same helper rather than independently replacing its alias. The final
symlink replacement is atomic, not a compare-and-swap against unrelated writers.

Recurring scheduling remains external. A scheduler may invoke plain
`journal-day`, which does not change a seat's saved continuation cwd. No timer,
cron entry or scheduler migration is part of this change. The one-time historical
landing and its private receipts are separate from future semantic composition.
