# One workspace, two views

A numbered Sway workspace represents one Herdr workspace and its single Kitty
projector. **Mod+grave** switches that workspace between Kitty and the Herdr web
UI's **Chat** view. The companion stays running out of sight; there is no Sway
tab strip. Changing Sway workspaces changes the work. Toggling changes its view.

The first switch opens a dedicated Chrome app window with the workspace/pane
deep link and the web UI sidebar hidden. Later switches exchange the two
windows at the same tile. This is the web chat, not the browser's xterm terminal.
Chrome uses a separate profile for all Herdr companions, so its first use may
require pairing/sign-in once; it does not take over a personal browser window.

Herdr attention follows the same association. A newly waiting agent makes the
visible representative urgent and sends a desktop notification. Activating the
notification returns to its workspace and relevant pane. Passive status updates
never switch workspaces. Visiting acknowledges attention; it does not answer an
agent or make a waiting request disappear from Herdr. The daemon deduplicates
notifications across polling cycles.

## Commands

```sh
herdr-context toggle
herdr-context show terminal
herdr-context show chat
herdr-context activate --workspace w1 --pane p1
herdr-context status --json
herdr-context reconcile
```

Workspace and pane arguments are Herdr IDs, not Sway numbers. Use `status --json`
to inspect the current mapping. **Switch Herdr Terminal / Chat** is also available
in Vicinae. Existing workspace creation, rename, close and restore commands keep
their Sway shortcuts.

## Configuration and lifecycle

`home/herdr-context.nix` enables the bridge only on the physical display host
(`myDisplay.enable`). The `herdr-attention` user service follows
`sway-physical-session.target`; the session imports its fresh `SWAYSOCK` before
starting that target. It does not attach to the separate headless browser seat,
start a timer, or change the lifetime of the Herdr server and its PTYs.

`services.herdrContext.webUrl` supplies `~/.config/herdr/context.json`:

```json
{"web_url":"https://strix.tail8dd1.ts.net:8443/"}
```

That default was read from Strix's Tailscale Serve configuration on 2026-10-14:
it proxies to the installed web UI at `127.0.0.1:7318`. It requires the physical
seat's existing tailnet access. Change the option if that endpoint moves; do not
use the laptop's localhost for a Strix service. For a manual invocation,
`HERDR_WEB_URL` overrides the URL and `HERDR_CONTEXT_CONFIG` selects another
configuration file. `HERDR_CONTEXT_BROWSER` selects the Chrome executable.

Operational inspection:

```sh
systemctl --user status herdr-attention.service
journalctl --user -u herdr-attention.service
herdr-context status --json
```

The scripts ship through the existing raw dotfile directory. The physical client
gets them in the Nix store (`rawDotfiles.inStore`); it needs no checkout. A host
using out-of-store links must have this branch in `~/mecattaf/dotfiles` before a
normal deployment. Implementation and tests do not deploy or reload the live
desktop.

## Boundaries and acceptance

One Kitty must remain associated with one Herdr workspace. Duplicate projectors
and ambiguous identities should produce a diagnostic instead of selecting an
arbitrary terminal. A workspace with several panes still needs a particular pane
for Chat; the selected pane/deep link is the finer-grained context. Chrome page
navigation stays within the web UI's existing routing support; unsupported
agent transcripts cannot become a rich chat through a Sway command.

Testing happens after the complete implementation. All compositor experiments
and runtime-sensitive tests must use `~/.local/bin/runtime-test -- ...`, including
on SSH targets. Never use the active desktop as a test fixture. The final checks
must cover:

- Kitty → Chat → Kitty in the same tile, preserving terminal state and chat draft.
- Several workspaces, rename/output moves, close/restore, and companion recreation.
- Waiting transitions, deduplication, acknowledgement, notification actions, and
  no focus theft while another workspace is active.
- Lost SSH/web UI connections and daemon restarts without closing any agent PTY.
- Client Home Manager evaluation and a private compositor check for Chrome's
  app ID, hidden companions, geometry, and urgency behavior.

Record what the isolated tests actually establish. A live session must not be
restarted, reloaded, or deployed merely to complete this checklist.
