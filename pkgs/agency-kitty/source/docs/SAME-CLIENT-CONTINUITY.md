# Keeping the same Kitty across a network loss

A surviving local Kitty **and a surviving client with recovery state** can
continue an ordered raw terminal stream without reconstructing a screen. That
is useful for thin-client sleep: Kitty already owns the real keyboard modes,
palette, image cache, placements, history and any partially received escape
sequence. Delivering only the missing original bytes avoids a shadow VT's
serialization limits. This is an architectural distinction, not a newly
implemented or runtime-qualified guarantee in this project.

There are three different cases:

- The existing TCP/SSH connection survives an interruption. Its ordinary
  reliable stream can continue; no application-level reattachment occurred.
- The network connection dies, but both protocol peers, their sequence/queue
  state, the remote PTY and the same local Kitty survive. An acknowledged
  catchup protocol can continue that stream on a new connection.
- The local client, Kitty window, server recovery state or machine is lost.
  Keeping only a remote shell does not recreate the missing local terminal
  state. A fresh frontend needs a separately qualified restoration mechanism.

The second case can preserve state the holder cannot serialize, including
native Kitty protocols unknown to libghostty. The inference requires complete,
ordered byte delivery, the same frontend state, and no intervening reset,
output deletion or replacement. It does not establish every protocol's
external resources or application behavior from source inspection alone.

## Eternal Terminal already implements the recovery mechanism

The existing clone is pinned to Eternal Terminal
[`060b18e7c4c8ac2ece6cac383282d7aefb942817`](https://github.com/MisterTea/EternalTerminal/tree/060b18e7c4c8ac2ece6cac383282d7aefb942817),
Apache-2.0. This pass read the source without building, installing, testing or
measuring it. Its optional HTM multiplexer is separate; direct ET does not
require a terminal layout manager.

Its normal [surviving-client reconnect](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/base/ClientConnection.cpp#L63-L75)
keeps the existing reader/writer. Both peers exchange received packet counts,
then resend the missing encrypted packets before returning to live traffic.
These are packet sequence counts, not a saved terminal screenshot or a
Kitty-specific parser. The [recovery exchange](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/base/Connection.cpp#L119-L215)
serializes reader/writer recovery, preserves the catchup order and rejects
invalid sequence/reset requests.

The [writer](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/base/BackedWriter.cpp#L16-L113)
backs up a packet before attempting to send it. A failed send is therefore not
an instruction for its caller to submit that packet again. The
[limits](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/base/BackedWriter.hpp#L29-L72)
are a 64 MiB connected recovery tail and at most another 64 MiB admitted after
disconnection. Those are packet-byte budgets, not whole-process RSS caps;
objects, framing and catchup copies add memory. When the disconnected budget
fills, admission waits and eventually backpressures the producer. If a peer
requires a sequence already evicted from the connected tail, recovery fails
with `Client is too far behind server.` Bounded memory cannot also promise
unlimited offline output and lossless continuation without backpressure.

The [reader counter](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/base/BackedReader.cpp#L116-L154)
records protocol receipt, including catchup entries retained in its local
queue. It is not an acknowledgement that Kitty parsed the bytes or a command
committed an effect. The client separately queues terminal output before
[writing it to the console](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/terminal/TerminalClient.cpp#L617-L675).
On the server, input passes through a separate
[pending PTY-input buffer](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/terminal/UserTerminalHandlerUnix.cpp#L467-L475).
Surviving queues are therefore part of the contract. These counters support
ordered transport recovery; they do not give exactly-once shell commands,
filesystem effects or recovery after a peer loses its memory.

There is an important obstruction to calling the current interactive ET an
unchanged, all-native-bytes solution. Its
[client interrupt handling](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/terminal/TerminalClient.cpp#L574-L588)
intentionally removes queued droppable output on Ctrl+C/Z/backslash input. The
[server](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/terminal/TerminalServer.cpp#L564-L589)
can discard a flood backlog of at least 64 KiB and drain more pending output.
The [output queue](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/src/base/WriteBuffer.hpp#L9-L31)
also has explicit tmux-control filtering/reordering policy. This is deliberate
interrupt responsiveness, but a dropped span inside a graphics/control string
is incompatible with a strict promise to deliver every original Kitty byte.
This is a source finding, not a reproduced ET corruption incident or a reason
to dismiss its existing reconnect design.

Fresh-process `et --attach` is explicitly different:
[reset recovery](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/docs/protocol.md#reset-recovery)
negotiates a new epoch, exchanges empty catchup buffers and restarts counters.
The saved session credentials do not preserve the former client's queues or
Kitty state. A retained remote PTY, reset transport or resize event does not
prove full native fresh-window reconstruction.

ET also introduces a separate authenticated reconnect transport and server
endpoint, normally TCP 2022 after SSH bootstrap. Any actual adoption needs its
own reviewed Tailnet/service/configuration boundary and native functional
admission; it is not simply enabling Kitty's existing SSH option. Its default
telemetry policy is documented upstream and would need an explicit packaging
choice. No ET service, credentials or policy changed in this investigation.
[Programs and configuration](https://github.com/MisterTea/EternalTerminal/blob/060b18e7c4c8ac2ece6cac383282d7aefb942817/README.md#installed-programs).

## What the other existing references do

The pinned [dtach `b027c27b`](https://github.com/crigler/dtach/blob/b027c27b2439081064d07a86883c8e0b20a183c9/master.c#L248-L339)
and [abduco `8c32909a`](https://github.com/martanne/abduco/blob/8c32909a159aaa9484c82b71f05b7a73321eb491/server.c#L181-L292)
are useful remote PTY owners. Their inspected raw relay loops have no
per-viewer sequence acknowledgement or retained missing-output journal.
They can read output without a surviving recipient; reattaching does not
recover that missing byte stream. Abduco's own
[manual](https://github.com/martanne/abduco/blob/8c32909a159aaa9484c82b71f05b7a73321eb491/abduco.1#L48-L61)
explicitly distinguishes raw relay from preserved terminal state.

[Shpool `0433875f`](https://github.com/shell-pool/shpool/blob/0433875f17a318e7b9334b1c37a2de3f7eaea152/libshpool/src/session_restore.rs#L41-L79)
restores through its configured spool/parser, or a null spool. Choosing no
restoration does not add missing-byte acknowledgement. These projects provide
process ownership; they are not interchangeable with ET's surviving-peer
packet recovery. An arbitrary SSH reconnection around them does not add it.

## What our current implementation does

The opt-in [SSH supervisor](../agency_kitty/attachment.py) preserves the local
Kitty view but starts a new stock SSH child after exit 255, after checking the
exact retained NAS identity. That child starts a new holder attachment and
its restore handshake. It does **not** preserve a peer's received-output
offset, catch up only missing bytes, or safely retry bytes consumed by a dead
SSH child. The same visible window still receives a newly serialized snapshot;
it has the documented fresh-attach limits.

The [native-forward client](../agency_kitty/native_forward.py) likewise is not
an implemented roaming loop. It launches one local compiled holder client over
one SSH Unix forward; a tunnel failure ends that attachment. Its retained NAS
PTY is useful, but the next client still requests restoration. Neither route
currently offers ET-style same-peer raw continuation.

Kitty's SSH kitten prepares terminfo, shell integration, files and convenience
connection sharing around stock SSH. Its
[0.50 launch path](https://github.com/kovidgoyal/kitty/blob/v0.50.0/kittens/ssh/main.go#L918-L946)
gives SSH the inherited terminal descriptors. Its
[ControlMaster/ControlPersist settings](https://github.com/kovidgoyal/kitty/blob/v0.50.0/kittens/ssh/main.go#L123-L146)
do not introduce a remote PTY owner or acknowledged catchup protocol.
[OpenSSH's ControlPersist](https://man.openbsd.org/ssh_config#ControlPersist)
keeps a shared connection available; it cannot replace that connection after
loss and reconstruct its former session channels. Brief outages may already
be survived by the same TCP/SSH connection, subject to both ends' timeouts.
That is not a guarantee for laptop sleep of arbitrary duration.

For a future same-frontend mode, the useful existing starting point is ET's
surviving-peer recovery, with its byte-dropping policies explicitly resolved
and the full native gates run. Required distinctions are exact terminal/peer
identity, surviving sequence/partial-write queues, bounded retention with
backpressure, and an explicit refusal when recovery history is unavailable.
New-window/process-loss recovery remains a separate feature. This document
does not add a transport, claim ET admission, promise command side effects,
or change the standalone SSH default.
