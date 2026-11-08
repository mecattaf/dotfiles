This integration owns about six thousand physical lines of runtime glue plus
separate terminal/compositor patches. It reuses native Kitty rendering,
OpenSSH, Neovim and libghostty; it still has a substantial compatibility and
qualification surface. It is not a zero-maintenance replacement for the
historical roughly 1,850-line Go holder demoted in the June handoff.

The [reproducible source inventory](evidence/maintenance/runtime-lines.json)
records file counts, hashes and input revisions. Physical lines include blanks,
comments and docstrings; these are not executable-statement counts. Tests,
research, docs, receipts and upstream dependency source are excluded.

- `agency_kitty/`: 4,279 lines in 27 Python files. Of these, 302 belong to the
  explicit native-forward/control prototype; the default direct SSH route
  does not use it. The package also owns metadata, lifecycle, target validation,
  image/transcript capabilities, editor requests and reconnect supervision.
- `kitty/`: 734 lines in four Python adapters.
- Dotfiles editor launchers: 243 Python lines in `dsh-editor` and
  `dsh-editor-tree`; four new editor Lua modules add 523 lines, including the
  259-line image adapter. Existing full Neovim configuration/plugins are not
  counted as newly owned code.
- Three fish integration files add 31 lines. The executable DSH tool and NAS
  native-catalogue companion add 171 lines. These categories total 5,981 lines.
- The eight-line example keybinding module and 264 lines of Nix wiring are
  separate deployment/example glue, excluded from that runtime subtotal.

Patch ownership is incremental, not the size of the upstream projects:

- `backend/zmx/agency-v4-vt1.patch`: 1,269 physical patch lines, +645/-90
  overall. After excluding build/dependency metadata and embedded tests, the
  runtime Zig delta is +555/-87; another 83 additions are tests and seven are
  build/dependency lines. This patch owns queue/backpressure correctness,
  attach-only/version isolation, snapshot admission and native state replay.
- Imagine native catalogue: +112/-44 production lines. Native drag handling:
  +182 production lines. NAS catalogue relay: +17/-8. Actual client entry:
  +3/-2. Their tests/docs are excluded from these production deltas.
- Domicile drag lifecycle: +244/-1 production Rust lines, excluding its tests,
  docs, build changes and e2e harness. Kitty's procfs memory fallback is a
  further +22/-23 Python delta in `pkgs/kitty-memory-procfs-fallback.patch`.

The lower-maintenance interfaces are ordinary OpenSSH argv/Unix forwarding,
Kitty's documented remote-control CLI, custom kitten entry points, watcher
events, user variables, keyboard/graphics/clipboard/notification protocols and
native shell-integration assets. Imagine entry adoption uses its public
`runImagine({keybindings})` and `ownedChords()` seam. The DSH plugin uses its
structured tool registration API and carries metadata, not terminal input.
Own typed envelopes and persistent schemas are also compatibility contracts:
canonical NAS UUID/directory/child identity must survive changes intact.

Kitty Python adapters have narrower, version-sensitive seams. `agency.py`
wraps the instance `Window.on_drop` and Boss primary-selection callback because
there is no public drop watcher; those adapters accept exactly 0.48.0 and
0.50.0. It also uses the native notification manager. `agency_watch.py` extends
`kittens.query_terminal.main.all_queries` and calls
`kitty.fast_data_types.cell_size_for_window` for exact pixels; that registry
extension has no independent future-version guarantee. Editor helpers inspect
`screen.last_reported_cwd`, use `Child.root_pid` with a `pid` fallback, and parse
the distinct file/Kitty shell-cwd forms. Sidebar launch uses native 0.50 docks;
0.48 requires a qualified horizontal-splits fallback. The dock path currently
accepts versions >=0.50, so the integration as a whole is not universally
closed to every unqualified future version.

Neovim uses the native RPC UI, not terminal-byte proxying: the local frontend
runs `nvim --server LOCAL_SOCKET --remote-ui`, with ordinary SSH forwarding to
the retained NAS server. Both sides must be >=0.12 and match major/minor;
current qualification uses 0.12.4. Checkpoint format v1 and pending vi request
lifecycle are owned contracts. The upstream 0.13 convenience SSH bootstrap is
not the persistence layer used here.

`kitty_image_remote.lua` is the most exact plugin seam. It verifies five
image.nvim 1.5.1 source SHA256 values, then adapts its private helper/terminal,
renderer, backend and image-processing paths. It temporarily intercepts the
helper's libuv TTY writer at load and restores that shared function. Public
Neovim UI events carry output; per-channel nonce queries recover exact native
cell geometry. A changed plugin file refuses setup until this adapter is
qualified. Upgrade gates must include full 32-plugin startup, actual Markdown
PNG rendering, fresh UI retransmission, simultaneous different-cell UIs,
retained unsaved work and explicit server-kill recovery.

The holder pins zmx `a35f00a2`, Ghostty `0fa3d577` (vt-1.0.0), Zig 0.17.0 and
fixed-output dependency hashes in `backend/zmx/source-build.nix`. It imports
Ghostty's Zig module and directly accesses screen/image/palette/formatter
state. The stable C ABI is not the interface this code uses. At the pinned
revision, `src/lib_vt.zig` explicitly withholds Zig source API stability;
`dist/doxygen/pages/stability.md` guarantees C ABI compatibility across 1.x,
while separately excluding snapshot bytes from that guarantee. Session
records retain the exact holder version; protocol 204 and distinct socket
namespaces prevent incompatible clients from silently replacing a PTY.
`upstream.json` retains and explicitly labels its historical version-3 fields;
its current-source pointer and the backend README identify the admitted v4-vt1
recipe/receipts. Existing variant identities are never rewritten.

On an upgrade, use the existing corresponding gates: actual native clipboard/
copy/drop and stale-target tests for Kitty; managed direct/fresh/resume
bootstrap typeahead, native OSC7/133 and same-process reconnect for OpenSSH;
full editor/image/recovery gates for Neovim; exact offline harness hook/image/
history gates for Codex/Claude; byte/queue/resize/paste and actual fresh-Kitty
graphics restoration for holder changes. Domicile/Imagine changes also need
loaded-engine attestation, real cross-app drag, exact catalogue click placement
and focus guards, and the actual compiled client-entry chords. Build/import
success alone does not cover these Python/private-protocol seams. Keep old
holder packages available for the sessions that still name them.

The original nightly checker hid future custom Kitty releases: it watched
`client.pkgs.kitty.version` under `nixpkgs-fresh`, while the literal custom
recipe overrides that leaf with 0.50.0. Dotfiles change `89a8e130` fixes discovery
through the checker's existing official GitHub issue-watch seam. It compares
full stable Kitty versions for client/NAS, excludes drafts/prereleases and
opens or reuses a review issue. It does not mutate the source pin, build or
deploy a release. The misleading fresh-input Kitty watch was removed. Its
29 targeted runtime-isolated source/mock checks passed without contacting
GitHub. `docs/kitty-updates.md` in dotfiles explains the required source-tree
hash, separate Go vendor hash, borrowed toolchain, procfs patch and native
qualification review. Fresh Go/shader tool changes may still affect the build.
The older update-check skill's claim that Kitty simply follows the fresh leaf
is superseded by this explicit pin-and-release-watch contract.
