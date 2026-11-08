# Why the web features do not require a web terminal

Ovis (formerly Herdr web UI) was inspected at
[`cda081f78eeb2a1dd428b8e8c42bbf2bdecde7b5`](https://github.com/devswha/ovis/tree/cda081f78eeb2a1dd428b8e8c42bbf2bdecde7b5),
MIT. The source is cloned, no installer or service was run.

Its architecture separates three things:

- A Bun server reads Herdr's Unix-socket metadata and agent state.
- Native Claude/Codex session-file readers build semantic chat, task and tool
  views beyond the terminal viewport. This does not come from a screenshot.
- The terminal bridge normally runs real `herdr terminal attach` in a Rust PTY
  sidecar (Node fallback), then streams those bytes to xterm.js. There is also a
  separate herdr-core adapter and an optional experimental libghostty drawing
  layer; neither makes the normal browser path an inherently faster native
  terminal.

Primary code: `server/core/terminal-process.ts`, `server/core/terminals.ts`,
`server/claude-transcript.ts`, `server/codex.ts`,
`server/herdr-core/attach-session.ts`, `src/components/PaneTerminal.tsx`.
The public [architecture description](https://github.com/devswha/ovis/blob/cda081f78eeb2a1dd428b8e8c42bbf2bdecde7b5/docs/guide.md#how-it-works)
aligns with the implementation. The pasted claim that Ovis is generally a
custom JSON grid-diff renderer instead of a terminal byte stream was not an
accurate account of this code.

The useful transfer is semantic transcript identity, explicit lifecycle state,
exact process/window binding, bounded observers and deliberate prompt actions.
A browser terminal renderer is not needed for Kitty image paste, clean native
selection, editor views, session persistence or desktop notifications. The
new helper uses exact harness SessionStart/Stop/SessionEnd data and the
standard native OSC7501 path where the installed terminal supports it. It
never infers a completed turn merely from a process exiting or output going
quiet.

## DSH ownership is a separate contract

The installed DSH0.2.1-rc.2 and updated0.2.2-rc.1 terminal controllers were inspected in their
`@deepseek-ai/dsh-api-terminal-controller` package. Its process owner is a
DSH session, not a local terminal window. Attachment cancellation preserves the
process and never replays input. `retain` holds an existing terminal without
activating an agent or taking input control. Host/session-owner disposal
explicitly cleans up the terminal processes. The default unattended policy is
7,200,000ms (two hours), with activity observation rather than an unconditional
kill exactly two hours after a disconnect.

The stock defaults also bound browser terminals to8 per DSH session,500×200
cells,1,000 scrollback lines,2MiB buffered output and64KiB input. These are DSH
controller policy, not limits of Kitty or the new native session provider.
No production retention setting was changed in this pass.

The existing native-DSH experiment proves that a native terminal can consume
DSH's raw output API without xterm. Its custom per-key JSON carrier is another
transport to benchmark; it is not automatically equivalent to the current
ordinary SSH path. This consolidation keeps the live byte path native and
keeps DSH chat links as metadata, rather than nesting one session holder under
another or pretending an external PTY belongs to DSH's server/epoch route.

The optional `@agency/kitty-native` plugin was mounted into the real installed
Host in a private fixture. It registered `kitty_native_sessions`, returned two
explicit terminal identities, filtered one by its chat link, rejected an
unknown identity, and left all stored metadata unchanged. No agent turn or
provider request was needed. The actual updated0.2.2-rc.1 installed bundle passed its batch raw-call API and
selected native composition executor without an agent/provider request. This
is concrete metadata integration. The source-qualified Imagine catalogue
bridge now accepts the distinct native route, with an explicit human launcher,
exact window class and validated resume receipt. Its135 tests and full build
pass; no live desktop source refresh or matching engine transition is claimed.
See integration/imagine and docs/DSH-INSTALLED-BUNDLE-PROOF.md.

## Status standards

[OSC7501](https://mitchellh.com/writing/program-status-osc7501) is a real generic
Program Status Protocol, published2026-10-06. The early offline TUI proof used the pre-upgrade installed Codex0.163.0
and observed its emission; Kitty0.50 has a native parser and public
`on_program_status_change` watcher. Kitty0.48, the live baseline, predates this
support. The protocol's existence does not prove every installed harness emits
it or that every desktop already consumes it.

The new exact-hook state and native status metadata are complementary:
standard OSC7501 expresses program state; hooks bind a particular saved
transcript and session identity, and distinguish a completed turn from process
lifetime. Neither requires a screen regex engine in the foreground byte path.
