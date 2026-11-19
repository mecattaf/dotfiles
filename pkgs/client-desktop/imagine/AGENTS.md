# Imagine working rules

- Use existing public Domicile capabilities/components first. Imagine owns its
  shell, policy, layout and presentation. Preserve `reference/manganese` and
  upstream/MIT provenance; do not patch the engine from this repository.
- Keep owned defaults separate from device facts. Black background, no topbar,
  zero gaps, rounded chrome, no focus glow, split-first windows, rail/Finder and
  vertical 35 ms motion are owned behavior. Named panels, scales, fonts and
  device selection come from client configuration; do not hard-code the Duo
  identities into package defaults.
- Source and engine are an inseparable qualified pair. A source-only pin does
  not select a patched engine. Keep configured SDK provenance, loaded browser
  executable/compositor-library mappings, and tests run on a prior engine as
  separate claims. Require the matching owner's qualification receipt and
  verify the actual loaded pair when consuming it.
- Ship checked TSX plus every relative production dependency together. Stamp
  immutable source identity into the entry and manage its companion user link:
  import discovery is lexical, while Vite follows the real symlink target.
  Verify semantic refresh and native/guest retention; ordinary code changes
  must not require logout. Live seat engine changes require a genuine PAM/logind
  session transition, with CLI, SDK config and recovery aligned after the old engine,
  escaped process scopes and listeners are gone. Keep recovery orchestration
  bounded and reuse existing login mechanisms; a successful one-shot prototype
  does not establish a requirement for a permanent recovery service.
- The Rust launcher holds the persistent profile lock. Inspect that launcher's
  lock when proving ordinary-profile reuse across an engine transition.
- Snapshot IPC has one owner in the existing command dispatcher. Stage its
  owner-only identity config atomically before watched linkGeneration: the hook
  reads once per mount and retries on unlock. Keep helper/protocol/Python pinned,
  typed desktop/window/DSH identities distinct and default snapshots free of
  titles, URLs and content. Read-only transport grants no DSH tool registration
  or mutation authority. Installing a source/engine pair on disk never changes
  the already loaded ABI; review identity tags/mappings with a matched upgrade.
- Tests launching compositors, sourcing shell fragments or cleaning runtime
  state use target `~/.local/bin/runtime-test -- ...`. Inspect exact functions;
  never source unbounded text. Keep dumps/failures and distinguish headless
  evidence from physical acceptance. Never repair tests by restarting Herdr,
  greetd, the desktop or the user manager, or rebooting a live seat.
  Retain transient portal failures and coredump-collector attempts even when
  final failed-unit lists are empty and no COREDUMP metadata was recorded.
- NAS owns sessions/credentials. Heavy work goes through the reviewed fleet
  path to strix-coordinator; strix-worker is dormant. Before each Nix build,
  verify the actual build host has at least 25 GiB free. New inter-host hops,
  including Nix stores, use strict Tailscale transport; no global SSH edits.
- During this transition Tom excludes Projects CLI and uncodixfy. Honor granted
  authorization without inventing confirmation gates. No unrequested commits,
  remotes, pushes or publication. Client runs no DSH/provider credentials.
- Client policy supplies panel temperatures through the public per-output
  display API (Tom, 2026-11-08). No engine gamma patch is permitted.
  Global whitepoint journals establish an all-monitor requested state;
  per-output LUT readback and physical color require separate evidence.
  Scroll/Niri recovery and sidebar-donor history are explicitly deferred.
  Wraith/terminal integration and full dsh-domicile IPC are separate chapters;
  do not absorb them into a small presentation change or deep-search notes.
- Ambient chat uses the public backgroundApps facility and reducer placement.
  Hide/show retains its guest; it does not close or create a server agent.
  Keep the full Agency window separate. App IDs identify native guests, while
  browser origins own selection/draft storage: distinct IDs alone do not
  isolate drafts. An optional second loopback origin reaches the same NAS
  Host through an independent Tailscale forward, never another client backend.
- Compact chat defaults remain optional. A fixed bootstrap executable receives
  no arbitrary URL/command arguments; credentials stay out of argv, logs and
  immutable configuration. Repeated toggles reuse the mounted guest. Lock,
  modal and newer navigation intent take priority over delayed launch focus.
