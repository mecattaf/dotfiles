# Direct NAS terminal metadata

`agency-kitty desktop terminal` registers its ordinary NAS SSH shell in the
same metadata catalogue as saved terminals. It creates no PTY holder and
executes Fish after a single registration. Input and output remain native
Kitty/OpenSSH traffic.

Pass context explicitly when opening a terminal:

```sh
agency-kitty desktop terminal --directory /home/tom/project \
  --workspace-id workspace-124 --chat-id chat-a --chat-id chat-b
agency-kitty catalogue --local --json
agency-kitty link TERMINAL_UUID --chat-id chat-c --workspace-id workspace-1000
```

The local catalogue command runs on NAS; omit `--local` on the seat. Workspace
references have no fixed numeric range. Links describe relationships; Imagine
retains window placement authority. The directory is the canonical NAS launch
directory, not a claim about a later foreground program's current directory.
Kitty user variables describe the launch context; a later link changes the NAS
catalogue rather than injecting an unsolicited GUI action.

## Lifecycle and identity

- Direct rows expose `mode: "direct"`, `resumable: false`, live status and
  `resume: null`. They never expose a holder version or holder socket.
- Registration binds the exact original NAS shell PID, process start time,
  boot ID and owned PTY device/inode. The Python bootstrap becomes Fish through
  `exec`, preserving that owner. Read-only catalogue queries verify those facts
  at the time of the query. There is no output watcher, polling service or
  per-key callback.
- Owner exit, reboot, PID/start mismatch, a changed PTY or inaccessible owner
  removes the entry from the live catalogue. Ended UUIDs remain reserved; a
  fresh owner cannot reuse them as either a direct or durable terminal.
- `describe` and `link` work for live direct entries without invoking a holder.
  `resume`, `attach`, `capture`, `close` and holder `rebind` refuse them. The
  saved-session chooser offers only resumable entries.
- The desktop launcher knows its first UUID before creating Kitty, so its
  actual OS-window class is `agencykitty-<uuidhex>`. New tabs share that class
  and each receive a fresh terminal UUID. Positive native Kitty window IDs are
  carried as additional metadata. A `direct` command run in an existing window
  reports an unknown class as `null`; it invents no mapping.
- A class identifies an OS window, and a Kitty window ID identifies a terminal
  within that Kitty instance. Neither grants remote-control or input authority.
  Persistent rows retain the older derived class as a launch hint; a separate
  live frontend reconciliation is needed for persistent sessions opened in tabs.

## Bounds and evidence

Records use owner-only directories and atomic 0600 files under the private NAS
session root's `direct/` directory. Reads use `O_NOFOLLOW`, validate file type
and ownership, and cap records at 32 KiB. The inventory is limited to 4,096
records and 512 KiB, including ended records. At the bound, registration fails
with an explicit archival message; it does not delete session state or start a
replacement transport. Administrative archival of ended metadata is an
explicit operation. It gives up those archived UUID reservations.

The combined direct/persistent metadata inventory has the same record and byte
bounds. Each terminal can link up to 64 chat IDs; workspace IDs are arbitrary
validated references up to 128 characters. These are metadata size limits,
not a nine-workspace desktop policy.

`tests/test_direct_registry.py` exercises actual owned private PTYs, original
owner death, boot/start mismatch, fresh-owner reuse refusal, private-file
symlink rejection, metadata bounds, multi-chat linking, endpoint refusal of all
holder actions, launch/tab class construction and an actual `remote direct`
bootstrap becoming Fish. `tests/test_harness_state.py` waits for the fixture
child's readiness before inspecting its PTY, avoiding the exec/dumpability
transition race without relaxing production validation.

Qualification runs through `runtime-test` on compute with private paths and
unchanged `HOME`. This test does not activate a laptop configuration or prove
physical display latency.
