# Imagine

These design notes began in the first-pass Agency prototype. This maintained
Imagine implementation is now the live client shell, refreshed from its public
package entry on 2026-11-05. The repository root README and the Imagine-entry
receipt record the exact integration and retention evidence.

Imagine is Tom's client-side Domicile shell, built from public Manganese
components and window-management primitives. Manganese is the starting kit;
Imagine owns the defaults and behavior. This directory changes no Domicile
source or engine. The first pass targets stock source
`67c29a9906905bd5e1679803232c2f510b3fed9e`.

## Decisions established by the first desktop pass

- **Separate device facts from user preferences.** Display identities, panel
  geometry, backlight selection and locally supplied fonts belong to the
  client. Shortcuts, workspace behavior and appearance are user preferences.
  Those preferences should eventually follow the agency-agency account;
  account synchronization is not implemented here yet.
- **Compose native capabilities before adding helpers.** Brightness and music
  controls use the public Domicile file/D-Bus interfaces; volume uses the
  stock audio integration. The OSD uses Domicile's built-in `LevelToast` and
  `ChoiceToast` components. Controls and their OSD belong to the shell together.
  Do not add personal bash, Sway IPC or a separate notification daemon to
  implement this behavior. Existing terminal routing is transitional while
  Wraith presentation and production DSH capability registration remain separate phases.
- **Improve Domicile upstream when the platform is missing something.** Start
  with capabilities already built into the project. Reproduce confirmed bugs
  and missing Wayland functionality on the relevant source/engine pair, check
  existing work, and use GitHub issues and PRs to address them. Keep ordinary
  user preferences in Agency configuration. Coordinate with the parallel
  Claude compositor work so these efforts do not duplicate or overwrite it.
- **Preserve deliberate user choices.** Keep saved manual night light and
  rounded window chrome. The current defaults are black background, no top
  bar, no outer or split gaps, and no focus glow. Windows open as splits;
  intentional tab groups remain available.
- **Make workspace homes explicit.** On the Duo, slots 1–9 belong to the upper
  display and slot 10 (Meta+0) to the lower, including empty slots. The client
  reserves 6–9 for the ASUS when connected and returns them upstairs when
  unplugged. A single
  display must still make every slot usable. The rail starts hidden, toggles
  with Meta+B, reserves 256 logical pixels when open, and follows the focused
  output. Finder in the rail searches real applications, workspaces and windows;
  Ctrl+K is left to the focused application.
- **Refresh ordinary changes.** Package configuration and its relative Imagine
  dependencies together, validate that exact package, and update the watched
  user config link. Engine changes may require a session restart. Console
  entry remains password-free, with `domicile` as the desktop launch word;
  a configuration update must not manipulate VTs or restart the user manager.
- **Expose real state and failures.** No placeholder actions or invented
  device/player state. Brightness and music report unavailable/error results
  through the OSD and console. Stock asynchronous volume-command failures are
  currently logged by the stock audio hook, without a separate error toast.

## Read-only desktop state

The deployed `ipc/` adapter projects this reducer and the final `chrome.screens`
geometry, including rail and per-window chrome. The existing command dispatcher
has one recognized snapshot owner; do not add another command-stream listener.
Typed window/browser/native IDs remain distinct from server-owned DSH sessions.
The qualified NAS→Zenbook route omits titles, URLs and content and grants no
mutation, generic execution, desktop HTTP listener or client DSH authority.
Production DSH registration and full i3ipc-equivalent actions/events remain
separate work. Evidence is in the overnight dsh-domicile-integration receipt.

## Lessons that affect implementation

The stock builder hashes imports beside the lexical config path, while Vite
resolves imports beside the real symlink target. A changed build hash alone
does not prove changed behavior. The Nix module therefore ships the TSX and
Imagine production source together and stamps its immutable identity into the
entry. An isolated test proved a complete bundle-link update changed visible
code while preserving the engine, compositor and native terminal process.
Updating a separate user-directory dependency link failed the semantic test;
do not use that alone as the deployment mechanism. The user-directory Imagine
link is still required for the stock import graph to resolve files at all.
Manage both links, keep their bundle targets paired, and verify the watched installed
user path and process/guest retention. A successful store-bundle build
alone does not prove the installed symlink layout works.

The optional snapshot identity config is read once per hook mount and retried
on unlock. Its owner-only atomic install must run before watched linkGeneration;
a config-only change needs coordinated refresh/reconciliation. Current native
SDK identity and layout tags belong to the loaded matched stock67c29a9/62a671f
pair. A newly copied engine/source on disk does not change that ABI. Keep
client helper/protocol payload and Python interpreter explicit and reproducible.

The Duo exposes a misleading `asus_screenpad` backlight in addition to its
two actual DRM eDP backlights. Native brightness selects the canonical DRM
devices, synchronizes the pair, and preserves the existing one-raw-unit floor.
Only the explicit F10 blank/restore operation writes zero. Test the device
selection and failure behavior before making physical writes.

Some stock desktop internals have no public composition hook. The small local
adaptations here retain their pinned provenance and MIT notice; prefer the
public reducer, types and UI components around them. Recheck these boundaries
when the independent upstream input/platform work changes the source/engine pin.

Runtime experiments belong inside `runtime-test` on compute. Preserve failed
runs and diagnostic dumps, and distinguish headless proof from physical-seat
acceptance. Explain a new design decision to Tom as it is made and update this
guidance when real use changes it.

Workspace motion is vertical at 35 ms with the recovered Scroll easing, direction,
late-arrival delay and completion lifecycle. A bounded adapter reads full logical
screen clipping geometry for every moving part; reduced motion still completes.
Do not infer physical 120 Hz frame pacing from headless timing assertions.

Client policy supplies a fixed 3850 K whitepoint through the public display API,
replacing scheduled night light on this seat. The stability rollback supports one
global value for all outputs and restores it natively after hotplug and modesets;
different panel temperatures need a newer qualified engine.
Scroll/Niri recovery and deeper sidebar-donor history remain
later chapters; do not revive them through an old checklist or deep notes scan.

## Running-window chrome command

The deployed presentation feature accepts `domicile send-shell imagine chrome
toggle|show|hide [running-window-id]`. Omitting the ID targets the active window.
The preference belongs to that running window, is pruned on close, and is not
persisted across shell reloads. Shared strips follow the visible tab; unrelated
ancestor container tabs remain available. Hidden chrome reclaims its height and
keeps rounded content corners. No new global shortcut is assigned. The isolated
proof covers actual native windows, PTYs, browser guest and websocket retention;
the exact reviewed candidate deployed by automatic refresh without restarting
the engine, native apps or two active chats. Physical shortcut acceptance remains
a user check; no live synthetic input was injected.

## Optional ambient chat viewer

`runImagine({ ambientChat: ... })` leaves ambient chat absent by default.
Enabling it requires an explicitly
reviewed client launcher, for example `{ launcher: "agency-chat-ambient-bootstrap" }`;
optional `width` and `height` default to 640 by 480 logical pixels. The launcher
is one executable, without URL, token or shell arguments. This source does not
install that helper, a tunnel, a binding or a backend.

When enabled, `domicile send-shell imagine ambient-chat show|hide|toggle` owns a
distinct `agency-chat-ambient` browser app through public background-app and
window reducer contracts. Hiding retains the actual guest and its draft. Show
targets the currently focused output/workspace, with the stock floating minimum;
an output too small for that minimum is refused. Lock/modal ownership and newer
navigation win over a late bootstrap. The existing command dispatcher remains
the only subscriber. No global Escape or application Control shortcut is taken.

The intended client helper bootstraps a second loopback origin through Tailscale
to the same NAS DSH Host. A distinct app ID alone does not separate localStorage:
origin separation preserves independent native DSH selection and drafts. DSH
continues to own session and provider lifecycle. No custom chat route, session
allocation or provider process belongs to this controller. The first private
stock67 proof retained two guests and independent unsent drafts across hide/show
and watched shell refresh; it did not qualify a physical seat or the candidate
965 engine. Its native teardown allocator dump remains recorded separately.
