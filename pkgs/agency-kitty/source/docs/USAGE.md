# Native Kitty workflow

Kitty stays the local terminal and Imagine owns desktop placement. Ordinary
typing uses native Kitty and OpenSSH. Background Python helpers run at startup,
on explicit gestures or on harness events; they do not proxy each key.

## Launch and reconnect

`agency-kitty desktop terminal` opens a managed direct NAS SSH window.
`agency-kitty desktop rescue` opens local fish. Direct mode has no holder and
ends when its SSH process ends. Its optional chat/workspace links are metadata,
not persistence. New Kitty tabs get independent terminal UUIDs.

Managed direct and persistent routes default to ordinary OpenSSH, with pinned
NAS terminfo and fish integration. This preserves complete commands typed
during startup. `AGENCY_KITTY_SSH_TRANSPORT=kitten` explicitly selects stock
Kitty SSH bootstrap; its bootstrap consumes complete pre-handshake input lines.

Ended direct-terminal metadata remains bounded and keeps its UUID reserved.
On NAS, `agency-kitty remote archive-direct --id UUID` explicitly archives one
ended record without changing a process or releasing that UUID. It refuses live,
unknown and already archived records. No automatic cleanup runs. See
DIRECT_CATALOGUE.md for the byte/hash receipt and private archive contract.

`agency-kitty open --directory /NAS/PATH --chat-id CHAT --workspace-id WORKSPACE`
explicitly creates a persistent NAS terminal and opens its Kitty window.
`agency-kitty resume UUID` reattaches that exact surviving NAS PTY. It never
creates a replacement for an unknown or ended session. `agency-kitty menu`
opens the explicit saved-session chooser; only its New selection creates one.

Detached native windows write Kitty launch diagnostics to private 0600 files
under the local session store's `launches/` directory (normally
`~/.local/state/agency-kitty/launches`). These are startup/Kitty diagnostics,
not a terminal-content log. Their descriptors are independent of a desktop
helper's captured stdout/stderr, so the helper can finish while Kitty stays
open. Existing diagnostics are retained for inspection.

`AGENCY_KITTY_RECONNECT=1 agency-kitty open --directory /NAS/PATH` opts into
bounded reconnection in that same view. The setting is inherited by its launch
and later tabs; it can also prefix `resume`, `new`, `menu` or `attach`. Only
persistent plain-SSH attachments are supervised. The supervisor verifies the
exact surviving NAS identity, never allocates a replacement, and retries at
most five times within a 45-second retry burst. An SSH child that runs for at
least 30 seconds resets that burst; this measures child lifetime rather than
application readiness or an absolute deadline for the whole attachment. It
preserves unconsumed local typeahead; it never replays bytes already consumed
by a dead SSH process.
Direct sessions end with their SSH-owned PTY. See ATTACHMENT-RECONNECT.md.

Persistent mode uses the version-matched source-built holder on NAS. It has no
layout manager, prefix key or terminal renderer. Attached application bytes
remain native Kitty protocol. Fresh reconnect uses a bounded shadow-state
snapshot; this has specific limits. Static explicitly identified RGB/RGBA/PNG
images are qualified, including repeated large-image replacement/deletion.
Known retained unsupported graphics states and detected OSC66 refuse strict replay.
Commands discarded by the shadow parser may be invisible to that validation;
strict mode is not universal protocol certification.
`ZMX_RESTORE_TEXT_ONLY=1` is an explicit degraded recovery escape, not full
protocol parity. The unwrapped direct route remains the compatibility baseline.

The existing Kitty configuration keeps 100,000 local scrollback lines while
attached. The holder retains at most 10,000 lines with a 64 MiB scrollback bound;
fresh text snapshots have a separate 32 MiB bound. A new window cannot recover
more terminal history than its holder retained. Saved semantic harness history
is a separate view, rather than a substitute for identical terminal scrollback.

`agency-kitty-native-forward --session UUID` is an opt-in local compiled client
over a private stock-SSH Unix forward. It requires the matching NAS version.
It avoids the resident SSH PTY, but OpenSSH does not apply interactive timing
padding to forwarding traffic. It is not the default launch policy. See
NATIVE_FORWARD.md for explicit fresh provisioning and lifecycle details.

## Managed gestures

The fleet module installs the Kitty watcher and mappings for tagged windows:

- Ctrl+B: toggle the native left Nvim file-tree dock. Inside Nvim, send its
  normal single Ctrl+B key so the editor can own the tree action.
- Ctrl+V: paste local clipboard content. Images upload to the fixed NAS image
  helper, then paste their remote path into the captured exact harness window.
  Multiple images use separate bracketed-paste events. No Enter is inserted.
  Inside Nvim, native Ctrl+V remains Visual Block.
- Ctrl+Shift+C: native Kitty copy with generic Copied feedback. Native mouse
  selection and soft-wrap handling remain Kitty's.
- Ctrl+Shift+H: read exact saved Claude/Codex semantic history in a separate
  local read-only Nvim view; without an exact binding, use existing native shell
  scrollback. History is not a reconstruction of unsaved TUI pixels/prompts.

Managed drag-selection completion also adds Copied feedback after Kitty's
native clipboard copy. This is a silent native desktop notice lasting 1.6
seconds, rather than an in-terminal overlay or replacement selection engine.

Image jobs capture terminal UUID, Kitty window/root-child identity and harness
occupant before work. After an exact harness binds, staged image/file/voice
actions also query its
NAS foreground identity. Suspended, ended or unverified agents receive no
input. The NAS check precedes local delivery rather than forming an atomic
cross-host transaction. Before Codex emits its first SessionStart, generic
terminal semantics remain. Closed, rebound or stale targets receive no input.
There is no fallback to the currently focused window. Clipboard MIME/magic and
image size are checked; batches contain at most 16 images of at most 16 MiB each.

Native cross-application file dragging additionally requires the matched
Domicile/Imagine drag patches. Installing this package does not replace a
running desktop engine or apply those source patches.

## Primary vi

With the fleet editor module enabled, fish `vi` uses a true local Nvim UI over
SSH/RPC to a retained per-directory NAS editor. In a managed NAS terminal it
blocks the original shell until that UI completes. Native `:detach` returns 0;
an explicit local window close returns 129. Both preserve the remote editor
and dirty buffers. An SSH/RPC lease failure instead preserves the pending
request; reattaching the same surviving retained parent PTY restores it. A lost
direct SSH PTY cannot preserve that shell request. Unmanaged NAS terminals fail
with guidance
before allocating an editor. Run `command nvim` explicitly when a conventional
NAS TUI is intended.

Idle/leave checkpoints protect dirty named and untitled buffers if the remote
editor itself dies. Recovery is explicit and never overwrites source files
until requested. These are checkpoints, not an every-keystroke power-loss
guarantee. Session persistence, editor persistence and agent conversation resume
are separate lifetimes.

## Agent and desktop metadata

Managed fish `cc`/`cx` route the original Claude/Codex arguments through
`agency-kitty harness ...`. Invocation-scoped hooks bind the exact transcript
and report working/waiting/completed-turn metadata. No global hook/config trust
is added. DSH agentStatus distinguishes verified foreground work, waiting and
completed turns from background, ended and legacy unverified bindings. Native
OSC99 handles desktop notifications; OSC7 reports cwd and OSC133 marks shell
boundaries. These protocols have different jobs.

`agency-kitty catalogue --local --json` reads bounded NAS metadata only.
`agency-kitty link UUID --chat-id CHAT --workspace-id REF` updates links.
DSH's `kitty_native_sessions` tool is read-only and has no launch/input/close
authority. The optional existing Imagine catalogue bridge joins native rows to
DSH chats. A human resume click validates the exact live persistent UUID and
current chat link. It uses the desktop's existing reducer and respects lock,
modal state and newer navigation. Native tabs can share an OS-window class;
catalogue focus identifies that OS window, not a particular Kitty tab.

## Sound and future voice

`agency-kitty capability sound startup|voice-start|voice-end|disconnected|done|attention`
plays an explicitly selected local sound. Private Anthropic captures belong in
`~/.local/share/agency-kitty/audio` or AGENCY_KITTY_AUDIO_DIR; they are not shipped
in this package. Completion/attention use the desktop's theme assets.
No new automatic agent-completion sound or notification policy is enabled.
The voice-text action accepts final text from a future system-wide ASR utility
and uses exact-target literal paste without submission. No bare-Space listener,
recording service or speech model is enabled here.

Packaging and the supplied source patches are separate from live activation.
Do not infer that a running Kitty, desktop engine or NAS session changed merely
because its updated executable is present in the Nix store.
