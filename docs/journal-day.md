# Fresh day workspaces

`journal-day` creates the current date directory under an existing configured
journal and atomically points a convenience symlink there. It prints the
permanent physical directory. It neither moves old work nor generates a brief,
reads notes, changes running sessions, harvests chats or schedules a job.

The host-local `~/.config/journal-day.json` contains `journal_root`, `today_link`,
and optionally `timezone` (default `Europe/Paris`), `state_dir` and
`session_commands` (default `["claude", "codex", "dsh"]`). These concrete
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
`journal-day`, which does not change a seat's saved continuation cwd.

## Unattended rotation

A plain call (no `--seat`) is the unattended rotation. It refuses, with exit
status 75 and a `Refusing to rotate while a session is open in <day>: pid N
(name)` line on stderr, while a harness process has its cwd at or under the day
the link would leave. Harnesses are matched by the basename of `argv[0]`, or by
`comm`, against `session_commands`; wrapped binaries and node CLIs often carry
another `comm`, so `argv[0]` is the one that counts. Idle shells do not count,
and neither does the caller's own process ancestry, so a worker that sits in the
day can still run it. Rotating never moves a running session (the kernel keeps
its cwd); the refusal keeps one session's writes through the link from being
split across two days. Status 75 is not a failure: nothing changed, and the next
fresh seat launch or the next scheduled run rotates. An already-correct link is a
no-op whether or not a session is open. Seat launches always rotate.

`--dry-run` prints the directory a run would select and returns the status a run
would return, but creates, locks, writes and rotates nothing: no day folder, no
state directory, no link.

A scheduled item's brief is one call and three outcomes: run `journal-day` once
with no arguments; on 0 report the printed path; on 75 quote the stderr line and
end without retrying; on anything else quote stderr and stop. It changes nothing
else. No timer,
cron entry or scheduler migration is part of this change. The one-time historical
landing and its private receipts are separate from future semantic composition.

## Unknowns and proposed defaults

External scheduler commissioning and semantic memory compilation remain outside
this helper. Use the original project cwd for a specific older conversation;
the remembered seat directory is the default for continuing its latest launch.
