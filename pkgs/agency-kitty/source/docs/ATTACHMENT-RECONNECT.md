# Optional persistent SSH reconnect

The production CLI opts in with `AGENCY_KITTY_RECONNECT=1` and
`AGENCY_KITTY_SSH_TRANSPORT=plain`; reconnect defaults to `0`. The setting can
prefix persistent `open`, `new`, `resume`, `menu` or `attach` and is inherited by
launched windows and later tabs. Direct sessions continue to exec SSH and end
with their SSH-owned PTY.

`attachment.supervise(session, argv, transport, policy=RetryPolicy(), env=...)`
waits on the inherited-terminal stock OpenSSH child. The CLI validates the
transport and opt-in before allocating a persistent session.

The supervisor performs no terminal reads, local echo, byte forwarding or input
rewriting. Active SSH owns the terminal. During initial lookup and reconnect
waiting, no-echo raw mode with local signal handling uses `TCSANOW`; final mode
restoration also uses `TCSANOW`, with no input flush. Bytes already consumed by
a dead SSH connection cannot be recovered or safely retried; typeahead still
queued in the local terminal is preserved for the next child. The remote v4
holder's RestoreReady/input ordering remains authoritative.

Initial canonical describe must identify this exact NAS UUID, persistent mode,
immutable launch directory, holder version and live owner. An explicitly newly
created record may be `created`/not-live for its first attachment. Direct, closed, unknown or foreign
identities are refused. Only exit 255 enters retry logic; other exits return.
Before every retry, a bounded `stdin=DEVNULL` canonical rebind must confirm the
same live UUID/version. An absent owner never triggers create, status reset,
replacement, host change or fallback transport. The static reviewed attach
argv must exactly equal the plain transport's canonical `attach_argv(session)`,
excludes allocation flags, and is reused verbatim. Linux pidfd readiness and a
private signal wake pipe block while SSH runs; there is no periodic active-child
check or terminal descriptor in this wait.

Defaults bound one unstable outage burst to 5 retries and 45 seconds, with
250 ms initial backoff capped at 4 seconds and 5-second canonical probes. A
30-second SSH-child lifetime resets that burst; this is child-running duration,
not an independent application-readiness measurement. Policy values have explicit
bounds. Exit 255 is the OpenSSH error convention, not proof that every such
error was a network fault; canonical verification and retry limits still apply.

SIGINT, SIGTERM and SIGHUP cancel reconnection and signal only the currently
owned SSH/probe child PID. Bounded teardown escalates only that PID. There is no
process-group kill, daemon restart or user-manager action. Terminal close is
handled by the inherited PTY and signal path.

Private functional evidence:
`/home/tom/kitty-consolidation/reconnect-proof/proof-5-frozen/receipt.json`.
The fixture uses actual stock `ssh -tt`, the existing externally supervised
private sshd, and exact source-built v4 NAS holder SHA256
`6a217563…aeed02`. A fixture-only loopback TCP fault injector closes one encrypted
SSH connection; no production relay is introduced.

The test preserves the same retained application PID/start/TTY, queues one
command plus literal Enter during backoff, and verifies exactly-once receipt.
Normal exit 0 and explicit remote helper exit 2 do not reconnect. Ended/unknown/direct
identities are refused without replacement. SIGINT closes the owned SSH child
while the NAS application survives, and caller terminal modes are restored.
HOME remains unchanged with the real home masked; login logs, runtime, network
and generated SSH keys are private. No latency samples or production sockets
are used. The inherited local PTY is tested without launching a graphical Kitty
window.

An unknown reconnect value or `kitten` plus reconnect refuses before allocation.

`tests/attachment_reconnect.py --cli` exercises the actual
`agency_kitty.cli.main(['attach', UUID])` entrypoint against a separate private
local metadata mirror and canonical NAS store. It observes owned interactive
SSH child PIDs through `/proc` without patching the CLI or supervisor. The
fixture retains all baseline refusal/cancellation checks and collects no
latency samples.

Actual CLI qualification passed with 149 aggregate Python tests:
`/home/tom/kitty-consolidation/reconnect-cli-proof/proof-1/receipt.json`.
The CLI source hash is recorded alongside the supervisor, SSH and holder hashes.
The same NAS application PID/start/TTY survived the forced loss, the local queue
received input while no interactive SSH child existed, and a fresh owned SSH
child delivered the command plus Enter once. The CLI then propagated normal
exit 0 without reconnecting.
