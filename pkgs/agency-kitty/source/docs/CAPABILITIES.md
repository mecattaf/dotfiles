# Native Kitty capability sidechannels

Normal typing and rendering stay in Kitty and SSH. These helpers run only after
an explicit gesture or a harness lifecycle event. There is no byte proxy,
render timer, output poller, global key listener or terminal multiplexer here.

## Installed interfaces

The root CLI dispatches `agency-kitty capability ...` to
`agency_kitty.capabilities.cli.main(argv)`. Install `kitty/agency.py` and
`kitty/agency_watch.py` beside the editor helper, and enable the watcher through
Kitty's `watcher` setting. All mapped gestures require `agency_host` and
`agency_session` user variables from the launcher. Workspace ownership remains
in Imagine and dsh-domicile.

The custom kitten supports `image`, `files --file ABS_IMAGE ...`, `copy`,
`transcript`, `editor-tree`, and `arm-drops`. `editor-tree` delegates to the
separate `agency_editor.sidebar` helper. No image worker opens a hidden overlay:
Kitty 0.48's behind-overlay mechanism buffers typing until the overlay is ready.
Background workers instead return through a remote-control custom-kitten
callback addressed to one window. Large payloads use Kitty's public Unix socket
protocol, avoiding operating-system argv limits. The callback compares window id, child pid,
host, managed terminal id and harness session id immediately before insertion.
A closed, rebound or replaced destination receives nothing. It never chooses
the window currently in focus as a fallback.

`image` reads the explicitly invoked local Wayland clipboard. It prefers PNG,
JPEG, GIF and WebP, verifies magic bytes against MIME, limits input to 16 MiB,
and bounds clipboard-owner response time. Explicit batches contain at most 16
images and retain one image payload in memory at a time. All uploads finish
before the first path is inserted. If there is no image, it invokes
Kitty's native clipboard paste into the captured destination. Image payloads
travel over a separate ordinary SSH invocation pinned to NAS's Tailnet address
`100.65.85.114` with `HostKeyAlias=nas`, strict host-key checking, no agent
forwarding and no reused ControlMaster. GUI and CLI reject another host or a
noncanonical managed UUID4. The fixed
`agency-kitty capability image-store EXT` helper writes a unique
0600 file in the user's 0700 `XDG_CACHE_HOME/agency-kitty/images` directory and
returns its absolute NAS path. Kitty performs terminal-mode-aware bracketed
paste of that path, quoting it when needed. Multiple images use individual
bracketed-paste events: Codex recognizes one image path per event. No Enter key is added. Multiline text is refused if the
destination has disabled bracketed paste, preventing newline-as-submit.

Image retention is explicit: `capability prune-images --older-than-hours 24`
removes only this helper's own regular image files. Delivery never runs a
global cleanup or deletes another application's files.

The drop adapter is qualified for exact Kitty 0.48.0 and 0.50.0. Those versions have no public
drop watcher; a wrapper on the tagged window's own `on_drop` method intercepts
local image URI lists, with no file reads or waits on the GUI thread. Other
content and unregistered/rebound windows retain native behavior. The wrapper
must be qualified before admitting another Kitty release.

Native drag selection and wrapping remain Kitty's. A second version-qualified
adapter observes Kitty's selection-complete callback after the native clipboard
operation has finished. It emits a generic native `Copied` notification and
`agency_feedback` event for the exact registered window. It never includes the
selected text. The original callback is restored when the last registered
window closes, provided the installed wrapper is still ours. No timer or
per-mouse-move hook is installed.

## Full agent history and native shell scrollback

`capability transcript --harness claude|codex --path ABS_JSONL [--stdout]`
exports saved semantic messages. It reads a stable prefix of one explicit
session file, tolerates a final record still being written, omits internal
metadata and thinking, and optionally includes tool calls/results with
`--include-tools`. It does not synthesize a terminal history from pixels or
claim to recover information the harness never persisted.

The `transcript` kitten gesture uses `agency_harness` and `agency_transcript`
when bound, snapshots the remote semantic history, and opens a separate local
read-only Nvim view. Live buffers are not renamed or repurposed. Without an
exact harness binding, the gesture resolves the existing
`kitty_scrollback_nvim` action alias, then falls back to Kitty's native
scrollback pager if that alias is absent.

Both current Claude Code and Codex support `SessionStart`/`SessionEnd` hooks
whose stdin JSON identifies `session_id` and `transcript_path`. The managed
fish launchers now install these for one invocation through `agency-kitty
harness claude|codex -- ORIGINAL_ARGUMENTS`. For other explicitly managed
launchers, configure
`agency-kitty capability bind-harness --harness claude` or `--harness codex`
for those lifecycle events. The remote PTY must export
`AGENCY_KITTY_SESSION=<managed-terminal-id>`. Hooks are inert in unmanaged
terminals. The managed shell launcher captures `AGENCY_KITTY_TERMINAL` once
before exec: original owned PTY, owner PID and process starttime. Hooks emit
single encoded OSC 1337 events through that verified original PTY, leaving
hook stdout/model context empty. This is necessary for Codex0.163, whose hook
runner starts a new session and has no `/dev/tty`. Before writing, the helper
checks that the original process and its stdout descriptor still identify the
same owned character PTY; a dead/reused owner receives no event. The local watcher validates the managed
session and binds the exact transcript. An old SessionEnd event cannot clear
a newer binding, and inherited `CODEX_THREAD_ID` prevents a Codex child agent
from rebinding its parent's window. There is no latest-file guess, history
directory scan or SQLite dependency.

The scoped launcher adds `capability harness-event --harness claude|codex` for
`UserPromptSubmit` and `Stop`, and
Claude's relevant `Notification` hooks, to publish exact-session `done` or
`waiting` metadata. `Stop` means a completed turn; `SessionEnd` never emits a
completion cue. A new prompt explicitly changes `done`/`waiting` to `working`
and clears old attention. The watcher validates the current harness occupant and sets
`agency_attention` plus `agency_status` for a DSH/Imagine consumer. It includes
no response text. DSH owns whether those events produce a sound or notification;
the terminal helper adds no duplicate alert policy.

At the start of this run, NAS Codex was `codex-cli 0.163.0`; its exact upstream release source
(`83086188ae0614bd882818ff1aa23f3194962012`) defines SessionStart, SessionEnd and
Stop in its config schema and serializes the exact input fields in
[hooks/src/schema.rs](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/hooks/src/schema.rs#L499).
[core/src/hook_runtime.rs](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/core/src/hook_runtime.rs#L155)
passes the active session and `hook_transcript_path()` into those hooks. That
path is explicitly nullable for non-local/ephemeral threads; such a start
updates occupant identity and clears an older history binding, retaining native
scrollback. Codex0.163 defers SessionStart until the first submitted turn;
its initial idle composer has no transcript binding yet. The exact source
also recognizes a single pasted image path using its image dimensions and
attaches it without submission. These contracts were then tested against the
actual installed TUI with a fully offline Responses fixture, as below.

The hook contract is documented by
[Claude's hook reference](https://code.claude.com/docs/en/hooks#sessionstart-input)
and [Codex's hooks configuration](https://developers.openai.com/codex/config-reference).

## Notifications, sounds and voice

`capability notify TITLE --body TEXT` emits encoded native OSC 99 notification
bytes. Payload encoding prevents injected terminal escapes, and notifications
do not request a focus change. Agent lifecycle notifications can remain in
their native harness or DSH event source; this package adds no notification
daemon or screen-state detector.

`capability sound startup|voice-start|voice-end|disconnected|done|attention`
plays an existing local asset. The four Anthropic captures are read from
`AGENCY_KITTY_AUDIO_DIR`, defaulting to
`~/.local/share/agency-kitty/audio`; no proprietary assets enter this Git tree
or its package. `done` and `attention` use the existing freedesktop themed
`complete.oga` and `message.oga`. Sound playback is explicit; no global key
binding or automatic sound policy was enabled.

The exact historical captures were recovered from the verified NAS colors
archive and staged privately at
`/home/tom/.wt/kitty-consolidation/private-audio/`. Their preserved manifest:

- `startup.mp3`: `69f33a819d946be619ecc134f36a70012eeaba332f576016e13d2a3cf99cf51c`.
- `enter_voice_mode.mp3`: `51680f6e9e5632fc4a0d4a8d32b63a0c24752dc728657db685af1c8759cf9bed`.
- `exit_voice_mode.mp3`: `9ecf7cd1d82a84388a6bbfb5d458f78a5c2ef388f6acb7451d0b6448984df178`.
- `disconnected.mp3`: `8a21b3e6f40e855572ebe0f87c084bb883de103db1584a3fc7105b109efe3655`.

`capability voice-text` accepts final UTF-8 text on stdin and the complete
captured target arguments. It uses the same literal paste callback and never
submits. This is a seam for the system-wide recording/ASR utility; there is no
bare-Space interception, recording daemon or speech model in this package.

## Qualification

All tests ran on strix-coordinator through `runtime-test`. Nothing was deployed
to a live desktop or typed into a live agent/editor.

- The capability unit tests cover bounded/mismatched images, private permissions,
  symlink refusal, narrowly scoped expiry, exact SSH argv, exact Unicode and
  newline delivery, stale windows/children/sessions/harness occupants,
  lifecycle binding identity, copy callback restoration, transcript filtering
  and safe OSC payload encoding. A 200 KB callback payload verifies that no
  individual argv-size limit truncates literal text. SSH subprocess input,
  stdout and stderr are streamed concurrently under allocation/time limits.
- `tests/ssh_image_roundtrip.py` starts a private loopback sshd with throwaway
  keys and an explicit private SSH configuration. It transferred 1,048,584
  image bytes unchanged, verified SHA-256 and 0600/0700 permissions, and refused
  an oversized image before SSH. No real credentials were read or copied.
- `tests/native_capabilities.py` launched a private Domicile session and exact
  Kitty 0.48.0. It observed the expected 41 bracketed-paste bytes, no implicit
  Enter, refusal of stale-child/stale-session/rebound callbacks, and one Kitty
  window with no worker overlay. Trusted compositor mouse events through a
  private DevTools target performed an actual native text drag and produced
  generic Copied feedback and a visible native Copied notification. Real OSC
  1337 output from the fixture PTY bound its exact harness transcript and
  published a completed-turn attention event; an occupant switch then returned
  a zero-input refusal. The receipt is
  `/home/tom/kitty-consolidation/proofs/native-capabilities-9/receipt.json` on
  compute. The SSH receipt after route hardening is
  `/home/tom/kitty-consolidation/proofs/ssh-images-pinned-1/receipt.json`.

The joint native proof also exercised a real local Wayland image clipboard,
the background production capability CLI, real SSH with throwaway keys, the
NAS file helper and the exact original Kitty TUI insertion in one run. It used
an abstract Kitty control socket as the live configuration does, verified the
68-byte PNG's SHA-256 and observed no Enter or worker overlay. Its test-only
SSH shim changes only the network endpoint; the production command still
contains the pinned NAS host identity and strict options.

Harness history is a semantic
JSONL export, not a pixel-identical capture of the harness-owned alternate
screen or its unsaved prompt. These boundaries remain explicit.

The isolated desktop emitted FUSE/portal/systemd-activation warnings because
the wrapper intentionally provides no live desktop runtime or devices. Logs
were retained; no live services were restarted or failures hidden.


## Native session chooser

`agency-kitty choose --directory /home/tom --workspace-id REF --chat-id CHAT`
opens a deliberate fzf menu on its own controlling TTY. Its catalogue is a
bounded, pinned NAS metadata read. Existing entries resume their exact UUID
through the public launcher, which rechecks liveness; unavailable PTYs are
not offered. Only selecting **New persistent NAS terminal** calls `open` with
the explicitly supplied directory, Imagine workspace, and DSH chat references.
Escape, catalogue failure, and unknown selections allocate no terminal. No
Sway workspace numbering is carried forward. `--linked-chat CHAT` optionally
filters existing entries without changing their bindings. The chooser ignores
inherited fzf default options and never supplies a preview or shell action.

`tests/chooser_tty.py` exercises the real installed fzf in a private controlling
TTY under `runtime-test`: exact existing-row selection, Escape cancellation,
and ignoring an injected default execute binding all pass. Receipt:
`/home/tom/kitty-consolidation/proofs/chooser-tty-2/receipt.json` on compute.
The parent launcher owns the Domicile entry point and the intentional Kitty
window/overlay that hosts this menu; background capability workers do not use it.

## Kitty 0.50 admission

The exact 0.50.0 candidate at
`/nix/store/rsa87scsxdhcdczvqqmlli13kmf4pclc-kitty-0.50.0/bin/kitty`
passes the same private Domicile native proof as 0.48: actual compositor drag
selection, visible native Copied popup, actual clipboard→private SSH→NAS file→
abstract Kitty socket→bracketed path paste, no implicit submit/worker overlay,
OSC harness binding/turn attention, and stale destination refusal. Receipt:
`/home/tom/kitty-consolidation/proofs/native-capabilities-050-1/receipt.json`.
The narrow selection/drop adapters admit only these two qualified exact
versions; other versions retain native drop behavior. File-drop adapter
installation and delegation are tested; this receipt does not claim an actual
cross-application Wayland file drag. The 0.50 remote-control PID reports the
child root process, so target snapshots use `child.root_pid` when available.


## Actual Codex harness proof

`tests/codex_tui.py` runs the exact installed Codex0.163 TUI on a private PTY,
inside `runtime-test` and a separate network namespace containing only its
loopback mock Responses server. A private bind masks `~/.codex`; HOME remains
unchanged and CODEX_HOME is never assigned. The provider has no credentials or
Authorization header. No real model request is sent. The actual TUI attaches
an existing PNG when its path arrives in a bracketed paste; no request occurs
until the test explicitly presses Enter. Its actual main request contains an
`input_image`. Codex also sends one optional automatic-title request to the
same offline fixture. Actual SessionStart, Stop and SessionEnd hooks reach the
production hook CLI, which emits metadata through the captured original PTY
rather than hook stdout. A real live JSONL transcript exports the first and
last of300 assistant lines from a40-row TTY, plus the user prompt. Current
Codex content provenance labels exclude generated environment blocks even
when their API role is `user`. Receipt:
`/home/tom/kitty-consolidation/proofs/codex-tui-7/receipt.json` on compute.
This is an actual harness interpretation proof, separate from the native
clipboard/SSH/Kitty transport proof; it is not a production deployment.

## Rebinding after client disconnect

`harness_state.record_event` stores only validated lifecycle metadata for an
already existing NAS terminal UUID, at `SessionStore.root/harness/UUID.json`.
There is no transcript text, input, arbitrary escape stream or latest-file
scan. Each explicit hook update verifies the original live PTY context, holds
a bounded per-UUID lock, and atomically replaces a bounded0600 JSON file in a
verified0700 directory using directory descriptors and NOFOLLOW. SessionEnd
and attention updates require the current exact harness and PTY owner; an old
exit cannot erase a newer occupant. An ephemeral/direct identity has no saved
session record and allocates no binding state.

`harness_state.read_rebind(UUID)` revalidates that exact original PTY owner and
constructs fresh typed binding/attention OSC events. Missing, ended or dead
owners return an empty result; malformed/unsafe state is refused. The remote
attach wrapper can emit these before entering the holder, restoring the exact
running harness in a fresh Kitty client. It never replays stored escape bytes.
The local watcher clears the previous occupant's attention when binding or
unbinding, then applies any separately restored attention event.

Five additional tests exercise typed restoration, original-owner death, null
history paths, old SessionEnd refusal, private modes, unknown-session refusal,
and symlink/size bounds. The actual offline Codex proof also writes real hook
state and reconstructs binding plus attention while the same Codex PID is
still running; receipt
`/home/tom/kitty-consolidation/proofs/codex-tui-state-1/receipt.json`. The fresh
SSH/Kitty reconnect gate is tracked separately by the native transport fixture.


## Actual Claude harness and special image paths

The exact installed Claude Code2.1.306 bundled image-path parser was inspected
locally, without copying or distributing proprietary code. It accepts shell
backslash escapes and paired outer quotes, reads the referenced image,
validates its MIME, and creates an image chip. The official
[image workflow](https://code.claude.com/docs/en/common-workflows#work-with-images)
likewise supports drag, clipboard, and image paths. The pasted-path bridge uses
backslash escaping rather than POSIX quote concatenation, which Claude's path
parser does not understand when a path contains an apostrophe.

`tests/claude_tui.py` qualifies the actual2.1.306 TUI in its fullscreen renderer,
with `.claude` and `.claude.json` privately masked and only a loopback Messages
fixture reachable. Only a declared dummy fixture key is supplied, with no real
credentials or external model calls. An image path containing spaces, an
apostrophe and a literal backslash becomes `[Image #1]` without submission;
after explicit Enter, the actual request contains image bytes. Actual
SessionStart/Stop/SessionEnd run the production hook CLI, emit correct exact
metadata and persist typed rebind state. Once Claude flushes its saved
transcript, semantic export contains the first and last of180 response lines
from a40-row fullscreen terminal. The test explicitly waits for that saved
flush; production export reads only the stable prefix already persisted.
Receipt: `/home/tom/kitty-consolidation/proofs/claude-tui-5/receipt.json`.

The same filename is independently qualified against actual Codex0.163.0 by
`tests/codex_tui.py`: image attachment before Enter, actual request image,
actual three lifecycle events, saved300-line semantic history and typed
restoration all pass. Receipt:
`/home/tom/kitty-consolidation/proofs/codex-tui-escaped-1/receipt.json`.

## Latest harness package admission

Both offline TUI fixtures accept `--binary ABS`, pass that exact executable
through their private inner sandbox, and obtain its actual `--version` for
the receipt. The reusable retained-session Codex fixture supports the same
option. Previous installed-version receipts remain preserved baselines.

The candidate Codex 0.167.0 passes the same actual image, lifecycle and semantic
history proof without a production capability change. Its image chip appears
before submission, the subsequent request contains image bytes, real
SessionStart/Stop/SessionEnd hooks run the production bridge, the saved300-line
answer exports beyond the viewport, and typed binding restores while the same
harness remains alive. Receipt on compute:
`/home/tom/kitty-consolidation/proofs/codex-tui-0167-1/receipt.json`.

Claude Code 2.1.319 also passes unchanged: the special escaped filename attaches
before Enter, the actual request contains the image, all three real hooks emit
the correct metadata, and saved180-line semantic history plus typed rebind
remain available. Receipt:
`/home/tom/kitty-consolidation/proofs/claude-tui-21319-1/receipt.json`.
Both tests use only their private loopback providers and masked application
credentials/config. These receipts qualify the executable behavior; package
activation and the joint native SSH route have separate receipts.
