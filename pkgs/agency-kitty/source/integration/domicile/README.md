# Imagine/Domicile launch integration

`keybindings.ts` is a reviewable additive key table for the current Domicile SDK.
Merge it into the existing Imagine key table and run that configuration's
`ownedChords` validation. It deliberately adds no new window manager, fixed
workspace slots, desktop listener or DSH Host. No production key was changed.

- Mod+Enter: `agency-kitty desktop terminal`, the native managed direct route.
- Mod+Ctrl+Shift+Enter: `agency-kitty menu`, explicit saved-session chooser.
- Mod+Shift+Enter: `agency-kitty desktop rescue`, ordinary local fish.

`agency-kitty open --directory /NAS/PATH --workspace-id ID --chat-id CHAT`
creates a resumable terminal. Repeat `--chat-id` for several DSH chats.
`agency-kitty link UUID --chat-id CHAT --workspace-id ID` updates its metadata.
IDs are explicit and distinct; a chat is never silently inferred from whichever
web window has focus. `resume UUID` verifies the exact live NAS PTY before
opening Kitty and never allocates a replacement for a missing identity.

The metadata catalogue supplies a unique `agencykitty-<uuidhex>` window class
for reconciliation by Imagine's real window reducer. Creating a metadata link
is not evidence that a window has been moved or that a DSH sidebar route owns
it. That UI placement must use Imagine's existing authority and revision checks.
The companion DSH plugin is independently mounted and tested; it does not type
into a terminal or open arbitrary commands from generated cards.

The current production config was read at the start of this run. Its launcher
is `domicile-apps terminal` and it uses ordinary OpenSSH, not `kitten ssh`.
Keep that reference available during rollout. Neither this file nor installing
the package rewrites a running shell/config or restarts any live session.
