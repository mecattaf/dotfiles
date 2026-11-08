# Native Kitty workflow

Kitty stays the local terminal and Imagine owns desktop placement. Ordinary
typing uses native Kitty and OpenSSH. Background Python helpers run at startup,
on explicit gestures or on harness events; they do not proxy each key.

## Launch and reconnect

`agency-kitty desktop terminal` opens a managed direct NAS SSH window.
`agency-kitty desktop rescue` opens local fish. Direct mode has no holder and
ends when its SSH process ends. Its optional chat/workspace links are metadata,
not persistence. New Kitty tabs get independent terminal UUIDs.

`agency-kitty open --directory /NAS/PATH --chat-id CHAT --workspace-id WORKSPACE`
explicitly creates a persistent NAS terminal and opens its Kitty window.
`agency-kitty resume UUID` reattaches that exact surviving NAS PTY. It never
creates a replacement for an unknown or ended session. `agency-kitty menu`
opens the explicit saved-session chooser; only its New selection creates one.

Persistent mode uses the version-matched source-built holder on NAS. It has no
layout manager, prefix key or terminal renderer. Attached application bytes
remain native Kitty protocol. Fresh reconnect uses a bounded shadow-state
snapshot; this has specific limits. Static explicitly identified RGB/RGBA/PNG
images are qualified, including repeated large-image replacement/deletion.
Unsupported graphics subsets and OSC66 restoration refuse strict replay.
`ZMX_RESTORE_TEXT_ONLY=1` is an explicit degraded recovery escape, not full
protocol parity. The unwrapped direct route remains the compatibility baseline.

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

Image jobs capture terminal UUID, Kitty window/root-child identity and harness
occupant before work. After an exact harness binds, staged image/file/voice actions also query its
NAS foreground identity. Suspended, ended or unverified agents receive no
input. The NAS check precedes local delivery rather than forming an atomic
cross-host transaction. Before Codex emits its first SessionStart, generic
terminal semantics remain. Closed, rebound or stale targets receive no input. There
is no fallback to the currently focused window. Clipboard MIME/magic and image
size are checked; batches contain at most16 images of at most16MiB each.

Native cross-application file dragging additionally requires the matched
Domicile/Imagine drag patches. Installing this package does not replace a
running desktop engine or apply those source patches.

## Primary vi

With the fleet editor module enabled, fish `vi` uses a true local Nvim UI over
SSH/RPC to a retained per-directory NAS editor. In a managed NAS terminal it
blocks the original shell until that UI explicitly detaches. A lost local UI
lease preserves the pending request and unsaved remote buffers; reconnecting
the managed terminal rebinds them. Unmanaged NAS terminals fail with guidance
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
completed turns from background, ended and legacy unverified bindings. Native OSC99 handles desktop notifications; OSC7 reports cwd and
OSC133 marks shell boundaries. These protocols have different jobs.

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
in this package. Completion/attention fall back to the desktop's theme assets.
The voice-text action accepts final text from a future system-wide ASR utility
and uses exact-target literal paste without submission. No bare-Space listener,
recording service or speech model is enabled here.

Packaging and the supplied source patches are separate from live activation.
Do not infer that a running Kitty, desktop engine or NAS session changed merely
because its updated executable is present in the Nix store.
