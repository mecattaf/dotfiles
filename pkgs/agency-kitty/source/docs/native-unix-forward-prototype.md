# Local native client through SSH Unix forwarding

This is an explicit transport prototype, with no default or configuration
promotion. The NAS owns the persistent application and its sole application
PTY. Kitty remains the local terminal renderer.

The existing interactive-holder path carries terminal bytes through Kitty's
local PTY, OpenSSH, an sshd session PTY, a remote native client, the holder's
Unix socket, and the application PTY. This prototype attaches the compiled
client locally and uses a stock OpenSSH Unix socket forward instead:

```text
Kitty PTY → local native framing client → private local Unix socket
          → stock OpenSSH -N -L → exact NAS holder socket → application PTY
```

Python validates the canonical existing session, holder version and socket
namespace, then owns startup and child lifetime. It never reads, forwards or
rewrites terminal input/output. Its steady wait uses child lifecycle pidfds.
The compiled client's active attach path frames bytes and resize events; its
terminal parser/daemon code is not used locally. `ZMX_ATTACH_ONLY=1` prevents
create-if-missing. Local environment tracking, session switching and detach
prefix interception are disabled. The exact client and holder versions must
match. Private runtime sockets are owned mode 0600 within mode 0700 directories.
Closing the local view ends its own tunnel/client and leaves the NAS holder.

Initial phase attached only to an already-created holder. An explicit
`--provision-directory` phase now creates a new canonical NAS identity and runs
a bounded experimental control endpoint through ordinary `ssh -T`, with
stdin connected to `/dev/null`. NAS package settings declare the exact Kitty
assets through `AGENCY_KITTY_FISH_INTEGRATION_DIR` and `TERMINFO`; the endpoint
requires owned, non-writable integration/terminfo files and sets `TERM=xterm-kitty`.
It does not depend on a previous interactive login having installed them.
A temporary native client uses a pipe until its exact holder socket exists,
then EOF detaches that client. The daemon and sole application PTY remain;
the endpoint and bootstrap client exit before local attachment. The control
program remains explicitly selected, with no default terminal promotion.

Source inspection corrected an earlier assumption: `kitten ssh -T` is an
explicit passthrough to ordinary OpenSSH. It neither installs Kitty assets nor
runs the interactive kitten's cleanup/drain path. The prototype now invokes
ordinary SSH directly and gives it no access to local terminal input. Its
native version probe also uses an owned private runtime namespace.

Before each native attachment, the canonical `remote rebind` endpoint returns
bounded freshly encoded typed harness/editor state for that exact live UUID.
The client checks the UUID, live status, exact versioned socket and envelope
before emitting its own base metadata and that typed rebind. No terminal
recording, latest-transcript search or arbitrary control stream is read.

## Timing protection is a separate policy axis

The actual installed client is OpenSSH 10.4p1. Its exact release source is
commit `e8dd756725e8800fcd0b3fd71ee6b4382d1e8fab`, cloned for inspection. The
[`clientloop.c` obfuscation gate](https://github.com/openssh/openssh-portable/blob/e8dd756725e8800fcd0b3fd71ee6b4382d1e8fab/clientloop.c#L590)
requires an open TTY channel. The
[`channels.c` predicate](https://github.com/openssh/openssh-portable/blob/e8dd756725e8800fcd0b3fd71ee6b4382d1e8fab/channels.c#L990)
specifically checks `client_tty`; the
[`packet.c` small-data predicate](https://github.com/openssh/openssh-portable/blob/e8dd756725e8800fcd0b3fd71ee6b4382d1e8fab/packet.c#L2275)
also requires interactive mode. A forwarding-only `ssh -N` connection has
neither. Merely leaving `ObscureKeystrokeTiming=yes` in configuration does not
apply interactive keystroke padding to this path. The
[official manual](https://man.openbsd.org/ssh_config.5#ObscureKeystrokeTiming)
describes the interactive 20ms default and its traffic-analysis purpose.

Any later comparison must therefore keep architecture and timing protection
separate: the ordinary interactive-holder path with its actual default policy,
that same path with explicitly disabled obfuscation, and the forwarding-only
path. A gain between different policy axes cannot be attributed to removal of
the extra PTY. No latency result has been claimed for this prototype.

An off-path dummy TTY was investigated as a possible stock policy-equivalent
control. It failed that requirement. OpenSSH10.4's
[`CHANNEL_BULK_NOTTY`](https://github.com/openssh/openssh-portable/blob/e8dd756725e8800fcd0b3fd71ee6b4382d1e8fab/channels.h#L85)
classifies `direct-*` forwards as bulk. Its
[`client_loop`](https://github.com/openssh/openssh-portable/blob/e8dd756725e8800fcd0b3fd71ee6b4382d1e8fab/clientloop.c#L1635)
sets the global interactive flag false while any bulk channel is open. Thus an
open TTY channel cannot make the forwarded stream pass the second obfuscation
gate. Merely setting identical IPQoS values does not change this flag.

The bounded `--native-forward-timing-policy` diagnostic in `proof-6` confirmed
the exact source behavior: the TTY-only connection positively started native
20ms obfuscation, opening the actual holder forward classified it bulk and
switched global mode off, and real forwarded app input plus another TTY byte
did not restart obfuscation. The same SSH connection and configured `yes`
policy were used throughout. This is a negative capability result, so no
supposedly protected off-path-TTY product mode was added. Its retained debug
log is `proof-6/ssh-off-path-tty-debug.log`; the fixture is not a benchmark.

The true-local Neovim frontend's native RPC Unix forward has this same stock
SSH transport distinction. Encryption and host authentication remain; the
interactive terminal timing-padding policy does not carry over automatically.

## Actual qualification

The private stock-SSH fixture's `--local-native-forward` option invokes the
prototype after the normal SSH kitten has created and resumed its retained
NAS fish. `proof-2/receipt.json` on Strix passed the actual route using the exact
activated Kitty 0.50 binary and attested official Domicile engine 63db244:

- One raw key reached the NAS application without Enter.
- A native font change propagated SIGWINCH and exact rows, columns and pixels:
  47x155 / 1395x893 became 30x99 / 1386x900.
- A 4MiB paste remained byte-for-byte exact after the application deliberately
  stopped reading for 600ms; SHA256 was
  `3cab7815c40973b8fb036c7a2a69b3649882622a4a0a2f1a980efa4ef8545577`.
- Actual Kitty handled truecolor text, an OSC52 private clipboard write, an
  OSC99 notification, a PNG graphics placement, a user variable and a native
  keyboard-protocol query/response.
- Fresh local client PID3132 replaced 2426 while the same NAS app PID1967,
  its application PTY and retained fish PID1120 survived.

Receipt path:
`/home/tom/agent-work/kitty-consolidation/native-forward/proof-2/receipt.json`.
The repeated `proof-3/receipt.json` includes source hashes and additionally
launched a real unknown-UUID native attachment. It failed before forwarding or
NAS allocation, and the remote session inventory stayed byte-for-byte equal.
The initial proof only failed because its color assertion expected semicolon
SGR, while Kitty's native text export correctly used the equivalent colon SGR.
That fixture failure and its logs are retained.

`proof-4/receipt.json` additionally passed fresh provisioning and typed rebind.
Stock SSH kitten bootstrap had remote TTY allocation disabled. Its control
receipt asserted non-TTY stdin/stdout; the local caller validated it before
attaching. Fresh NAS fish PID3915 owned its sole application PTY, captured the
exact original hook context, and retained variables across fresh local clients.
A deliberately named typed hook fixture bound a private transcript UUID; the
canonical rebind restored it on the fresh client with no new hook. This was a
typed hook fixture, not a claim that a model or harness ran in this gate.
The actual provider-free Codex/Claude fixtures are independent qualifications.
`proof-6` repeated the full native forwarding and fresh-provision gates while
also establishing the timing-policy result above.

`proof-7` repeated all functional gates on the exact manual stable-v4-vt1
binary (SHA256 `2dc79e81add4ab50a202ea1b8189d2f6daf1b7d5a11148a27c788fec236044d6`).
The frozen source-built artifact then passed `proof-9` with SHA256
`204fe21bebcbdd3e9d2d4efa8713f669c269384c2b1b383b6705413ff9df988f`, activated
Kitty0.50 and the attested official63db244 engine. This gate additionally:

- Queued an actual complete command including Enter before fresh bootstrap;
  the retained NAS fish executed it after attachment with no Python input relay.
- Queued exact bytes before an existing holder's SSH describe/native startup;
  the existing NAS raw application received the complete sequence unchanged.
- Verified fresh fish had `TERM=xterm-kitty`, exact copied/hashed Kitty
  terminfo and the loaded upstream vendor integration.
- Used native Kitty command-output boundaries to retrieve only
  `OSC133_NATIVE_MARKER`, and read its actual OSC7 cwd as the NAS nested directory.
- Retained the same fresh NAS fish, variables and canonical typed harness
  binding across another local client without a new hook.

The Enter gate uses a test-only bounded pause in the private SSH shim before
its actual remote control command. Production code never adds a pause, reads
terminal input or replays an early-key buffer. Fixture copies only public Kitty
assets, hashes them against the exact package, and retains production ownership
validation even though its user namespace maps store uid0 to nobody.

These are isolated software/loopback functional gates. They do not measure
physical keyboard/display latency or Tailscale. Stable-v4's independent native
reconnect-graphics qualification belongs to its dedicated backend receipt.
This architecture still changes the SSH interactive timing-padding policy,
which remains a separate required decision before any default promotion.

`proof-11` adds actual primary editor lifecycle coverage on that frozen binary:
one Ctrl+B opens the left native tree, the parent native client remains alive,
NAS fish `vi` blocks while a true local Neovim UI edits its retained NAS server,
and a lost lifecycle lease leaves the original request and unsaved buffer alive.
A fresh local native terminal attachment consumes canonical typed rebind and
automatically opens the same pending request against the same NAS editor PID.
`:detach` completes the original blocked fish command with status0. Local fish
`vi` also uses that same directory editor in its existing native terminal;
explicit editor-window close returns129, and unmanaged NAS vi refuses with
actionable guidance and no alternate editor allocation. The provisioning
client's diagnostic stderr now has an incremental16KiB cap; an oversized real
child is killed without marking its canonical session active.

The combined `proof-13` passed all of the above with the complete32-plugin
configuration: catppuccin/noir colors, Markdown Tree-sitter, marksman, native
clipboard, actual Markdown PNG and fresh-UI retransmission. Two simultaneous
local UIs used native9x19 and14x30 font cells while each retained the full
1280x640 source image, correct aspect and actual split-viewport clipping.
Closing the first UI transferred the stable geometry anchor to the second.
The same gate restored pending primary vi through the native holder forward.
Its failed predecessor `proof-12` exposed a fixture race that checked the
Nvim marker before the local native UI process existed; readiness now also
requires the actual `--remote-ui` foreground process.
