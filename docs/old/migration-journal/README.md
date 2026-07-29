# Archived implementation notes

These are the still-useful NixOS implementation records retained after the
completed system consolidation. They are historical evidence, not deployment
guidance; the live flake and modules remain authoritative.

## Retained records

- **[ds4-dual-node-lessons.md](ds4-dual-node-lessons.md)** (Jun 17) — build
  report + postmortem for the dual-node ds4 (DeepSeek V4 Flash) cluster
  across two Strix Halo boxes over Thunderbolt.
- **[nvim-sweep.md](nvim-sweep.md)** (Jun 20, 878 lines) — full Nix
  integration plan for the nvim config (lazy.nvim retained, zero
  functionality-loss contract).
- **[remote-access-mesh.md](remote-access-mesh.md)** (Jul 5) — wayvnc +
  Remmina + SSH mesh design (supersedes the abandoned Sunshine/Moonlight
  plan); declarative any-device-to-any-device access on mainline niri.

## Cross-references

- `references/devlogs/1h26/ds4-deepseek-local/README.md` (notes repo) —
  points at `ds4-dual-node-lessons.md` by name; updated 2026-07-04 to this
  new path.
