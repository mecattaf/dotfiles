# Migration journal — Fedora/chezmoi → NixOS

The working documents behind the `nix` branch, landed here from loose files
at `~/mecattaf/*.md` (desktop-reorg 2026-07-04, annotation :64: "those are
very likely to do directly with the projects that i am envisioning ...
those are to also be rolled into `~/mecattaf/dotfiles`"). Filenames are kept
as-is — they're cited by name elsewhere (see Cross-references below).

**System of record: [`nix-decisions.md`](nix-decisions.md).** Everything
else here is either input to it (the sweeps) or downstream of it (harvests,
research, handoff notes).

## The files, dated (Jun 17-20 2026 era)

- **[nix-decisions.md](nix-decisions.md)** (Jun 20) — the one place to return
  to; every ratified call about moving `harness` + `harnessRPM` + `dotfiles`
  into one Nix setup.
- **[ds4-dual-node-lessons.md](ds4-dual-node-lessons.md)** (Jun 17) — build
  report + postmortem for the dual-node ds4 (DeepSeek V4 Flash) cluster
  across two Strix Halo boxes over Thunderbolt.
- **[harness-sweep.md](harness-sweep.md)** (Jun 20) — disposition of every
  item in the `harness` repo (system layer), file by file; ratified calls
  fold into `nix-decisions.md`.
- **[dotfiles-sweep.md](dotfiles-sweep.md)** (Jun 20) — 3-agent sweep of
  `dotfiles/home/` (chezmoi root), classifying each config RAW / TYPED /
  AS-IS / COPY / GONE.
- **[nvim-sweep.md](nvim-sweep.md)** (Jun 20, 878 lines) — full Nix
  migration plan for the nvim config (lazy.nvim retained, zero
  functionality loss contract); implemented per `nix-build-handoff.md`.
- **[nix-test-compare.md](nix-test-compare.md)** (Jun 20) — **nix-test
  harvest**: what the earlier autonomous/blind `nix-test` attempt did,
  mined for the bits worth keeping. `nix-test` itself was deleted; its
  rescued raw docs (audits, secrets, strix-halo research, initial-chats)
  live in the notes repo at
  `references/devlogs/1h26/nix-test-rescue/` — this file is the
  distilled ADOPT/ALIGN/DIVERGE/WRONG compare, not the raw rescue.
- **[nix-ouverture.md](nix-ouverture.md)** (Jun 20) — forward-looking
  companion to `nix-decisions.md`; the thesis that the migration converges
  on one shape (typed options → CLI/daemon + config, à la microvm.nix).
- **[remote-access-mesh.md](remote-access-mesh.md)** (Jul 5) — wayvnc +
  Remmina + SSH mesh design (supersedes the abandoned Sunshine/Moonlight
  plan); declarative any-device-to-any-device access on mainline niri.
- **[nix-build-handoff.md](nix-build-handoff.md)** (Jun 20) — handoff
  snapshot: Layer 1 built/validated/pushed on `nix`, next action is
  flashing the Zenbook Duo per `../zenbook-duo-flash.md`.

## Cross-references

- `references/devlogs/1h26/nix-test-rescue/` (notes repo) — the raw
  `nix-test` rescue (pre-deletion), separate from `nix-test-compare.md`'s
  distilled harvest above.
- `references/devlogs/1h26/ds4-deepseek-local/README.md` (notes repo) —
  points at `ds4-dual-node-lessons.md` by name; updated 2026-07-04 to this
  new path.
- `../zenbook-duo-flash.md` — the install runbook `nix-build-handoff.md`
  hands off to.
