# Agency Kitty

Native Kitty transport and small workflow extensions for Tom's Domicile,
Imagine and DSH desktop. Kitty owns terminal rendering. The ordinary attached
key/output path must not traverse a Python repaint loop, a web terminal, or
Herdr's UI. One durable session has one stable identity; workspace ownership
belongs to Imagine/dsh-domicile rather than a terminal multiplexer.

This is a separately reviewable consolidation under active development.
Nothing here installs itself or changes a running desktop.

The run's research and evidence are in
`~/notes/journal/2026/11/07/kitty-consolidation/`.

## Boundaries

- `agency_kitty/transport.py`, `sessions.py`, `server.py`: transport lane.
- `agency_kitty/capabilities/` and `kitty/agency.py`: capabilities lane.
- `agency_kitty/cli.py`, `integration/`, `packaging/`: integration lane.
- Neovim and fleet configuration live in a separate dotfiles worktree.

Capability sidechannels handle images, copy feedback, transcript export and
notifications. They must not be inserted into every keystroke. Live credentials
remain on their original hosts. Requests must name a session/window; no ambient
fallback may type into whichever window happens to be focused.

Durability means an SSH disconnect does not kill the NAS PTY/editor. Surviving
a NAS reboot additionally requires harness history/editor recovery; those are
different guarantees and must be described separately.

Ordinary direct SSH terminals also expose bounded live metadata to DSH/Imagine,
without a PTY holder. See [direct terminal metadata](docs/DIRECT_CATALOGUE.md)
for lifecycle checks, launch context, class mapping and explicit limits.

The installed `agency-kitty-native-forward` prototype explicitly attaches a
local compiled client through an SSH Unix-socket forward. It changes SSH's
interactive timing-padding policy and does not replace the desktop launcher.
See [native forwarding usage and requirements](docs/NATIVE_FORWARD.md).
