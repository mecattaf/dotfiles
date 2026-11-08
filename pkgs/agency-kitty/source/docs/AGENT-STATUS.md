# Native agent status and pending image callbacks

Managed Claude/Codex launch captures one exact PID, process start, group,
session and boot identity before exec. SessionStart attests that process's
actual executable device/inode after exec. Typed hooks remain the status
source; no screen parser, resident monitor or input proxy is added.

Both durable and live direct terminal identities can save this private state.
Direct hooks must match the original registered shell/PTY context. On catalogue
read, the original owner remains valid and its Linux foreground process group
must match the exact agent process. A stopped/background process reports
`background`; a crashed/replaced process reports `ended`, even while fish
survives. Legacy bindings without invocation tracking report `unverified`.
Only verified foreground invocations expose `idle`, `working`, `done` or
`waiting`. SessionEnd can clear its matching occupant after the shell exits;
an old process/session cannot clear a newer one.

The DSH catalogue's optional `agentStatus` contains exactly `version`, `harness`,
`state`, `foreground` and `verified`. It includes no transcript path/content,
prompt, model response or process command line. This does not mutate DSH chat
attention or choose sound/notification policy. The existing desktop frame can
add an explicit projection separately; this change does not modify Imagine.

Async image/file/voice paste work captured for a bound harness performs one
bounded pinned-NAS validity query after staging, before callback delivery. A
background, ended or unverified occupant receives zero input. The Kitty GUI
callback remains nonblocking and rechecks its exact window, SSH child, terminal
UUID and harness session. The NAS check precedes callback delivery; it is not
an atomic cross-host input compare-and-swap. Shell-command-stop watchers are
unchanged, so historical OSC133 markers during reconnect cannot erase a fresh
binding. New tracked background/dead invocations do not replay stale bindings.
Codex defers SessionStart until its first submission. Before that first typed
hook there is no exact harness-session binding; existing generic-terminal
callback semantics remain. This change does not claim invocation tracking for
that phase. Ordinary native text clipboard fallback is unchanged.

Evidence on compute:

- `test_agent_status.py`: actual private PTY job control with a surviving shell
  owner, direct and persistent records, suspend/foreground/crash transitions,
  old-process refusal and SessionEnd after owner exit.
- `/home/tom/kitty-consolidation/proofs/codex-agent-status-2-final/receipt.json`:
  actual managed Codex0.167 image attachment, exact hooks/trust, semantic history,
  suspend/refuse/resume through the actual helper validity endpoint.
- `/home/tom/kitty-consolidation/proofs/claude-agent-status-2-final/receipt.json`:
  the same actual managed Claude2.1.319 gate with preserved user hooks.

The TUI proofs use private offline providers and configuration. Their validity
endpoint runs as a real helper child; only the test SSH endpoint is redirected
locally and GUI delivery is observed by a spy. They establish the foreground
decision and worker refusal, alongside the already qualified native Kitty
callback. They do not claim a new physical GUI or fresh-SSH reconnect gate.
