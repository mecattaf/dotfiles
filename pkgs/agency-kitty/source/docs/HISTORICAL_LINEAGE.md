# The native terminal workflow: Fedora to Domicile

Research recorded 2026-11-07/08. This is a read-only audit of dotfiles Git
history and the preserved notes. Historical launchers were read, never run or
sourced. A commit proves what was written; a preserved runtime receipt proves
only the host, version and route that receipt actually exercised. Neither is
automatically evidence of a fleet-wide deployment.

The consistent goal is older than Herdr: Kitty renders locally, the agent and
files live remotely, a small keeper preserves one process session, and the
desktop arranges independent native windows. A new-terminal gesture creates a
new session; resuming an old session is a separate explicit action. Editor
state, agent conversation history and a PTY's rendered screen are different
things to preserve.

## Direct user statements and their limits

The preserved February 26/27 conversation already specifies a Fedora thin
client running Niri, Kitty and Chrome, with the coding agent and session keeper
on a server. In an archived user turn Tom says, “one terminal window = one os
window,” then clarifies, “No split multiplexing.” He is indifferent between
shpool and zmx pending stability tests, and explicitly excludes tmux.

Source: [the archived conversation](/home/tom/notes/references/devlogs/1h26/pre-sync/kmux/shpool-versus-zmx.md),
especially the February 26 opening and February 27 clarification. The original
local path is
`/home/tom/notes/references/devlogs/1h26/pre-sync/kmux/shpool-versus-zmx.md:57`.
This is an archived user turn, stronger evidence of his intent than the
assistant's subsequent feasibility report.

The June 16 user turn makes the principle explicit again: “be kitty maximalist
ie when there are different ways to do something, you follow the kitty
friendly method.” The next user turn says a keeper such as zmosh, zmx or shpool
would be a component, while the surrounding Herdr/cmux behavior could be
adapted. Source:
`/home/tom/notes/references/devlogs/1h26/june18-nix-learnings.md`, the June 16
discussion. Its assistant turns are proposals and technical claims to verify,
not evidence those features were implemented.

The current request changes several historical preferences. Image paste is
now essential; June 11's summary that images were unimportant is superseded.
Imagine/Domicile owns workspace organization; Niri/Sway numbering does not
transfer. A native file-tree utility is wanted, while a second terminal
multiplexer is not. The intended `vi` route is now a local native Nvim UI
connected to a retained NAS editor server.

## 2024–2025: the native editor and scrollback are the original baseline

The first dotfiles commit, [5d12091b, May 4 2024](https://github.com/mecattaf/dotfiles/commit/5d12091b),
already sets `alias vi='nvim'` and `EDITOR=nvim` in `fish/config.fish`.
The native editor is a long-standing command habit rather than an addition
made for Herdr.

[5477b1ad, July 19 2024](https://github.com/mecattaf/dotfiles/commit/5477b1ad)
reclaims Kitty's Ctrl+Shift+B for `NvimTreeToggle`, sending the modified-key
sequence `ESC[66;5u`. Nvim's Ctrl+B continues to focus the tree. This establishes
the exact distinction later disrupted by Herdr's Ctrl+B prefix: the user
expects an editor action from one keypress, with the terminal transporting the
modified key correctly.

[ef7bf287, August 19 2024](https://github.com/mecattaf/dotfiles/commit/ef7bf287)
adds `kitty-scrollback.nvim` to both the Kitty and Nvim configs. The maps are
Ctrl+Shift+H for scrollback, Ctrl+Shift+G for last command output, and a
Ctrl+Shift+right-click action for a chosen command's output. Kitty remote
control and shell integration are enabled as part of that feature. These are
real committed configuration changes, with the old immutable-home path
`/var/home/dev` in the kitten alias; they are not evidence that a later
alternate-screen TUI's complete semantic history was ever available there.

[965fedeb, October 1 2025](https://github.com/mecattaf/dotfiles/commit/965fedeb)
updates `dot_config/scroll/scripts/executable_nvim-terminal.lua`. It finds the
actual descendant Nvim process, reads that process's cwd, and opens an
independent native terminal below the editor, with a temporary 66/33 height
arrangement and cleanup when the editor exits. Its purpose is explicitly to
provide an IDE arrangement without using Nvim's embedded terminal emulator.
The useful inheritance is directory-aware native windows; the Scroll-specific
placement and process-tree assumptions are historical implementation details.

## March–May 2026: shpool preserves the process; Kitty keeps the surface

The March 13 archived discussion describes the actual three-context workflow:
Claude Code CLI, Nvim for editing/viewing, and Fish. Tom notes that Nvim is
configured to update a file he is viewing when Claude changes it. Source:
`/home/tom/notes/references/devlogs/1h26/pre-sync/dotfile-shpool-indicator.md`.
The same conversation considers a combined Kitty/Nvim status bar, but the
subsequent assistant's enthusiasm is not a shipped feature.

The code predates that discussion. [ea902727, March 5](https://github.com/mecattaf/dotfiles/commit/ea902727)
moves Nvim's `hs`/`vs` mappings behind the leader specifically to avoid delayed
`h`/`v` motions; adds native file-link opening in a new Nvim OS window through
`open-actions.conf`; and adds Kitty cursor trails. This is a concrete earlier
example of perceived input responsiveness being affected by a key-prefix
mapping, independently of network or terminal rendering speed.

[3b35ab1d, March 5](https://github.com/mecattaf/dotfiles/commit/3b35ab1d)
adds the inotify-based directory watcher, guarded hot reload, Diffview refresh
and yank-with-path support. The editor is intended to remain a live reader of
files agents edit, with useful paths/ranges to take back into the harness. It
does not need to run inside the agent's terminal to do that.

[3983ccd1, March 21](https://github.com/mecattaf/dotfiles/commit/3983ccd1)
adds shpool config plus Starship/Nvim session indicators and 100,000 Kitty
scrollback lines. The commit's prose claims all Kitty protocols are preserved;
that is implementation intent, not a protocol conformance receipt. In
particular, the historical config's `[session] session_restore_mode` spelling
should not be copied without checking the actual version's schema. The useful
boundary remains clear: shpool holds the PTY; it does not own the desktop's
window arrangement.

[f80f1fce, April 18](https://github.com/mecattaf/dotfiles/commit/f80f1fce)
introduces `desk` as `kitten ssh harness-desktop -t shpool attach main`.
Follow-up changes select Fish and forward the SSH environment, so the prompt
can distinguish a remote session. This also creates a real wrapper bug: every
new terminal attaches to `main`, so two windows can compete for one shell.

[40e5e9b8, May 5](https://github.com/mecattaf/dotfiles/commit/40e5e9b8)
fixes that bug by generating a new UUID when `desk` has no argument, while an
explicit argument resumes that identity. `REMOTE_TERMINAL_SETUP.md` records
the before/after and the distinction between opening and resuming.
[b19b5c48, May 5](https://github.com/mecattaf/dotfiles/commit/b19b5c48)
adds Mod+Ctrl+Shift+Return → `resume-terminal` → an fzf list of existing
sessions. This exact user's menu predates both Herdr and its workspace UI.
[08bb7b80](https://github.com/mecattaf/dotfiles/commit/08bb7b80)
then fixes the SSH login-shell environment so the helper is on PATH.

The historical `SHPOOL_VS_ZELLIJ.md` correctly separates persistence from
layout ownership. Its conceptual argument survives the later compositor
changes: a keeper is useful without giving that keeper another pane/tab UI.

## April–June: a separate Kitty harness experiment, with a corrected ending

The archived `kitty-harness` work is distinct from September's `herdr-kitten`
repository and July's dotfiles `annex_*` kittens. Similar names should not be
collapsed into one continuous deployed program.

The April concept explores a thin agent harness using Kitty protocols,
external frontends and shpool. The user explicitly describes shpool as the
persistence component that keeps him agnostic about whether he consumes the
agent directly in Kitty or through another interface. These are design
conversations, not proof that every proposed renderer/protocol feature shipped.
Sources:
`/home/tom/notes/references/devlogs/1h26/kitty-harness/initial-april-concept/APPENDIX-kitty-agent.md`
and `kitty-agent-concept-continued.md`.

May 30 has actual preserved runtime evidence. The later correction in
`may31/noon-verdict.md` Appendix A records stock `kitten ssh`, Kitty 0.47.1,
loopback transport tests and a real Sodimo/Tailscale disconnect/reconnect with
the same holder and pi processes surviving. The corrected final tally is 20
fresh passes, zero failures and zero skips. One earlier “pass” was a real test
bug: a grep matched the configuration's echoed marker despite live SSH
exit 255. It was caught, retained as a masked-pass artifact, and replaced by a
server-origin marker check after the required Kitty upgrade.

The important distinction is preserved in that correction: this proved a
holder binary and gate harness invoked through stock SSH, not a complete
packaged everyday entry point. A later audit's “remote NOT BUILT” conclusion
was itself retracted because it had looked for a custom Go SSH implementation
that was deliberately absent.

The authoritative close of this arc is
`/home/tom/notes/references/devlogs/1h26/kitty-harness/june-handoff.md`, June 11.
It demotes roughly 1,850 lines of custom Go holder code on maintenance merits,
not because remote transport was impossible. The chosen survival core was
shpool + stock `kitten ssh` + vanilla pi. The useful product was the native
remote-control capability bus and window-native agents. It retained
show-a-window, explicit pre-typed commands and structured agent/window
metadata; it rejected several renderer ambitions. Its recorded user decisions
also reject send-region at that time, so old code's existence does not justify
silently restoring that feature today.

## June–July: Nix changes packaging, then zmx and the annex change behavior

The immutable Fedora lineage is visible directly in the first Nix skeleton,
[39a81c98, June 20](https://github.com/mecattaf/dotfiles/commit/39a81c98):
its description names the old bootc image, COPR packages and chezmoi dotfiles,
and it offers a standalone Home Manager bridge for the still-live Fedora
host. [2507b55e](https://github.com/mecattaf/dotfiles/commit/2507b55e)
then places raw Kitty/Fish/shpool and other configs through Home Manager while
preserving their editability. This is packaging continuity, not evidence of a
new terminal transport. [d5a06636, July 29](https://github.com/mecattaf/dotfiles/commit/d5a06636)
finally removes the Fedora transition output and documents NixOS-only main.

[55eb63f8, July 7](https://github.com/mecattaf/dotfiles/commit/55eb63f8)
briefly replaces shpool with zmosh, pursuing UDP roaming after SSH bootstrap.
[a7ce43a7, also July 7](https://github.com/mecattaf/dotfiles/commit/a7ce43a7)
replaces it with upstream zmx. Its recorded reasons are an unmaintained zmosh
fork and a stale Zig dependency lock that broke the Nix build; the chosen route
is once again `kitten ssh ... -t zmx attach ... fish`. It explicitly gives up
UDP roaming while keeping the remote process alive after SSH disconnects.
The adjacent comment that plain SSH had “died” should be read as the client
connection dying, not the already-preserved server process necessarily dying.

The July 11–12 changes add instant session creation, annotated pickers, titles
and a fixed `ZMX_DIR` universe. Important later correction:
[061b5be7](https://github.com/mecattaf/dotfiles/commit/061b5be7)
records that the LLM-driven ZMX_TITLE pipeline never ran in production and its
sidecar was empty. It should not be remembered as a proven daily feature merely
because several implementation commits describe it.

[c302c296, July 15](https://github.com/mecattaf/dotfiles/commit/c302c296)
introduces the shared `annex-cmd` substrate. Temporary `annex-*` utility
sessions are hidden from the normal `term-*` resume picker. It centralizes
host routing, forwards explicit picker context and reaps abandoned utility
sessions. Crucially, its own source documents an unverified thin-client gap:
Nvim writes the pick file on the coordinator while a local Kitty watcher tries
to read that path locally. A successful local picker is not proof of an
end-to-end remote picker.

[d4bfa5ef, July 15](https://github.com/mecattaf/dotfiles/commit/d4bfa5ef)
adds the universal Ctrl+B/Ctrl+Shift+B tree kitten. In a shell/agent it opens
a small native Kitty utility split; in Nvim it passes the key through. Because
the local process tree sees only a `zmx attach` client, Nvim emits the explicit
`nvim=1` user variable through the terminal. This is the relevant predecessor
of today's per-client native Nvim marker, rather than a reason to inspect
terminal titles or guess the foreground process over SSH.

The same day's composer/transcript work evolves through several implementations:
[31d15d33](https://github.com/mecattaf/dotfiles/commit/31d15d33),
[fda2085d](https://github.com/mecattaf/dotfiles/commit/fda2085d),
[645550ff](https://github.com/mecattaf/dotfiles/commit/645550ff),
[15374a5f](https://github.com/mecattaf/dotfiles/commit/15374a5f) and
[ee3f6b56](https://github.com/mecattaf/dotfiles/commit/ee3f6b56).
The useful behaviors are a native editor for a harness prompt and a separate
semantic transcript viewer. The fixes show concrete integration costs: an
absolute editor executable when PATH was insufficient; restoring the harness's
width after a viewer closes; and changing into the exact conversation cwd
before resuming to avoid “No conversation found.” These are stronger evidence
than a blanket claim that any generic scrollback capture can replace a
harness-aware view.

## September: deliberate replacement, then the image boundary forces a reversal

[20dfc9bc, September 1](https://github.com/mecattaf/dotfiles/commit/20dfc9bc)
deletes six annex kittens and their Ctrl+B/Ctrl+G/transcript-viewer maps. The
record explicitly says the file picker and transcript viewer have no
replacement in that change. Kitty remote control, shell integration and the
existing kitty-scrollback mappings are deliberately retained.

[061b5be7](https://github.com/mecattaf/dotfiles/commit/061b5be7)
deletes the matching annex/zmx scripts and rewrites `desk` to Herdr remote.
It acknowledges another regression: Ctrl+G returns to the global in-pane
`EDITOR=nvim`; it does not preserve the old native composer merely by
installing Herdr. The cleanup's rationale is recorded product consolidation,
not proof those removed features had become useless.

The September `herdr-kitten` project is a different architecture: Herdr owns
panes/workspaces/agents, while Kitty windows project them. Its preserved final
source is `2f3aa71906a55afe3bebf16f9873a6206f448f7a`, MIT. The early round2 audit
found real Kitty-loader failures, wrong-window selection, OS argv-size limits
and paste framing problems. Its rule is useful today: target identity and
actual native-loader tests matter more than a CLI unit test that never loads
the kitten. The current capability implementation tests real native callbacks,
large payloads and stale-target refusal instead of copying that old façade.

Sources:
`/home/tom/notes/references/devlogs/2h26/sept1-herdr-dotfiles-waves/SEPT1/round2/artifacts/RULING-kitten.md`
and `/home/tom/notes/references/devlogs/herdr-kitten/README.md`.

[186b36d2, September 11](https://github.com/mecattaf/dotfiles/commit/186b36d2)
tries to guarantee a fresh terminal by running the Herdr client on the
coordinator over SSH. [89c5fdf9](https://github.com/mecattaf/dotfiles/commit/89c5fdf9)
and [3bdef06b, September 13](https://github.com/mecattaf/dotfiles/commit/3bdef06b)
reverse that route to a full local `herdr --remote` projector. The decisive
reason recorded in `DECISIONS.md` is image paste/drop: Herdr's image clipboard
bridge exists in its remote client, so the prior route failed to carry a
laptop screenshot into the agent. Tom explicitly ruled image paste and
file-drop important.

That decision also retires herdr-kitten, quoting the SSH-boundary ruling.
The surrounding entry matters: the seat's allowed package topology and the
unimplemented remote forwarding tier were constraints, not a general theorem
that native kittens cannot operate over SSH. The current run proves a
different design end to end: local clipboard → separately pinned SSH upload →
NAS path → exact native Kitty callback → actual Codex/Claude attachment.

The full projector route carries more product behavior: prefix chords,
workspace selection and a reconnect loop. It also records a limitation: after
reattach it may land on the server's default target rather than the workspace
that particular client was viewing. This is another reason to preserve an
explicit stable session identity instead of coupling resume to global focus.

There are two separate voice histories. [2bf0fa99, September 2](https://github.com/mecattaf/dotfiles/commit/2bf0fa99)
wires system-wide hold-Mod+Space through Voxtype, with a Herdr route and native
Wayland fallback. The same commit explicitly records a real incompatibility:
the configured streaming path bypasses its post-processing callback, and the
spinner's output hook fires per segment rather than on key release. It is not
proof of a complete working dictation transport merely because its static
configuration passed. [12d018a2, September 26](https://github.com/mecattaf/dotfiles/commit/12d018a2)
places the distinct bare-Space Herdr patch behind
`myHerdr.holdSpaceDictation.enable`, default false, recording Tom's instruction
that it was no longer used after the Parakeet route. The patch's presence is
therefore not evidence it was active in the latest terminal experience.

[42a30f89, September 11](https://github.com/mecattaf/dotfiles/commit/42a30f89)
addresses the headless-host clipboard boundary in Nvim: an inherited remote
Wayland display had sent yanks to a clipboard at the server rather than the
laptop. The replacement uses OSC52 writes and a local register cache. Its
copy-only policy is deliberate: the historical Herdr route did not answer
clipboard reads, so a native OSC52 paste could otherwise wait up to ten
seconds. Clipboard provider behavior is another capability-specific concern,
not evidence of slow ordinary key delivery.

## October–November: the front end moves; the native boundary still matters

The nine-workspace restriction has a concrete source. In
[bab72378, October 7](https://github.com/mecattaf/dotfiles/commit/bab72378),
`home/dot_local/bin/herdr-picker` defines `herdr-slot-([1-9])`, accepts only
workspace numbers 1–9 and allocates with `range(1, 10)`. When those slots are
occupied or parked it raises “All nine Herdr slots are occupied or parked.”
This is the desktop bridge's chosen slot model, not an inherent Kitty limit or
an unavoidable consequence of preserving remote sessions.

[f4e130a0, October 14](https://github.com/mecattaf/dotfiles/commit/f4e130a0)
adds `herdr-attention`: a three-second metadata snapshot feed projects explicit
Herdr `blocked` transitions into Sway urgency and notifications. It separates
whether an agent is waiting from whether the user has acknowledged it by
focusing the workspace, and it tracks session identity and episode sequence to
avoid carrying acknowledgement to a new occupant. Those semantics are useful;
the polling source and compositor-specific placement do not need to transfer.
The file explicitly does not treat `idle` or `done` as an unanswered question.

[1b2ee9c2, October 14](https://github.com/mecattaf/dotfiles/commit/1b2ee9c2)
adds persistent Terminal/Chat companions. The inactive native terminal/browser
view is parked in Sway's scratchpad and swapped with its partner; the registry
stores explicit context identity. It deliberately avoids mutating the Herdr
server's global focus to guess which pane a particular Kitty displays. This
is a predecessor of chat/workspace associations around native windows, not a
reason for DSH to own another terminal grid.

[4997de0e](https://github.com/mecattaf/dotfiles/commit/4997de0e) and
[89b7cfb6, October 23](https://github.com/mecattaf/dotfiles/commit/89b7cfb6)
move the fleet's agent/transport entry points toward NAS while offloading
compute. The second change explicitly routes new clients without replacing
live Strix views. A source or package update therefore cannot be assumed to
describe an already-running keeper; preserving its live processes was an
intentional constraint before this consolidation pass too.

The pre-consolidation Domicile history includes
[09c26099, November 4](https://github.com/mecattaf/dotfiles/commit/09c26099),
which permits an explicit desktop Herdr client config in the terminal launcher.
As with every history entry, the available Git object and a live launcher
inspection are separate evidence; this report does not infer the active
generation from a branch's commit message.

The adjacent November 4 launcher implementation matters as history rather
than a feature to preserve verbatim. [9c66c8ae](https://github.com/mecattaf/dotfiles/commit/9c66c8ae)
starts from local terminal control and opens an existing NAS Herdr view;
[cab71096](https://github.com/mecattaf/dotfiles/commit/cab71096)
reduces that to one explicit destination selection and discards typeahead at
the local/remote boundary. Its reason is concrete: the pinned Herdr public API
cannot select the exact new client, so the launcher must not silently attach
to a running agent or change global focus to manufacture a fresh shell. The
current direct new-shell launcher and exact saved UUID resume solve the
identity problem at its source; the old warning/confirmation loop need not
become the everyday Mod+Enter experience.

The current user's observed improvement is real subjective evidence, but this
history alone cannot assign its cause. The installed Herdr 0.9.3 source does
establish an extra presentation cadence: `src/app/mod.rs:37` defines 16ms,
`src/app/runtime.rs:74` gates render/presentation times, and
`src/server/headless.rs:516` applies those gates before streaming a retained
surface or complete render. An idle first frame can render immediately; this
is not a statement that every key is delayed by exactly 16ms. Current measured
latency and Domicile version comparison belong to the separate qualification
receipts.

## What to carry forward, and what history does not authorize

Carry the enduring behaviors: direct native Kitty input/rendering; explicit
fresh versus resume; a keeper that preserves one remote process session;
native selection with a generic Copied acknowledgement; a bounded independent
image channel; exact harness lifecycle/transcript identities; a local native
Nvim UI with retained NAS state; cwd-aware native editor windows; and a small
catalogue that Imagine/DSH can associate with chats/workspaces without owning
another terminal layout engine.

Keep semantic history separate from screen recovery. A keeper can restore a
rendered state; the harness's exact JSONL can provide conversation beyond the
viewport; a retained editor server can preserve unsaved buffers and undo.
Neither raw escape replay nor a generic scrollback getter substitutes for all
three. The current image.nvim proof further shows why a fresh native editor
UI must receive actual image bytes again, even when its rows/columns match the
old window.

Do not copy old fixed `main` attachment, globally focused Herdr pane commands,
host-local picker files across an SSH boundary, automatic selection of the
latest transcript, arbitrary screen scraping for agent state, unqualified
Kitty monkey patches or a second nine-workspace model. Do not restore the dark
LLM title pipeline or rejected send-region feature solely because their source
still exists in history.

Historical technical prose needs verification. The archive contains the
explicitly retracted May 31 remote verdict, optimistic claims that a shadow
parser cannot affect the live path, and claims that raw replay guarantees full
TUI history. None is a current qualification. The current implementation uses
source-qualified native APIs, actual harness hooks, stable transcript paths,
native graphics receipts and private end-to-end SSH tests to establish those
boundaries directly.
