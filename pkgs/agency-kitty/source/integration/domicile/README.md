# Imagine/Domicile launch integration

`client-entry.patch` is the exact adoption artifact for the existing client
configuration. It changes only three chords before the existing `ownedChords`
validation. `keybindings.ts` also shows those actions as an additive fragment.
Neither artifact changes Imagine's Desktop, AgencyKeys, engine or window reducer.
No production key was changed.

The canonical dotfiles client profile still describes Sway and omits the
separate Domicile owner's current composition. Use the
[client composition plan](CLIENT-ADOPTION.md) before preparing a client
deployment; installing this package is not a complete desktop rollout.

- Mod+Enter: `agency-kitty desktop terminal`, the native managed direct route.
- Mod+Ctrl+Shift+Enter: `agency-kitty menu`, explicit saved-session chooser.
- Mod+Shift+Enter: `agency-kitty desktop rescue`, ordinary local fish.

## Existing configuration seam

Imagine already accepts public `ImagineOptions.keybindings`. `runImagine()`
passes it to Desktop, and the existing client entry supplies
`keybindings: { keybindings }`. Its source lineage is:

- Owner worktree: `/home/tom/.wt/dotfiles/domicile-first-pass-20261105`.
- Entry: `home/dot_config/domicile/domicile.tsx`, dirty relative to owner HEAD
  `87491201700acc5051cb3edfb55f5551a4eb9fbe` when captured.
- Exact original entry:6,250bytes, SHA256
  `b6cf824a58a96efe6ec8f7d4d674e9a2cf9dff771524a81e4ef96033c0ad4fb9`.
- Patched entry SHA256:
  `61d031227c1e7f731f72046a148f224a20be2ed4b57a01b6c8a3426a5bd9d72d`.
- Existing Nix seam: `programs.domicilePhysical.configSource`, a path option in
  that owner's `modules/domicile.nix`. Its existing pipeline stamps the Imagine
  source identity, bundles the relative production dependencies beside the
  entry, runs Domicile's builder/check-config, and manages the watched user link.

`client-entry-provenance.json` records the patch hash and capture boundary.
`git apply --check` and actual application to a private copy of those exact
original bytes produced the recorded patched hash. Reversing the three chord
changes recovered every original byte; existing `ownedChords()` and public
`runImagine` options were preserved. This copy check is separate from compiling
the complete entry with its SDK/Imagine source and qualifying actual native
keypress routing. It does not authorize replacing the other owner's dirty file
or prove what a running client has loaded. Re-check its original hash before an
owner-reviewed adoption; drift requires a fresh artifact and qualification.

The baseline `domicile-apps` helper is a fixed dispatcher with no terminal
command-selection setting. It creates Kitty with a `domicile-terminal` shell
override, which uses ordinary pinned NAS SSH. Installing an XDG desktop entry
cannot redirect that existing command. Shadowing `domicile-apps` or its window
class would conflict with the whole-directory helper link and lose explicit
terminal identity; it is not the adoption mechanism. The public client-entry
seam is sufficient, with no internal Imagine source patch required.

The original entry's once-per-compositor startup command and legacy
`domicile-terminal.desktop` entry still call `domicile-apps terminal`. This
minimal patch keeps those baseline routes available. It leaves browser, Files,
workspace/display policy, chat launchers, startup, manual night light and every
other key untouched. Selecting these static chords creates managed identities;
it does not silently infer a chat/workspace association.

## Explicit session and desktop relationships

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
the package rewrites a running shell/config or restarts any live session. The
patch is staged for review; it has not been adopted on the live client.
